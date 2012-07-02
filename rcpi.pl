#!/usr/bin/perl
#/opt/local/bin/perl -T
#
########## VERSION AND REVISION ################################
## Copyright (C) 2012, RuimTools denis@ruimtools.com
##
my $REV='API Server 020712rev.33.5 HFX-576';
##
#################################################################
## 
########## MODULES ##############################################
use DBI;
use Data::Dumper;
use IO::Socket;
use IO::Select;
use XML::Simple;
use Digest::SHA qw(hmac_sha512_hex);
use URI::Escape;
use LWP::UserAgent;
use Switch;
use POSIX;
use Time::Local;
use Time::HiRes qw(gettimeofday);
use IO::File;
use Encode;
use warnings;
use strict;
no warnings 'once';
########## END OF MODULES #######################################
#
#################################################################
# MAKE FORK AND CHROOT
#################################################################
#chroot("/opt/ruimtools/") or die "Couldn't chroot to /opt/ruimtools: $!";
our $pid = fork;
exit if $pid;
die "Couldn't fork: $!" unless defined($pid);
POSIX::setsid() or die "Can't start a new session: $!";
my $PIDFILE = new IO::File;
$PIDFILE->open(">/opt/ruimtools/tmp/rcpi.pid");
print $PIDFILE $$;
$PIDFILE->close();
###############################################################
#
###############################################################
# SIG handle to reload configuration kill -HUP
###############################################################
#$SIG{INT} = $SIG{TERM}= 
$SIG{HUP} = \&phoenix;
# trap $SIG{PIPE}
sub phoenix {
print("RELOAD CONFIGURATION...");
my $SELF = $0;   # needs full path
exec($SELF) or die "Couldn't restart: $!\n";
}
###############################################################
#
########## DEBUG OPTIONS ######################################
# 0 - off all logs
# 1 - print INFO to LOG_FILE
# 2 - print INFO&SQL to LOG_FILE
# 3 - print INFO&DEBUG&SQL to STDOUT&LOG_FILE
# 4 - print to all STDOUT&LOG_FILE
# *All transactions will always store in DB
# **Default is 2
#
if(@ARGV){our $debug=$ARGV[0]}else{use vars qw($debug );$debug=2}
#################################################################
#
########## LOG FILE #############################################
our $LOGFILE = IO::File->new("/opt/ruimtools/log/rcpi.log", "a+");
#
########## CONFIGURATION FOR MAIN SOCKET ########################
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
# Multiplexing sockets handlers
#################################################################
#
our $sock = new IO::Socket::INET (LocalHost => $HOST,LocalPort => $PORT,Proto => 'tcp',Listen => 32,ReuseAddr => 1,);
our $read_set = new IO::Select($sock); 
our $new_sock;
#
while(1) {#forever
		my ($read_handle_set) = IO::Select->select($read_set, undef, undef, undef);
		#while(my @ready = $read_set->can_read) {
		foreach $new_sock (@$read_handle_set) { 
			if ($new_sock == $sock) {
				my $new = $new_sock->accept();
				$read_set->add($new);
				print "RUIMTOOLS-$REV\n";
			}else {#processing 
					while(our $PROXY_REQUEST=<$new_sock>){
						if ($PROXY_REQUEST =~/897234jhdln328sLUV/){
							our $INNER_TID;
							my ($s, $usec) = gettimeofday();my $format = "%06d";$usec=sprintf($format,$usec);$INNER_TID=$s.$usec;
							&response('LOG',"API-SOCKET-OPEN","##################################################");
							&response('LOG','SOCKET',"OPEN $new_sock");
							&main();
							&response('LOG','SOCKET',"CLOSE $new_sock");
							&response('LOG',"API-SOCKET-CLOSE","##################################################");
							$read_set->remove($new_sock);close($new_sock);
						}else{ 
							$read_set->remove($new_sock);close($new_sock);
						}#else closed socket
				}#while
			}#else processing
		}#foreach
	#}#while ready
} #while(1)
###############################################################
#
########## MAIN #################################################
## Main procedure to control all functions
#################################################################
sub main{
use vars qw($PROXY_REQUEST $INNER_TID $LOGFILE $new_sock);
our $lwp = LWP::UserAgent->new;
if ($PROXY_REQUEST ne 'EMPTY'){
	our %XML_KEYS=&XML_PARSE($PROXY_REQUEST,'PROXY');
	my $qkeys= keys %XML_KEYS;
	&response('LOG','MAIN-XML-PARSE-RETURN',$qkeys);
		if ($qkeys){#if kyes>0
		my $IN_SET='';
		$IN_SET="$XML_KEYS{msisdn}:$XML_KEYS{mcc}:$XML_KEYS{mnc}:$XML_KEYS{tadig}" if  $XML_KEYS{msisdn};
		$IN_SET=$IN_SET.":$XML_KEYS{code}:$XML_KEYS{sub_code}" if $XML_KEYS{code};
		$IN_SET=$IN_SET."$XML_KEYS{ident}:$XML_KEYS{amount}" if $XML_KEYS{salt};
		$IN_SET=$IN_SET."$XML_KEYS{TotalCurrentByteLimit}" if $XML_KEYS{SessionID};
		$XML_KEYS{transactionid}=$XML_KEYS{SessionID} if $XML_KEYS{SessionID};
		$XML_KEYS{imsi}=$XML_KEYS{GlobalIMSI} if $XML_KEYS{SessionID};
		&response('LOGDB',"$XML_KEYS{request_type}","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'IN',$IN_SET);
		#Get action type
		my $ACTION_TYPE_RESULT=&GET_TYPE($XML_KEYS{request_type});
			eval {#save subref
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
	else {#else switch action_type_result
		use vars qw($subref);
		eval {#save subroutine
		our $ACTION_RESULT=&$subref($XML_KEYS{imsi});
		};warn $@ if $@;  &response('LOG',"MAIN-ACTION-SUBREF","ERROR $ACTION_TYPE_RESULT") if $@;
		use vars qw($ACTION_RESULT);
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
our $DUMPER=Dumper (XML::Simple->new()->XMLin($REQUEST_LINE)) if $debug>3;
};warn $@ if $@; return "XML not well-formed" if $@;
#
use vars qw($REQUEST $DUMPER);
&response('LOG',"XML-PARSE-REQUEST-$REQUEST_OPTION","$REQUEST_LINE") if $debug>3;
#
our $REMOTE_HOST=$REQUEST->{authentication}{host};
#
switch ($REQUEST_OPTION){
	case 'PROXY' {
		if ($REQUEST->{query}){#if request in 'query' format
			&response('LOG',"XML-PARSE-DUMPER","$DUMPER")if $debug>3;
			our %Q=();
			my @QUERY=split(' ',$REQUEST->{query});
				foreach my $pair(@QUERY){
					my  ($key,$val)=split('=',$pair);
					$Q{$key}=$val;#All variables from request
				}#foreach
				my $qkeys = keys %Q;
				&response('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION",$qkeys)if $debug>3;;
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
	case 'SIG_SendSMSMT' {
		my $SMS=$REQUEST->{SMS_Response}{REQUEST_STATUS};
		our $ERROR=$REQUEST->{Error_Message};
		&response('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$SMS $ERROR");
		return "$ERROR$SMS";
	}#sms MT
	case 'SIG_SendResale' {
		my $USSD=$REQUEST->{RESALE_Response}{RESPONSE};
		our $ERROR=$REQUEST->{Error_Message};
		&response('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$USSD $ERROR");
		return $USSD;
	}#resale
	case 'SIG_GetTIME' {
		my $TIME=$REQUEST->{RESPONSE};
		our $ERROR=$REQUEST->{Error_Message};
		&response('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$TIME $ERROR");
		return "$ERROR$TIME";
	}#get time
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
use vars qw($LOGFILE $dbh);
my $SQL=qq[@_];
my $now = localtime;
print $LOGFILE "[$now]-[API-SQL-MYSQL]: $SQL\n" if $debug>=2; #DONT CALL VIA &RESPONSE
print "[$now]-[API-SQL-MYSQL]: $SQL\n" if $debug>3;
#
my ($rc, $sth);
our (@result, $new_id);
#
@result=();
if($SQL!~m/^SELECT/i){#INSERT/UPDATE request
&response('LOG','SQL-MYSQL-GET','DO') if $debug>3;
	$rc=$dbh->do($SQL);#result code
	push @result,$rc;#result array
	$new_id = $dbh -> {'mysql_insertid'};#autoincrement id
}#if SQL INSERT UPDATE
else{#SELECT request
&response('LOG','SQL-MYSQL-GET','EXEC') if $debug>3;
	$sth=$dbh->prepare($SQL);
	$rc=$sth->execute;#result code
	@result=$sth->fetchrow_array;
	$sth->finish();
}#else SELECT
#
if($rc){#if result code
	our $sql_aff_rows =$rc;
	#my $sql_record = @result;
	&response('LOG','SQL-MYSQL-RETURNED',"@result $rc $new_id")if $debug>3;
	&response('LOG','SQL-MYSQL-RETURNED',$#result+1);
	return @result; 
}#if result code
else{#if no result code
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
use vars qw($INNER_TID $LOGFILE);
my $timer='0';
my ($s, $usec) = gettimeofday();
my $format = "%06d"; 
$usec=sprintf($format,$usec);
my $mcs=$s.$usec;
$timer=int($mcs-$INNER_TID) if $INNER_TID;
my $now = localtime;
#
open(LOGFILE,">>",'/opt/ruimtools/log/rcpi.log');
#
my ($ACTION_TYPE,$RESPONSE_TYPE,$RONE,$RSEC,$RTHI,$RFOUR)=@_;
if($ACTION_TYPE!~m/^LO/){
	my $SQL=qq[SELECT response FROM cc_actions where code="$ACTION_TYPE"];
	my @sql_record=&SQL($SQL);
my	$XML=$sql_record[0];
my	($ROOT,$SUB1,$SUB2,$SUB3)=split('::',$XML);
my $now = localtime;
	if($RESPONSE_TYPE eq 'OK'){
		my	$OK=qq[<?xml version="1.0" ?><$ROOT><$SUB1>$RONE</$SUB1><$SUB2>$RSEC</$SUB2><$SUB3>$RTHI</$SUB3></$ROOT>\n] if ($RTHI);
		$OK=qq[<?xml version="1.0" ?><$ROOT><$SUB1>$RONE</$SUB1><$SUB2>$RSEC</$SUB2></$ROOT>\n] if (($RSEC ne '')&&(!$RTHI));
		$OK=qq[<?xml version="1.0" ?><$ROOT><$SUB1>$RONE</$SUB1></$ROOT>\n] if ($RSEC eq '');
		my $LOG="[$now]-[$timer]-[API-RESPONSE-SENT]: $OK\n"; 
		print $LOGFILE $LOG if (($debug<=4)&&($debug!=0));
		print $LOG if $debug>=3; 
		return $OK;
	}#if OK
	elsif ($RESPONSE_TYPE eq 'ERROR'){
		my	$ERROR=qq[<?xml version="1.0" ?><Error><Error_Message>$RONE</Error_Message></Error>\n];
		my $LOG="[$now]-[$timer]-[API-RESPONSE-SENT]: $ERROR\n";
		print $LOGFILE $LOG if (($debug<=4)&&($debug!=0));
		print $LOG if $debug>=3;
		return $ERROR;
	}#elsif ERROR
}#ACTION TYPE ne LOG
elsif($ACTION_TYPE eq 'LOG'){
	my	$LOG="[$now]-[$timer]-[API-LOG-$RESPONSE_TYPE]: $RONE\n";
	print $LOGFILE $LOG if (($debug<=4)&&($debug!=0));
	print $LOG if $debug>=3;
	$LOGFILE->flush();
	}#ACTION TYPE LOG
	elsif($ACTION_TYPE eq 'LOGDB'){
		my $SQL=qq[INSERT INTO cc_transaction (`id`,`type`,`inner_tid`,`transaction_id`,`IMSI`,`status`,`info`,`timer`) values(NULL,"$RESPONSE_TYPE",$INNER_TID,"$RONE","$RSEC","$RTHI","$RFOUR",$timer)];
		&SQL($SQL) if $debug<=3;
		my $LOG='';
		$LOG="[$now]-[$timer]-[API-LOGDB]: $SQL\n" if $debug==4;
		$LOG="[$now]-[$timer]-[API-LOGDB-TRANSACTION]: $RESPONSE_TYPE $RONE\n" if (($debug<=3)&&($debug!=0));
		print $LOGFILE $LOG if $debug<=4;
		print $LOG if $debug>=3;
	}#ACTION TYPE LOGDB
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
$SQL=qq[SELECT id, status, credit, phone, company_website, traffic_target from cc_card where useralias="$IMSI" or firstname="$IMSI"];
my @sql_record=&SQL($SQL);
my ($sub_id,$sub_status,$sub_balance,$sub_msisdn,$host,$resale)=@sql_record;
if ($sub_id>0){#if found subscriber
	switch ($sub_status){#sub status
		case 1 {#active already
			print $new_sock &response('LU_CDR','OK',"$XML_KEYS{cdr_id}",'1') if !$CHECK_ONLY;
			&response('LOGDB',"$XML_KEYS{request_type}","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'OK',"CHECK_ONLY $XML_KEYS{cdr_id}");
			my $SQL=qq[UPDATE cc_card set phone="$msisdn" where id=$sub_id];
			my $sql_result=&SQL($SQL);
			my $LU_H_result=&LU_H;#track sim card LU history
			&response('LOG','MAIN-LU-H-RETURN',"$LU_H_result");
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
#
	if(($ussd=$USSD=~/(\*125\*275\*100\*)(\d+)#/)||($ussd=$USSD=~/(\*111\*)(\d+)#/)||($ussd=$USSD=~/(\*112\*)(\d+).*#/)){#if USSD callback
		&response('LOG','MOC-SIG-SPOOL-REQUEST',"$2,$IMSI,$sub_id,$sub_active,$sub_balance,$sub_cid,$sub_peer,$sub_sim_site") if $resale eq '0';
		my $result=&SPOOL($2,$IMSI,$sub_id,$sub_active,$sub_balance,$sub_cid,$sub_peer,$sub_sim_site) if $resale eq '0';
		&response('LOG','MOC-SIG-RESALE-REQUEST',"CB,$IMSI,$resale,$2") if $resale ne '0';
		$result=&resale('CB',"$IMSI","$resale","$2") if $resale ne '0';
		return $result;
	}elsif($ussd=$USSD=~/\*(\d{3}).?(.*)#/){#if USSD general
		&response('LOG','MOC-SIG-USSD-REQUEST',"$1,$2,$IMSI,$sub_cid,$sub_balance") if (($resale eq '0')||($1 eq '122'));
		my $result=&USSD($1,$2,$IMSI,$sub_cid,$sub_balance) if (($resale eq '0')||($1 eq '122'));
		&response('LOG','MOC-SIG-USSD-REQUEST',"UD,$IMSI,$resale,$1,$2") if (($resale ne '0')&&($1 ne '122'));
		$result=&resale('UD',"$IMSI","$resale","$1","$2") if (($resale ne '0')&&($1 ne '122'));
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
					my $SQL=qq[SELECT request from cc_actions where code="get_rate"];
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
			&response('LOGDB','auth_callback_sig',"$Q{transactionid}","$IMSI",'ERROR',"CANT GET MSRN: $offline $ERROR");
			print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"Please try to change roaming operator. Your number is offline for us");
			### RFC try to call directly on UK number
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
		print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"Your Number: $number Your Personal Code: $sub_cid");
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
		my $SQL=qq[SELECT request from cc_actions where code='get_rate'];
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
			}#if number length 12 digits
			else{ #if number length
				&response('LOGDB','USSD',"$Q{transactionid}","$IMSI",'RSP',"Error: Incorrect number $2");
				print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"Incorrect number $2. Please use format: *127*+380 XX XXX XXXX#");
				return 'USSD -1';
			}#end else if number length
	}#case 127
###
	case "128"{#balance request
		&response('LOG','MOC-SIG-USSD-RATES-REQUEST',"$ussd_code");
		&response('LOGDB','USSD',"$Q{transactionid}","$IMSI",'OK',"$ussd_code");
		print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"Please wait sms with rate list for your location");
		return 'USSD 0';
	}#case 128
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
use vars qw($lwp);
#
my $URL='';
my $msrn=0;
my $time=timelocal(localtime());
our $transaction_id=$time.int(rand(1000));
my ($code,$query,$host,$msisdn,$message_code,$options,$options1)=@_;
$message_code='EMPTY' if !$message_code;
#
$host='https://api2.globalsimsupport.com/WebAPI/C9API.aspx?' if !$host;
#
my $SQL=qq[SELECT request, from_unixtime($time),response FROM cc_actions where code="$code" or code="$message_code"];#or used for USSD msg
my @sql_record=&SQL($SQL);
#
my $URL_QUERY=$sql_record[0];
my $timestamp=uri_escape($sql_record[1]);
my $message=$sql_record[2];
#
switch ($code){
	case "SIG_GetTIME" {#get max time for call
		$URL_QUERY=~s/_DEST_/$msisdn/;
		$URL_QUERY=~s/_SUBID_/$query/;
		$URL=$URL_QUERY;
		&response('LOG',"$code-URL-SET","$URL")if $debug>3;
		$query=$Q{'imsi'};#for cc_transaction usage
	}#case gettime
	case "SIG_GetMSRN" {# get msrn
	#reserved for future	$msrn=&reuse_msrn($query) if $options eq '126';#code 126 checks is not safety for changes
	#reserved for future	&response('LOG',"$code-REUSE-GET","$msrn");
		$URL=qq[transaction_id=$transaction_id&query=$query&$URL_QUERY&timestamp=$timestamp] if $msrn==0;
		&response('LOG',"$code-URL-SET","$URL")if $debug>3;
	}#case getmsrn
	#
	case "SIG_SendUSSD" {#send ussd
			if ($message_code=~/^pmnt/){#USSD for PMNT
				my $SQL=qq[SELECT CONCAT('%2B',phone) FROM cc_card where username="$options"];
				my @sql_record=&SQL($SQL);
				$msisdn=$sql_record[0];
				$message=~s/_AMOUNT_/$options1/;
				$message=~s/_CN_/$options/;
			}#if message_code PMNT
			$message=uri_escape($message);
		$URL=qq[transaction_id=$transaction_id&ussdto=$msisdn&$URL_QUERY&message=$message&timestamp=$timestamp] if $message_code;
		&response('LOG',"$code-URL-SET","$URL")if $debug>3;
	}#case sendussd
	#
	case "SIG_SendSMSMT" {#send sms MT to sub
		if ($message_code=~/^pmnt/){#USSD for PMNT
			my $SQL=qq[SELECT CONCAT('%2B',phone) FROM cc_card where username="$options"];
			my @sql_record=&SQL($SQL);
			$msisdn=$sql_record[0];
			$message=~s/_AMOUNT_/$options1/;
			$message=~s/_CN_/$options/;
			$message=uri_escape($message);
		}#if message_code PMNT
		if ($message_code=~/^mcc/){#USSD for MCC
		my ($IN,$OUT,$SMS,$EX)=split(':',$options1);
				$message=~s/_CN_/$options/;
				$message=~s/_IN_/$IN/;
				$message=~s/_OUT_/$OUT/;
				$message=~s/_SMS_/$SMS/;
				$message=~s/_NO_/$EX/;
				$msisdn='%2B'.$msisdn;
				$message=uri_escape($message);
			}#if message_code PMNT
			if ($message_code=~/^inner_sms/){#SMS internal subscriber
			$message=$options;
			$msisdn='%2B'.$msisdn;
			}#if message internal
		$URL=qq[transaction_id=$transaction_id&smsto=$msisdn&smsfrom=ruimtools&$URL_QUERY&message=$message&timestamp=$timestamp] if $message_code;
		&response('LOG',"$code-URL-SET","$URL")if $debug>3;
	}#case sendsms MT
	#
	case "SIG_SendSMS" {#send sms MO to any MSISDN
		$URL=qq[transaction_id=$transaction_id&smsto=%2B$query&smsfrom=ruimtools&$URL_QUERY&msisdn=$options1&message=$options&timestamp=$timestamp];
		$query=$Q{'imsi'};#for cc_transaction usage
	}#case sendsms MO
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
		&response('LOG',"$code-URL-SET","$URL")if $debug>3;
	}#case sendresale
	else{
		return 0;
	}#else switch code
}#switch code
#
our $SENDGET=qq[$host$URL] if $URL;
#
&response('LOGDB',"$code","$transaction_id","$query",'REQ',"$SENDGET $msrn"); 
#
if ($URL){
eval {use vars qw($SENDGET); alarm(10); local $SIG{ALRM} = sub { die "SSL timeout\n" }; &response('LOG',"SENDGET-$code-LWP-REQ","$SENDGET");
my $LWP_response = $lwp->get($SENDGET);
if ($LWP_response->is_success) { our @XML=$LWP_response->decoded_content; }#if success
else{ die $LWP_response->status_line; }#else success response
};#eval lwp
alarm(0);
	if ($@) {#if errors
		if ($@ =~ /SSL timeout/){ warn "Request timed out";	}#if timeout
		else{ warn "Error in request: $@"; }#else other errors
	}#if erorrs
}#if URL
#my $content = $lwp->get($SENDGET);
#my @XML=$content->decoded_content if $URL;
#
use vars qw(@XML);
if (@XML){
	&response('LOG',"$code-RESPOND","@XML") if $debug>=3;
	my $SENDGET_result=&XML_PARSE("@XML",$code);
	&response('LOGDB',$code,"$transaction_id","$query",'RSP',"$SENDGET_result") if $SENDGET_result;
	&response('LOGDB',$code,"$transaction_id","$query",'ERROR','SENDGET NO RESPOND') if !$SENDGET_result;
	return $SENDGET_result;
}#if lwp return
elsif($msrn){
	&response('LOG',"$code-REQUEST","REUSE $msrn");
	&response('LOGDB',$code,"$transaction_id","$query",'REUSE',"$msrn");
	return $msrn;
}#elsif msrn
else{# timeout
	&response('LOG',"$code-REQUEST","Timed out 5 sec with socket");
	&response('LOGDB',$code,"$transaction_id","$query",'ERROR','Timed out 10 sec with socket');
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
my ($code,$sub_code,$options);
my $imsi=$_[0];
$code=$Q{'code'};
$sub_code=$Q{'sub_code'};
$options=$Q{'options'};
switch ($code){
	case 'ping' {#PING
		&response('LOG','RC-API-CMD',"PING");
		&response('LOGDB','CMD',"$Q{transactionid}","$imsi",'OK',"PING $code");
		print $new_sock &response('rc_api_cmd','OK',$Q{transactionid},"PING OK");
		return 'CMD 0';
	}#case ping
	case 1 {#GET_MSRN
		my $auth_result=&auth($Q{auth_key},'RESALE',$Q{reseller},'-md5');
		if ($auth_result==0){
		&response('LOG','RC-API-CMD',"GET_MSRN");
		my $SQL=qq[SELECT id,traffic_target,id_seria from cc_card where (useralias="$Q{imsi}" or firstname="$Q{imsi}")];
		my @sql_record=&SQL($SQL);
		my $sub_id=$sql_record[0];
		my $traffic_target=$sql_record[1];
		my $card_seria=$sql_record[2];
		my $resale_TID="$Q{transactionid}";
		my $msrn=&SENDGET('SIG_GetMSRN',"$imsi");
		&bill_resale($Q{auth_key},'SIG_GetMSRN');
		if($Q{auth_key} eq $traffic_target){#resellers subscriber
		&response('LOGDB','CMD',"$Q{transactionid}","$imsi",'OK',"GET_MSRN $code $Q{auth_key}");
		print $new_sock &response('rc_api_cmd','OK',$resale_TID,"$msrn") if $options ne 'cleartext';
		$msrn=~s/\+// if $options eq 'cleartext';#cleartext for ${EXTEN} usage
		print $new_sock $msrn if $options eq 'cleartext';
		return 'CMD 1';}#if resellers subscriber
			else{#if CFU subscriber
		&response('LOGDB','CMD',"$Q{transactionid}","$imsi",'OK',"GET_MSRN CFU:$card_seria $code $Q{auth_key}");
		my $resale_TID="$Q{transactionid}";
		my $limit=&SENDGET('SIG_GetTIME',$sub_id,'https://127.0.0.1',$msrn) if $card_seria eq '2';
		print $new_sock &response('rc_api_cmd','OK',$resale_TID,"$msrn","$limit") if $options ne 'cleartext';
		$msrn=~s/\+// if $options eq 'cleartext';#cleartext for ${EXTEN} usage
		print $new_sock "$resale_TID:$msrn:$limit" if $options eq 'cleartext';
				}#esle CFU
		return 'CMD 1';
		}#if auth
		else{
		&response('LOGDB','CMD',"$Q{transactionid}","$imsi",'ERROR',"NO AUTH $auth_result $Q{auth_key}");
		print $new_sock &response('rc_api_cmd','OK',$Q{transactionid},"NO AUTH");
		return 'CMD 1 NO AUTH';
		}#else
	}#case 1
	case 'get_stat' {#GET STAT
		&response('LOG','RC-API-CMD',"GET_STAT");
		&response('LOGDB','CMD',"$Q{transactionid}","$imsi",'OK',"GET_STAT $code $sub_code");
		my $SQL=qq[SELECT request from cc_actions where code="$sub_code"];
		my @sql_record=&SQL($SQL);
		$SQL="$sql_record[0]";
		$SQL=~s/_FROMDEST_/$Q{msisdn}/ if $sub_code eq 'get_rate';#Get Rate to Dest get_rate
		$SQL=~s/_TODEST_/$Q{options}/ if $sub_code eq 'get_rate';#Get Rate to Dest get_rate
		$SQL=~s/_CARD_/$Q{card_number}/ if (($sub_code eq 'get_card_number')&&($Q{card_number}=~/^\d{10}$/));#Get CardNumber get_card_number
		$SQL=~s/_RESELLER_/$Q{reseller}/ if $sub_code eq 'get_resale_msrn';#Get Resellers MSRN count get_resale_msrn
		$SQL=~s/_TYPE_/$Q{options}/ if $sub_code eq 'get_resale_msrn';#Get Resellers MSRN count get_resale_msrn
		@sql_record=&SQL($SQL);
		my $stat_result=$sql_record[0];
		$stat_result=substr($stat_result,0,6) if $sub_code eq 'get_rate';#Get Rate to Dest get_rate
		print $new_sock &response('rc_api_cmd','OK',$Q{transactionid},"$stat_result");
		&response('LOG','RC-API-CMD-STAT',"$stat_result");
		return 'CMD 2';
	}#case get_stat
	case 'send_ussd' {#SEND_USSD
		&response('LOG','RC-API-CMD',"SEND_USSD");
		&response('LOGDB','CMD',"$Q{transactionid}","$imsi",'REQ',"SEND_USSD $code");
		my $USSD_result=&SENDGET('SIG_SendUSSD','','',$Q{msisdn},$sub_code);
		&response('LOG','RC-API-CMD',"SEND_USSD $USSD_result");
		&response('LOGDB','CMD',"$Q{transactionid}","$imsi",'OK',"SEND_USSD_RESULT $USSD_result");
		print $new_sock &response('rc_api_cmd','OK',$Q{transactionid},"$Q{msisdn} $USSD_result");
		return 'CMD 3';
	}#case send_ussd
	case 'get_session_time' {#Get max session time
		&response('LOG','RC-API-CMD',"GET_SESSION_TIME");
		&response('LOGDB','CMD',"$Q{transactionid}","$imsi",'REQ',"GET_SESSION_TIME $code");
		my $SQL=qq[SELECT id from cc_card where useralias="$imsi" or firstname="$imsi"];
		my @sql_record=&SQL($SQL);
		my $sub_id=$sql_record[0];
		my $USSD_result=&SENDGET('SIG_GetTIME',$sub_id,'https://127.0.0.1',$Q{msisdn});
		&response('LOG','RC-API-CMD',"GET_SESSION_TIME $USSD_result");
		&response('LOGDB','CMD',"$Q{transactionid}","$imsi",'OK',"GET_SESSION_TIME $USSD_result");
		print $new_sock $USSD_result if $options eq 'cleartext';
		print $new_sock &response('rc_api_cmd','OK',$Q{transactionid},"$USSD_result") if $options ne 'cleartext';;
		return 'CMD 4';
	}#case get_session_time
	case 'set_debug'{#set debug
	$debug=$sub_code;
	&response('LOG','RC-API-CMD',"SET_DEBUG to $debug");
	return 'CMD 5';
	}#case set debug
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
	case 'LU'{#LU_CDR request
		&response('LOG','RESALE-REQUEST-TYPE',"$req_type $imsi,$cgi,,LU,$options");
		&response('LOGDB',"$req_type","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'REQ',"RESALE $resale");
		my $SENDGET_result=&SENDGET('SIG_SendResale',$imsi,$cgi,'','SIG_SendResale_LU',$options,$options1);
		&bill_resale($resale,'SIG_SendResale_LU');#Send LU to Resaler
		&response('LOGDB',"$req_type","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'RSP',"RESALE $SENDGET_result");
		return $SENDGET_result;# OK or <error code>
	}#case LU
	case 'CB'{#CallBack request
		&response('LOG','RESALE-REQUEST-TYPE',"$req_type $imsi,$cgi,,CB,$options");
		&response('LOGDB',"$req_type","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'REQ',"RESALE $resale");
		my $SENDGET_result=&SENDGET('SIG_SendResale',$imsi,$cgi,'','SIG_SendResale_CB',$options);
		&bill_resale($resale,'SIG_SendResale_CB');#Send CB to Resaler
		print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"$SENDGET_result");
		&response('LOGDB',"$req_type","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'RSP',"RESALE $SENDGET_result");
		return $SENDGET_result;# OK or <error code>
	}#case CB
	case 'UD'{#USSD reuqest
		&response('LOG','RESALE-REQUEST-TYPE',"$req_type $imsi,$cgi,,UD,$options,$options1");
		&response('LOGDB',"$req_type","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'REQ',"RESALE $resale");
		#$code,$query,$host,$msisdn,$message_code,$options,$options1
		my $SENDGET_result=&SENDGET('SIG_SendResale',$imsi,$cgi,'','SIG_SendResale_UD',$options,$options1);
		&bill_resale($resale,'SIG_SendResale_UD');#Send USSD to Resaler
		&response('LOGDB',"$req_type","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'RSP',"RESALE $SENDGET_result");
		print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"$SENDGET_result");
		return $SENDGET_result;# OK or <error code>
	}#case USSD
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
my $SQL=qq[SELECT resale_price from cc_actions where code="$sig_id"];
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
### SUB AUTH
# $data signed by $key = $digest
##
sub auth{
use vars qw(%Q $REMOTE_HOST);
my ($data,$type,$agent,$dgst,$sign)=@_;
#my $md5=qq[echo _KYES_ |/usr/bin/openssl dgst $dgst];
our ($digest,$agent_login,$mch_name,$rate,$key,$sgn);
&response('LOG',"RC-API-$type-AUTH","$REMOTE_HOST:$agent:$data:$dgst")if $debug>3;
&response('LOG',"RC-API-$type-AUTH","$agent");
switch ($type){#select auth type
	case "RESALE"{#resale auth
		my $SQL=qq[SELECT login, firstname, lastname from cc_agent where firstname="$data" and active=1];
		my @sql_record=&SQL($SQL);
		($agent_login,$key,$sign)=@sql_record;
		$data=$REMOTE_HOST.$agent_login;
		#$md5=~s/_KYES_/$REMOTE_HOST$reseller_name$public_key/;
	}#case resale
	case "PAYMNT"{#paymnt auth
		my $SQL=qq[SELECT name, auth_key, rate from cc_epaymnter where host="$agent"];
		my @sql_record=&SQL($SQL);
		($mch_name,$key,$rate)=@sql_record;
		#$md5=~s/_KYES_/-n $KEY/;
		#$md5="$md5 $auth_key";
	}#case paymnt
else{
	&response('LOG',"RC-API-AUTH-RETURNED","Error: UNKNOWN TYPE $type");
	}#end else switch type
}#end switch type 
$digest=hmac_sha512_hex("$data","$key");
$dgst=substr($digest,0,5);
$sgn=substr($sign,0,5);
&response('LOG',"RC-API-$type-DIGEST-CHECK","$dgst eq $sgn") if $debug>=3;
if ($digest eq $sign){#if ok
&response('LOG','RC-API-AUTH',"OK");
return 0;
}#end if ok
else{#digest != sign
&response('LOG','RC-API-AUTH',"NO AUTH");
return -1;
	}#else if auth OK
}#END sub auth ##
#
sub PAYMNT{
use vars qw($REMOTE_HOST $new_id);
my @TR= keys %{ $REQUEST->{payment}{transactions}{transaction} };
our ($SQL_T_result,$CARD_NUMBER,$AMOUNT);
my $SQL='';
$SQL=qq[INSERT INTO cc_epayments (`payment_id`, `ident`,`status`,`amount`,`currency`,`timestamp`,`salt`,`sign`,`transactions_ids`) values("$REQUEST->{payment}{id}","$REQUEST->{payment}{ident}","$REQUEST->{payment}{status}","$REQUEST->{payment}{amount}","$REQUEST->{payment}{currency}","$REQUEST->{payment}{timestamp}","$REQUEST->{payment}{salt}","$REQUEST->{payment}{sign}","@TR")];
my $SQL_P_result=&SQL($SQL);
&response('LOG','PAYMNT-EPMTS-SQL-RESULT',"$SQL_P_result");
## AUTH
&response('LOG','PAYMNT-AUTH-REQ',"$REQUEST->{payment}{salt},PAYMNT,$REMOTE_HOST,-sha512,$REQUEST->{payment}{sign}");
if (&auth($REQUEST->{payment}{salt},'PAYMNT',$REMOTE_HOST,"-sha512 -hmac",$REQUEST->{payment}{sign})==0){
&response('LOG','PAYMNT-TR-RESULT',"@TR");
use vars qw($rate $mch_name);
foreach my $tr (@TR){#for each transaction id
$REQUEST->{payment}{transactions}{transaction}{$tr}{info}=~s/"//g; #"
$REQUEST->{payment}{transactions}{transaction}{$tr}{info}=~/{(.*):(.*),(.*):(.*)}/;;
$CARD_NUMBER=$2;
my $SQL='';
$SQL=qq[INSERT INTO cc_epayments_transactions (`id`,`mch_id`, `srv_id`,`amount`,`currency`,`type`,`status`,`code`, `desc`,`info`) values("$tr","$REQUEST->{payment}{transactions}{transaction}{$tr}{mch_id}","$REQUEST->{payment}{transactions}{transaction}{$tr}{srv_id}","$REQUEST->{payment}{transactions}{transaction}{$tr}{amount}","$REQUEST->{payment}{transactions}{transaction}{$tr}{currency}","$REQUEST->{payment}{transactions}{transaction}{$tr}{type}","$REQUEST->{payment}{transactions}{transaction}{$tr}{status}","$REQUEST->{payment}{transactions}{transaction}{$tr}{code}","$REQUEST->{payment}{transactions}{transaction}{$tr}{desc}","$CARD_NUMBER")];
$SQL_T_result=&SQL($SQL);
&response('LOG','PAYMNT-TR-SQL-RESULT',"$SQL_T_result");
$SQL=qq[UPDATE cc_epayments set process="$SQL_T_result" where id=$new_id];
my $SQL_update_result=&SQL($SQL);
if (($REQUEST->{payment}{transactions}{transaction}{$tr}{type}==11)&&($SQL_T_result>0)){#if debited transaction
$AMOUNT=$REQUEST->{payment}{transactions}{transaction}{$tr}{amount}/$rate;
$SQL=qq[INSERT into `msrn`.`cc_epayment_log` (`amount`, `paymentmethod`, `cardid`, `cc_owner`) values ( round($AMOUNT,3), "$mch_name", (select id from cc_card where username="$CARD_NUMBER"),"$tr")];
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
#
my $USSD_result=&SENDGET('SIG_SendSMSMT','','','','pmnt_ok',"$CARD_NUMBER","$REQUEST->{payment}{id}") if $SQL_T_result>0;
$USSD_result=&SENDGET('SIG_SendSMSMT','','','','pmnt_error',"$CARD_NUMBER","$REQUEST->{payment}{id}") if $SQL_T_result<0;
#
return $SQL_T_result;
}# END sub PAYMNT
#
### sub LOCATION HISTORY ##
sub LU_H{
use vars qw(%Q);
my $SQL='';
if (($Q{imsi})&&($Q{mnc})&&($Q{mcc})&&($Q{request_type})){#if signaling request
$SQL=qq[UPDATE cc_card set country=(select countrycode from cc_country, cc_mnc where countryname=country and mcc="$Q{mcc}" limit 1), zipcode="$Q{mcc} $Q{mnc}", tag=(select mno from cc_mnc where mnc="$Q{mnc}" and mcc="$Q{mcc}") where (useralias="$Q{imsi}" or firstname="$Q{imsi}") and country!=(select countrycode from cc_country, cc_mnc where countryname=country and mcc="$Q{mcc}" limit 1)];
my @sql_result=&SQL($SQL);
# SEND WELCOME SMS
my $UPDATE_result=$sql_result[0];
$UPDATE_result=0 if $sql_result[0] eq '0E0';
if ($UPDATE_result eq '1'){#if subscriber change country
$SQL=qq[SELECT countryname,rates from cc_country where countrycode=(select country from cc_card where useralias="$Q{imsi}" or firstname="$Q{imsi}")];
my @sql_result=&SQL($SQL);
my $countryname=$sql_result[0];
my $countryrate=$sql_result[1];
my $USSD_result=&SENDGET('SIG_SendSMSMT','','',$Q{msisdn},'mcc_new',"$countryname","$countryrate");
}#if change country
#
return $sql_result[0]; 
}#end if signaling
}# END sub LU_H
#
## SMS section ##########################################################
#
### sub USSD_SMS #
sub SMS{
use vars qw(%Q);
my ($ussd_subcode,$sms_id)=@_;
my ($flag,$sms_opt,$sms_dest,$sms_text);
our $sms_result;
#
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
$SQL=~s/_SRC_/$Q{msisdn}/g;
$SQL=~s/_FLAG_/$num_page/g;
my @sql_result=&SQL($SQL);
$sms_text=$sql_result[0];
$sms_dest=$sql_result[1];
&response('LOG','SMS-ENC-RESULT',"$sms_text");
$sms_text=uri_escape($sms_text);
my $sms_from=uri_unescape($Q{msisdn});
$sms_from=~s/\+//;
&response('LOG','SMS-TEXT-ENC-RESULT',"$#sql_result");
&response('LOG','SMS-SEND-PARAM',"$sms_dest,'ruimtools',$sms_text,$sms_from");
$SQL=qq[SELECT id from cc_card where phone="$sms_dest"];
my $SQL_inner_result=&SQL($SQL);
if ($SQL_inner_result>0){#internal subscriber
&response('LOG','SMS-REQ',"INTERNAL");
$sms_result=&SENDGET('SIG_SendSMSMT','','',$sms_dest,'inner_sms',"$sms_text");
}#if internal
else{#external subscriber
&response('LOG','SMS-REQ',"EXTERNAL");
$sms_result=&SENDGET('SIG_SendSMS',$sms_dest,'','ruimtools','',"$sms_text",$sms_from);
}#else external
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
### sub MO_SMS
# Authenticate outbound SMS request.
###
sub MO_SMS{
use vars qw(%Q);
print $new_sock &response('MO_SMS','OK',$Q{transactionid},1,'RuimTools');
&response('LOGDB','MO_SMS',$Q{transactionid},$Q{imsi},'RSP',"RuimTools 1");
}#end sub MO_SMS
#
### sub MT_SMS
# Authenticate inbound SMS request.
###
sub MT_SMS{
print $new_sock &response('MT_SMS','OK',$Q{transactionid},1);
&response('LOGDB','MT_SMS',$Q{transactionid},$Q{imsi},'RSP',"1");
}#end sub MT_SMS
#
### sub MOSMS_CDR
# MOSMS (Outbound) CDRs
##
sub MOSMS_CDR{
	my $CDR_result=&SMS_CDR;
	&response('LOG','MOSMS_CDR',$CDR_result);
	print $new_sock &response('MOSMS_CDR','OK',$Q{transactionid},$CDR_result);
	&response('LOGDB','MOSMS_CDR',$Q{transactionid},$Q{imsi},'RSP',"$CDR_result");
}#end sub MOSMS_CDR
#
### sub MTSMS_CDR
# MTSMS (Inbound) CDRs
###
sub MTSMS_CDR{
	my $CDR_result=&SMS_CDR;
	&response('LOG','MTSMS_CDR',$CDR_result);
	print $new_sock &response('MTSMS_CDR','OK',$Q{transactionid},$CDR_result);
	&response('LOGDB','MTSMS_CDR',$Q{transactionid},$Q{imsi},'RSP',"$CDR_result");
}#end sub MTSMS_CDR
#
### sub SMSContent_CDR
# SMS Content CDRs
##
sub SMSContent_CDR{
	use vars qw(%Q);#workaround #19 C9RFC
	$Q{'cdr_id'}='NULL';#workaround #19 C9RFC
	my $CDR_result=&SMS_CDR;
	&response('LOG','SMSContent_CDR',$CDR_result);
	print $new_sock &response('MT_SMS','OK',$Q{transactionid},$CDR_result);
	&response('LOGDB','SMSContent_CDR',$Q{transactionid},$Q{imsi},'RSP',"$CDR_result");
}#end sub SMSContent_CDR
#
### SMS_CDR
# Processing CDRs for each type of SMS
###
sub SMS_CDR{
use vars qw(%Q);
#
$Q{timestamp}=uri_unescape($Q{timestamp});
$Q{message_date}=uri_unescape($Q{message_date});
#
my $SQL=qq[INSERT into `msrn`.`cc_sms_cdr` ( `id`, `msisdn`, `allow`, `reseller_charge`, `timestamp`, `smsc`, `user_charge`, `mnc`, `srcgt`, `request_type`, `smsfrom`, `IOT`, `client_charge`, `transactionid`, `route`, `imsi`, `user_balance`, `message_date`,`carrierid`,`message_status`,`service_id`,`sms_type`,`sender`,`message`,`original_cli`) values ( "$Q{cdr_id}", "$Q{msisdn}", "$Q{allow}", "$Q{reseller_charge}", "$Q{timestamp}", "$Q{smsc}", "$Q{user_charge}", "$Q{mnc}", "$Q{srcgt}", "$Q{request_type}", "$Q{smsfrom}", "$Q{IOT}", "$Q{client_charge}", "$Q{transactionid}", "$Q{route}", "$Q{imsi}", "$Q{user_balance}", "$Q{message_date}","$Q{carrierid}","$Q{message_status}","$Q{service_id}","$Q{sms_type}","$Q{sender}","$Q{message}","$Q{original_cli}")];
my $sql_result=&SQL($SQL);
&response('LOG','SMS_CDR',$sql_result);
return $sql_result; 
}#end sub SMS_CDR
# end SMS section
##########################################################
#
### sub DataAUTH
sub DataAUTH{
print $new_sock &response('DataAUTH','OK',0);
}# end sub DataAUTH
#
###
### sub msisdn_allocation
# First LU with UK number allocation
###
sub msisdn_allocation{
use vars qw(%Q);
my $SQL=qq[UPDATE cc_card set phone="$Q{MSISDN}" where useralias=$Q{IMSI} or firstname=$Q{IMSI}];
my $sql_result=&SQL($SQL);
print $new_sock &response('msisdn_allocation','OK',$Q{transactionid},$sql_result);
&response('LOG','msisdn_allocation',$sql_result);
&response('LOGDB','msisdn_allocation',1,$Q{IMSI},'RSP',"$Q{MSISDN} $sql_result");	
}#end sub msisdn_allocation
#
######### END #################################################	