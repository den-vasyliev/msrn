#!/usr/bin/perl
#
####################################################
## Copyright (C) 2012, RuimTools denis@ruimtools.com
#
# API CGI for PROXY SERVER 230612rev.6.0
#
####################################################
#
use IO::Socket;
use CGI;
use URI::Escape;
#
#
$query = new CGI;
$HOST='127.0.0.1';
$PORT='35001';
$LOGFILE='/opt/ruimtools/log/api.log';
$now = localtime;
#
my $sock = new IO::Socket::INET (PeerAddr => $HOST,PeerPort => $PORT,Proto => 'tcp',);
die "Could not create socket: $!\n" unless $sock;#generate error 500 if rcpi not reachable
#
print "Content-Type: text/xml\n\n";
#
eval {#check for 10 sec timeout
local $SIG{ALRM} = sub { die 'Timed Out'; }; 
alarm 10;
#
## LOGG ######################################
my $remote_host=$query->remote_host();
sub logg{
my $MESSAGE=$_[0];
open(LOGFILE,">>","$LOGFILE") or die $!;
my $LOG="[$now]-[API-LOG]: $MESSAGE\n";	
print STDOUT $LOG if $debug==1;
print LOGFILE $LOG;
close LOGFILE;
}## END LOGG #################################
#
&logg("GET CONNECTION FROM ".$query->remote_host());
&logg("GET QUERY ".$query->url(-path_info=>1,-query=>1));
#
foreach $field (sort ($query->param)) {
    if ($field=~/timestamp2012/){next;}
	foreach $value ($query->param($field)) {
$PARAM{$field}=uri_unescape($value);
$PARAM{'xml'}=~s/<\?xml.*\?>/ / if $field eq 'xml';#for payments
&logg("CATCH QUERY $field $value");
push @QUERY,"$field=".uri_escape($value);#for general request
$qr=$qr."$field=".uri_escape($value).';';#for lab request
    }#foreach value
push @QUERY,"code=2 imsi=0 msisdn=1 request_type=rc_api_cmd sub_code=76 transactionid=10" if $field eq 'card_number';#for payments
}#foreach fiels
#
if ($PARAM{imsi} eq '234180000079890'){#if lab imsi
@result=`curl 'http://127.0.0.1:8008/roamingcenter/?$qr'`;#redirect to java lab server
print @result;
exit;#end processing
}#if lab redirect
else{#if general request
if (!$PARAM{xml}){#if not xml payments
&logg("SEND QUERY @QUERY");
print $sock qq[<?xml version="1.0" encoding="UTF-8"?><SIG_QUERY><authentication><key>897234jhdln328sLUV</key><host>$remote_host</host></authentication><query>@QUERY</query></SIG_QUERY>\r\n];}
else{#else if xml payments
&logg("SEND QUERY $PARAM{xml}");
print $sock qq[<?xml version="1.0" encoding="UTF-8"?><SIG_QUERY><authentication><key>897234jhdln328sLUV</key><host>$remote_host</host></authentication>$PARAM{xml}</SIG_QUERY>\r\n] if $PARAM{xml};
}#else xml param
}#else general request
#
$sock->autoflush(1);
my $line;
while ($line = <$sock>) {#read socket unswer
&logg("SEND RESPONSE $line");
print "$line\n";
if ($line=~m/MOC_response/i){close $sock}#not sure why
}#while read sock
close or die "close: $!";#close or die
};#eval
#
alarm 0; # race condition protection 
print qq[<?xml version="1.0" ?><Error><Error_Message>TIMED OUT 10 SECONDS</Error_Message></Error>\012] if ( $@ && $@ =~ /Timed Out/ );#timeout
### END ####################################
