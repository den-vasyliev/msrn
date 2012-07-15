#!/usr/bin/perl
#/opt/local/bin/perl -T
#
########## VERSION AND REVISION ################################
## Copyright (C) 2012, RuimTools denis@ruimtools.com
##
my $REV='API Server 160712rev.42.2 OPTIMAL'.int(rand(100));
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
use Digest::MD5 qw(md5);
use URI::Escape;
use LWP::UserAgent;
#use LWP::ConnCache::MaxKeepAliveRequests;
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
########## KEYS #############################################
system('stty','-echo');
print STDOUT "Enter login:\n";
chop(my $LOGIN = <STDIN>);
print STDOUT "Enter passwd:\n";
chop(my $PASS = <STDIN>);
print STDOUT "Enter key:\n";
chop(our $KEY = <STDIN>);
system('stty','echo');
################################################################
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
#
our $LOGFILE = IO::File->new("/opt/ruimtools/log/rcpi.log", "a+");
#
########## CONFIGURATION FOR MAIN SOCKET ########################
my $HOST='127.0.0.1';
my $PORT='35001';
#################################################################
#
########## CONNECT TO MYSQL #####################################
our $dbh = DBI->connect('DBI:mysql:msrn',$LOGIN,$PASS);
die "No auth!" unless defined($dbh);
#
&response('LOG','API',"$REV Ready at $$ deb $debug");
#################################################################
############### LWP ##############################################
#use LWP::ConnCache::MaxKeepAliveRequests;
#our $lwp = LWP::UserAgent->new;
#$lwp->conn_cache(
#    LWP::ConnCache::MaxKeepAliveRequests->new(
#        total_capacity          => 10,
#        max_keep_alive_requests => 100,
#    )
#);
#################################################################
########## SYSTEM PROMPTS #######################################
our %SYS=(0=>'CARD CANCELED',1=>'ACTIVE',2=>'NEW CARD. WAIT FOR REGISTRATION',3=>'WAITING CONFIRMATION',4=>'RESERVED',5=>'CARD EXPIRED',6=>'SUSPENDED FOR UNDERPAYMENT',9=>'RESALE');
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
					while(our $XML_REQUEST=<$new_sock>){
						if ($XML_REQUEST =~/897234jhdln328sLUV/){
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
use vars qw($XML_REQUEST $INNER_TID $LOGFILE $new_sock %Q);
our $lwp = LWP::UserAgent->new;
	our %XML_KEYS=&XML_PARSE($XML_REQUEST,'SIG_GetXML');
	my $qkeys= keys %XML_KEYS;
	&response('LOG','MAIN-XML-PARSE-RETURN',$qkeys);
		if ($qkeys){#if not empty set
		my $IN_SET='';
		$IN_SET=uri_unescape($XML_KEYS{msisdn}).":$XML_KEYS{mcc}:$XML_KEYS{mnc}:$XML_KEYS{tadig}" if  $XML_KEYS{msisdn};#General
		$IN_SET=$IN_SET.":$XML_KEYS{code}:$XML_KEYS{sub_code}" if $XML_KEYS{code};#USSD
		$IN_SET=$IN_SET."$XML_KEYS{ident}:$XML_KEYS{amount}" if $XML_KEYS{salt};#PAYMNT
		$IN_SET=$IN_SET."$XML_KEYS{TotalCurrentByteLimit}" if $XML_KEYS{SessionID};#PAYMNT
		$IN_SET=$IN_SET."$XML_KEYS{calllegid}:$XML_KEYS{bytes}:$XML_KEYS{seconds}:$XML_KEYS{mnc}:$XML_KEYS{mcc}:$XML_KEYS{amount}" if $XML_KEYS{calllegid};#DATA
		$XML_KEYS{transactionid}=$XML_KEYS{SessionID} if $XML_KEYS{SessionID};#DATA
		$XML_KEYS{imsi}=$XML_KEYS{GlobalIMSI} if $XML_KEYS{SessionID};#DATA
		&response('LOGDB',"$XML_KEYS{request_type}","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'IN',$IN_SET);#Register IN request
		#Get action type
		my $ACTION_TYPE_RESULT=&GET_TYPE($XML_KEYS{request_type});
			eval {#save subref
				our $subref=\&$ACTION_TYPE_RESULT;#Make reference to sub
			};warn $@ if $@;  &response('LOG',"MAIN-ACTION-SUBREF","ERROR $ACTION_TYPE_RESULT") if $@;
		&response('LOG','MAIN-GET_TYPE',$ACTION_TYPE_RESULT);
##
	switch ($ACTION_TYPE_RESULT){#if we understand action
		case 1 {#Incorrect URL
			print $new_sock &response('LU_CDR','ERROR','#'.__LINE__.' INCORRECT URL VARIABLES');
			&response('LOGDB',"$XML_KEYS{request_type}","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'ERROR','INCORRECT URL VARIABLES');
		}#case 1
		case 2 {#Incorrect type
			print $new_sock &response('LU_CDR','ERROR','#'.__LINE__.' INCORRECT ACTIONS TYPE');
			&response('LOGDB',"$XML_KEYS{request_type}","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'ERROR','INCORRECT ACTIONS TYPE');
		}#case 2
		case 3 {#Not found at all
			&response('LOG','MAIN-GET_TYPE','NOT FOUND');
			print $new_sock &response('LU_CDR','ERROR','#'.__LINE__.' INCORRECT URI')}
	else {#else switch ACTION TYPE RESULT correct action
		use vars qw($subref);
		eval {#safty subroutine
		our $ACTION_RESULT=&$subref();#calling to reference
		};warn $@ if $@;  &response('LOG',"MAIN-ACTION-SUBREF","ERROR $ACTION_TYPE_RESULT") if $@;
		use vars qw($ACTION_RESULT);
			if($ACTION_RESULT){#action return result
				&response('LOG',"MAIN-ACTION-RESULT-$ACTION_TYPE_RESULT","$ACTION_RESULT");
			}#if ACTION RESULT
			else{&response('LOG',"MAIN-ACTION-RESULT-$ACTION_TYPE_RESULT",'NO ACTION_RESULT');
			}#no result returned
		}#else switch ACTION TYPE RESULT
##
	}#switch ACTION TYPE RESULT
}#if keys
else{#else if keys
	&response('LOGDB',"UNKNOWN REQUEST",0,0,'IN',"$XML_REQUEST");
	&response('LOG','MAIN-XML-PARSE-KEYS',$qkeys);
	print $new_sock &response('LU_CDR','ERROR','#'.__LINE__.' INCORRECT XML KEYS',0);
}#else if keys
}########## END sub main ########################################
#
########## XML_PARSE ############################################
## Function to parse XML data
## Usage XML_PARSE(<XML>,<OPTION>)
## Accept pure xml on input
## Return hash with key=value for XML request and MSRN 
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
	case 'SIG_GetXML' {
		&response('LOG',"XML-PARSE-DUMPER","$DUMPER")if $debug>3;
##if request in 'query' format
		if ($REQUEST->{query}){
			our %Q=();
			my @QUERY=split(' ',$REQUEST->{query});
				foreach my $pair(@QUERY){
					my  ($key,$val)=split('=',$pair);
					$Q{$key}="$val";#All variables from request
				}#foreach
				#}#if
				my $qkeys = keys %Q;
				&response('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION",$qkeys)if $debug>3;;
				return %Q;
		}#if request
##if request in 'payments' format		
		elsif($REQUEST->{payment}){
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
#if request in 'postdata' format
		elsif($REQUEST->{'complete-datasession-notification'}){
		&response('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION",'POSTDATA');
		our %Q=('request_type'=>'POSTDATA');
		$Q{'transactionid'}=$REQUEST->{'complete-datasession-notification'}{callid};
		my @KEYS= keys %{ $REQUEST->{'complete-datasession-notification'}{callleg} };
		foreach my $xml_keys (@KEYS){#foreach keys
				if ((ref($REQUEST->{'complete-datasession-notification'}{callleg}{$xml_keys}) eq 'HASH')&&($xml_keys eq 'agentcost')){#if HASH
					my @SUBKEYS= keys %{ $REQUEST->{'complete-datasession-notification'}{callleg}{$xml_keys} } ;
					foreach my $sub_xml_keys (@SUBKEYS){# foreach subkeys
						&response('LOG',"XML-PARSE-RETURN-KEYS","$sub_xml_keys=$REQUEST->{'complete-datasession-notification'}{callleg}{$xml_keys}{$sub_xml_keys}")if $debug>3;
						$Q{$sub_xml_keys}=$REQUEST->{'complete-datasession-notification'}{callleg}{$xml_keys}{$sub_xml_keys};
					}#foreach sub xml_keys
				}#if HASH
					else{#else not HASH
					&response('LOG',"XML-PARSE-RETURN-KEYS","$xml_keys=$REQUEST->{'complete-datasession-notification'}{callleg}{$xml_keys}")if $debug>3;
					$Q{$xml_keys}=$REQUEST->{'complete-datasession-notification'}{callleg}{$xml_keys};
							}#else not HASH
					}#foreach xml_keys
				my $SQL=qq[select useralias from cc_card where phone=$Q{'number'}];
				my @sql_records=&SQL($SQL);
				$Q{imsi}=$sql_records[0];
			return %Q;
		}#elsif postdata
		else{#unknown format
			&response('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION",'UNKNOWN FORMAT');
		}#else unknown
	}#xml
	case 'SIG_GetMSRN' {
		my $MSRN=$REQUEST->{MSRN_Response}{MSRN};
		our $ERROR=$REQUEST->{Error_Message};
		&response('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$MSRN $ERROR");
		return $MSRN;
	}#msrn
	case 'send_ussd' {
		my $USSD=$REQUEST->{USSD_Response}{REQUEST_STATUS};
		our $ERROR=$REQUEST->{Error_Message};
		&response('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$USSD $ERROR");
		return $USSD;
	}#ussd
	case 'SIG_SendSMS_MO' {
		my $SMS=$REQUEST->{SMS_Response}{REQUEST_STATUS};
		our $ERROR=$REQUEST->{Error_Message};
		&response('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$SMS $ERROR");
		return "$ERROR$SMS";
	}#sms
	case 'SIG_SendSMS_MT' {
		my $SMS=$REQUEST->{SMS_Response}{REQUEST_STATUS};
		our $ERROR=$REQUEST->{Error_Message};
		&response('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$SMS $ERROR");
		return "$ERROR$SMS";
	}#sms MT
	case 'SIG_SendAgent' {
		my $USSD=$REQUEST->{RESALE_Response}{RESPONSE};
		our $ERROR=$REQUEST->{Error_Message};
		&response('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$USSD $ERROR");
		return $USSD;
	}#resale
	case 'get_session_time' {
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
uri_unescape($Q{calldestination})=~/^\*(\d{3})\*?(\D{0,}\d{0,}).?(.{0,}).?/;
($Q{USSD_CODE},$Q{USSD_DEST},$Q{USSD_EXT})=($1,$2,$3);$Q{imsi}=0 if !$Q{imsi};
foreach my $pair (split(';',${SQL("SELECT get_sub($Q{imsi})",2)}[0])){
	my ($key,$value)=split('=',$pair);
	$Q{$key}=$value;#foreach
}
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
use vars qw($LOGFILE $dbh $INNER_TID $timer);
my $SQL=qq[$_[0]];
my $flag=qq[$_[1]];
$SQL=qq[SELECT get_text(].$SQL.qq[,NULL)] if $flag eq '1';
my $now = localtime;
print $LOGFILE "[$now]-[$INNER_TID]-[$timer]-[API-SQL-MYSQL]: $SQL\n" if (($debug>=2)and($SQL!~/get_auth_key/)); #DONT CALL VIA &RESPONSE
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
	return \@result if $flag;
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
$INNER_TID=0 if !$INNER_TID;
our $timer='0';
my ($s, $usec) = gettimeofday();
my $format = "%06d"; 
$usec=sprintf($format,$usec);
my $mcs=$s.$usec;
$timer=int($mcs-$INNER_TID) if $INNER_TID;
my $now = localtime;
#
open(LOGFILE,">>",'/opt/ruimtools/log/rcpi.log');
open(STDERR, ">>", '/opt/ruimtools/log/errlog.log');
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
		my $LOG="[$now]-[$INNER_TID]-[$timer]-[API-RESPONSE-SENT]: $OK\n"; 
		print $LOGFILE $LOG if (($debug<=4)&&($debug!=0));
		print $LOG if $debug>=3; 
		return $OK;
	}#if OK
	elsif ($RESPONSE_TYPE eq 'ERROR'){
		my	$ERROR=qq[<?xml version="1.0" ?><Error><Error_Message>$RONE</Error_Message></Error>\n];
		my $LOG="[$now]-[$INNER_TID]-[$timer]-[API-RESPONSE-SENT]: $ERROR\n";
		print $LOGFILE $LOG if (($debug<=4)&&($debug!=0));
		print $LOG if $debug>=3;
		return $ERROR;
	}#elsif ERROR
}#ACTION TYPE ne LOG
elsif($ACTION_TYPE eq 'LOG'){
	my	$LOG="[$now]-[$INNER_TID]-[$timer]-[API-LOG-$RESPONSE_TYPE]: $RONE\n";
	print $LOGFILE $LOG if (($debug<=4)&&($debug!=0));
	print $LOG if $debug>=3;
	$LOGFILE->flush();
	}#ACTION TYPE LOG
	elsif($ACTION_TYPE eq 'LOGDB'){
		my $SQL=qq[INSERT INTO cc_transaction (`id`,`type`,`inner_tid`,`transaction_id`,`IMSI`,`status`,`info`,`timer`) values(NULL,"$RESPONSE_TYPE",$INNER_TID,"$RONE","$RSEC","$RTHI","$RFOUR",$timer)];
		&SQL($SQL) if $debug<=4;
		my $LOG='';
		$LOG="[$now]-[$INNER_TID]-[$timer]-[API-LOGDB]: $SQL\n" if $debug==4;
		$LOG="[$now]-[$INNER_TID]-[$timer]-[API-LOGDB-TRANSACTION]: $RESPONSE_TYPE $RONE\n" if (($debug<=3)&&($debug!=0));
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
use vars qw($new_sock %Q);
&response('LOG','LU-REQUEST-IN',"$Q{imsi} $Q{msisdn}");
if ($Q{SUB_ID}>0){#if found subscriber
			my $UPDATE_result=${SQL(qq[SELECT set_country($Q{imsi},$Q{mcc},$Q{mnc},"$Q{msisdn}")],2)}[0];
			if ($UPDATE_result){#if contry change
my $TRACK_result=LWP('SIG_SendSMSMT',${SQL(qq[SELECT get_uri('SIG_SendSMSMT',"$Q{imsi}",NULL,"$Q{msisdn}",'mcc_new','ruimtools',NULL)],2)}[0]);
	$TRACK_result=LWP('SIG_SendSMSMT',${SQL(qq[SELECT get_uri('SIG_SendSMSMT',NULL,NULL,"$Q{msisdn}",'get_ussd_codes','ruimtools',NULL)],2)}[0]);
				&response('LOG','MAIN-LU-HISTORY-RETURN',"$TRACK_result");
			}#if country change
			print $new_sock &response('LU_CDR','OK',"$Q{SUB_ID}",'1');
			&response('LOGDB',"LU_CDR","$Q{transactionid}","$Q{imsi}",'OK',"$Q{SUB_ID} $Q{imsi} $Q{msisdn}");
			&response('LOG','LU-REQUEST-OK',"$Q{imsi} $Q{msisdn} $Q{SUB_ID}");
			return $Q{SUB_ID};
}else{#else no sub_id
	print $new_sock &response('LU_CDR','ERROR','#'.__LINE__.'  SUBSCRIBER NOT FOUND');
	&response('LOG','LU-SUB-ID',"SUBSCRIBER NOT FOUND $Q{imsi}");
	&response('LOGDB','LU_CDR',"$Q{transactionid}","$Q{imsi}",'ERORR','SUBSCRIBER NOT FOUND');
	return -1;
}#else not found
}########## END sub LU_CDR ######################################
#
########## AUTHENTICATION CALLBACK MOC_SIG ######################
## Processing CallBack and USSD requests
################################################################# 
#
sub auth_callback_sig{
#	my	$result=agent("$Q{USSD_CODE}","$Q{imsi}","$Q{SUB_AGENT_ID}","$Q{USSD_DEST}","$Q{USSD_EXT}","$Q{SUB_AGENT_ADDR}","$Q{SUB_AGENT_KEY}");
use vars qw(%Q);
my $result;
&response('LOG',"SIG-$Q{USSD_CODE}-REQUEST","$Q{imsi},$Q{USSD_CODE},$Q{USSD_DEST},$Q{USSD_EXT}");
if($Q{SUB_STATUS}==1){#if subscriber active
#if($Q{SUB_OPTIONS}=~/$Q{USSD_CODE}/){
##CALL
$result=&SPOOL() if $Q{USSD_CODE}=~/111|112/;
##USSD
$result=&USSD() if $Q{USSD_CODE}!~/111|112/;
return $result;
#}#processing
	}#if subscriber active
	else{#status not 1
		&response('LOG','MAIN-SIG-INCORRECT-STATUS',"$Q{SUB_STATUS}");
		&response('LOGDB','STATUS',"$Q{transactionid}","$Q{imsi}",'ERROR',"$Q{SUB_STATUS}");
		print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"$SYS{$Q{SUB_STATUS}}") if $SYS{$Q{SUB_STATUS}};
		print $new_sock &response('LU_CDR','ERROR','#'.__LINE__.' INCORRECT STATUS') if !$SYS{$Q{SUB_STATUS}};
	}#else status
}## END sub auth_callback_sig
#
#
############## SUB SPOOL ######################
## Spooling call
##############################################
sub SPOOL{
use vars qw($ERROR %Q $sql_aff_rows);
#my ($dest,$IMSI,$sub_cid,$sub_trunkprefix)=@_;
my $msisdn=uri_unescape($Q{msisdn});
my $uniqueid=timelocal(localtime())."-".int(rand(1000000));
$Q{USSD_DEST}=~/^(\+|00)?([1-9]\d{7,15})$/;
$Q{USSD_DEST}=$2;
&response('LOG','SPOOL-GET-DEST',"$Q{USSD_DEST}");
&response('LOGDB','SPOOL',"$Q{transactionid}","$Q{imsi}",'CALL',"$msisdn to $Q{USSD_DEST}");
#&response('LOG','MOC-SIG-GET_MSRN-REQUEST',$Q{imsi});
my $msrn=LWP('SIG_GetMSRN',${SQL(qq[SELECT get_uri('SIG_GetMSRN',"$Q{imsi}",NULL,NULL,'SIG_GetMSRN',NULL,NULL)],2)}[0]);
my $offline=1 if $msrn eq 'OFFLINE';
$msrn=~s/\+//;# + from xml response
&response('LOG','SPOOL-GET-MSRN-RESULT',$msrn);
#
	if (($msrn)and($Q{USSD_DEST})and(!$offline)){
		# Call SPOOL		
		my $SPOOL_RESULT=${SQL(qq[select spool($msrn,"$uniqueid","$Q{SUB_TRUNK_TECH}/$Q{SUB_TRUNK_PREF}$msrn\@$Q{SUB_TRUNKCODE}","$Q{USSD_DEST}",$Q{SUB_CN})],2)}[0];	
#		my $SPOOL_RESULT=&AMI('call_spool',"$msrn:$dest:$sub_cid:$sub_peer");
		if($SPOOL_RESULT==1){
			my $rate=${SQL(qq[SELECT round(get_rate($msrn,$Q{USSD_DEST}),2)],2)}[0];
			&response('LOG','SPOLL-GET-SPOOL',$sql_aff_rows);
			print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},${SQL(qq[select get_text($Q{imsi},'spool','wait',"$msrn:$Q{USSD_DEST}")],2)}[0]);
			&response('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'SPOOL',"$uniqueid");
			return 'SPOOL SUCCESS 0';
		}else{
			print $new_sock &response('auth_callback_sig','ERROR','#'.__LINE__.' CANT SPOOL CALL');
			&response('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'ERROR','CANT SPOOL CALL');
			return 'SPOOL ERROR -1';
			}#else CANT SPOOL
	}#if msrn and dest
	else{#else not msrn and dest
		&response('LOGDB','SPOOL',"$Q{transactionid}","$Q{imsi}",'ERROR',"CANT GET MSRN: $offline $ERROR");
		print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},${SQL("SELECT get_text(NULL,'spool','offline',NULL)",2)}[0]);
		### RFC try to call directly on UK number?
		return 'SPOOL WARN -2';	
		}#else not msrn and dest
}########## END SPOOL ##########################
#
############# SUB USSD #########################
## Processing USSD request
###############################################
sub USSD{
use vars qw(%Q);
switch ($Q{USSD_CODE}){
###
	case "000"{#SUPPORT request
		&response('LOG','SIG-USSD-SUPPORT-REQUEST',"$Q{USSD_CODE}");
		&response('LOGDB','support',"$Q{transactionid}","$Q{imsi}",'OK',"$Q{USSD_CODE}");
		print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},${SQL(qq[NULL,'ussd',$Q{USSD_CODE}],1)}[0]);
		return "USSD 0";
	}#case 000
###
	case "100"{#MYNUMBER request
		&response('LOG','SIGSIG-USSD-MYNUMBER-REQUEST',"$Q{USSD_CODE}");
		&response('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'OK',"$Q{USSD_CODE}");
		my $number=uri_unescape("$Q{msisdn}");
		print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},${SQL(qq[$Q{imsi},'ussd',$Q{USSD_CODE}],1)}[0]);
		return "USSD 0";
	}#case 100
###
	case "110"{#IMEI request
		&response('LOG','SIG-USSD-IMEI-REQUEST',"$Q{USSD_CODE}");
		&response('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'OK',"$Q{USSD_CODE} $Q{USSD_DEST}");
		$Q{USSD_CODE}=~/(\d+)\*(\w+)\*(\d+)/;
		print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"Your IMEI: $1");
		my $SQL=qq[UPDATE cc_card set address="$1 $2" where useralias="$Q{imsi}" or firstname="$Q{imsi}"];
		my $SQL_result=&SQL($SQL);
		return "USSD $SQL_result";
	}#case 110
###
	case "122"{#SMS request
		&response('LOG','SIG-USSD-SMS-REQUEST',"$Q{USSD_CODE} $Q{USSD_DEST} $Q{USSD_EXT}");
		&response('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'OK',"$Q{USSD_CODE} $Q{USSD_DEST} $Q{USSD_EXT}");
		my $SMS_result=SMS();
		my $SMS_response=${SQL(qq[NULL,'ussd',$Q{USSD_CODE}$SMS_result],1)}[0];
		$SMS_response="UNKNOWN" if $SMS_response eq '';
		&response('LOG','SIG-USSD-SMS-RESULT',"$SMS_result");
		&response('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'RSP',"$SMS_result");
		print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"$SMS_response");
		return "USSD $SMS_result";
	}#case 122
###
	case "123"{#voucher refill request
		&response('LOG','SIG-USSD-VAUCHER-REQUEST',"$Q{USSD_CODE}");
		print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},${SQL(qq[NULL,'ussd',$Q{USSD_CODE}],1)}[0]) if !$Q{USSD_EXT};
		return 'USSD 0';
		my $voucher_add=${SQL(qq[SELECT voucher($Q{imsi},$Q{SUB_CN},$Q{USSD_DEST})],2)}[0];
			if($voucher_add>0){
					&response('LOG','SIG-USSD-VOUCHER-SUCCESS',"$Q{USSD_DEST}");
					&response('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'OK',"$Q{USSD_CODE} $Q{USSD_DEST}");
					print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"YOUR BALANCE $Q{SUB_CREDIT} UPDATED TO $voucher_add\$");
					return 'USSD 0';
			}else{
					&response('LOG','SIG-USSD-VOUCHER-ERROR',"NOT VALID");
					&response('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'ERROR',"$Q{USSD_DEST} NOT VALID");
					print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"VOUCHER NOT VALID");
					return 'USSD -1';
				}#else
	}#case 123
###
	case "124"{#balance request
		&response('LOG','SIG-USSD-BALANCE-REQUEST',"$Q{USSD_CODE}");
		&response('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'OK',"$Q{USSD_CODE}");
		print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},${SQL(qq[$Q{imsi},'ussd',$Q{USSD_CODE}],1)}[0]);
		return 'USSD 0';
	}#case 124
###
	case "126"{#RATES request
		&response('LOG','SIG-USSD-RATES',"$Q{USSD_CODE} $Q{USSD_DEST}");
		&response('LOGDB','USSD',"$Q{transactionid}","$Q{imsi}",'OK',"$Q{USSD_CODE} $Q{USSD_DEST}");
		my $msrn=LWP(${SQL(qq[SELECT get_uri('SIG_GetMSRN',"$Q{imsi}",NULL,NULL,NULL,NULL,NULL)],2)}[0]);
		$Q{USSD_CODE}=~/(.?)(\d{12})/;
		my $dest=$2;
		my $rate=${SQL("SELECT round(get_rate($msrn,$dest),2)",2)}[0];
		&response('LOG','SIG-USSD-RATES-RETURN',"$rate");
		&response('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'OK',"$Q{USSD_CODE}");
		print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"Rate to $Q{USSD_DEST} is \$ $rate");
		return "USSD 0";
	}#case 126
###
	case "127"{#CFU request
		&response('LOG','SIG-USSD-CFU-REQUEST',"$Q{USSD_CODE} $Q{USSD_DEST}");
		if ($Q{USSD_DEST}=~/^(\+|00)?(\d{5,15})$/){#if prefix +|00 and number length 5-15 digits
			&response('LOG','SIG-USSD-CFU-REQUEST',"Subcode processing $Q{USSD_DEST}");
				 my $CFU_number=$2;
				 my $SQL=qq[SELECT get_cfu_code($Q{imsi},"$CFU_number")];
					#my @SQL_result=&SQL($SQL);
					my $CODE=${SQL("$SQL",2)}[0];
				$CODE=LWP('SIG_SendSMS_MO',${SQL(qq[SELECT get_uri('SIG_SendSMSMO',NULL,"+$CFU_number",'447700079964','SIG_SendSMS_MO','447700079964',"$CODE")],2)}[0]) if $CODE=~/\d{5}/;
					$CFU_number='NULL' if $CODE!~/0|1|INUSE/;
					$SQL=qq[SELECT get_cfu_text("$Q{imsi}","$CODE",$CFU_number)];
					my $TEXT_result=${SQL("$SQL",2)}[0];
					print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},$TEXT_result);
					&response('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'RSP',"$CODE $Q{USSD_CODE} $Q{USSD_DEST}");
					return "USSD $CODE";
			}#if number length
			else{#else check activation
			&response('LOG','SIG-USSD-CFU-REQUEST',"Code processing $Q{USSD_CODE} $Q{USSD_DEST}");
				my $SQL=qq[SELECT get_cfu_text("$Q{imsi}",'active',NULL)];
				my @SQL_result=&SQL($SQL);
				my $TEXT_result=$SQL_result[0]; 
				print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"$TEXT_result");
				&response('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'RSP',"$Q{USSD_CODE} $Q{USSD_DEST}");
				return "USSD $#SQL_result";
				}
	}#case 127
###
	case "128"{#country rates request
		&response('LOG','SIG-COUNTRY-RATES-REQUEST',"$Q{USSD_CODE}");
		&response('LOGDB','USSD',"$Q{transactionid}","$Q{imsi}",'OK',"$Q{USSD_CODE}");
		print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},${SQL(qq[NULL,'ussd',$Q{USSD_CODE}],1)}[0]);
		my $USSD_result=LWP('SIG_SendSMSMT',${SQL(qq[SELECT get_uri('SIG_SendSMSMT',"$Q{imsi}",NULL,"$Q{msisdn}",'mcc_new','ruimtools',NULL)],2)}[0]);
		#my $SQL_result=&LU_H(1);
		return 'USSD $SQL_result';
	}#case 128
	case "129"{#ussd codes request
		&response('LOG','SIG-USSD-CODES-REQUEST',"$Q{USSD_CODE}");
		&response('LOGDB','USSD',"$Q{transactionid}","$Q{imsi}",'OK',"$Q{USSD_CODE}");
		print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},${SQL(qq[NULL,'ussd',$Q{USSD_CODE}],1)}[0]);
		my $SMSMT_result=LWP('SIG_SendSMSMT',${SQL(qq[SELECT get_uri('SIG_SendSMSMT',NULL,NULL,"$Q{msisdn}",'get_ussd_codes','ruimtools',NULL)],2)}[0]);
		return "USSD $SMSMT_result";
	}#case 129
	
###
	else{#switch ussd code
		&response('LOG','SIG-USSD-UNKNOWN-REQUEST',"$Q{USSD_CODE}");
		&response('LOGDB','USSD',"$Q{transactionid}","$Q{imsi}",'ERROR',"$Q{USSD_CODE}");
		print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"UNKNOWN USSD REQUEST");
	return 'USSD -3';
	}#end else switch ussd code (no code defined)
}#end switch ussd code
}## END sub USSD ###################################
#
########### LWP #############################################
## Process all types of requests
## Return MSRN or NULL, Status
#################################################################
sub LWP{
use vars qw($lwp);
our $transaction_id=timelocal(localtime()).int(rand(1000));
our $MSG=$_[0];
our $URI=$_[1];
our @XML=();
#
&response('LOGDB',"$MSG","$transaction_id","$Q{imsi}",'REQ',"$URI"); 
#
if ($URI){
eval {use vars qw($URI @XML); alarm(10); local $SIG{ALRM} = sub { die "SSL timeout\n" }; &response('LOG',"LWP-$MSG-LWP-REQ","$URI");
my $LWP_response = $lwp->get($URI);
if ($LWP_response->is_success) {  @XML=$LWP_response->decoded_content; }#if success
else{ die $LWP_response->status_line; }#else success response
};#eval lwp
alarm(0);
	if ($@) {#if errors
		if ($@ =~ /SSL timeout/){ warn "Request timed out";	}#if timeout
		else{ warn "Error in request: $@"; }#else other errors
	}#if erorrs
}#if URI
else{return 0}#else URI empty
#
use vars qw(@XML);
if (@XML){
	&response('LOG',"$MSG-RESPOND","@XML") if $debug>=3;
	my $LWP_result=&XML_PARSE("@XML",$MSG);
	&response('LOGDB',$MSG,"$transaction_id","$Q{imsi}",'RSP',"$LWP_result") if $LWP_result;
	&response('LOGDB',$MSG,"$transaction_id","$Q{imsi}",'ERROR','LWP NO RESPOND') if !$LWP_result;
	return $LWP_result;
}#if lwp return
else{# timeout
	&response('LOG',"$MSG-REQUEST","Timed out 10 sec with socket");
	&response('LOGDB',$MSG,"$transaction_id","$Q{imsi}",'ERROR','Timed out 10 sec with socket');
	return 0;
}#end else
}########## END sub GET_MSRN ####################################
#
##### RC_API_CMD ################################################
## Process all types of commands to RC
## Accept CMD, Options
## Return message
#################################################################
sub rc_api_cmd{
my $auth_result=&auth('AGENT');
$Q{code}='get_msrn' if $Q{code} eq '1';#temp for old format
if ($auth_result==0){&response('LOG','RC-API-CMD',"AUTH OK $auth_result");}#if auth
else{
&response('LOGDB',"$Q{USSD_CODE}","$Q{transactionid}","$Q{imsi}",'ERROR',"NO AUTH $auth_result $Q{auth_key}");
print $new_sock &response('rc_api_cmd','OK',$Q{transactionid},"NO AUTH");
return 'CMD 1 NO AUTH';
}#else no auth				
my $result;
&response('LOG','RC-API-CMD',"$Q{code}");
&response('LOGDB',"$Q{code}","$Q{transactionid}","$Q{imsi}",'STAT',"$Q{'sub_code'} $Q{'options'}");
switch ($Q{code}){
	case 'ping' {#PING
		print $new_sock &response('rc_api_cmd','OK',$Q{transactionid},"PING OK");
		$result='0';
	}#case ping
	case 'get_msrn' {#GET_MSRN
		my $msrn=LWP('SIG_GetMSRN',${SQL(qq[SELECT get_uri(NULL,"$Q{imsi}",NULL,NULL,'SIG_GetMSRN',NULL,NULL)],2)}[0]);
	#	my $bill_result=${SQL(qq[select bill_agent("$Q{agent}",'SIG_GetMSRN'],2)}[0];
		if(!$Q{CFU}){#agents subscriber
		&response('LOGDB',"$Q{code}","$Q{transactionid}","$Q{imsi}",'OK',"");
		print $new_sock &response('rc_api_cmd','OK',$Q{transactionid},"$msrn") if $Q{options} ne 'cleartext';
		$msrn=~s/\+// if $Q{options} eq 'cleartext';#cleartext for ${EXTEN} usage
		print $new_sock $msrn if $Q{options} eq 'cleartext';
		return 'CMD 1';}#if agents subscriber
			else{#if CFU subscriber
		&response('LOGDB',"$Q{code}","$Q{transactionid}","$Q{imsi}",'OK',"CFU:$Q{login}");
		my $agent_TID="$Q{transactionid}";
	my $limit=LWP('get_session_time',${SQL(qq[SELECT get_uri(NULL,NULL,NULL,$Q{msrn},'get_session_time',$Q{SUB_ID},NULL)],2)}[0]) if $Q{SUB_OPTIONS}=~/CFU/;
		print $new_sock &response('rc_api_cmd','OK',$agent_TID,"$msrn","$limit") if $Q{options} ne 'cleartext';
		$msrn=~s/\+// if $Q{options} eq 'cleartext';#cleartext for ${EXTEN} usage
		print $new_sock "$agent_TID:$msrn:$limit" if $Q{options} eq 'cleartext';
				}#esle CFU
		return 'CMD 1';
	}#case 1
	case 'get_stat' {#GET STAT
		my $SQL;
		switch ($Q{sub_code}){#switch CMD
			case 'get_card_number'{$SQL=qq[SELECT $Q{sub_code}($Q{card_number})]}
			case 'get_rate'{$SQL=qq[SELECT round($Q{sub_code}($Q{msisdn},$Q{options}),2)]}
			case 'get_agent_msrn'{$SQL=qq[SELECT $Q{sub_code}("$Q{options}","$Q{agent}")]}#map reseller to agent
			else {$SQL=qq[SELECT -1]}
			}#switch CMD
			$result=${SQL("$SQL",2)}[0];
			print $new_sock &response('rc_api_cmd','OK',$Q{transactionid},"$result");
		}#case get_stat
	case 'send_ussd' {#SEND_USSD
		$result=&LWP('send_ussd',${SQL(qq[SELECT get_uri(NULL,NULL,NULL,$Q{msisdn},$Q{code},$Q{sub_code},NULL)],2)}[0]);
		print $new_sock &response('rc_api_cmd','OK',$Q{transactionid},"$Q{msisdn} $result");
		}#case send_ussd
	case 'get_session_time' {#Get max session time
		$result=&LWP('get_session_time',${SQL(qq[select get_uri(NULL,$Q{imsi},NULL,$Q{msisdn},'get_session_time',NULL,NULL)],2)}[0]);
		print $new_sock $result if $Q{options} eq 'cleartext';
		print $new_sock &response('rc_api_cmd','OK',$Q{transactionid},"$result") if $Q{options} ne 'cleartext';;
		}#case get_session_time
	case 'set_debug'{#set debug
		$debug=$Q{sub_code};
		$result=$debug;
		}#case set debug
	else {
		&response('LOG','RC-API-CMD-UNKNOWN',"$Q{code}");
		&response('LOGDB','API-CMD',"$Q{transactionid}","$Q{imsi}",'ERROR',"$Q{code}");
		print $new_sock &response('rc_api_cmd','OK',$Q{transactionid},"UNKNOWN CMD REQUEST");
		return 'CMD -1';
		}#else switch code
}#switch code
		&response('LOG','RC-API-CMD',"$Q{code} $result");
		&response('LOGDB',"$Q{code}","$Q{transactionid}","$Q{imsi}",'OK',"RESULT $result");
		return 'CMD $result';

}##### END sub RC_API_CMD ########################################
#
##### AGENT ################################################
## Process agent request
## Accept request type, imsi, reseller auth_key, options
## Return message to subscriber
#################################################################
sub agent{
use vars qq(%Q);
my ($ussd_code,$imsi,$agent_id,$ussd_dest,$ussd_ext,$agent_addr,$agent_key)=@_;
my $LWP_result;
$ussd_code='CB' if $ussd_code=~/111|112/;
$ussd_code='UD' if $ussd_code!~/111|112|LU/;
if (($agent_key)&&($agent_addr)){#if found key and address
		&response('LOG','AGENT-REQUEST-$ussd_code',"$imsi,$agent_id,$ussd_dest,$ussd_ext,$agent_addr,$agent_key");
		&response('LOGDB',"SIG_SendAgent_$ussd_code","$Q{transactionid}","$Q{imsi}",'SND',"AGENT $agent_id");
$LWP_result=LWP('SIG_SendAgent',${SQL(qq[SELECT get_uri(NULL,"Q{$imsi}","$agent_addr",NULL,"SIG_SendAgent_$ussd_code",$Q{USSD_DEST},$Q{USSD_EXT})],2)}[0]);
		my $bill_result=${SQL(qq[select bill_agent($agent_id,"SIG_SendResale_$ussd_code"],2)}[0];
		&response('LOG','AGENT-RESPONSE-$ussd_code',"$bill_result $LWP_result");
		&response('LOGDB',"SIG_SendAgent_$ussd_code","$Q{transactionid}","$Q{imsi}",'RSP',"AGENT $LWP_result $bill_result");
		print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"$LWP_result") if $ussd_code!='LU';
		return $LWP_result;# OK or <error code>
}else{#not found agent key or address
&response('LOG','AGENT-AUTH-KEY',"NOT FOUND $agent_key");
print $new_sock &response('auth_callback_sig','OK',$Q{transactionid},"AUTH FAILED: NO KEY");
return -1;
}#else no key or address
}# END sub AGENT
##################################################################
#
### SUB AUTH ##################################################################
# $data signed by $key = $digest
##
sub auth{
use vars qw(%Q $REMOTE_HOST $KEY);
my ($type,$data,$sign,$key)=@_;
return 0 if $Q{auth_key}=='7354bff766a40f54d17f6e397cbbba76';#temp for old format
&response('LOG',"RC-API-$type-AUTH","$type:$REMOTE_HOST:$Q{agent}:$Q{reseller}:$data:$sign")if $debug>3;
&response('LOG',"RC-API-$type-AUTH","$type $Q{agent} $Q{reseller}");
switch ($type){#select auth type
	case "AGENT"{#resale auth
		$REMOTE_HOST=~s/\.//g;
		$data=$REMOTE_HOST;
		$key=${SQL(qq[SELECT AES_DECRYPT(auth_key,"$KEY") from cc_agent WHERE login="$Q{agent}"],2)}[0];
		$sign=$Q{auth_key};
	}#case resale
	case "PAYMNT"{#paymnt auth
		$key=${SQL(qq[SELECT AES_DECRYPT(auth_key,"$KEY") from cc_epaymnter WHERE host="$REMOTE_HOST"],2)}[0];
	}#case paymnt
else{
	&response('LOG',"RC-API-AUTH-RETURNED","Error: UNKNOWN TYPE $type");
	}#end else switch type
}#end switch type 
my $digest=hmac_sha512_hex("$data","$key");
my $dgst=substr($digest,0,7);
my $sgn=substr($sign,0,7);
&response('LOG',"RC-API-$type-DIGEST-CHECK","$dgst eq $sgn")if $debug>=3;;
if ($digest eq $sign){#if ok
&response('LOG','RC-API-AUTH',"OK");
return 0;
}#end if ok
else{#digest != sign
&response('LOG','RC-API-AUTH',"NO AUTH");
return -1;
	}#else if auth OK
}#END sub auth ##################################################################
#
## SUB PAYMNT ###################################################################
sub PAYMNT{
use vars qw($new_id);
my @TR= keys %{$REQUEST->{payment}{transactions}{transaction}};
our ($SQL_T_result,$CARD_NUMBER,$AMOUNT);
my $SQL='';
$SQL=qq[INSERT INTO cc_epayments (`payment_id`, `ident`,`status`,`amount`,`currency`,`timestamp`,`salt`,`sign`,`transactions_ids`) values("$REQUEST->{payment}{id}","$REQUEST->{payment}{ident}","$REQUEST->{payment}{status}","$REQUEST->{payment}{amount}","$REQUEST->{payment}{currency}","$REQUEST->{payment}{timestamp}","$REQUEST->{payment}{salt}","$REQUEST->{payment}{sign}","@TR")];
my $SQL_P_result=&SQL($SQL);
&response('LOG','PAYMNT-EPMTS-SQL-RESULT',"$SQL_P_result");
&response('LOG','PAYMNT-AUTH-REQ',"PAYMNT,$REQUEST->{payment}{salt},$REQUEST->{payment}{sign}");
## AUTH
if (auth('PAYMNT',$REQUEST->{payment}{salt},$REQUEST->{payment}{sign})==0){
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
					$AMOUNT=$REQUEST->{payment}{transactions}{transaction}{$tr}{amount};
					$SQL=qq[INSERT into `msrn`.`cc_epayment_log` (`amount`, `paymentmethod`, `cardid`, `cc_owner`) values (round($AMOUNT*(SELECT value from cc_currencies WHERE currency='UAH')/100,3), "IPAY", (select id from cc_card where username="$CARD_NUMBER"),"$tr")];
					my $SQL_debit_result=&SQL($SQL);
					&response('LOG','PAYMNT-TR-DEBIT-SQL-RESULT',"$SQL_debit_result");
				}#end if debited
		}#foreach tr
}#end if auth
else{#else if auth
	$SQL_T_result="-1";
	&response('LOG','PAYMNT-AUTH-RESULT',"NO AUTH");
}#end esle if auth
	&response('LOGDB',"PAYMNT","$REQUEST->{payment}{id}",0,'RSP',"$SQL_T_result @TR");
	print $new_sock "200 $SQL_T_result";
	my $SMSMT_result=LWP('SIG_SendSMSMT',${SQL(qq[SELECT get_uri('SIG_SendSMSMT',NULL,NULL,NULL,"pmnt_$SQL_T_result","$CARD_NUMBER","$REQUEST->{payment}{id}")],2)}[0]);
	return $SQL_T_result;
}# END sub PAYMNT ##################################################################
#
## SMS section ##########################################################
#########################################################################
### sub SMS #############################################################
sub SMS{
use vars qw(%Q);
my ($flag,$sms_opt,$sms_to,$sms_text,$type,$SQL);
$flag=$Q{USSD_DEST};
$sms_opt=$Q{USSD_EXT};
our $sms_result;
#
&response('LOG','SMS-REQ',"$Q{USSD_DEST} $Q{USSD_EXT}") if $debug>=3;
$flag=~/(\d{1})(\d{1})/;
my ($page,$num_page)=($1,$2);
#
if ($page eq '1'){#if first page
	$sms_opt=~/^(\D|00)?([1-9]\d{7,15})\*(\w+)#/;
	$sms_to='+'.$2;
	$sms_text=$3;
}#if first page
else{#else next page
	$sms_to="multipage";
	$sms_opt=~/(\w+)#/;
	$sms_text=$1;
}#else next page
#
&response('LOG','SMS-REQ',"$flag,$sms_to");
$SQL=qq[INSERT INTO cc_sms (`id`,`src`,`dst`,`flag`,`text`,`inner_tid`,`imsi`) values ("$Q{transactionid}","$Q{msisdn}","$sms_to","$flag","$sms_text","$INNER_TID","$Q{imsi}")];
my $sql_result=&SQL($SQL);
&response('LOG','SMS-REQ',"$sql_result");
#if insert ok
	if ($sql_result>0){#if insert ok
#		$flag=~/(\d{1})(\d{1})/;
#if num page
			if ($num_page eq $page){#if num page
				($sms_text,$sms_to,$type)=split('::',${SQL(qq[SELECT get_sms_text("$Q{msisdn}",$num_page,$Q{imsi})],2)}[0]);
#if return content		
				if (($sms_text) and ($sms_to=~/^\+([1-9]\d{7,15})/)){#if return content
				&response('LOG','SMS-ENC-RESULT',"$sms_text");
				$sms_text=uri_escape($sms_text);
				my $sms_from=$Q{msisdn};
					&response('LOG','SMS-TEXT-ENC-RESULT',"$sms_text");
					&response('LOG','SMS-SEND-PARAM',"$sms_to,'ruimtools',$sms_text,$sms_from");
#internal subscriber
						if ($type eq 'IN'){#internal subscriber
							&response('LOG','SMS-REQ',"INTERNAL");
		$sms_result=LWP('SIG_SendSMS_MT',${SQL(qq[SELECT get_uri('SIG_SendSMSMT',NULL,"$sms_to","$Q{msisdn}",'SIG_SendSMS_MT',"$Q{msisdn}","$sms_text")],2)}[0]);
						}#if internal
						elsif($type eq 'OUT'){#external subscriber
							&response('LOG','SMS-REQ',"EXTERNAL");
		$sms_result=LWP('SIG_SendSMS_MO',${SQL(qq[SELECT get_uri('SIG_SendSMSMO',NULL,"$sms_to","$Q{msisdn}",'SIG_SendSMS_MO',"$Q{msisdn}","$sms_text")],2)}[0]);
						}#else external
					$SQL=qq[UPDATE cc_sms set status="$sms_result" where src="$Q{msisdn}" and flag like "%$num_page" and status=0 and imsi=$Q{imsi}];
					my $sql_update_result=&SQL($SQL);
					return $sms_result;
#if return content		
				}#if return content
				else{#mark sms as error
my $sql_update_result=${SQL(qq[UPDATE cc_sms set status="-1" where src="$Q{msisdn}" and flag like "%$num_page" and status=0 and imsi=$Q{imsi}],2)}[0];
return 3;
					}#else mark sms
				}#if num_page==page
				else{#else multipage
					return 2;
					}#end else multipage
					}#if insert
				else{#else no insert
						return -1;
					}#end else
}# END sub USSD_SMS #############################################################
#
### sub MO_SMS ##################################################################
# Authenticate outbound SMS request.
###
sub MO_SMS{
use vars qw(%Q);
print $new_sock &response('MO_SMS','OK',$Q{transactionid},0,'RuimTools');#By default reject outbound SMS MO
&response('LOGDB','MO_SMS',$Q{transactionid},$Q{imsi},'RSP',"RuimTools 0");
}#end sub MO_SMS
#
### sub MT_SMS ##################################################################
#
# Authenticate inbound SMS request ##############################################
###
sub MT_SMS{
print $new_sock &response('MT_SMS','OK',$Q{transactionid},1);# By default we accept inbound SMS MT
&response('LOGDB','MT_SMS',$Q{transactionid},$Q{imsi},'RSP',"1");
}#end sub MT_SMS
#
### sub MOSMS_CDR ##################################################################
#
# MOSMS (Outbound) CDRs ############################################################
##
sub MOSMS_CDR{
	my $CDR_result=&SMS_CDR;
	&response('LOG','MOSMS_CDR',$CDR_result);
	print $new_sock &response('MOSMS_CDR','OK',$Q{transactionid},$CDR_result);
	&response('LOGDB','MOSMS_CDR',$Q{transactionid},$Q{imsi},'RSP',"$CDR_result");
}#end sub MOSMS_CDR ################################################################
#
### sub MTSMS_CDR ##################################################################
# MTSMS (Inbound) CDRs
###
sub MTSMS_CDR{
	my $CDR_result=&SMS_CDR;
	&response('LOG','MTSMS_CDR',$CDR_result);
	print $new_sock &response('MTSMS_CDR','OK',$Q{transactionid},$CDR_result);
	&response('LOGDB','MTSMS_CDR',$Q{transactionid},$Q{imsi},'RSP',"$CDR_result");
}#end sub MTSMS_CDR ################################################################
#
### sub SMSContent_CDR
# SMS Content CDRs #################################################################
##
sub SMSContent_CDR{
	use vars qw(%Q);#workaround #19 C9RFC
	$Q{'cdr_id'}='NULL';#workaround #19 C9RFC
	my $CDR_result=&SMS_CDR;
	&response('LOG','SMSContent_CDR',$CDR_result);
	print $new_sock &response('MT_SMS','OK',$Q{transactionid},$CDR_result);
	&response('LOGDB','SMSContent_CDR',$Q{transactionid},$Q{imsi},'RSP',"$CDR_result");
}#end sub SMSContent_CDR ############################################################
#
### SMS_CDR #########################################################################
# Processing CDRs for each type of SMS
###
sub SMS_CDR{
use vars qw(%Q);
#
#$Q{timestamp}=uri_unescape($Q{timestamp});
#$Q{message_date}=uri_unescape($Q{message_date});
#
my $SQL=qq[INSERT into `msrn`.`cc_sms_cdr` ( `id`, `msisdn`, `allow`, `reseller_charge`, `timestamp`, `smsc`, `user_charge`, `mnc`, `srcgt`, `request_type`, `smsfrom`, `IOT`, `client_charge`, `transactionid`, `route`, `imsi`, `user_balance`, `message_date`,`carrierid`,`message_status`,`service_id`,`sms_type`,`sender`,`message`,`original_cli`) values ( "$Q{cdr_id}", "$Q{msisdn}", "$Q{allow}", "$Q{reseller_charge}", "$Q{timestamp}", "$Q{smsc}", "$Q{user_charge}", "$Q{mnc}", "$Q{srcgt}", "$Q{request_type}", "$Q{smsfrom}", "$Q{IOT}", "$Q{client_charge}", "$Q{transactionid}", "$Q{route}", "$Q{imsi}", "$Q{user_balance}", "$Q{message_date}","$Q{carrierid}","$Q{message_status}","$Q{service_id}","$Q{sms_type}","$Q{sender}","$Q{message}","$Q{original_cli}")];
my $sql_result=&SQL($SQL);
&response('LOG','SMS_CDR',$sql_result);
return $sql_result; 
}#end sub SMS_CDR ##################################################################
# end SMS section ##################################################################
#
### sub DataAUTH ###################################################################
sub DataAUTH{
use vars qw(%Q);
my $SQL=qq[SELECT data_auth("$Q{IMSI}","$Q{MCC}","$Q{MNC}")];
my @sql_result=&SQL($SQL);
my $data_auth=$sql_result[0];
&response('LOG','DataAUTH',$data_auth);
print $new_sock &response('DataAUTH','OK',$data_auth);
}
### END sub DataAUTH ###############################################################
#
### sub POSTDATA ###################################################################
sub POSTDATA{
&response('LOG','POSTDATA',);
print $new_sock "200";	
} 
### END sub POSTDATA ##############################################################
#
### sub msisdn_allocation #########################################################
# First LU with UK number allocation
###
sub msisdn_allocation{
use vars qw(%Q);
my $SQL=qq[UPDATE cc_card set phone="$Q{MSISDN}" where useralias=$Q{IMSI} or firstname=$Q{IMSI}];
my $sql_result=&SQL($SQL);
print $new_sock &response('msisdn_allocation','OK',$Q{transactionid},$sql_result);
&response('LOG','msisdn_allocation',$sql_result);
&response('LOGDB','msisdn_allocation',1,$Q{IMSI},'RSP',"$Q{MSISDN} $sql_result");	
}#end sub msisdn_allocation #######################################################
#
######### END #################################################	