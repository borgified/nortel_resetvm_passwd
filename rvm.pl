#!/usr/bin/env perl

use warnings;
use strict;
use WWW::Mechanize;

use CGI qw/:standard/;
use Net::LDAP;



my %config = do "/secret/ldap_act.config";

my $host        = $config{'host'};
my $ldaps       = $config{'ldaps'};
my $adminDn     = $config{'adminDn'};
my $adminPwd    = $config{'adminPwd'};
my $searchBase  = $config{'searchBase'};

my %nortel = do "/secret/nortel.config";

my $nhost		= $nortel{'nhost'};
my $nuserid		= $nortel{'nuserid'};
my $npassword	= $nortel{'npassword'};


sub main{

#get user's windows username and password and authenticate against LDAP
#provide link to reset password


#	my $username    = param('username');
#	my $password    = param('password');

	print header;
	print <<HTML
<html>
<form method="post" action="rvm.pl">
Login with your windows username/password<p>
username: <input type="text" name="username">
password: <input type="password" name="password"><p>
<input type="submit" value="RESET VOICEMAIL PASSWORD TO 0000">
</form>
<hr>
HTML
;
	if(param()){

		my $username=param('username');
		my $password=param('password');

		if(&ok($username,$password)){

			my $ext=&login($username,$password);

			if($ext == -1){
				print "<br>No phone number in your Active Directory details found... cannot determine extension. Aborting.\n";
			}elsif($ext == 0){
				print "<br>wrong username/password combination";
			}else{
				my($successful)=&resetvoice($ext);
				unless($successful){
					print "<br>Unable to reset voicemail password for $username because your extension in AD could not be matched up with an identical extension in the phone system to reset.";
				}
			}

			sub ok() {
				my $username=shift;
				my $password=shift;
				my $fine=1;

				if(!$username){ print 'need username',br; $fine=0;}
				if(!$password){ print 'need password',br; $fine=0;}

				return $fine;
			}
		}
	}
	print "</html>";
}

&main;




sub login{
#input: windows username, windows password
#output: user's extension = successful login, 0 = failed login, -1 = no extension details
	my($username,$password)=@_;

	my $userdn = testGuid ($username, $password);


	if ($userdn)
	{

		return &getUserExt($username);

	}else{

		return 0;

	}

	sub getUserDn
	{
		my $ldap;
		my $guid = shift;
		my $dn;
		my $entry;

		if ($ldaps) {
			$ldap = Net::LDAPS->new($host, verify=>'none') or die "$@";
		}
		else {
			$ldap = Net::LDAP->new($host, verify=>'none') or die "$@";
		}

		my $mesg = $ldap->bind ($adminDn, password=>"$adminPwd");

		$mesg->code && return undef;

		$mesg = $ldap->search(base => $searchBase, filter => "sAMAccountName=$guid" );

		$mesg->code && return undef;
		$entry = $mesg->shift_entry;

		if ($entry)
		{
			$dn = $entry->dn;
#$entry->dump;
		}


		$ldap->unbind;

		return $dn;
	}


	sub getUserExt
	{
		my $ldap;
		my $guid = shift;
		my $ext;
		my $entry;

		if ($ldaps) {
			$ldap = Net::LDAPS->new($host, verify=>'none') or die "$@";
		}
		else {
			$ldap = Net::LDAP->new($host, verify=>'none') or die "$@";
		}

		my $mesg = $ldap->bind ($adminDn, password=>"$adminPwd");

		$mesg->code && return undef;

		$mesg = $ldap->search(base => $searchBase, filter => "sAMAccountName=$guid" );

		$mesg->code && return undef;
		$entry = $mesg->shift_entry;

		if ($entry)
		{
			$ext = $entry->get_value('telephoneNumber');
		}


		$ldap->unbind;

		if($ext=~/(\d{4})$/){
			$ext = $1;
		}else{
			$ext = -1;
		}
	
		return $ext;
	}


	sub testGuid
	{
		my $ldap;

		my $guid = shift;
		my $userPwd = shift;

		my $userDn = getUserDn ($guid);

		return undef unless $userDn;

		if ($ldaps) {
			$ldap = Net::LDAPS->new($host, verify=>'none') or die "$@";
		}
		else {
			$ldap = Net::LDAP->new($host, verify=>'none') or die "$@";
		}

		my $mesg = $ldap->bind ($userDn, password=>"$userPwd");

		if ($mesg->code)
		{
# Bad Bind
			print $mesg->error . "\n";
			return undef;
		}

		$ldap->unbind;

		return $userDn;
	}





}



sub resetvoice{
#input:  $ext, user extension to be reset
#output: 0 if unsuccessful, 1 if successful
	my($ext)=@_;


	my $url = "https://$nhost/CallPilotManager";

	$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

	my $mech = WWW::Mechanize->new();
	$mech->get($url);

	$mech->submit_form(
			fields          => {
			UserId        => $nuserid,
			Password        => $npassword,
			}
			);

	my $stuff = $mech->content();

#get to main menu
	$stuff=~/window\.location = \"(.*)\"/;
	my $newurl="https://$nhost".$1;
	$mech->get($newurl);

#click change/delete mailbox
	$stuff=$mech->content();
	$stuff=~/a href="(.*)">Change\/Delete Mailbox/;
	$newurl="https://$nhost".$1;
	$mech->get($newurl);

#select the user we want to reset password (identified by their extension)

	$stuff=$mech->content();
	unless($stuff=~/\<tr align="center" bgcolor="#......"\>\<td class="tableText"\>(.*)\<\/td\>\<td class="tableText".*Activity\<\/a\>\<\/td\> \<td class="tableLink"\>\<a href=" (.*) " onClick="return confirm\('Are you sure you want to reset password to default for Mailbox Number $ext/){
	return 0;
	}

#this is the url to run to reset the voicemail
#	print $1;
#	print "\n";
#this is the name of the user about to be reset
#	print $2;

$newurl="https://$nhost".$2;
$mech->get($newurl);
print "<br>Voicemail password reset for $1 complete.";

#logout
$mech->get("https://$nhost/Voicemail-cgi-bin/F983Wui.exe");


	return 1;
}
