#!/usr/bin/perl
#
####################################################
## Copyright (C) 2012, RuimTools denis@ruimtools.com
#
# API CGI for PROXY SERVER 130712rev.13.0
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
$lab=0;#for lab always 0
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
    if ($field=~/timestamp|message_date/){next;}
	foreach $value ($query->param($field)) {
$PARAM{$field}=uri_unescape($value);
$PARAM{'xml'}=~s/<\?xml.*\?>/ / if $field eq 'xml';#for payments
$PARAM{'POSTDATA'}=~s/POSTDATA=/ / if $field eq 'POSTDATA';#for data cdr
&logg("CATCH QUERY $field $value");
push @QUERY,"$field=$value";#for general request
$qr=$qr."$field=$value;";#for lab request
    }#foreach value
push @QUERY,"code=get_stat request_type=rc_api_cmd sub_code=get_card_number transactionid=10" if $field eq 'card_number';#for payments
}#foreach fiels
#
if (($PARAM{imsi} eq '234180000079890')||($PARAM{IMSI} eq '234180000079890')){#if java lab imsi
@result=`curl 'http://10.10.10.2:8008/roamingcenter/?$qr'`;#redirect to java lab server
print @result;
close $sock;
exit;#end processing
}#if java lab redirect
elsif (((  ( ($PARAM{imsi} eq '234180000379608')||($PARAM{IMSI} eq '234180000379608')||($PARAM{POSTDATA}) )&&($lab==1) ))){#if perl lab imsi
@result=`curl 'http://10.10.10.2/cgi-bin/api.pl?$qr'`;#redirect to perl lab server
print @result;
close $sock;
exit;#end processing
}#if perl lab redirect
else{#if general request
if ((!$PARAM{xml})&&(!$PARAM{POSTDATA})){#if not xml payments
&logg("SEND QUERY @QUERY");
print $sock qq[<?xml version="1.0" encoding="UTF-8"?><SIG_QUERY><authentication><key>897234jhdln328sLUV</key><host>$remote_host</host></authentication><query>@QUERY</query></SIG_QUERY>\r\n];}
else{#else if xml payments
&logg("SEND QUERY $PARAM{xml} $PARAM{POSTDATA}");
print $sock qq[<?xml version="1.0" encoding="UTF-8"?><SIG_QUERY><authentication><key>897234jhdln328sLUV</key><host>$remote_host</host></authentication>$PARAM{xml}</SIG_QUERY>\r\n] if $PARAM{xml};
print $sock qq[<?xml version="1.0" encoding="UTF-8"?><SIG_QUERY><authentication><key>897234jhdln328sLUV</key><host>$remote_host</host></authentication>$PARAM{POSTDATA}</SIG_QUERY>\r\n] if $PARAM{POSTDATA};
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
