#!/usr/bin/perl
#/opt/local/bin/perl -T
#
########## VERSION AND REVISION ################################
## Copyright (C) 2012, RuimTools denis@ruimtools.com
##
my $REV='API Server 140612rev.21.4 SMS_MP_ENC';
##
#################################################################
## 
########## MODULES ##############################################
use DBI;
use Data::Dumper;
use IO::Socket;
use IO::Select;
use XML::Simple;
use Digest::SHA1;
use URI::Escape;
use Switch;
use POSIX;
use Time::Local;
use IO::File;
use Encode;
use warnings;
use strict;
no warnings 'once';
########## END OF MODULES #######################################
#
our $curl='/usr/bin/curl -k -f -s -m 10';
#
##############################################
## MAKE FORK AND CHROOT
## chroot("/opt/ruimtools/") or die "Couldn't chroot to /opt/ruimtools: $!";
our $pid = fork;
exit if $pid;
die "Couldn't fork: $!" unless defined($pid);
POSIX::setsid() or die "Can't start a new session: $!";
our $exit = 0;
#
my $PIDFILE = new IO::File ;
$PIDFILE->open(">/opt/ruimtools/tmp/rcpi.pid");
print $PIDFILE $$;
$PIDFILE->close();
#
sub signal_handler {use vars qw($exit); $exit = 1};
#
#$SIG{INT} = $SIG{TERM}= 
$SIG{HUP} = \&phoenix;
# trap $SIG{PIPE}
sub phoenix {
print("RESTARTING...");
my $SELF = $0;   # needs full path
exec($SELF) or die "Couldn't restart: $!\n";
}
##############################################
#
until ($exit) {
########## DEBUG OPTIONS ###############################
# 1 - print INFO to LOG_FILE
# 2 - print INFO&SQL to LOG_FILE
# 3 - print INFO&DEBUG&SQL to STDOUT&LOG_FILE
# 4 - print to STDOUT&LOG_FILE; print SQL queries
# *All transactions will always store in DB
#
if(@ARGV){our $debug=$ARGV[0]}else{use vars qw($debug );$debug=3}
#################################################################
#
########## OPEN MAIN SOCKET ##########
my $HOST='127.0.0.1';
my $PORT='35001';
&response('LOG','API',"$REV Ready at $$ deb $debug");
#################################################################
#
########## CONNECT TO MYSQL #####################################
our $dbh = DBI->connect('DBI:mysql:msrn', 'msrn', 'msrn');
#################################################################
#
########## LISTEN FOREVER #######################################
our $sock = new IO::Socket::INET (LocalHost => $HOST,LocalPort => $PORT,Proto => 'tcp',Listen => 10,ReuseAddr => 1,);
#
while(1) {
use vars qw($sock);
#
our $new_sock = $sock->accept();
#
my $sockaddr= getpeername($new_sock);
my ($port, $iaddr) = sockaddr_in($sockaddr);
our $ip_address= inet_ntoa($iaddr);
&response('LOG',"API-SOCKET-OPEN","SUCCESS $port $ip_address ##################################################");
#
########## READING INCOMING REQUEST FROM PROXY ##################
#
while(our $PROXY_REQUEST=<$new_sock>) {

if ($PROXY_REQUEST =~/897234jhdln328sLUV/){
&response('LOG','SOCKET',"OPEN $new_sock");
&response('LOG','XML-KEY',"OK");
}else{#NO XML
print $new_sock &response('LU_CDR','ERROR','INCORRECT XML-KEY','0');
$new_sock->shutdown(2);
$PROXY_REQUEST='EMPTY';last;
}#if VALIDATION
#
########## CALL MAIN ############################################
#
&main();
#
########## MAIN #################################################
## Main procedure to control all functions
#################################################################
sub main{
use vars qw($PROXY_REQUEST);
if ($PROXY_REQUEST ne 'EMPTY'){
our %XML_KEYS=&XML_PARSE($PROXY_REQUEST,'PROXY');
my $qkeys= keys %XML_KEYS;
&response('LOG','MAIN-XML-PARSE-RETURN',$qkeys);
if ($qkeys){#if kyes>0
my $IN_SET='';
$IN_SET="$XML_KEYS{msisdn}:$XML_KEYS{mcc}:$XML_KEYS{mnc}:$XML_KEYS{tadig}" if  $XML_KEYS{msisdn};
$IN_SET=$IN_SET.":$XML_KEYS{code}:$XML_KEYS{sub_code}" if $XML_KEYS{code};
$IN_SET=$IN_SET."$XML_KEYS{ident}:$XML_KEYS{amount}" if $XML_KEYS{salt};
&response('LOGDB',"$XML_KEYS{request_type}","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'IN',$IN_SET);
my $LU_H_result=&LU_H;
&response('LOG','MAIN-LU-H-RETURN',"$LU_H_result");
#Get action type
my $ACTION_TYPE_RESULT=&GET_TYPE($XML_KEYS{request_type});
eval {
	our $subref=\&$ACTION_TYPE_RESULT;
	};warn $@ if $@;  &response('LOG',"MAIN-ACTION-SUBREF","ERROR $ACTION_TYPE_RESULT") if $@;
&response('LOG','MAIN-GET_TYPE',$ACTION_TYPE_RESULT);
switch ($ACTION_TYPE_RESULT){
case 1 {
	print $new_sock &response('LU_CDR','ERROR','#'.__LINE__.' INCORRECT URL VARIABLES');
	&response('LOGDB',"$XML_KEYS{request_type}","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'ERROR','INCORRECT URL VARIABLES');
	}#case 1
case 2 {
	print $new_sock &response('LU_CDR','ERROR','#'.__LINE__.' INCORRECT ACTIONS TYPE');
	&response('LOGDB',"$XML_KEYS{request_type}","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'ERROR','INCORRECT ACTIONS TYPE');
	}#case 2
case 3 {
	&response('LOG','MAIN-GET_TYPE','NOT FOUND');
	print $new_sock &response('LU_CDR','ERROR','#'.__LINE__.' INCORRECT URI')}
else {#else case action_type_result
	use vars qw($subref);
	my $ACTION_RESULT=&$subref($XML_KEYS{imsi});
	if($ACTION_RESULT){
	&response('LOG',"MAIN-ACTION-RESULT-$ACTION_TYPE_RESULT","$ACTION_RESULT");
	}#if ACTION RESULT
	else{&response('LOG',"MAIN-ACTION-RESULT-$ACTION_TYPE_RESULT",'NO ACTION_RESULT');}
	}#else switch ACTION TYPE RESULT
	}#switch ACTION TYPE RESULT
}#if keys
else{#else if keys
&response('LOGDB',"UNKNOWN REQUEST",0,0,'IN',"$PROXY_REQUEST");
&response('LOG','MAIN-XML-PARSE-KEYS',$qkeys);
print $new_sock &response('LU_CDR','ERROR','INCORRECT XML KEYS',0);
}#else if keys
}else{#EMPTY XML
&response('LU_CDR','ERROR','NO ALLOWED','0');
&response('LOGDB',"EMPTY",'NULL','NULL','ERORR','NO ALLOWED');
}#if EMPTY
}########## END sub main ########################################
#
########## XML_PARSE ############################################
## Function to parse XML data from proxy and msrn request/respond
## Usage XML_PARSE(<XML>,<OPTION>)
## Accept pure xml on input
## Return hash with key=value for PROXY request and MSRN 
#################################################################
sub XML_PARSE{
my $REQUEST_LINE=$_[0];
my $REQUEST_OPTION=$_[1];
my @QUERY='';
#
eval {#error exceprion
our $REQUEST=XML::Simple->new()->XMLin($REQUEST_LINE); 
our $DUMPER=Dumper (XML::Simple->new()->XMLin($REQUEST_LINE));
#our %DUMPER_HESH=Dumper (XML::Simple->new()->XMLin($REQUEST_LINE));
};warn $@ if $@; return "XML not well-formed" if $@;
#
use vars qw($REQUEST $DUMPER);
&response('LOG',"XML-PARSE-REQUEST-$REQUEST_OPTION","$REQUEST_LINE") if $debug>=3;
#
our $REMOTE_HOST=$REQUEST->{authentication}{host};
#
switch ($REQUEST_OPTION){
	case 'PROXY' {
if ($REQUEST->{query}){#if request in 'query' format
&response('LOG',"XML-PARSE-DUMPER","$DUMPER")if $debug>=3;;
our %Q=();
my @QUERY=split(' ',$REQUEST->{query});
foreach my $pair(@QUERY){
my  ($key,$val)=split('=',$pair);
	$Q{$key}=$val;#All variables from request
}#foreach
my $qkeys = keys %Q;
&response('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION",$qkeys);
return %Q;
}#if request
elsif($REQUEST->{payment}){#if request in 'payments' format
&response('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION",'PAYMENTS');
our %Q=('request_type'=>'PAYMNT');
$Q{'transactionid'}=$REQUEST->{payment}{id};
my @KEYS= keys %{ $REQUEST->{payment} };
foreach my $xml_keys (@KEYS){
&response('LOG',"XML-PARSE-RETURN-KEYS","$xml_keys=$REQUEST->{payment}{$xml_keys}")if $debug>3;
$Q{$xml_keys}=$REQUEST->{payment}{$xml_keys};
}#foreach xml_keys
return %Q;
}#elsif payments
else{#unknown format
&response('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION",'UNKNOWN FORMAT');
}#else unknown
	}#proxy
	case 'SIG_GetMSRN' {
my $MSRN=$REQUEST->{MSRN_Response}{MSRN};
our $ERROR=$REQUEST->{Error_Message};
&response('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$MSRN $ERROR");
return $MSRN;
	}#msrn
	case 'SIG_SendUSSD' {
my $USSD=$REQUEST->{USSD_Response}{REQUEST_STATUS};
our $ERROR=$REQUEST->{Error_Message};
&response('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$USSD $ERROR");
return $USSD;
	}#ussd
	case 'SIG_SendSMS' {
my $SMS=$REQUEST->{SMS_Response}{REQUEST_STATUS};
our $ERROR=$REQUEST->{Error_Message};
&response('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$SMS $ERROR");
return "$ERROR$SMS";
	}#sms
	case 'SIG_SendResale' {
my $USSD=$REQUEST->{RESALE_Response}{RESPONSE};
our $ERROR=$REQUEST->{Error_Message};
&response('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$USSD $ERROR");
return $USSD;
	}#resale
	else {
		print &response('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION",'NO OPTION FOUND $@');
		return "Error: $@";}
}#switch OPTION
}#END sub XML_PARSE
#
########## GET TYPE #############################################
## Resolve request type action with cc_actions
## Checks each parameter with database definition 
## Returns code of request type or 2 (no such type) or 3 (error)
#################################################################
sub GET_TYPE{
use vars qw(%Q);
my $request_type=$_[0];
my $SQL=qq[SELECT request FROM cc_actions where code="$request_type"];
#
my @sql_records=&SQL($SQL);
&response('LOG','GET-TYPE-SQL-RECORDS',$sql_records[0]) if $debug>3;
#
if(@sql_records){#IF MYSQL OK
	if ($sql_records[0]){
	&response('LOG','GET_TYPE-MYSQL',@sql_records) if $debug>3;
my %MASK;
my 	@MASK=split('::',$sql_records[0]);
	for (my $i =$[; $i <= $#MASK; $i++){
		 $MASK{$MASK[$i]}='mask';
		}#for
#
our $PASS=1;
foreach my $q(keys %Q){
	if($MASK{$q} ne ''){
	&response('LOG','GET_TYPE-XML',"OK $q=$Q{$q}");
	 $PASS=0;
}else{
	&response('LOG','GET_TYPE-XML',"Error $q");
	$PASS=1;last
	}#else
}#foreach
#
use vars qw($PASS);
if( $PASS==0){
return $Q{request_type};
}else{return 1;}#else PASS STRUCTURE
}else#NO ACTIONS TYPE
{return 2;}
}else#if MYSQL ERROR
{return 3;}#else NOT GET_TYPE
}########## END GET_TYPE ########################################
#
########## SQL ##################################################
## Performs SQL request to database
## Accept SQL input
## Return SQL records or mysql error
#################################################################
sub SQL{ 
my $SQL=qq[@_];
my $now = localtime;
open(LOGFILE,">>",'/opt/ruimtools/log/rcpi.log') or die $! if $debug>=2;
print LOGFILE "[$now]-[API-SQL-MYSQL]: $SQL\n" if $debug>=2; #DONT CALL VIA &RESPONSE
print "[$now]-[API-SQL-MYSQL]: $SQL\n" if $debug>=3;

my $rv; 
my $sth;
our @result=();
if($SQL!~m/^SELECT/i){
$rv=$dbh->do($SQL);
push @result,$rv;
}
else{
$sth=$dbh->prepare($SQL);
$rv=$sth->execute;
@result=$sth->fetchrow_array;
$sth->finish();
}
if($rv){
	our $sql_aff_rows =$rv;
	my $sql_record = @result;
	&response('LOG','SQL-MYSQL-RETURNED',"@result $rv");
	return @result; 
	}else{
	&response('LOG','SQL-MYSQL-RETURNED','Error');
	return -1;
}#else MYSQL ERROR
}########## END sub SQL	#########################################
#
########## RESPONSE #############################################
## Takes care of all types of response
## Accept three options. Return log line to STDOUT, FILE, SOCKET
## Usage response(<LOG OPTION>,<OK|ERROR|CUSTOM>,<MESSAGE>)
#################################################################
sub response{
#	
my $now = localtime;
open(LOGFILE,">>",'/opt/ruimtools/log/rcpi.log') or die $!;
#
my ($ACTION_TYPE,$RESPONSE_TYPE,$MESSAGE0,$MESSAGE1,$MESSAGE2,$MESSAGE3)=@_;
if($ACTION_TYPE!~m/^LO/){
	my $SQL=qq[SELECT response FROM cc_actions where code="$ACTION_TYPE"];
	my @sql_record=&SQL($SQL);
my	$XML=$sql_record[0];
	#CDR_RESPONSE::CDR_ID::CDR_STATUS MOC_response::TRANSACTION_ID::DISPLAY_MESSAGE
my	($ROOT,$SUB0,$SUB1)=split('::',$XML);
my $now = localtime;
if($RESPONSE_TYPE eq 'OK'){
my	$OK=qq[<?xml version="1.0" ?><$ROOT><$SUB0>$MESSAGE0</$SUB0><$SUB1>$MESSAGE1</$SUB1></$ROOT>\n];
	my $LOG="[$now]-[API-RESPONSE-SENT]: $OK\n"; 
	print LOGFILE $LOG if $debug<=4;
	print $LOG if $debug>=3; 
	return $OK;
}#if OK
elsif ($RESPONSE_TYPE eq 'ERROR'){
my	$ERROR=qq[<?xml version="1.0" ?><Error><Error_Message>$MESSAGE0</Error_Message></Error>\n];
	my $LOG="[$now]-[API-RESPONSE-SENT]: $ERROR\n";
	print LOGFILE $LOG if $debug<=4;
	print $LOG if $debug>=3;
	return $ERROR;
}#elsif ERROR
}#ACTION TYPE ne LOG
elsif($ACTION_TYPE eq 'LOG'){
my	$LOG="[$now]-[API-LOG-$RESPONSE_TYPE]: $MESSAGE0\n";
print LOGFILE $LOG;	
print $LOG if $debug>=3;
}#ACTION TYPE LOG
elsif($ACTION_TYPE eq 'LOGDB'){
my $SQL=qq[INSERT INTO cc_transaction (`id`,`type`,`transaction_id`,`IMSI`,`status`,`info`) values(NULL,"$RESPONSE_TYPE","$MESSAGE0","$MESSAGE1","$MESSAGE2","$MESSAGE3")];
	&SQL($SQL) if $debug<=3;
	my $LOG='';
	$LOG="[$now]-[API-LOGDB]: $SQL\n" if $debug==4;
	$LOG="[$now]-[API-LOGDB]: $RESPONSE_TYPE $MESSAGE0\n" if $debug<=3;
	print LOGFILE $LOG if $debug<=4;
	print $LOG if $debug>=3;
}#ACTION TYPE LOGDB
#close LOGFILE;
}########## END sub response ####################################
#
########## LU_CDR ###############################################
## Process LU_CDR request
## 1) Checks if subscriber exist
## 2) If true - check active status and update to active
## 3) If false - return error respond
## Used by MOC_SIG to check subscriber status
#################################################################
sub LU_CDR{ 
use vars qw($new_sock $sql_selected $sql_aff_rows %Q %XML_KEYS);
my $SQL='';
my $IMSI=$_[0];
my $CHECK_ONLY=$_[1];
my $msisdn=uri_unescape($Q{msisdn});
$msisdn=~s/\+//;
&response('LOG','LU-REQUEST-IN',"$IMSI $msisdn");
#$SQL=qq[SELECT id, status, credit, phone, company_website from cc_card where useralias=$IMSI and phone=$msisdn];
$SQL=qq[SELECT id, status, credit, phone, company_website, traffic_target from cc_card where useralias="$IMSI" or firstname="$IMSI"];
my @sql_record=&SQL($SQL);
my ($sub_id,$sub_status,$sub_balance,$sub_msisdn,$host,$resale)=@sql_record;
if ($sub_id>0){#if found subscriber
switch ($sub_status){#sub status
		case 1 {#active already
			print $new_sock &response('LU_CDR','OK',"$XML_KEYS{cdr_id}",'1') if !$CHECK_ONLY;
			&response('LOGDB',"$XML_KEYS{request_type}","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'OK',"CHECK_ONLY $XML_KEYS{cdr_id}");
			return $sub_id;
			}#case 1
		case 2 {#new
			my $status=1;
			$status=9 if $resale>0;
			my $SQL=qq[UPDATE cc_card set status=$status, phone="$msisdn" where id=$sub_id];
			my $sql_result=&SQL($SQL);
			&response('LOGDB',"$XML_KEYS{request_type}","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'OK',"ACTIVATED $XML_KEYS{cdr_id}");
			&response('LOG','LU-MYSQL-SET-ACTIVE',"$sub_id") if $sql_result>0;
			&response('LOG','LU-MYSQL',"UPDATED $sql_aff_rows rows") if $sql_result>0;
			#SEND WELCOME MESSAGE WITH BALANCE
			## my $USSD_result=&SENDGET('SIG_SendUSSD','',$host,$Q{msisdn},'welcome');
			print $new_sock &response('LU_CDR','OK',"$XML_KEYS{cdr_id}",'1') if (!$CHECK_ONLY) and ($sql_result>0);
			print $new_sock &response('LU_CDR','ERROR','#'.__LINE__.'  CANT SET ACTIVE') if $sql_result<0;
			my $resale_result=&resale('LU',"$IMSI","$resale","$XML_KEYS{mcc}","$XML_KEYS{mnc}") if $resale ne '0';
			&response('LOG','LU-RESALE-RETURN',"$resale_result") if $resale ne '0';
			return $resale_result if $resale ne '0';
			return $sub_id if $sql_result>0;
			return -1 if $sql_result<0;
			}#case 2
		case 9 {#resale subscription
			print $new_sock &response('LU_CDR','OK',"$XML_KEYS{cdr_id}",'1') if !$CHECK_ONLY;
			&response('LOG','LU-RESALE',"$XML_KEYS{imsi}");
			my $resale_result=&resale('LU',"$IMSI","$resale","$XML_KEYS{mcc}","$XML_KEYS{mnc}") if !$CHECK_ONLY;
			&response('LOG','LU-RESALE-RETURN',"$resale_result");
			return $sub_id;
			}#case 9
		else {return -1}#unknown
					}#switch sub status
				}#if found
else{#else no sub_id=not found
print $new_sock &response('LU_CDR','ERROR','#'.__LINE__.'  SUBSCRIBER NOT FOUND') if !$CHECK_ONLY;
&response('LOG','LU-MYSQL-SUB-ID',"SUBSCRIBER NOT FOUND $IMSI");
&response('LOGDB','LU_CDR',"$Q{transactionid}","$IMSI",'ERORR','SUBSCRIBER NOT FOUND');
return -2;
}#else not found
}########## END sub LU_CDR ######################################
#
#
########## AMI ##################################################
## Process and originate call via AMI and/or database spool
## Accept action and command
## Usage AMI(<ACTION>,<COMMAND>)
## Returns success code 0 or error 1 
################################################################# 
sub AMI{
my $Action=$_[0];
my $CMD=$_[1];
my $unixtime=timelocal(localtime());
my ($MSISDN,$EXTEN,$CALLERID,$PEER)=split(':',$CMD);
&response('LOG','AMI-REQUESTED',@_) if $debug>=1;

switch ($Action){
	case 'login' {;}#deprecated by call_spool
	case 'orig' {;}#deprecated by call_spool
	case 'call_spool'{
#
our $uniqueid=$unixtime."-".int(rand(1000000));
my $entry_time="from_unixtime($unixtime)";
my $status='PENDING';
my $server_ip='localhost';
my $callback_time="from_unixtime($unixtime)";
$EXTEN=~s/\+//;
my $channel="SIP/$MSISDN\@$PEER";
my $context='a2billing-callback';
my $timeout='30000';
$MSISDN=~/(00000)(\d+)/;
my $variable="CALLED=$2,CALLING=$EXTEN,CBID=$uniqueid,LEG=$CALLERID";
my $account=$CALLERID;
#
my $SQL=qq[INSERT INTO `cc_callback_spool` VALUES (null,"$uniqueid", $entry_time, "$status", 'localhost', '1', '', '', '', $callback_time, "$channel", "$EXTEN", "$context", '1', '', '', "$timeout", "$CALLERID", "$variable", "$account", '', '', null, '1')];
#
my @sql_record=&SQL($SQL);
#
&response('LOG','AMI-CALL-SPOOL-UNIQUEID',"$uniqueid");
&response('LOG','AMI-CALL-SPOOL-RETURN',"$sql_record[0]");
return $sql_record[0];
	}#call_spool
	else {;}#no Action
}#switch Action
}########## END sub AMI #########################################
#
#
########## reuse_msrn #############################################
## Process MSRN reuse
## Accept IMSI
## Return MSRN or NULL
#################################################################
sub reuse_msrn{
my $query=$_[0];
&response('LOG','GET_MSRN-REQUEST',"REUSE $query");
my $SQL=qq[SELECT info from cc_transaction where type='SIG_GetMSRN' and status='RSP' and IMSI="$query" and date BETWEEN DATE_ADD(now(),INTERVAL -55 SECOND) and now()];
my @sql_record=&SQL($SQL);
my $REUSE_MSRN=$sql_record[0];
$REUSE_MSRN=0 if (($REUSE_MSRN eq '0E0')||($REUSE_MSRN eq ''));
#$REUSE_MSRN=0;
&response('LOG','GET_MSRN-REUSE-RETURN',"$REUSE_MSRN");
return $REUSE_MSRN;
}########## END sub reuse_msrn ####################################
#
#
########## AUTHENTICATION CALLBACK MOC_SIG ######################
## Processing CallBack request
## 1) Checks subscriber by LU_CDR
## 2) Checks subscribers balance and active status
## 3) If active and balance>1 request MSRN for subscribers IMSI
## Accept IMSI
## Return processing responds and originate call via AMI function
## Usage auth_callback_sig(<IMSI>)
################################################################# 
#
sub auth_callback_sig{ 
my $IMSI=$_[0];
my $LU=&LU_CDR($IMSI,'CHECK_ONLY');
&response('LOG','MOC-SIG-LU-SUB-CHECK',$LU);
#
if ($LU>0){#if subscriber exist and active, 0 - if resale
my $SQL=qq[SELECT id, status, credit, username, company_name, company_website, traffic_target from cc_card where useralias="$IMSI"];
my @sql_record=&SQL($SQL);
my ($sub_id,$sub_active,$sub_balance,$sub_cid,$sub_peer,$sub_sim_site,$resale)=@sql_record;
#
my $USSD=uri_unescape($Q{calldestination});
my $ussd=0;

if(($ussd=$USSD=~/(\*125\*275\*100\*)(\d+)#/)||($ussd=$USSD=~/(\*111\*)(\d+)#/)||($ussd=$USSD=~/(\*112\*)(\d+).*#/)){#if USSD callback
&response('LOG','MOC-SIG-SPOOL-REQUEST',"$2,$IMSI,$sub_id,$sub_active,$sub_balance,$sub_cid,$sub_peer,$sub_sim_site") if $resale eq '0';
my $result=&SPOOL($2,$IMSI,$sub_id,$sub_active,$sub_balance,$sub_cid,$sub_peer,$sub_sim_site) if $resale eq '0';
&response('LOG','MOC-SIG-RESALE-REQUEST',"CB,$IMSI,$resale,$2") if $resale ne '0';
$result=&resale('CB',"$IMSI","$resale","$2") if $resale ne '0';
return $result;
}elsif($ussd=$USSD=~/\*(\d{3}).?(.*)#/){#if USSD general
&response('LOG','MOC-SIG-USSD-REQUEST',"$1,$2,$IMSI,$sub_cid,$sub_balance") if $resale eq '0';
my $result=&USSD($1,$2,$IMSI,$sub_cid,$sub_balance) if $resale eq '0';
&response('LOG','MOC-SIG-USSD-REQUEST',"UD,$IMSI,$resale,$1,$2") if $resale ne '0';
$result=&resale('UD',"$IMSI","$resale","$1","$2") if $resale ne '0';
return $result;
}#elsif ussd
else{
&response('LOG','MOC-SIG-USSD-INCORRECT-REQUEST',"$USSD");
&response('LOGDB','USSD',"$Q{transactionid}","$IMSI",'ERROR',"$USSD");
print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"INCORRECT USSD REQUEST");
return -2;
}#incorrect ussd
}#if LU>0
else{#else LU<0
&response('LOGDB','auth_callback_sig',"$Q{transactionid}","$IMSI",'ERROR','SUBSCRIBER NOT FOUND');
return 'MOC-SIG-WARNING -1';
}#else LU<0
}## END sub AUTH_CALLBACK_SIG
#
#
############## SUB SPOOL ######################
## Spooling call
##
##############################################
sub SPOOL{
use vars qw($ERROR $uniqueid %Q $sql_aff_rows);
my ($dest,$IMSI,$sub_id,$sub_active,$sub_balance,$sub_cid,$sub_peer,$sub_sim_site)=@_;
my $msisdn=uri_unescape($Q{msisdn});
$msisdn=~s/\+//;
$dest=~s/\+//;
#
&response('LOG','MOC-SIG-CHECK-BALANCE-ACTIVE',"$sub_balance  $sub_active");
#
if (($sub_active==1)and($sub_balance>=1)){#if status 1 and balance >1
&response('LOGDB','auth_callback_sig',"$Q{transactionid}","$IMSI",'REQ CALL',"$msisdn to $dest");
&response('LOG','MOC-SIG-GET_MSRN-REQUEST',$IMSI);
# Get MSRN
my $msrn=&SENDGET('SIG_GetMSRN',"$IMSI",$sub_sim_site);
my $offline='OFFLINE' if $msrn eq 'OFFLINE';
$msrn=~s/\+//;
$msrn='00000'.$msrn if $sub_peer eq 'voicetrd';
#
&response('LOG','MOC_SIG-GET_MSRN-GOT',$msrn);
if (($msrn)and($dest)and(!$offline)){
# Call SPOOL
my $SPOOL_RESULT=&AMI('call_spool',"$msrn:$dest:$sub_cid:$sub_peer");
#
if($SPOOL_RESULT==1){
my $SQL=qq[SELECT request from cc_actions where id=71];
my @sql_record=&SQL($SQL);
$SQL="$sql_record[0]";
$SQL=~s/_FROMDEST_/$msrn/;
$SQL=~s/_TODEST_/$dest/;
my @sql_result=&SQL($SQL);
my $rate=substr($sql_result[0],0,6);
&response('LOG','MOC-SIG-GET-SPOOL',$sql_aff_rows);
print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"Please wait... Calling $dest. Rate $rate. Balance $sub_balance");
&response('LOGDB','auth_callback_sig',"$Q{transactionid}","$IMSI",'SPOOL',"$uniqueid");
return 'SPOOL SUCCESS 0';
}else{
	print $new_sock &response('auth_callback_sig','ERROR','#'.__LINE__.' CANT SPOOL CALL');
	&response('LOGDB','auth_callback_sig',"$Q{transactionid}","$IMSI",'ERROR','CANT SPOOL CALL');
return 'SPOOL ERROR -1';
}#else CANT SPOOL
}#if msrn and dest
else{#else not msrn and dest
	#print $new_sock &response('auth_callback_sig','ERROR','#'.__LINE__.' CANT GET MSRN OR DEST');
	&response('LOGDB','auth_callback_sig',"$Q{transactionid}","$IMSI",'ERROR',"CANT GET MSRN: $offline $ERROR");
	print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"Please try to change roaming operator. Your number is offline for us");
return 'SPOOL ERROR -2';	
}#else not msrn and dest
}#if Status 1 and Balance >1
else{#else Status !=1 and Balance <1  
if (eval($sub_balance)<1){
print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},'NO BALANCE');
&response('LOGDB','auth_callback_sig',"$Q{transactionid}","$IMSI",'ERROR','NO BALANCE');
return 'SPOOL WARNING -3';
}#if BALANCE
elsif($sub_active!=1){
print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},'SUBSCRIBER NOT ACTIVE');
&response('LOGDB','auth_callback_sig',"$Q{transactionid}","$IMSI",'ERROR','SUBSCRIBER NOT ACTIVE');
return 'SPOOL WARNING -4';
}#elsif NOT ACTIVE
}#else Balance<1
}########## END SPOOL ##########################
#
#
############# SUB USSD #########################
## Processing USSD requests
##
###############################################
sub USSD{
my($ussd_code,$ussd_subcode,$IMSI,$sub_cid,$sub_balance)=@_;
switch ($ussd_code){
###
	case "000"{#SUPPORT request
&response('LOG','MOC-SIG-USSD-SUPPORT-REQUEST',"$ussd_code");
&response('LOGDB','USSD',"$Q{transactionid}","$IMSI",'OK',"$ussd_code");
print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"Your Request Registered");
return "USSD 0";
	}#case 000
###
	case "100"{#MYNUMBER request
&response('LOG','MOC-SIG-USSD-MYNUMBER-REQUEST',"$ussd_code");
&response('LOGDB','USSD',"$Q{transactionid}","$IMSI",'OK',"$ussd_code");
my $number=uri_unescape("$Q{msisdn}");
print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"Your Number: $number. Your Personal Code: $sub_cid");
return "USSD 0";
	}#case 100
###
	case "110"{#IMEI request
&response('LOG','MOC-SIG-USSD-IMEI-REQUEST',"$ussd_code");
&response('LOGDB','USSD',"$Q{transactionid}","$IMSI",'OK',"$ussd_code $ussd_subcode");
$ussd_subcode=~/(\d+)\*(\w+)\*(\d+)/;
print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"Your IMEI: $1");
my $SQL=qq[UPDATE cc_card set address="$1 $2" where useralias="$IMSI" or firstname="$IMSI"];
my $SQL_result=&SQL($SQL);
return "USSD $SQL_result";
	}#case 110
###
case "122"{#SMS request
&response('LOG','MOC-SIG-USSD-SMS-REQUEST',"$ussd_code");
&response('LOGDB','USSD',"$Q{transactionid}","$IMSI",'REQ',"$ussd_code $ussd_subcode");
my $SMS_result=&SMS("$ussd_subcode",$Q{transactionid});
my $SMS_response='';
switch ($SMS_result){
	case 1 {#one message sent
	$SMS_response="Your message was sent";
	}#case 1
	case 2 {#one message sent
	$SMS_response="Please wait while sending message...";
	}#case 2
	else{#unknown result
	$SMS_response="UNKNOWN";
	}#else
}#end switch sms result
	&response('LOG','MOC-SIG-USSD-SMS-RESULT',"$SMS_result");
	&response('LOGDB','USSD',"$Q{transactionid}","$IMSI",'RSP',"$SMS_result");
	print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"$SMS_response");
	return "USSD $SMS_result";
	}#case 122
###
	case "123"{#voucher refill request
&response('LOG','MOC-SIG-USSD-VAUCHER-REQUEST',"$ussd_subcode");
&response('LOGDB','USSD',"$Q{transactionid}","$IMSI",'REQ',"$ussd_subcode");
my $voucher_add=&voucher($IMSI,$sub_cid,$ussd_subcode);
switch($voucher_add){
case '-1'{
&response('LOG','MOC-SIG-USSD-VOUCHER-ERROR',"NOT VALID");
&response('LOGDB','USSD',"$Q{transactionid}","$IMSI",'ERROR',"$ussd_subcode NOT VALID");
print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"VOUCHER NOT VALID");
return 'USSD -1';
}#case -1
case '-2'{
&response('LOG','MOC-SIG-USSD-VOUCHER-ERROR',"CANT REFILL");
&response('LOGDB','USSD',"$Q{transactionid}","$IMSI",'ERROR',"$ussd_subcode CANT REFILL");
print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"CANT REFILL BALANCE");
return 'USSD -2';
}#case -2
else{
&response('LOG','MOC-SIG-USSD-VOUCHER-SUCCESS',"$ussd_subcode");
&response('LOGDB','USSD',"$Q{transactionid}","$IMSI",'OK',"$ussd_code $ussd_subcode");
print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"YOUR BALANCE $sub_balance UPDATED TO $voucher_add\$");
return 'USSD 0';
}#switch else
}#switch voucher
	}#case 123
###
	case "124"{#balance request
&response('LOG','MOC-SIG-USSD-BALANCE-REQUEST',"$ussd_code");
&response('LOGDB','USSD',"$Q{transactionid}","$IMSI",'OK',"$ussd_code");
print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"Balance $sub_balance");
return 'USSD 0';
	}#case 124
###
	case "126"{#RATES request
&response('LOG','MOC-SIG-USSD-RATES',"$ussd_code $ussd_subcode");
&response('LOGDB','USSD',"$Q{transactionid}","$IMSI",'OK',"$ussd_code $ussd_subcode");
my $msrn=&SENDGET('SIG_GetMSRN',"$IMSI",'','','',"$ussd_code");
my $SQL=qq[SELECT request from cc_actions where id=71];
my @sql_record=&SQL($SQL);
$SQL="$sql_record[0]";
$ussd_subcode=~/(.?)(\d{12})/;
$SQL=~s/_FROMDEST_/$2/;
$SQL=~s/_TODEST_/$msrn/;
my @sql_result=&SQL($SQL);
my $rate=substr($sql_result[0],0,6);
&response('LOG','MOC-SIG-USSD-RATES-RETURN',"$rate");
print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"Rate from $msrn to $ussd_subcode is $rate");
return "USSD 0";
	}#case 126
###
	case "127"{#CFU request
&response('LOG','MOC-SIG-USSD-CFU-REQUEST',"$ussd_code $ussd_subcode");
&response('LOGDB','USSD',"$Q{transactionid}","$IMSI",'REQ',"$ussd_code $ussd_subcode");
if ($ussd_subcode=~/(.?)(380\d{9})/){#if number length 12 digits
my $SQL=qq[UPDATE cc_card set fax="$2" where useralias="$IMSI" or firstname="$IMSI"];
my $SQL_result=&SQL($SQL);
print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"Please call **21*+380445945754# from $2 to activate. Call ##21# to deactivate") if $SQL_result==1;
&response('LOGDB','USSD',"$Q{transactionid}","$IMSI",'OK',"$ussd_code $ussd_subcode $SQL_result") if $SQL_result==1;
print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"Sorry, number $2 already in use.") if $SQL_result!=1;
&response('LOGDB','USSD',"$Q{transactionid}","$IMSI",'RSP',"Error: $2 already in use $SQL_result") if $SQL_result != 1;
return "USSD $SQL_result";
}else{ #if number length
&response('LOGDB','USSD',"$Q{transactionid}","$IMSI",'RSP',"Error: Incorrect number $2");
print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"Incorrect number $2. Please use format: 380 XX XXX XXXX");
return 'USSD -1';
}#end else if number length
	}#case 127
###
else{#switch ussd code
&response('LOG','MOC-SIG-USSD-UNKNOWN-REQUEST',"$ussd_code");
&response('LOGDB','USSD',"$Q{transactionid}","$IMSI",'ERROR',"$ussd_code");
print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"UNKNOWN USSD REQUEST");
return 'USSD -3';
}#end else switch ussd code (no code defined)
}#end switch ussd code
}## END sub USSD ###################################
#
#
########### VOUCHER ################################
## Process voucher refill request 
##
###################################################
sub voucher{
my ($IMSI,$USERNAME,$VOUCHER)=@_;
my $SQL=qq[SELECT credit from cc_voucher where voucher="$VOUCHER" and activated='t' and expirationdate>now() and currency='USD' and used=0];
my @sql_result=&SQL($SQL);
if ($sql_result[0]>=1){
my $refill=$sql_result[0];
$SQL=qq[UPDATE cc_voucher set usedate=now(),activated='f', used=1,usedcardnumber="$USERNAME" where voucher="$VOUCHER"];
my $sql_result=&SQL($SQL);
$SQL=qq[UPDATE cc_card set credit=credit+$refill where (useralias="$IMSI" or firstname="$IMSI") and username="$USERNAME"];
 $sql_result=&SQL($SQL);
if ($sql_result>0){
$SQL=qq[SELECT id from cc_card where (useralias="$IMSI" or firstname="$IMSI") and username="$USERNAME"];
my @sql_result=&SQL($SQL);
my $sub_id=$sql_result[0];
$SQL=qq[INSERT INTO cc_logpayment (`payment`,`card_id`,`description`) values ($refill,$sub_id,$VOUCHER)];
$sql_result=&SQL($SQL);
return $refill;#refill balance ok
}else{return -2}#cant refill balance
}else{return -1}#no voucher found
}## END SUB VAUCHER #############################
#
########## CLOSE PROXY REQUEST #################################
#
########### SENDGET #############################################
## Process all types of requests
## Accept Type, IMSI, Message
## Return MSRN or NULL, Status
#################################################################
sub SENDGET{
use vars qw($curl);
#
my $URL='';
my $msrn=0;
our $transaction_id=timelocal(localtime());
my ($code,$query,$host,$msisdn,$message_code,$options,$options1)=@_;
#
#$host='http://127.0.0.1/cgi-bin/get.cgi?' if !$host;
$host='http://api2.globalsimsupport.com/WebAPI/C9API.aspx?' if !$host;
#
my $SQL=qq[SELECT request, from_unixtime($transaction_id) FROM cc_actions where code="$code"];
my @sql_record=&SQL($SQL);
#
my $URL_QUERY=$sql_record[0];
my $timestamp=uri_escape($sql_record[1]);
#
if ($message_code){#if message text code is defined
my $SQL=qq[SELECT response FROM cc_actions where code="$message_code" or id="$message_code"];
my @sql_record=&SQL($SQL);
our $message=$sql_record[0];
$message=uri_escape($message) if $code ne 'SIG_SendResale';
}#if message_code
#
switch ($code){
	case "SIG_GetMSRN" {
		$msrn=&reuse_msrn($query) if $options eq '126';
		&response('LOG',"$code-REUSE-GET","$msrn");
		$URL=qq[transaction_id=$transaction_id&query=$query&$URL_QUERY&timestamp=$timestamp] if $msrn==0;
		&response('LOG',"$code-URL-SET","$URL");
	}#case getmsrn
	case "SIG_SendUSSD" {
		use vars qw($message);
		$URL=qq[transaction_id=$transaction_id&ussdto=$msisdn&$URL_QUERY&&message=$message&timestamp=$timestamp] if $message_code;
	}#case sendussd
	case "SIG_SendSMS" {
		$URL=qq[transaction_id=$transaction_id&smsto=%2B$query&smsfrom=ruimtools&$URL_QUERY&msisdn=$options1&message=$options&timestamp=$timestamp];
	}#case sendsms
	case "SIG_SendResale" {
		&response('LOG',"$code-PARAM_GET","$query,$host,$msisdn,$message_code,$options,$options1");
		$URL_QUERY=~s/_TIMESTAMP_/$timestamp/;
		$URL_QUERY=~s/_TRANSID_/$transaction_id/;
		$message=~s/_IMSI_/$query/;
		$message=~s/_ACTIVE_/$options/;
		$message=~s/_MNC_/$options/;
		$message=~s/_MCC_/$options1/;
		$message=~s/_DEST_/$options/;
		$message=~s/_CODE_/$options/;
		$message=~s/_SUBCODE_/$options1/;
		$URL=qq[$URL_QUERY;$message];
		&response('LOG',"$code-URL-SET","$URL");
	}#case sendresale
	else{
		return 0;
	}#else switch code
}#switch code
#
my $SENDGET=qq[$host$URL] if $URL;
#
&response('LOG',"SENDGET-$code-URL","$SENDGET") if $debug>=3;
&response('LOGDB',"$code","$transaction_id","$query",'REQ',"$SENDGET $msrn"); 
#
&response('LOG',"SENDGET-$code-URL","$curl $SENDGET");
my @XML=`$curl "$SENDGET"` if $URL;
#
if (@XML){
&response('LOG',"$code-RESPOND","@XML") if $debug>=3;
my $SENDGET_result=&XML_PARSE("@XML",$code);
&response('LOGDB',$code,"$transaction_id","$query",'RSP',"$SENDGET_result") if $SENDGET_result;
&response('LOGDB',$code,"$transaction_id","$query",'ERROR','SENDGET NO RESPONDS') if !$SENDGET_result;
return $SENDGET_result;
}#if curl return
elsif($msrn){
&response('LOG',"$code-REQUEST","REUSE $msrn");
&response('LOGDB',$code,"$transaction_id","$query",'REUSE',"$msrn");
return $msrn;
}#elsif msrn
else{# timeout
&response('LOG',"$code-REQUEST","Timed out 5 sec with socket");
&response('LOGDB',$code,"$transaction_id","$query",'ERROR','Timed out 5 sec with socket');
return 0;
}#end else
}########## END sub GET_MSRN ####################################
#
#
##### RC_API_CMD ################################################
## Process all types of commands to RC
## Accept CMD, Options
## Return message
#################################################################
sub rc_api_cmd{
my $code;
my $sub_code;
my $options;
my $imsi=$_[0];
$code=$Q{'code'};
$sub_code=$Q{'sub_code'};
$options=$Q{'options'};
switch ($code){
	case 0 {#PING
		&response('LOG','RC-API-CMD',"PING");
		&response('LOGDB','CMD',"$Q{transactionid}","$imsi",'OK',"PING $code");
		print $new_sock &response('rc_api_cmd','OK',$Q{transactionid},"PING OK");
		return 'CMD 0';
		}#case 0
	case 1 {#GET_MSRN
		my $auth_result=&auth($Q{auth_key},'RESALE',$Q{reseller},'-md5');
		if ($auth_result==0){
		&response('LOG','RC-API-CMD',"GET_MSRN");
		&response('LOGDB','CMD',"$Q{transactionid}","$imsi",'OK',"GET_MSRN $code $Q{auth_key}");
		my $resale_TID="$Q{transactionid}";
		my $msrn=&SENDGET('SIG_GetMSRN',"$imsi");
		&bill_resale($Q{auth_key},53);
		print $new_sock &response('rc_api_cmd','OK',$resale_TID,"$msrn") if $options ne 'cleartext';
		$msrn=~s/\+// if $options eq 'cleartext';
		print $new_sock $msrn if $options eq 'cleartext';
		return 'CMD 1';
		}#if auth
		else{
		&response('LOGDB','CMD',"$Q{transactionid}","$imsi",'ERROR',"NO AUTH $auth_result $Q{auth_key}");
		print $new_sock &response('rc_api_cmd','OK',$Q{transactionid},"NO AUTH");
		return 'CMD 1 NO AUTH';
		}#else
		}#case 1
	case 2 {#GET STAT
		&response('LOG','RC-API-CMD',"GET_STAT");
		&response('LOGDB','CMD',"$Q{transactionid}","$imsi",'OK',"GET_STAT $code $sub_code");
		my $SQL=qq[SELECT request from cc_actions where id="$sub_code"];
		my @sql_record=&SQL($SQL);
		$SQL="$sql_record[0]";
		$SQL=~s/_FROMDEST_/$Q{msisdn}/ if $sub_code==71;
		$SQL=~s/_TODEST_/$Q{options}/ if $sub_code==71;
		$SQL=~s/_CARD_/$Q{card_number}/ if $sub_code==76;
		$SQL=~s/_RESELLER_/$Q{reseller}/ if $sub_code==77;
		$SQL=~s/_TYPE_/$Q{options}/ if $sub_code==77;
		@sql_record=&SQL($SQL);
		my $stat_result=$sql_record[0];
		$stat_result=substr($stat_result,0,6) if $sub_code==71;
		print $new_sock &response('rc_api_cmd','OK',$Q{transactionid},"$stat_result");
		&response('LOG','RC-API-CMD-STAT',"$stat_result");
		return 'CMD 2';
		}#case 2
	case 3 {#SEND_USSD
		&response('LOG','RC-API-CMD',"SEND_USSD");
		&response('LOGDB','CMD',"$Q{transactionid}","$imsi",'REQ',"SEND_USSD $code");
		my $USSD_result=&SENDGET('SIG_SendUSSD','','http://api2.globalsimsupport.com/WebAPI/C9API.aspx?',$Q{msisdn},$sub_code);
		&response('LOG','RC-API-CMD',"SEND_USSD $USSD_result");
		&response('LOGDB','CMD',"$Q{transactionid}","$imsi",'OK',"SEND_USSD_RESULT $USSD_result");
		print $new_sock &response('rc_api_cmd','OK',$Q{transactionid},"$Q{msisdn} $USSD_result");
		return 'CMD 3';
		}#case 3
		else {
		&response('LOG','RC-API-CMD-UNKNOWN',"$code");
		&response('LOGDB','CMD',"$Q{transactionid}","$Q{imsi}",'ERROR',"$code");
		print $new_sock &response('rc_api_cmd','OK',$Q{transactionid},"UNKNOWN CMD REQUEST");
		return 'CMD -1';
		}#else switch code
		}#switch code
}##### END sub RC_API_CMD ########################################
#
##### RESALE ################################################
## Process resale request
## Accept request type, imsi, reseller auth_key, options
## Return message to subscriber
#################################################################
sub resale{
use vars qq(%Q);
my ($req_type,$imsi,$resale,$options,$options1)=@_;
my $SQL=qq[SELECT lastname, address from cc_agent where firstname="$resale"];
my @sql_record=&SQL($SQL);
my ($auth_key,$cgi)=@sql_record;

if (($auth_key)&&($cgi)){
switch ($req_type){
	case 'LU'{
		&response('LOGDB',"$req_type","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'REQ',"RESALE $resale");
		my $SENDGET_result=&SENDGET('SIG_SendResale',$imsi,$cgi,'','73',$options,$options1);
		&bill_resale($resale,73);
		&response('LOGDB',"$req_type","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'RSP',"RESALE $SENDGET_result");
		return $SENDGET_result;# OK or <error code>
		}#case LU
	case 'CB'{
		&response('LOG','RESALE-REQUEST-TYPE',"$req_type $imsi,$cgi,,74,$options");
		&response('LOGDB',"$req_type","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'REQ',"RESALE $resale");
		my $SENDGET_result=&SENDGET('SIG_SendResale',$imsi,$cgi,'','74',$options);
		&bill_resale($resale,74);
		print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"$SENDGET_result");
		&response('LOGDB',"$req_type","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'RSP',"RESALE $SENDGET_result");
		return $SENDGET_result;# OK or <error code>
		}#case CB
	case 'UD'{
		&response('LOG','RESALE-REQUEST-TYPE',"$req_type $imsi,$cgi,'','75',$options,$options1");
		&response('LOGDB',"$req_type","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'REQ',"RESALE $resale");
		#$code,$query,$host,$msisdn,$message_code,$options,$options1
		my $SENDGET_result=&SENDGET('SIG_SendResale',$imsi,$cgi,'','75',$options,$options1);
		&bill_resale($resale,75);
		&response('LOGDB',"$req_type","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'RSP',"RESALE $SENDGET_result");
		print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"$SENDGET_result");
		return $SENDGET_result;# OK or <error code>
		}#case CB
	else {
		&response('LOG','RESALE-REQUEST-TYPE',"UNKNOWN $req_type");
		}#else
}#switch req_type
}#if auth_key and cgi
else{#not found resaler or no cgi
&response('LOG','RESALE-AUTH-KEY',"NOT FOUND $auth_key");
print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"Authentification failed");
return -1;
}#else
}# END sub RESALE #
#
sub bill_resale{
my ($reseller,$sig_id)=@_;
&response('LOG','RESALE-BILLING',"$reseller,$sig_id");
my $SQL=qq[SELECT resale_price from cc_actions where id=$sig_id];
my @sql_record=&SQL($SQL);
my $resale_price=$sql_record[0];
if ($resale_price>0){#if found sig_id
$SQL=qq[UPDATE cc_agent set credit=credit+$resale_price where firstname="$reseller"];
my $sql_result=&SQL($SQL);
&response('LOG','RESALE-BILLING-RESULT',"OK $sql_result") if $sql_result>0;
&response('LOG','RESALE-BILLING-RESULT',"ERROR $sql_result") if $sql_result<=0;
}else{#sig_id not found
&response('LOG','RESALE-BILLING-PRICE',"ERROR $resale_price");
}#else if resale_price
}# END bill_resale #############
#
sub auth{
use vars qw(%Q $REMOTE_HOST);
my ($KEY,$type,$agent,$dgst,$ikey)=@_;
my $md5=qq[echo '_KYES_' |/usr/bin/openssl dgst $dgst];
my $md5_result='';
our ($reseller_name,$public_key,$auth_key);
&response('LOG',"RC-API-$type-AUTH","$REMOTE_HOST:$agent:$KEY:$dgst");
switch ($type){#select auth type
	case "RESALE"{#resale auth
my $SQL=qq[SELECT login,firstname,lastname from cc_agent where firstname="$KEY" and active=1];
my @sql_record=&SQL($SQL);
($reseller_name,$public_key,$ikey)=@sql_record;
$md5=~s/_KYES_/$REMOTE_HOST$reseller_name$public_key/;
	}#case resale
###
	case "PAYMNT"{#paymnt auth
my $SQL=qq[SELECT name, auth_key, rate from cc_epaymnter where host="$agent"];
my @sql_record=&SQL($SQL);
(our $mch_name, my $auth_key, our $rate)=@sql_record;
$md5=~s/_KYES_/$KEY$auth_key/;
}#case paymnt
else{
&response('LOG',"RC-API-AUTH-RETURNED","Error: UNKNOWN TYPE $type");
}#end else switch type
}#end switch type 
#
&response('LOG',"RC-API-$type-MD5","$REMOTE_HOST:$agent:$KEY");
$md5_result=`$md5`;
chomp($md5_result);
&response('LOG',"RC-API-$type-MD5-RESULT","$md5 $md5_result") if $debug>=3;
#
&response('LOG',"RC-API-$type-KEYS-CHECK","$md5_result eq $ikey") if $debug>=3;
if ($md5_result eq $ikey){#if md5 OK
&response('LOG','RC-API-AUTH',"OK");
return 0;
}#end if md5
else{#md5 != auth_key
&response('LOG','RC-API-AUTH',"NO AUTH");
return -1;
	}#else if auth OK
}#END sub auth ##
#
sub PAYMNT{
use vars qw($REMOTE_HOST);
my @TR= keys %{ $REQUEST->{payment}{transactions}{transaction} };
our $SQL_T_result;
my $SQL='';
$SQL=qq[INSERT INTO cc_epayments (`payment_id`, `ident`,`status`,`amount`,`currency`,`timestamp`,`salt`,`sign`,`transactions_ids`) values("$REQUEST->{payment}{id}","$REQUEST->{payment}{ident}","$REQUEST->{payment}{status}","$REQUEST->{payment}{amount}","$REQUEST->{payment}{currency}","$REQUEST->{payment}{timestamp}","$REQUEST->{payment}{salt}","$REQUEST->{payment}{sign}","@TR")];
my $SQL_P_result=&SQL($SQL);
&response('LOG','PAYMNT-EPMTS-SQL-RESULT',"$SQL_P_result");
## AUTH
&response('LOG','PAYMNT-AUTH-REQ',"$REQUEST->{payment}{salt},PAYMNT,$REMOTE_HOST,-sha512,$REQUEST->{payment}{sign}");
if (&auth($REQUEST->{payment}{salt},'PAYMNT',$REMOTE_HOST,"-sha512",$REQUEST->{payment}{sign})==0){
&response('LOG','PAYMNT-TR-RESULT',"@TR");
use vars qw($rate $mch_name);
foreach my $tr (@TR){
$REQUEST->{payment}{transactions}{transaction}{$tr}{info}=~m/(\w?):(.*)}/;
my $CARD_NUMBER=$2;
my $SQL='';
$SQL=qq[INSERT INTO cc_epayments_transactions (`id`,`mch_id`, `srv_id`,`amount`,`currency`,`type`,`status`,`code`, `desc`,`info`) values("$tr","$REQUEST->{payment}{transactions}{transaction}{$tr}{mch_id}","$REQUEST->{payment}{transactions}{transaction}{$tr}{srv_id}","$REQUEST->{payment}{transactions}{transaction}{$tr}{amount}","$REQUEST->{payment}{transactions}{transaction}{$tr}{currency}","$REQUEST->{payment}{transactions}{transaction}{$tr}{type}","$REQUEST->{payment}{transactions}{transaction}{$tr}{status}","$REQUEST->{payment}{transactions}{transaction}{$tr}{code}","$REQUEST->{payment}{transactions}{transaction}{$tr}{desc}","$CARD_NUMBER")];
$SQL_T_result=&SQL($SQL);
&response('LOG','PAYMNT-TR-SQL-RESULT',"$SQL_T_result");
if ($REQUEST->{payment}{transactions}{transaction}{$tr}{type}==11){#if debited transaction
my $amount=$REQUEST->{payment}{transactions}{transaction}{$tr}{amount}/$rate;
$SQL=qq[INSERT into `msrn`.`cc_epayment_log` (`amount`, `paymentmethod`, `cardid`, `cc_owner`) values ( round($amount,2), "$mch_name", (select id from cc_card where username="$CARD_NUMBER"),"$tr")];
my $SQL_debit_result=&SQL($SQL);
&response('LOG','PAYMNT-TR-DEBIT-SQL-RESULT',"$SQL_debit_result");
}#end if debited
}#foreach tr
}#end if auth
else{#else if auth
$SQL_T_result="-1 NO AUTH";
&response('LOG','PAYMNT-AUTH-RESULT',"NO AUTH");
}#end esle if auth
#use vars qw($SQL_T_result);
&response('LOGDB',"PAYMNT","$REQUEST->{payment}{id}",0,'RSP',"$SQL_T_result @TR");
print $new_sock "200 $SQL_T_result";
return $SQL_T_result;
}# END sub PAYMNT
#
### sub LOCATION HISTORY ##
sub LU_H{
use vars qw(%Q);
my $SQL='';
if (($Q{imsi})&&($Q{mnc})&&($Q{mcc})&&($Q{request_type})){#if signaling request
$SQL=qq[UPDATE cc_card set country=(select countrycode from cc_country, cc_mnc where countryname=country and mcc="$Q{mcc}" limit 1), zipcode="$Q{mcc} $Q{mnc}", tag=(select mno from cc_mnc where mnc="$Q{mnc}" and mcc="$Q{mcc}") where useralias="$Q{imsi}" or firstname="$Q{imsi}"];
my $sql_result=&SQL($SQL);
return $sql_result; 
}#end if signaling
}# END sub LU_H
#
### sub USSD_SMS #
sub SMS{
use vars qw(%Q);
my ($ussd_subcode,$sms_id)=@_;
my $flag;
my $sms_opt;
my $sms_dest;
my $sms_text;
&response('LOG','SMS-REQ',"$ussd_subcode");
$ussd_subcode=~/(\d{2})\*(.+)/;
$flag=$1;
$sms_opt=$2;
$flag=~/(\d{1})(\d{1})/;
if ($1==1){#if first page
$sms_opt=~/(\D?)(\d{10,})\*(\w+)/;
$sms_dest=$2;
$sms_text=$3;
}else{#else next page
$sms_dest="multipage";
$sms_text=$sms_opt;
}#if first page
#$sms_text=~s/00//g; -- save full ucs2
my $SQL=qq[SELECT request FROM cc_actions where code="get_sms_text"];
my @sql_record=&SQL($SQL);
&response('LOG','SMS-REQ',"$flag,$sms_dest");
$SQL=qq[INSERT INTO cc_sms (`id`,`src`,`dst`,`flag`,`text`) values ("$sms_id","$Q{msisdn}","$sms_dest","$flag","$sms_text")];
my $sql_result=&SQL($SQL);
&response('LOG','SMS-REQ',"$sql_result");
if ($sql_result>0){#if insert ok
$flag=~/(\d{1})(\d{1})/;
my $page=$1;
my $num_page=$2;
if ($num_page==$page){#if last multipage
$SQL=qq[$sql_record[0]];
$SQL=~s/_SRC_/$Q{msisdn}/;
$SQL=~s/_FLAG_/$num_page/;
my @sql_result=&SQL($SQL);
$sms_text=$sql_result[0];
$sms_dest=$sql_result[1];
#$SQL="SELECT X'$sms_text'";
#@sql_result=&SQL($SQL);
&response('LOG','SMS-ENC-RESULT',"$sms_text");
my $gsm0338=encode("gsm0338", $sql_result[0]);    # loads Encode::GSM0338 implicitly
&response('LOG','SMS-ENC-RESULT-GSM',"$gsm0338");
my $utf8=decode("gsm0338", $gsm0338);
$utf8=uri_escape($utf8);
&response('LOG','SMS-ENC-RESULT-UTF',"$utf8");
$sms_text=$utf8;
my $sms_from=uri_unescape($Q{msisdn});
$sms_from=~s/\+//;
&response('LOG','SMS-TEXT-ENC-RESULT',"$#sql_result");
&response('LOG','SMS-SEND-PARAM',"'SIG_SendSMS',$sms_dest,'','ruimtools','',$sms_text,$sms_from");
&response('LOG','SMS-SEND-CMD',"SENDGET('SIG_SendSMS',$sms_dest,'','ruimtools','',$sms_text,$sms_from)");
#my $sms_result=&SENDGET('SIG_SendSMS',$sms_dest,'','ruimtools','',$sms_text,$sms_from);
my $sms_result=1;
$SQL=qq[UPDATE cc_sms set status=$sms_result where src="$Q{msisdn}" and flag like "%$num_page" and status=0];
my $sql_update_result=&SQL($SQL);
return $sms_result;
}#if num_page==page
else{#else multipage
return 2;
}#end else multipage
	}#if insert
	else{#else no insert
return -1;
	}#end else
}# END sub USSD_SMS
#
&response('LOG','SOCKET',"CLOSE $new_sock ##################################################");
$new_sock->shutdown(2);
################################################################
}#new_sock
}#while(1)
}#until exit 
######### END #################################################
