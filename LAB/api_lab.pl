#!/usr/bin/perl
#
####################################################
## Copyright (C) 2012, RuimTools denis@ruimtools.com
#
# API CGI for PROXY SERVER 300512rev.4.0
#
####################################################
#
use IO::Socket;
use CGI;
use URI::Escape;
#
print "Content-Type: text/xml\n\n";
#
$query = new CGI;
$HOST='127.0.0.1';
$PORT='35001';
$LOGFILE='/opt/ruimtools/log/api.log';
$now = localtime;
#
eval { 
local $SIG{ALRM} = sub { die 'Timed Out'; }; 
alarm 10;
#
my $sock = new IO::Socket::INET (PeerAddr => $HOST,PeerPort => $PORT,Proto => 'tcp',);
#die "Could not create socket: $!\n" unless $sock;
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
    foreach $value ($query->param($field)) {
&logg("CATCH QUERY $field");
$PARAM{$field}=uri_unescape($value);
$PARAM{'xml'}=~s/<\?xml.*\?>/ / if $field eq 'xml';
&logg("CATCH QUERY $field $value");
push @QUERY,"$field=".uri_escape($value);
    }#foreach value
push @QUERY,"code=2 imsi=0 msisdn=1 request_type=rc_api_cmd sub_code=76 transactionid=10" if $field eq 'card_number';
}#foreach fiels
#
if (!$PARAM{xml}){
&logg("SEND QUERY @QUERY");
print $sock qq[<?xml version="1.0" encoding="UTF-8"?><SIG_QUERY><authentication><key>897234jhdln328sLUV</key><host>$remote_host</host></authentication><query>@QUERY</query></SIG_QUERY>\r\n];}
else{
&logg("SEND QUERY $PARAM{xml}");
print $sock qq[<?xml version="1.0" encoding="UTF-8"?><SIG_QUERY><authentication><key>897234jhdln328sLUV</key><host>$remote_host</host></authentication>$PARAM{xml}</SIG_QUERY>\r\n] if $PARAM{xml};
}
$sock->autoflush(1);
my $line;
while ($line = <$sock>) {
print "$line\n";
if ($line=~m/MOC_response/i){close $sock}
}#while read sock
close  or die "close: $!";
};#eval
#
alarm 0; # race condition protection 
print qq[<?xml version="1.0" ?><Error><Error_Message>TIMED OUT 10 SECONDS</Error_Message></Error>\012] if ( $@ && $@ =~ /Timed Out/ ); 
### END ####################################