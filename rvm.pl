#!/usr/bin/env perl

use warnings;
use strict;
use WWW::Mechanize;

use CGI qw/:standard/;
use Net::LDAP;



my %config = do "/secret/ldap.config";

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
<form method="post" action="/cgi-bin/rvm.pl">
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

			if($ext != 0){

				my $name=&resetvoice($ext);
				print "<br>voicemail password reset for $name complete";


			}else{
				print "<br>wrong username/password combination";
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
#output: user's extension = successful login, 0 = failed login
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
			print "no phone number found... cannot determine extension. aborting.\n";
			return 0;
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
#output: $name of user that was reset

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
	$stuff=~/\<tr align="center" bgcolor="#......"\>\<td class="tableText"\>(.*)\<\/td\>\<td class="tableText".*Activity\<\/a\>\<\/td\> \<td class="tableLink"\>\<a href=" (.*) " onClick="return confirm\('Are you sure you want to reset password to default for Mailbox Number $ext/;

#this is the url to run to reset the voicemail
#	print $1;
#	print "\n";
#this is the name of the user about to be reset
#	print $2;

$newurl="https://$nhost".$2;
$mech->get($newurl);

#logout
$mech->get("https://$nhost/Voicemail-cgi-bin/F983Wui.exe");


	return $1;
}