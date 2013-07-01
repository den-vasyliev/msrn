#!/usr/bin/perl
#/usr/bin/perl
#/opt/local/bin/perl -T
#
########## VERSION AND REVISION ################################
## Copyright (C) 2012, RuimTools denis@ruimtools.com
##
my $rev='MSRN.ME 010713-rev.70.0';
##
#################################################################
## 
########## MODULES ##############################################
use threads;
use threads::shared;
use FCGI;
use WWW::Curl::Easy;
use Redis;
#use Net::Telnet();
use DBI;
use Data::Dumper;
use IO::Socket;
#use XML::Simple;
#use XML::Bare::SAX::Parser;
use XML::Bare;
#Business::PayPal;
use Digest::SHA qw(hmac_sha512_hex);
use Digest::MD5 qw(md5_hex);
use URI::Escape;
use Text::Template;
use Email::Valid;
use Switch;
use POSIX;
use Time::Local;
use Time::HiRes qw(gettimeofday);
use Benchmark qw(:hireswallclock);
use IO::File;
use File::Copy;
use Encode;
use warnings;
use strict;
no warnings 'once';
########## END OF MODULES #######################################
#
########## CONFIG STRINGS #######################################
our $R0 = Redis->new(server => 'localhost:6379',encoding => undef,);
$R0->hset('CONF','rev',"$rev");
#my %CONF :shared;
my %CONF=$R0->hgetall('CONF');
my %SYS=$R0->hgetall('STATUS');
my %SIG=$R0->hgetall('SIG');
####### MAKE FORK AND CHROOT ####################################
#chroot("/opt/ruimtools/") or die "Couldn't chroot to /opt/ruimtools: $!";
our $pid = fork;
exit if $pid;
die "Couldn't fork: $!" unless defined($pid);
POSIX::setsid() or die "Can't start a new session: $!";
my $PIDFILE = new IO::File;
$PIDFILE->open(">/opt/ruimtools/tmp/rcpi.pid");# change to programm path (!)
print $PIDFILE $$;
$PIDFILE->close();
###############################################################
# 
####### SIG handle to reload configuration kill -HUP ##########
#$SIG{INT} = $SIG{TERM}= 
$SIG{HUP} = \&phoenix;
# trap $SIG{PIPE}
sub phoenix {
	print("RELOAD CONFIGURATION...");
	my $SELF = $0;   # needs full path
	exec($SELF) or die "Couldn't restart: $!\n";
}#phoenix
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
#################################################################
#
########## LOG FILE #############################################
our $LOGFILE = IO::File->new("/opt/ruimtools/log/rcpi.log", "a+");
########## CONFIGURATION FOR MAIN SOCKET ########################
#$HOST='127.0.0.1' if $SERVER eq 'pbx';
#$HOST='10.10.10.2' if $SERVER eq 'lab';
#$HOST='127.0.0.1' if $SERVER eq 'dmx';
#$PASS='ca11me!' if $SERVER eq 'dmx';
#2 if $SERVER eq 'dmx';
#################################################################
#
########## CONNECT TO MYSQL #####################################
our $dbh = DBI->connect_cached('DBI:mysql:msrn',$CONF{login},$CONF{pass});die "No auth!" unless defined($dbh);
##################################################################
#
############ ACTION DB CACHE #####################################
#my $rows=[];
#while (my $row = ( shift(@$rows) || shift(@{$rows=$sth->fetchall_arrayref(undef,300)||[]}))){;}#while
##################################################################
#
############### XML ##############################################
#our $xs = XML::Simple->new(ForceArray => 0,KeyAttr => {});
#our $xml=new XML::Bare;
##################################################################
#
########## OPEN SOCKET ###########################################
our $sock = FCGI::OpenSocket("$CONF{host}:$CONF{port}",10);
########## REV PRINT #############################################
print "$CONF{rev} Ready at $$ debug level $CONF{debug}\n";
####################### MULTITHREADING ###########################
#default $min_ready_count = 10;# limit amount of connections to db
#default $max_request_count = 500;# max connectons
########### MAIN HASH ############################################
########### WRITEBLDE PARAMETERS #################################
share($CONF{'debug'});
share($CONF{'debug_imsi'});
share($CONF{'fake-msrn'});
share($CONF{'fake-xml'});
share($CONF{'fake-agent-xml'});
share($CONF{'fake-call'});
share($CONF{'max-call-time'});
share($CONF{'ready_count'});
share($CONF{'call_count'});
##################################################################
async(\&handler,1);#start redis thread
#
use vars qw(%Q $dbh);
while (1){
 lock($CONF{'ready_count'});
########### RUN THREADS ASYNC #####################################
 for (; $CONF{'ready_count'} < $CONF{'min_ready_count'}; $CONF{'ready_count'}++){ async(\&handler) }
##################################################################
 cond_wait($CONF{'ready_count'});
}#while
#
sub set_ready_flag{
	lock($CONF{'ready_count'}); 
	$CONF{'ready_count'}++; 
#	$Q{sub_code}=0;#change it (!)
#	$Q{SUB_GRP_ID}=0;#change it (!)
}#set_ready
#
sub clear_ready_flag{
	lock($CONF{'ready_count'});
	$CONF{'ready_count'}--;
	cond_broadcast($CONF{'ready_count'});
}#clear_ready
############ THREADS HANDLER #########################################
sub handler{
	require FCGI;
	our %Q=();
	my $redis_start=shift;
	my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV, $sock);
  	my $request_count = 0;
    my $tid=threads->tid();
    our $t0;					
############ REDIS SYNC TRANSACTIONS ####################################
if ($redis_start){#thread for redis sync 
#my $dbh = DBI->connect('DBI:mysql:msrn',$CONF{login},$CONF{pass});
	my $i=0;
	my @subscriptions=$R0->lrange('subscriptions',0,-1);
	$R0->subscribe(@subscriptions,
		sub{
			my ($value,$topic,$subscribtions)=@_;
######## CMD CONF ###
			if ($topic eq 'CONF'){
				my $R = Redis->new(server => 'localhost:6379',encoding => undef,);
				$CONF{$value}=$R->hget('CONF',$value);
				$R->zadd('tid',$i,"[API-COMMAND-$topic]: $value -> $CONF{$value}");
				$R->quit;
				$i++;
			}#if conf_reload
#
my $SQL='';
 $SQL=qq[INSERT INTO cc_transaction_memory (`id`,`type`,`inner_tid`,`transaction_id`,`IMSI`,`status`,`info`,`timer`) values ($value)] if $topic eq 'transactions';
 #$SQL=qq[INSERT INTO cc_transaction SELECT * FROM cc_transaction_memory WHERE inner_tid=$value limit 100] if $topic eq 'transactions';
#print "$SQL\n";
# 			$dbh->do($SQL) if $value&&$SQL;

				}#sub
					);#subscribe
$R0->wait_for_messages($CONF{redis_sync_timeout}) while $CONF{redis_keep_sync};
}#if tid 1
########################################################################
########## PROCCESING CONNECTIONS ######################################
  while ($request_count++ < $CONF{'max_request_count'} && $request->Accept() >= 0){
my ($s, $usec) = gettimeofday();my $format = "%06d";$usec=sprintf($format,$usec);$Q{INNER_TID}=$s.$usec;
$Q{'timestamp'}=strftime("%Y-%m-%d %H:%M:%S", localtime);
$Q{'tid'}=int(rand(1000000));
our $redis_sock = new IO::Socket::INET (PeerAddr =>'127.0.0.1',PeerPort => 6379,Proto => 'tcp',blocking=>0);
    clear_ready_flag;
	my $env = $request->GetEnvironment();
 $t0=Benchmark->new;
	$Q{REMOTE_ADDR}=$env->{REMOTE_ADDR};
	########### SET TIMER & INNER TID #####################################
	my ($t1,$t2,$td0);
########### IF POST REQUEST #####################################
	if ($env->{REQUEST_METHOD} eq 'POST'){$Q{REQUEST}=<STDIN>;}#if post
########### IF GET REQUEST ######################################
		elsif($env->{REQUEST_METHOD} eq 'GET'){$Q{REQUEST}=$env->{QUERY_STRING};}#elsif GET
########### IF VALID REQUEST #####################################
			if($Q{REQUEST}=~m/request_type|api_cmd/g){#if valid request
				print main();
			}else{#else not valid request
			print response('api_cmd','PLAINTEXT',$CONF{page404});
					}# if empty set
			$t2=Benchmark->new;
			$td0 = timediff($t2, $t0);	
	logger('RDB',"COMMIT","DONE:$Q{REMOTE_ADDR} DEBUG:$CONF{debug} TID:$tid IN: ".substr($td0->[0],0,8)." ##########");
#
$redis_sock->close;
set_ready_flag;
  }#while < max_request_count
  clear_ready_flag;
  threads->self->detach();
}#handler
#
########## MAIN #################################################
sub main{
use vars qw(%Q $dbh);
our $R = Redis->new(server => 'localhost:6379',encoding => undef,);
#
$dbh = DBI->connect_cached('DBI:mysql:msrn',$CONF{login},$CONF{pass});
#
	if (XML_PARSE($Q{REQUEST},'REQUEST')>0){#if not empty set
		my $head= redis('KEYS',"REQUEST_TYPE:$Q{request_type}") ? $Q{request_type} : return response('MAIN','ERROR','REQUEST TYPE UNKNOWN');
		uri_unescape($Q{calldestination})=~/^\*(\d{3})(\*|\#)(\D{0,}\d{0,}).?(.{0,}).?/ if $Q{calldestination};
		($Q{USSD_CODE},$Q{USSD_DEST},$Q{USSD_EXT})=($1,$3,$4);
		$Q{imsi}=$Q{imsi} ? $Q{imsi} : $Q{IMSI} ? $Q{IMSI} :0;
		$head=$Q{USSD_CODE} if $Q{calldestination};
		$Q{request_type}="payment" if $Q{salt};
		$Q{request_type}="data" if $Q{SessionID};
		$Q{request_type}="postdata" if $Q{calllegid};
		$Q{imsi}=$Q{IMSI} if $Q{request_type} eq 'msisdn_allocation';
		$Q{transactionid}=$Q{cdr_id} if $Q{request_type} eq 'msisdn_allocation';
		$Q{transactionid}=$Q{SessionID} if $Q{SessionID};#DATA
		$Q{imsi}=$Q{GlobalIMSI} if $Q{SessionID};#DATA
#			my $IN_SET="$head:";#need request type and : as first INFO
#			$IN_SET=$IN_SET.uri_unescape($Q{msisdn}).":$Q{mcc}:$Q{mnc}:$Q{tadig}" if  $Q{msisdn};#General
#			$IN_SET=$IN_SET."$Q{ident}:$Q{amount}" if $Q{salt};#PAYMNT
#			$IN_SET=$IN_SET."$Q{TotalCurrentByteLimit}" if $Q{SessionID};#DATA AUTH
#			$IN_SET=$IN_SET."$Q{calllegid}:$Q{bytes}:$Q{seconds}:$Q{mnc}:$Q{mcc}:$Q{amount}" if $Q{calllegid};#POSTDATA
#
########### GET ACTION TYPE ######################################
if ($Q{imsi}&&$R->hlen("imsi:$Q{imsi}")){
	my %SUB=$R->hgetall("imsi:$Q{imsi}");
	map {$Q{$_}=$SUB{$_}} keys %SUB;
	}elsif($Q{imsi}){
	$Q{email_STATUS}='IMSI NOT FOUND'; 
	email(); 
	return response('MOC_response','OK','SIM NOT REGISTERED')
	}#if imsi
########### SET SUBREF ##########################################
my	$ACTION_TYPE=$Q{request_type}; $ACTION_TYPE='agent' if ($Q{SUB_GRP_ID}>1&&$Q{request_type} ne 'api_cmd');
	eval {our $subref=\&$ACTION_TYPE;};warn $@ if $@;  logger('LOG',"MAIN-ACTION-SUBREF","ERROR $ACTION_TYPE $@") if $@;
##################################################################
use vars qw($subref);
#
########### USSD DIRECT CALL ###########
if (!$Q{USSD_CODE} && $Q{request_type} eq 'auth_callback_sig'){
uri_unescape($Q{calldestination})=~/^\*(\d{7,14})\#/;
$Q{USSD_DEST}=$1;
$Q{USSD_CODE}=112; 
}#if USSD DIRECT CALL
########################################
our ($ACTION_STATUS,$ACTION_CODE,$ACTION_RESULT);
		eval {
		($ACTION_STATUS,$ACTION_CODE,$ACTION_RESULT)=&$subref();
		};warn $@ if $@;  logger('LOG',"MAIN-ACTION-SUBREF","ERROR $ACTION_TYPE $@") if $@;
		logger('LOG',"MAIN-ACTION-RESULT-$ACTION_TYPE","$ACTION_STATUS $ACTION_CODE $ACTION_RESULT") if $CONF{debug}==4;
		bill($Q{request_type}) if $ACTION_CODE>0;
		$R->quit;$dbh->disconnect;
		return "$ACTION_RESULT" if $ACTION_STATUS;
		return &response('MOC_response','OK','SORRY NO RESULT #'.__LINE__) if !$ACTION_STATUS;
}#if keys
else{#else if keys
	return &response('LU_CDR','ERROR','INCORRECT KEYS #'.__LINE__,0);
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
use vars qw($R);
$_[0]=~s/\r\n//g;
my $REQUEST_LINE=$_[0];
my $REQUEST_OPTION=$_[1];
my @QUERY='';
#
if ($REQUEST_LINE=~m/xml version/){
logger('LOG',"XML-PARSE-REQUEST",$REQUEST_LINE) if $CONF{debug}==4;
my $xml=new XML::Bare(text=>$REQUEST_LINE, simple =>1);
$Q{REQUEST}=$xml->parse();
$Q{REQUEST}=$Q{REQUEST}->{@{[keys $Q{REQUEST}]}[3]};
}#if xml
else{#CGI REQUEST
	logger('LOG',"CGI-PARSE-REQUEST",$Q{REQUEST}) if $CONF{debug}==4;
		$Q{REQUEST}=~tr/\&/\;/;
		my %Q_tmp=split /[;=]/,$Q{REQUEST}; map {$Q{$_}=uri_unescape($Q_tmp{$_})} keys %Q_tmp;
		return scalar keys %Q_tmp;
}#else cgi
#
switch ($REQUEST_OPTION){
	case 'REQUEST' {
		if($Q{REQUEST}){
		logger('LOG',"XML-PARSE-KEYS", join(',',sort keys $Q{REQUEST}->{api_cmd})) if $CONF{debug}==4;
		map {$Q{$_}=$Q{REQUEST}->{api_cmd}{$_}{value} if $_!~/^_(i|z|pos)$/;} keys $Q{REQUEST}->{api_cmd};
		$Q{request_type}='api_cmd';
		return scalar keys %Q;
		}
##if request in 'payments' format		
#		elsif($Q{REQUEST}->{payment}){
#			logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION",'PAYMENTS') if $CONF{debug}==4;;
#			our %Q=('request_type'=>'PAYMNT');
#			$Q{'transactionid'}=$Q{REQUEST}->{payment}{id};
#			my @KEYS= keys %{ $Q{REQUEST}->{payment} };
#				foreach my $xml_keys (@KEYS){
#					logger('LOG',"XML-PARSE-RETURN-KEYS","$xml_keys=$Q{REQUEST}->{payment}{$xml_keys}") if $CONF{debug}==4;
#					$Q{$xml_keys}=$Q{REQUEST}->{payment}{$xml_keys};
#				}#foreach xml_keys
#			return %Q;
#		}#elsif payments
#if request in 'postdata' format
		elsif($Q{REQUEST}->{'complete-datasession-notification'}){
		logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION",'POSTDATA') if $CONF{debug}==4;
		our %Q=('request_type'=>'POSTDATA');
		$Q{'transactionid'}=$Q{REQUEST}->{'complete-datasession-notification'}{callid}{value};
		my @KEYS= keys %{ $Q{REQUEST}->{'complete-datasession-notification'}{callleg}{value} };
		foreach my $xml_keys (@KEYS){#foreach keys
				if ((ref($Q{REQUEST}->{'complete-datasession-notification'}{callleg}{$xml_keys}{value}) eq 'HASH')&&($xml_keys eq 'agentcost')){#if HASH
					my @SUBKEYS= keys %{ $Q{REQUEST}->{'complete-datasession-notification'}{callleg}{$xml_keys}{value} } ;
					foreach my $sub_xml_keys (@SUBKEYS){# foreach subkeys
	logger('LOG',"XML-PARSE-RETURN-KEYS","$sub_xml_keys=$Q{REQUEST}->{'complete-datasession-notification'}{callleg}{$xml_keys}{$sub_xml_keys}{value}") if $CONF{debug}==4;
						$Q{$sub_xml_keys}=$Q{REQUEST}->{'complete-datasession-notification'}{callleg}{$xml_keys}{$sub_xml_keys}{value};
					}#foreach sub xml_keys
				}#if HASH
					else{#else not HASH
					logger('LOG',"XML-PARSE-RETURN-KEYS","$xml_keys=$Q{REQUEST}->{'complete-datasession-notification'}{callleg}{$xml_keys}{value}") if $CONF{debug}==4;
					$Q{$xml_keys}=$Q{REQUEST}->{'complete-datasession-notification'}{callleg}{$xml_keys}{value};
							}#else not HASH
					}#foreach xml_keys
				my $SQL=qq[select useralias from cc_card where phone like "%$Q{'number'}"];
				my @sql_records=&SQL($SQL);
				$Q{imsi}=$sql_records[0];
			return %Q;
		}#elsif postdata
		else{#unknown format
			logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION",'UNKNOWN FORMAT') if $CONF{debug}==4;
			return;
		}#else unknown
	}#xml
	case /get_msrn/ {
		$Q{msrn}=$Q{REQUEST}->{MSRN_Response}{MSRN}{value};
		$Q{mcc}=$Q{REQUEST}->{MSRN_Response}{MCC}{value};
		$Q{mnc}=$Q{REQUEST}->{MSRN_Response}{MNC}{value};
		$Q{tadig}=$Q{REQUEST}->{MSRN_Response}{TADIG}{value};
		$Q{msrn}=~s/\+//;#supress \+ from xml response (!)
		our $ERROR=$Q{REQUEST}->{Error_Message} ? $Q{REQUEST}->{Error_Message}{value} : 0;
		logger('LOG',"XML-PARSER-DONE","$Q{msrn} $Q{mcc} $Q{mnc} $Q{tadig} $Q{mtc} $ERROR") if $CONF{debug}==4;
		$Q{mtc}= redis('keys',"PLMN:$Q{tadig}:*") ? redis('get',$R->keys("PLMN:$Q{tadig}:*")) : 0;
		redis('hset',"$Q{imsi}:msrn",'msrn','OFFLINE') if $Q{msrn} eq 'OFFLINE';
		redis('EXPIRE',"$Q{imsi}:msrn",300) if $Q{msrn} eq 'OFFLINE';
		bill($REQUEST_OPTION) if $ERROR==0;
		logger('LOG',"XML-PARSED-$REQUEST_OPTION","$Q{msrn} $Q{mcc} $Q{mnc} $Q{tadig} $Q{mtc} $ERROR") if $CONF{debug}==4;
		return $Q{msrn};
	}#msrn
	case 'send_ussd' {
		my $USSD=$Q{REQUEST}->{USSD_Response}{REQUEST_STATUS}{value};
		our $ERROR=$Q{REQUEST}->{Error_Message}{value};
		logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$USSD $ERROR") if $CONF{debug}==4;
		return $USSD;
	}#ussd
	case /sms_m/ {
		my $SMS=$Q{REQUEST}->{SMS_Response}{REQUEST_STATUS}{value};
		our $ERROR=$Q{REQUEST}->{Error_Message}{value};
		logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$SMS $ERROR") if $CONF{debug}==4;
		return "$ERROR$SMS";
	}#sms
	case /agent/ {
		my $USSD=$Q{REQUEST}->{RESALE_Response}{RESPONSE}{value};
		our $ERROR=$Q{REQUEST}->{Error_Message}{value};
		logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$USSD $ERROR") if $CONF{debug}==4;
		return $USSD;
	}#resale
	case 'get_session_time' {
		my $TIME=$Q{REQUEST}->{RESPONSE}{value};
		our $ERROR=$Q{REQUEST}->{Error_Message}{value};
		logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$TIME $ERROR") if $CONF{debug}==4;
		return "$ERROR$TIME";
	}#get time
	case 'get_user_info' {
		my $BALANCE=$Q{REQUEST}->{Balance}{value};
		our $ERROR=$Q{REQUEST}->{Reason}{value};
		logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$BALANCE $ERROR") if $CONF{debug}==4;
		return "$ERROR$BALANCE";
	}#get user info
	case 'set_user_balance' {
		my $BALANCE=$Q{REQUEST}->{Result}{value};
		our $ERROR=$Q{REQUEST}->{Reason}{value};
		logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$BALANCE $ERROR") if $CONF{debug}==4;
		return "$ERROR$BALANCE";
	}#set user balance
	case 'new_user' {
		my $NEW=$Q{REQUEST}->{Result}{value};
		our $ERROR=$Q{REQUEST}->{Reason}{value};
		logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$NEW $ERROR") if $CONF{debug}==4;
		return "$ERROR$NEW";
	}#new user
	case /siminfo/i {
		$Q{PIN}=$Q{REQUEST}->{Sim}{Password}{value};
		our $ERROR=$Q{REQUEST}->{Error}{value};
		logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","xxxx $ERROR") if $CONF{debug}==4;
		return "xxxx$ERROR";
	}#sim info	
	else {
		print logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION",'NO OPTION FOUND $@') if $CONF{debug}==4;
		return "Error: $@";}
}#switch OPTION
}#END sub XML_PARSE
#
########## GET TYPE #############################################
## Resolve request type action with cc_actions
## Checks each parameter with database definition 
## Returns code of request type or 2 (no such type) or 3 (error)
#################################################################
#sub GET_TYPE{
#use vars qw(%Q);
#my $request_type=$_[0];
#
#uri_unescape($Q{calldestination})=~/^\*(\d{3})(\*|\#)(\D{0,}\d{0,}).?(.{0,}).?/ if $Q{calldestination};
#($Q{USSD_CODE},$Q{USSD_DEST},$Q{USSD_EXT})=($1,$3,$4);
#$Q{imsi}=0 if !$Q{imsi};
#$Q{imsi}=$Q{IMSI} if $Q{IMSI};
#my $R = Redis->new(server => 'localhost:6379',encoding => undef,);
#my %SUB=$R->hgetall("imsi:$Q{imsi}") if $Q{imsi}>0;
#$R->quit;
#map {$Q{$_}=$SUB{$_}} keys %SUB;
#		foreach my $item(keys %Q){
#				logger('LOG','GET-TYPE',"$item=$Q{$item}") if $CONF{debug}==5;
#}#foreach item

#	return $Q{request_type};
#}########## END GET_TYPE ########################################
#
########## SQL ##################################################
## Performs SQL request to database
## Accept SQL input
## Return SQL records or mysql error
#################################################################
sub SQL{ 
	#(!) -skip-column-names
use vars qw($LOGFILE $dbh $timer);
my $SQL=qq[$_[0]];
my $flag=qq[$_[1]] if $_[1];
$flag=-1 if !$_[1];
$SQL=qq[SELECT get_text($SQL)] if $flag eq '1';
#my $now = localtime;
#
my ($rc, $sth);
our (@result, $new_id,$error_str);
#
@result=();
if($SQL!~m/^SELECT/i){#INSERT/UPDATE request
logger('LOG','SQL-MYSQL-GET',"DO $SQL") if $CONF{debug}==4;
	$rc=$dbh->do($SQL);#result code
	push @result,$rc;#result array
	$new_id = $dbh -> {'mysql_insertid'};#autoincrement id
}#if SQL INSERT UPDATE
else{#SELECT request
logger('LOG','SQL-MYSQL-GET',"EXEC $SQL") if $CONF{debug}==4;
	$sth=$dbh->prepare($SQL);
	$rc=$sth->execute;#result code
	@result=$sth->fetchrow_array;
#	$sth->finish();
}#else SELECT
#
if($rc){#if result code
	our $sql_aff_rows =$rc;
	$new_id=0 if !$new_id;;
	logger('LOG','SQL-MYSQL-RETURNED-[code/array/id]',"$rc/@result/$new_id") if $CONF{debug}==4;
	return \@result if $flag;
	return @result; 
}#if result code
else{#if no result code
	#$error_str=;
	logger('LOG','SQL-MYSQL-RETURNED','Error: '.$dbh->errstr) if $CONF{debug}==4;
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
use vars qw($LOGFILE $t0 $R);
$Q{transaction_id}=$Q{transactionid};
(my $ACTION_TYPE, my $RESPONSE_TYPE,$Q{display_message})=@_;
#my	($ROOT,$SUB1,$SUB2,$SUB3)=split('::',redis('hget','response',$ACTION_TYPE));
my $HEAD=qq[Content-Type: text/xml\n\n<?xml version="1.0" ?>];
#
switch ($RESPONSE_TYPE){
	case 'OK'{
		my $xml=new XML::Bare(simple=>1);
		my $hash->{$ACTION_TYPE}= my $rec={};
			foreach my $value ($R->SMEMBERS("RESPONSE:$ACTION_TYPE")){
				$rec->{$value}={value => $Q{$value}} if $Q{$value};
			}
		return $HEAD.$xml->xml($hash);
	}#case OK
	case 'ERROR'{
	my	$ERROR=qq[<Error><Error_Message>$Q{display_message}</Error_Message></Error>\n];
		return $HEAD.$ERROR;
	}#case ERROR
	case 'PLAINTEXT'{
		$HEAD="Content-Type: text/html\n\n";
		return $HEAD.$Q{display_message};
	}#case PLAINTEXT
}#switch
}########## RESPONSE #############################################
########## LOGGER ##############################################
sub logger{
use vars qw($LOGFILE $t0);
## SET TIMERS
my $t3=Benchmark->new;
my $td1=timediff($t3, $t0);
my $timer=substr($td1->[0],0,8);
my ($s, $usec) = gettimeofday();my $format = "%06d";$usec=sprintf($format,$usec);
my $now=$Q{timestamp}.":$usec";
##
my ($LOG_TYPE,$RESPONSE_TYPE,$LOG)=@_;
#
switch ($LOG_TYPE){
case 'RDB'{
	redis('zadd',$Q{INNER_TID},$timer,"[$now]-[$Q{INNER_TID}]-[$timer]-[API-LOG-$RESPONSE_TYPE]:$LOG") if $CONF{debug}>0 and $CONF{'debug_imsi'} eq $Q{imsi};
	redis('zadd','TID',$Q{INNER_TID},"[$now]-[$timer]-[$Q{imsi}]-[$Q{request_type}]-[$Q{code}$Q{USSD_CODE}]-[$Q{INNER_TID}]") if $RESPONSE_TYPE eq 'COMMIT' and $CONF{debug}>0;
}#redis DB
case 'LOG'{
	redis('zadd',$Q{INNER_TID},$timer,"[$now]-[$Q{INNER_TID}]-[$timer]-[API-LOG-$RESPONSE_TYPE]:$LOG") if $CONF{debug}>0;
 # and $CONF{'debug:imsi'} eq $Q{imsi};
#	redis('publish',$CONF{'redis_subscription'},$Q{INNER_TID}) if $RESPONSE_TYPE eq 'COMMIT';
my	$LOG="[$now]-[$Q{INNER_TID}]-[$timer]-[$Q{imsi}]-[$RESPONSE_TYPE]: $LOG" if $CONF{debug}==5;
	print $LOGFILE "$LOG\n" if $CONF{debug}==5;
	$LOGFILE->flush() if $CONF{debug}==5;
	}#case LOG
case 'LOGDB'{
#(!)	my $SQL=qq[INSERT INTO cc_transaction_memory (`id`,`type`,`inner_tid`,`transaction_id`,`IMSI`,`status`,`info`,`timer`) values(NULL,"$RESPONSE_TYPE",$Q{INNER_TID},"$R1","$R2","$R3","$R4",$timer)];
#	redis('publish','transactions',"NULL,'$RESPONSE_TYPE',$Q{INNER_TID},'$R1','$R2','$R3','$R4','$timer'");
#	print $LOGFILE "$SQL\n" if $CONF{debug}==4;
#	$LOGFILE->flush() if $CONF{debug}==4;
#	&SQL($SQL);
	}#case LOGDB
}#switch
}########## END sub logger ######################################
#
########## LU_CDR ###############################################
## Process LU_CDR request
## 1) Checks if subscriber exist
## 2) If true - check active status and update to active
## 3) If false - return error respond
## Used by MOC_SIG to check subscriber status
#################################################################
sub LU_CDR{ 
#use vars qw($new_sock %Q);
#if ($Q{SUB_ID}>0){#if found subscriber
			my $UPDATE_result=${SQL(qq[SELECT set_country($Q{imsi},$Q{mcc},$Q{mnc},"$Q{msisdn}")],2)}[0];
			redis('hset',$Q{imsi},'msrn','ONLINE');
# Comment due activation proccess
#			if ($UPDATE_result){#if contry change
#			my $msrn=CURL('get_msrn_free',${SQL(qq[SELECT get_uri2('get_msrn',"$Q{imsi}",NULL,NULL,NULL,NULL)],2)}[0]);
#my $TRACK_result=CURL('sms_mt_free',${SQL(qq[SELECT get_uri2('mcc_new',"$Q{imsi}",NULL,"$Q{msisdn}",'ruimtools',"$Q{iot_charge}")],2)}[0]);
	#$TRACK_result=CURL('sms_mt',${SQL(qq[SELECT get_uri2('get_ussd_codes',NULL,NULL,"$Q{msisdn}",'ruimtools',NULL)],2)}[0]);
#				logger('LOG','MAIN-LU-HISTORY-RETURN',"$TRACK_result");
#			}#if country change
			#logger('LOGDB',"LU_CDR","$Q{transactionid}","$Q{imsi}",'OK',"$Q{SUB_ID} $Q{imsi} $Q{msisdn}");
#			logger('LOG','LU-REQUEST-OK',"$Q{imsi} $Q{msisdn} $Q{SUB_ID}") if $CONF{debug}==4;
			return ('OK',$Q{SUB_ID},response('CDR_response','OK',1));
#}else{#else no sub_id
#	logger('LOG','LU-SUB-ID',"SUBSCRIBER NOT FOUND $Q{imsi}") if $CONF{debug}==4;
#	logger('LOGDB','LU_CDR',"$Q{transactionid}","$Q{imsi}",'ERROR','SUBSCRIBER NOT FOUND');
#	return ('LU_CDR',0,&response('LU_CDR','ERROR','SUBSCRIBER NOT FOUND #'.__LINE__));
#	}#else not found
}########## END sub LU_CDR ######################################
#
########## AUTHENTICATION CALLBACK MOC_SIG ######################
## Processing CallBack and USSD requests
################################################################# 
#
sub auth_callback_sig{
use vars qw(%Q);
my @result;
logger('LOG',"SIG-$Q{USSD_CODE}-REQUEST","$Q{imsi},$Q{USSD_CODE},$Q{USSD_DEST},$Q{USSD_EXT}") if $CONF{debug}==4;
if(($Q{SUB_STATUS}==1)||($Q{USSD_CODE}=~/^(123|100|000|110|111)$/)){#if subscriber active
	if (($Q{USSD_CODE}=~/112/)&&$Q{USSD_DEST}){@result=SPOOL()}
	else{@result=USSD()}
	return @result;
		}#if subscriber active
	else{#status not 1 or balance request
		logger('LOG','auth_callback_sig-INCORRECT-STATUS',"$Q{SUB_STATUS} #".__LINE__) if $CONF{debug}==4;
		logger('LOGDB','STATUS',"$Q{transactionid}","$Q{imsi}",'ERROR',"$Q{SUB_STATUS}");
		$Q{email_STATUS}="$Q{SUB_STATUS} $SYS{$Q{SUB_STATUS}}";
		email();
		return ('OK',1, response('MOC_response','OK',"$SYS{$Q{SUB_STATUS}}")) if $SYS{$Q{SUB_STATUS}};
#		return ('INCORRECT STATUS',0, response('LU_CDR','ERROR','#'.__LINE__.' INCORRECT STATUS')) if !$SYS{$Q{SUB_STATUS}};
	}#else status
}## END sub auth_callback_sig
#
############## SUB SPOOL ######################
## Spooling call
##############################################
sub SPOOL{
use vars qw($ERROR %Q $sql_aff_rows %CONF);
my $msisdn=uri_unescape($Q{msisdn});
my $uniqueid=timelocal(localtime())."-".int(rand(1000000));
my $USSD_dest=$Q{USSD_DEST};
my $internal=0;
#
# INTERNAL CALL
	if($Q{USSD_DEST}=~/^([3-4][0-9]\d{3})$/){#if internal call destination
logger('LOG','SPOOL-GET-INTERNAL-CALL',"$Q{USSD_DEST}") if $CONF{debug}==1;
		if ($Q{imsi} eq "2341800001".$1){#self call
logger('LOG','SPOOL-GET-INTERNAL-SELF',"$Q{USSD_DEST}") if $CONF{debug}==1;
	return ('CALL SELF', -4,response('MOC_response','OK',template('spool:dest_self')));
		}#if self call
		my ($status,$code,$msrn)=CURL('get_msrn',${SQL(qq[SELECT get_uri2('get_msrn',"2341800001$1",NULL,NULL,NULL,NULL)],2)}[0]);#get msrn for internal call
	$msrn=~s/\+//;#supress \+ from xml response
logger('LOG','SPOOL-GET-INTERNAL-MSRN-RESULT',$msrn) if $CONF{debug}==1;
		if ($msrn eq 'OFFLINE'){#if dest offline
	return ('OFFLINE DEST', -5,response('MOC_response','OK',template('spool:dest_offline')));
		}#if offline
if ($msrn=~/\d{7,15}/){
	$Q{USSD_DEST}=$msrn;
	$internal=1;
	}else{
logger('LOGDB','SPOOL',"$Q{transactionid}","$Q{imsi}",'ERROR',"MISSING MSRN $msrn $Q{USSD_DEST} $msrn");
	return ('OFFLINE DEST', -5,response('MOC_response','OK',template('spool:dest_offline')));
}#return offline or empty msrn  
}#if internal call
	elsif ($Q{USSD_DEST}=~/^(\+|00)?([1-9]\d{7,15})$/){#elsif outbound call destianation
logger('LOG','SPOOL-GET-OUTBOUND-CALL',"$Q{USSD_DEST}") if $CONF{debug}==1;
	$Q{USSD_DEST}=$2;#set dest
}#elsif outbound call
else {#else incorrect dest
$Q{USSD_DEST}=0;
}#else incorrect dest
	logger('LOG','SPOOL-GET-DEST',"$Q{USSD_DEST} in $USSD_dest") if $CONF{debug}==1;
	logger('LOGDB','SPOOL',"$Q{transactionid}","$Q{imsi}",'CALL',"$msisdn to $Q{USSD_DEST}");
# END INTERNAL CALL
#
# PROCESSING CALL
if ($Q{USSD_DEST}){#if correct destination number process imsi msrn
	my	$msrn=$2 if (($Q{USSD_CODE}==128)&&($Q{USSD_EXT}=~/^(\+|00)?([1-9]\d{7,15})#?$/));#local number call
logger('LOG','SPOOL-LOCAL-NUMBER-CALL',"$msrn $Q{USSD_EXT}") if $msrn and $CONF{debug}==1;
	(my $status,my $code,$msrn)=CURL('get_msrn',template('get_msrn')) if !$msrn;
	my $offline=1 if $msrn eq 'OFFLINE';
	$msrn=~s/\+//;#supress \+ from xml response
logger('LOG','SPOOL-GET-MSRN-RESULT',$msrn) if $CONF{debug}==1;
#
if (($msrn=~/\d{7,15}/)and(!$offline)){
## Call SPOOL
	($Q{'DEST_RATE'},$Q{'MSRN_RATE'},$Q{'CB_TRUNKCODE'})=split(':',${SQL(qq[select get_limit($Q{USSD_DEST},$msrn)],2)}[0]);
	$Q{'CB_TRUNKPREFIX'}=$CONF{"trunk:$Q{'CB_TRUNKCODE'}"};
	$Q{'CALL_RATE'}=($Q{'DEST_RATE'}+$Q{'DEST_RATE'}/$CONF{'markup'}+$Q{'MSRN_RATE'})/100+$Q{'mtc'};
	$Q{'CALL_LIMIT'}=floor(($Q{'SUB_CREDIT'}/$Q{'CALL_RATE'})*60);
	$Q{'CALL_LIMIT'}=$CONF{'max-call-time'} if $Q{'CALL_LIMIT'}>$CONF{'max-call-time'};
	$Q{'SUB_CREDIT'}=sprintf '%.2f',$Q{'SUB_CREDIT'};
	$Q{'CALL_RATE'}=sprintf '%.2f',$Q{'CALL_RATE'};
logger('LOG','SPOOL-GET-TRUNK-[trunk/prefix/rate/limit]',"$Q{SUB_TRUNKCODE}/$Q{'CB_TRUNKPREFIX'}/$Q{CALL_RATE}/$Q{CALL_LIMIT}") if $CONF{debug}==4;
	my $CALLFILE="$uniqueid-$msrn";
	my $CALL = IO::File->new("$CONF{TMPDIR}/$CALLFILE", "w");
	my $CallAction=qq[Channel: $Q{'SUB_TRUNK_TECH'}/$Q{'CB_TRUNKPREFIX'}$msrn\@$Q{'CB_TRUNKCODE'}
Context: $Q{'SUB_CONTEXT'}
Extension: $Q{'USSD_DEST'}
CallerID: "$Q{'USSD_DEST'}" <$Q{'USSD_DEST'}>
Priority: 1
Account: $Q{'SUB_CN'}
Setvar: CALLED=$msrn
Setvar: CALLING=$Q{'USSD_DEST'}
Setvar: CBID=$uniqueid
Setvar: TARIFF=5
Setvar: LEG=$Q{'SUB_CN'}
Setvar: TRUNK=$Q{'SUB_TRUNKCODE'}
Setvar: LIMIT=$Q{'CALL_LIMIT'}
Setvar: RATEA=$Q{'MSRN_RATE'}
Setvar: RATEB=$Q{'DEST_RATE'}
Setvar: ActionID=$uniqueid];
print $CALL $CallAction;
close $CALL;
chown 100,101,"$CONF{'TMPDIR'}/$CALLFILE";
my $mv=$CONF{'fake-call'};
$mv=move("$CONF{'TMPDIR'}/$CALLFILE", "$CONF{'SPOOLDIR'}/$CALLFILE") if $CONF{'fake-call'}!=1;
#
			$Q{USSD_DEST}=$USSD_dest if $internal==1;
return ("SPOOL-[move/uniqid/rate] $mv:$uniqueid:$Q{CALL_RATE}",$mv,response('MOC_response','OK',template('spool:wait')));
	}#if msrn and dest
	else{#else not msrn and dest
		logger('LOGDB','SPOOL',"$Q{transactionid}","$Q{imsi}",'ERROR',"MISSING MSRN $msrn $Q{USSD_DEST} $offline $ERROR");
		return ('OFFLINE', -2,response('MOC_response','OK',template('spool:offline')));
		}#else not msrn and dest
}#if dest
else{
		logger('LOGDB','SPOOL',"$Q{transactionid}","$Q{imsi}",'ERROR',"MISSING DEST $USSD_dest");
		return ('NO DEST',-3,response('MOC_response','OK',template('spool:nodest')));
}#else dest	
}########## END SPOOL ##########################
#
############# SUB USSD #########################
## Processing USSD request
###############################################
sub USSD{
use vars qw(%Q $R);
#
switch ($Q{USSD_CODE}){
###
	case "000"{#SUPPORT request
		logger('LOG','SIG-USSD-SUPPORT-REQUEST',"$Q{USSD_CODE}") if $CONF{debug}==4;
		$Q{email}="denis\@ruimtools.com";
		$Q{email_sub}="NEW TT: [$Q{imsi}]";
		$Q{email_text}=${SQL(qq[NULL,'ussd',$Q{USSD_CODE},NULL],1)}[0];
		$Q{email_FROM}="SUPPORT";
		$Q{email_from}="denis\@ruimtools.com";
		email();
		return ('OK',1,response('MOC_response','OK',${SQL(qq[NULL,'ussd',$Q{USSD_CODE},NULL],1)}[0]));		
			}#case 000
###
	case "100"{#MYNUMBER request
		logger('LOG','SIG-USSD-MYNUMBER-REQUEST',"$Q{USSD_CODE}") if $CONF{debug}==4;
		$Q{SUB_INTER}=substr($Q{imsi},-5,5);
#		my @SUB_DID=$R->LRANGE("did:$Q{imsi}",0,0);
		$Q{SUB_DID}= $R->LLEN("did:$Q{imsi}") ? $R->LRANGE("did:$Q{imsi}",0,0) : $Q{globalmsisdn};
#		$Q{SUB_DID}=$Q{globalmsisdn} if @SUB_DID==0;
		$Q{SUB_CREDIT}=sprintf '%.2f',$Q{SUB_CREDIT};
		return ('OK',1,response('MOC_response','OK',template("ussd:$Q{USSD_CODE}")));		
	}#case 100
###
	case "110"{#IMEI request
		logger('LOG','SIG-USSD-IMEI-REQUEST',"$Q{USSD_DEST}") if $CONF{debug}==4;
		redis('hset',"imsi:$Q{imsi}",'SUB_HANDSET',"$Q{USSD_DEST} $Q{USSD_EXT}");
		return ('OK',$Q{USSD_DEST},response('MOC_response','OK',template("ussd:$Q{USSD_CODE}")));
	}#case 110
###
	case "122"{#SMS request
		logger('LOG','SIG-USSD-SMS-REQUEST',"$Q{USSD_CODE} $Q{USSD_DEST} $Q{USSD_EXT}") if $CONF{debug}==4;
		#logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'OK',"$Q{USSD_CODE} $Q{USSD_DEST} $Q{USSD_EXT}");
		my $SMS_result=SMS();#process sms
		my $SMS_response=${SQL(qq[NULL,'ussd',$Q{USSD_CODE}$SMS_result,NULL],1)}[0];#get response text by sms result
		$SMS_response="Sorry, unknown result. Please call *000#" if $SMS_response eq '';#something wrong - need support
		logger('LOG','SIG-USSD-SMS-RESULT',"$SMS_result") if $CONF{debug}==4;
		#logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'RSP',"$SMS_result");
		return ('OK',$SMS_result, &response('auth_callback_sig','OK',$Q{transactionid},"$SMS_response"));
		
	}#case 122
###
	case [111,123]{#voucher refill request
		$Q{USSD_CODE}=123 if $Q{USSD_CODE}==111;
		logger('LOG','SIG-USSD-BALANCE-REQUEST',"$Q{USSD_CODE}") if $CONF{debug}==4;
#(!)		$Q{SUB_CREDIT_INET}=CURL('get_user_info',template('get_user_info'));
		$Q{SUB_CREDIT}=sprintf '%.2f',$Q{SUB_CREDIT};
		return ('OK',1,response('MOC_response','OK',template("ussd:111"))) if !$Q{USSD_DEST};
my		%V=$R->hgetall("voucher:$Q{USSD_DEST}");
		$V{used}=1 if not defined $V{used};
		$R->hset("imsi:$Q{imsi}",'SUB_CREDIT',$Q{SUB_CREDIT}+$V{amount}) if $V{used}==0;
		$R->hset("voucher:$Q{USSD_DEST}",'used',1) if $V{used}==0;
		$Q{SUB_CREDIT}=$Q{SUB_CREDIT}+$V{amount} if $V{used}==0;
		$Q{SUB_CREDIT}=sprintf '%.2f',$Q{SUB_CREDIT};
			logger('LOG','SIG-USSD-VOUCHER-RESULT-[voucher/used]',"$Q{USSD_DEST}/$V{used}") if $CONF{debug}==4;
			return ('OK',$V{used}, response('MOC_response','OK',template("ussd:123$V{used}")));			
	}#case 123
#
	case "125"{#voip account
	logger('LOG','SIG-USSD-VOIP-ACCOUNT-REQUEST',"$Q{USSD_CODE}") if $CONF{debug}==4;
	my ($status,$code,$new_user)=CURL('new_user',${SQL(qq[SELECT get_uri2('new_user',"$Q{imsi}",NULL,NULL,NULL,NULL)],2)}[0]) if !$Q{SUB_VOIP};
	#logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'RSP',"$Q{USSD_CODE} $new_user") if !$Q{SUB_VOIP};
	return ('OK',1, &response('auth_callback_sig','OK',$Q{transactionid},${SQL(qq[$Q{imsi},'ussd',$Q{USSD_CODE},NULL],1)}[0]));
	}#case 124
###
	case "126"{#RATES request
		logger('LOG','SIG-USSD-RATES',"$Q{USSD_CODE} $Q{USSD_DEST}") if $CONF{debug}==4;
		#logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'OK',"$Q{USSD_CODE} $Q{USSD_DEST}");
		return ('NO DEST',-1,&response('auth_callback_sig','OK',$Q{transactionid},"Please check destination number!")) if $Q{USSD_DEST} eq '';
		$Q{USSD_DEST}=~/^(\+|00)?([1-9]\d{1,15})$/;
		my $dest=$2;
		my ($status, $code, $msrn)=CURL('get_msrn',${SQL(qq[SELECT get_uri2('get_msrn',"$Q{imsi}",NULL,NULL,NULL,NULL)],2)}[0]);
		my $rate=${SQL(qq[SELECT round(get_rate($msrn,$dest),2)],2)}[0] if $msrn=~/^(\+)?([1-9]\d{7,15})$/;
		logger('LOG','SIG-USSD-RATES-RETURN',"$rate") if $CONF{debug}==4;
	return ('OK',1,&response('auth_callback_sig','OK',$Q{transactionid},"Callback rate to $Q{USSD_DEST}: \$ $rate. Extra: ".substr($Q{iot_charge}/0.63,0,4))) if $rate=~/\d/;
		return ('OFFLINE',0,&response('auth_callback_sig','OK',$Q{transactionid},"Sorry, number offline")) if $msrn=~/OFFLINE/;
	}#case 126
###
	case "127"{#CFU request
		logger('LOG','SIG-USSD-CFU-REQUEST',"$Q{USSD_CODE} $Q{USSD_DEST}") if $CONF{debug}==4;
		if ($Q{USSD_DEST}=~/^(\+|00)?(\d{5,15})$/){#if prefix +|00 and number length 5-15 digits
			logger('LOG','SIG-USSD-CFU-REQUEST',"Subcode processing $Q{USSD_DEST}") if $CONF{debug}==4;
				 my $CFU_number=$2;
				 my $SQL=qq[SELECT get_cfu_code($Q{imsi},"$CFU_number")];
					my $CODE=${SQL("$SQL",2)}[0];
(my $status,my $code,$CODE)=CURL('sms_mo',${SQL(qq[SELECT get_uri2('sms_mo',NULL,"+$CFU_number","$Q{msisdn}",'ruimtools',"$CODE")],2)}[0]) if $CODE=~/\d{5}/;
					$CFU_number='NULL' if $CODE!~/0|1|INUSE/;
					$SQL=qq[SELECT get_cfu_text("$Q{imsi}","$CODE",$CFU_number)];
					my $TEXT_result=${SQL("$SQL",2)}[0];
					return ('OK',$CODE,&response('auth_callback_sig','OK',$Q{transactionid},$TEXT_result));
					#logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'RSP',"$CODE $Q{USSD_CODE} $Q{USSD_DEST}");
			}#if number length
			else{#else check activation
			logger('LOG','SIG-USSD-CFU-REQUEST',"Code processing $Q{USSD_CODE} $Q{USSD_DEST}") if $CONF{debug}==4;
				my $SQL=qq[SELECT get_cfu_text("$Q{imsi}",'active',NULL)];
				#my @SQL_result=&SQL($SQL);
				my $TEXT_result=${SQL("$SQL",2)}[0]; 
				return ('OK', $Q{USSD_CODE},&response('auth_callback_sig','OK',$Q{transactionid},"$TEXT_result"));
				#logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'RSP',"$Q{USSD_CODE} $Q{USSD_DEST}");
				}
	}#case 127
###
	case "128"{#local call request
		logger('LOG','SIG-LOCAL-CALL-REQUEST',"$Q{USSD_CODE}") if $CONF{debug}==4;
		#logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'OK',"$Q{USSD_CODE}");
		my $SPOOL_result=SPOOL() if $Q{USSD_EXT};
		return ('OK',1, $SPOOL_result) if $Q{USSD_EXT};
		return ('OK', 1, &response('auth_callback_sig','OK',$Q{transactionid},${SQL(qq["$Q{imsi}",'ussd',$Q{USSD_CODE},$Q{mcc}],1)}[0]));
	}#case 128
###
	case "129"{#my did request
		logger('LOG','SIG-DID-NUMBERS-REQUEST',"$Q{USSD_CODE} $Q{USSD_DEST} $Q{USSD_EXT}") if $CONF{debug}==4;#(!) hide pin
		$Q{USSD_DEST}=$Q{imsi} if ($Q{USSD_DEST}!~/^(\+|00)?([1-9]\d{7,15})$/);
		if ($Q{USSD_EXT}=~/^([0-9]\d{3})#?$/){# check pin
		$Q{-o}='-d';
		($Q{-h},$Q{user},$Q{pass})=@{SQL(qq[SELECT description,auth_login,auth_pass from cc_provider WHERE provider_name='C94'],2)};
		$Q{actions}='SimInformationByMSISDN'; $Q{request}='IMSI';
		CURL($Q{actions},XML());
		logger('LOG','SIG-DID-NUMBERS-PIN-CHECK',"SUCCESS") if $1==$Q{PIN} and $CONF{debug}==4;;
		logger('LOG','SIG-DID-NUMBERS-PIN-CHECK',"ERROR") if $1!=$Q{PIN} and $CONF{debug}==4;
		return ('PIN INCORRECT',-1,&response('auth_callback_sig','OK',$Q{transactionid},"Please enter correct PIN")) if $1!=$Q{PIN};
		$Q{USSD_DEST}=$Q{SUB_ID};
		}#if pin
		my $did=${SQL(qq[SELECT set_did("$Q{USSD_DEST}")],2)}[0];
		return ('OK',1, &response('auth_callback_sig','OK',$Q{transactionid},"$did"));
	}#case 128
###

	else{#switch ussd code
	return ('NO CODE DEFINED',-3,&response('auth_callback_sig','OK',$Q{transactionid},${SQL(qq["$Q{imsi}",'ussd',$Q{USSD_CODE},NULL],1)}[0]));
	}#end else switch ussd code (no code defined)
}#end switch ussd code
}## END sub USSD ###################################
#
########### CURL #############################################
## Process all types of requests
## Return MSRN or NULL, Status
#################################################################
sub CURL{
our $transaction_id=timelocal(localtime()).int(rand(1000));
our $MSG=$_[0];
our $DATA=$_[1];
my $HOST=$Q{SUB_AGENT_ADDR};
our $response_body='';
($HOST,$DATA)=split('\?',$DATA) if($DATA=~/\?/);
$DATA=$DATA.'&'.$Q{SUB_AGENT_METHOD}.'='.$Q{SUB_AGENT_AUTH} if $Q{SUB_AGENT_AUTH}>0;
#
logger('LOG',"API-CURL-$MSG-PARAM","$HOST $DATA") if $CONF{debug}==4;
#
return ('FAKE-MSRN',1,$CONF{'fake-msrn'}) if $CONF{'debug'}==4&&$CONF{'fake-msrn'}&&$MSG=~/get_msrn/&&!$CONF{'fake-xml'};
return ('FAKE-XML',1,XML_PARSE($CONF{'fake-xml'},$MSG)) if $CONF{'fake-xml'}&&$MSG ne 'agent';
return ('OFFLINE',0,'OFFLINE') if redis('hget',"$Q{imsi}:msrn",'msrn') eq 'OFFLINE'&&$MSG=~/get_msrn/;
return ('FAKE-AGENT-XML',1,XML_PARSE($CONF{'fake-agent-xml'},$MSG)) if $CONF{'fake-agent-xml'}&&$MSG eq 'agent';
#
our $curl = WWW::Curl::Easy->new;
$curl->setopt (CURLOPT_SSL_VERIFYHOST, 0);
$curl->setopt( CURLOPT_SSL_VERIFYPEER, 0);
$curl->setopt( CURLOPT_POSTFIELDS, $DATA);
$curl->setopt( CURLOPT_POSTFIELDSIZE, length($DATA));
$curl->setopt( CURLOPT_POST, 1);
$curl->setopt( CURLOPT_CONNECTTIMEOUT,5);
$curl->setopt( CURLOPT_HEADER, 0);
$curl->setopt( CURLOPT_URL, $HOST);
$curl->setopt( CURLOPT_WRITEDATA, \$response_body);
#
$DATA=~/request_type=(\w{0,20})/;
#logger('LOGDB',"$MSG","$transaction_id","$Q{imsi}",'IN',"$MSG:CURL $1"); 
#
if ($DATA){
eval {use vars qw($curl $response_body %Q); logger('LOG',"API-CURL-$MSG-REQ",$HOST.' '.length($DATA)) if $CONF{debug}==4;
my $retcode = $curl->perform;
my $response_code = $curl->getinfo(CURLINFO_HTTP_CODE) if $retcode==0;
logger('LOG',"API-CURL-ERROR-BUF",$curl->strerror($retcode)) if $retcode!=0 and $CONF{debug}==4;
$Q{curl_error}=$curl->strerror($retcode) if $retcode!=0; 
};warn $@ if $@;  logger('LOG',"API-CURL-ERROR","$@") if $@;
}#if URI
else{return ('NO URI',0)}#else URI empty
#
use vars qw($response_body);
if ($response_body){
	logger('LOG',"$MSG-RESPOND","$response_body") if $CONF{debug}==5;
	my $CURL_result=&XML_PARSE("$response_body",$MSG);
	logger('LOGDB',$MSG,"$transaction_id","$Q{imsi}",'ERROR','CURL NO RESPONSE') if $CURL_result eq '';
	return ('OK',1,$CURL_result);
}#if CURL return
else{# timeout
	logger('LOG',"CURL-$MSG-REQUEST","Timed out 5 sec with socket") if $CONF{debug}==4;
	return ('TIMEOUT',0);
}#end else
}########## END sub GET_MSRN ####################################
#
##### RC_API_CMD ################################################
## Process all types of commands to RC
## Accept CMD, Options
## Return message
#################################################################
sub api_cmd{
if (&auth()){logger('LOG','RC-API-CMD',"AUTH OK") if $CONF{debug}==4;}#if auth
else{
	logger('LOG','RC-API-CMD',"AUTH ERROR") if $CONF{debug}==4;
	return ('NO AUTH',-1,response('api_cmd','PLAINTEXT',"$Q{transactionid},ERROR,-3"));
}#else no auth				
my $result;
logger('LOG','RC-API-CMD',"$Q{code}") if $CONF{debug}==4;
switch ($Q{code}){
	case 'ping' {#PING
		sleep 7 if $Q{options} eq 'sleep';
		return ('OK', 1, response('ping','PLAINTEXT',"PING OK "));
	}#case ping
	case 'get_msrn' {#GET_MSRN
		my $msrn;
		if ($Q{imsi}){#if imsi defined
			(my $status,my $code, $Q{msrn})=CURL('get_msrn',template('get_msrn'));
			return ('OK', 1,response('get_msrn','OK')) if $Q{options} ne 'cleartext';
#			$msrn=~s/\+// if $Q{options} eq 'cleartext';#cleartext for ${EXTEN} usage
			return ('OK',1,response('get_msrn','PLAINTEXT')) if $Q{options} eq 'cleartext';
		}#if imsi
		else{#if no imsi
			logger('LOGDB',"$Q{code}","$Q{transactionid}","$Q{imsi}",'ERROR',"IMSI UNDEFINED $Q{imsi}");
			return ('IMSI UNDEFINED',-1,response('get_msrn','ERROR',"IMSI UNDEFINED $Q{imsi} $Q{msrn}"));
		}#else no imsi
	}#case msrn
	case 'get_did' {#PROCESS DID number
		logger('LOG','RC-API-CMD-DID-[did/src]',"$Q{rdnis}/$Q{src}") if $CONF{debug}==4;
			if (length($Q{rdnis})==6){
				$Q{imsi}=$CONF{'imsi_prefix'}.$Q{rdnis};
			#	GET_TYPE();
				}#GROUP CALL
			else{#IMSI CALL
				$Q{imsi}=redis('hget',"did:$Q{rdnis}",'imsi');
				}#IMSI CALL
		if ($Q{imsi}=~/$CONF{'imsi_prefix'}/){#if did assigned to imsi
				#	GET_TYPE();
		my ($status,$code,$msrn)=CURL('get_msrn_did',template('get_msrn'));
		logger('LOG','RC-API-CMD-DID-[status/code/msrn]',"$status,$code,$msrn") if $CONF{debug}==4;
			if ($msrn=~/\d{7,15}/){
				($Q{'MSRN_RATE'},$Q{'CB_TRUNK'})=split(':',${SQL(qq[select get_limit(NULL,$msrn)],2)}[0]);
				$msrn=$CONF{"trunk:$Q{'CB_TRUNK'}"}.$msrn;
				$Q{'SUB_CN'}=redis('hget',"imsi:$Q{imsi}",'SUB_CN');
				$Q{'SUB_CREDIT'}=redis('hget',"imsi:$Q{imsi}",'SUB_CREDIT');
				$Q{'CALL_LIMIT'}=($Q{'SUB_CREDIT'}*100/($Q{'MSRN_RATE'}+$Q{'mtc'}))*60;
				$Q{'CALL_LIMIT'}=floor($Q{'CALL_LIMIT'});
				$Q{'MSRN_RATE'}=sprintf '%.0f',$Q{'MSRN_RATE'};
				return ('OK',1,response('get_did','PLAINTEXT',"$Q{transactionid}:$Q{'SUB_CN'}:$msrn:$Q{'CALL_LIMIT'}:$Q{'CB_TRUNK'}:$Q{'MSRN_RATE'}"));
			}else{
				return ('OFFLINE',-1,response('get_did','PLAINTEXT',"$Q{transactionid}:OFFLINE:-1"));
				}#else msrn 7-15
		}#if imsi call
	}#case get_did
	case 'send_ussd' {#SEND_USSD
		$result=CURL('send_ussd',${SQL(qq[SELECT get_uri2("$Q{code}",NULL,NULL,"$Q{msisdn}","$Q{sub_code}",NULL)],2)}[0]);
		return ('OK',1,response('api_response','OK',$Q{transactionid},"$Q{msisdn} $result"));
		}#case send_ussd
	case 'stat' {#STAT
		my ($i,@s);
		my @k=$R->hkeys('STAT:AGENT:'.$R->hget('AGENT',$Q{digest})) if $Q{imsi}==0;
		my @v=$R->hvals('STAT:AGENT:'.$R->hget('AGENT',$Q{digest})) if $Q{imsi}==0;
		   @k=$R->hkeys("STAT:SUB:$Q{imsi}") if $Q{imsi}>0;
		   @v=$R->hvals("STAT:SUB:$Q{imsi}") if $Q{imsi}>0;
#		   foreach my $k(@k){$k=~/.*-\[(.*)\]-/; push @s,$k.':'.$v[$i++].':'.$1 if $k=~/$Q{date}/}
		map {$_=~/.*-\[(.*)\]-/; my $c=$1; push @s,$_.':'.$v[$i++]*$SIG{$c} if $_=~/$Q{date}/} @k;
		$Q{stat}=join("\n\r",@s);
		return ('OK',1,response('api_response','OK',$Q{stat}));
		}#case stat
	else {
		logger('LOG','RC-API-CMD-UNKNOWN',"$Q{code}") if $CONF{debug}==4;
		logger('LOGDB','API-CMD',"$Q{transactionid}","$Q{imsi}",'ERROR',"$Q{code}");
		return ('API CMD',1,response('api_response','ERROR',"UNKNOWN CMD REQUEST"));
		}#else switch code
}#switch code
		logger('LOG','RC-API-CMD',"$Q{code} $result") if $CONF{debug}==4;
		logger('LOGDB',"$Q{code}","$Q{transactionid}","$Q{imsi}",'OK',"RESULT $result");
		return ('API CMD',$result);
}##### END sub RC_API_CMD ########################################
#
##### AGENT ################################################
sub agent{
use vars qw(%Q);
$Q{request_type}='USSD' if $Q{request_type} eq 'auth_callback_sig';
$Q{request_type}=$SYS{$Q{USSD_CODE}} if $SYS{$Q{USSD_CODE}};
$Q{USSD_DEST}=uri_escape($Q{calldestination}) if $Q{request_type} eq 'USSD';
$Q{mtc}= redis('KEYS',"PLMN:$Q{tadig}:$Q{mcc}:".int $Q{mnc}) ? $R->get("PLMN:$Q{tadig}:$Q{mcc}:".int $Q{mnc}) : 0;
#return ('AGENT DEBUG',1,response('MOC_response','OK',template('agent'))) if $CONF{debug_imsi}==$Q{imsi} and $CONF{debug}==4;
my @result=CURL('agent',template('agent'));
return ($result[0],$result[1],response('MOC_response','OK',$result[2]));
}# END sub AGENT
##################################################################
#
### SUB AUTH ########################################################
sub auth{
my	$md5 = Digest::MD5->new;
	$md5->add($Q{REMOTE_ADDR}, $Q{auth_key}, $Q{agent});
	$Q{digest} = $md5->hexdigest;
logger('LOG',"RC-API-DIGEST-CHECK","$Q{REMOTE_ADDR}, $Q{auth_key}, $Q{agent}, $Q{digest}") if $CONF{debug}==4;
return $R->HEXISTS('AGENT',$Q{digest});
}#END sub auth ##################################################################
#
## SUB PAYMNT ###################################################################
sub PAYMNT{
my (@TR,@IDs);
our ($SQL_T_result,$CARD_NUMBER,$AMOUNT);
$SQL_T_result="-1";
foreach my $TR(@{$Q{REQUEST}->{payment}{transactions}{transaction}}){
	push @IDs,$TR->{id};
}#foreach
my $SQL=qq[INSERT INTO cc_epayments (`payment_id`, `ident`,`status`,`amount`,`currency`,`timestamp`,`salt`,`sign`,`transactions_ids`) values("$Q{REQUEST}->{payment}{id}","$Q{REQUEST}->{payment}{ident}","$Q{REQUEST}->{payment}{status}","$Q{REQUEST}->{payment}{amount}","$Q{REQUEST}->{payment}{currency}","$Q{REQUEST}->{payment}{timestamp}","$Q{REQUEST}->{payment}{salt}","$Q{REQUEST}->{payment}{sign}","@IDs")];
my $SQL_P_result=&SQL($SQL);
logger('LOG','PAYMNT-EPMTS-SQL-RESULT',"$SQL_P_result") if $CONF{debug}==4;
## AUTH
if (auth('PAYMNT',$Q{REQUEST}->{payment}{salt},$Q{REQUEST}->{payment}{sign})==0){
	logger('LOG','PAYMNT-TR-RESULT',"@IDs") if $CONF{debug}==4;
		foreach my $TR (@{$Q{REQUEST}->{payment}{transactions}{transaction}}){#for each transaction id
			$TR->{desc}=~/(\d{1,12})/;
			$CARD_NUMBER=$1;
my $SQL=qq[INSERT INTO cc_epayments_transactions (`id`,`mch_id`, `srv_id`,`amount`,`currency`,`type`,`status`,`code`, `desc`,`info`) values("$TR->{id}","$TR->{mch_id}","$TR->{srv_id}","$TR->{amount}","$TR->{currency}","$TR->{type}","$TR->{status}","$TR->{code}","$TR->{desc}","$CARD_NUMBER")];
$SQL_T_result=&SQL($SQL);
logger('LOG','PAYMNT-TR-SQL-RESULT',"$SQL_T_result") if $CONF{debug}==4;
		}#foreach tr
}#end if auth
else{#else if auth
	logger('LOG','PAYMNT-AUTH-RESULT',"NO AUTH") if $CONF{debug}==4;
}#end esle if auth
	$Q{imsi}=${SQL(qq[SELECT useralias from cc_card WHERE username=$CARD_NUMBER],2)}[0];
	logger('LOGDB',"PAYMNT","$Q{REQUEST}->{payment}{id}","$Q{imsi}",'RSP',"$CARD_NUMBER $SQL_T_result @IDs");
	return ('PAYMNT 1',&response('payment','PLAINTEXT',"200 $SQL_T_result"));
# we cant send this sms with no auth because dont known whom
	my ($status,$code,$SMSMT_result)=CURL('sms_mt',${SQL(qq[SELECT get_uri2("pmnt_$SQL_T_result","$CARD_NUMBER",NULL,NULL,"$CARD_NUMBER","$Q{REQUEST}->{payment}{id}")],2)}[0]);
		$Q{email}="pay\@ruimtools.com";
		$Q{email_sub}="PAYMENT[$Q{imsi}]: for $CARD_NUMBER $SQL_T_result";
		$Q{email_text}="";
		$Q{email_FROM}="CallMe! Payments";
		$Q{email_from}="pay\@ruimtools.com";
		email();
	return $SQL_T_result;
}## END sub PAYMNT ##################################################################
#
########################### PAYPAL section ############################################
sub PAYPAL{
$Q{memo}=~tr/[\,,\;,\:," ","-",\n]/\;/; 
my @Memo=split(";",$Q{memo});
our ($rcpt, $email, $email_pri, $email_text);
$Q{receipt_id}=$Q{txn_id} if !$Q{receipt_id};
# 
foreach my $memo(@Memo){
	my $result=""; 
	next if $memo eq ""; 
	if ($memo=~/([_a-z0-9-]+(\.[_a-z0-9-]+)*@[a-z0-9-]+(\.[a-z0-9-]+)*(\.[a-z]{2,4}))/) {$email=Email::Valid->address(-address  => $1, -tldcheck => 1); next} 
	if ($memo=~/\+?(\d{11,15})/){ $rcpt=$1; next} 
	if($memo=~/(\d{10})/){$Q{'personal_number'}=$1; next}
}#foreach
#
my $SQL=qq[INSERT INTO cc_paypal (memo,mc_gross,item_number,tax,payer_id,payment_status,first_name,mc_fee,personal_number,business,num_cart_items,payer_email,btn_id1,txn_id,receipt_id,payment_type,last_name,item_name,receiver_email,payment_fee,quantity,receiver_id,txn_type,mc_gross_1,mc_currency,residence_country,transaction_subject,payment_gross,ipn_track_id) values ("$Q{memo}","$Q{mc_gross}","$Q{item_number}","$Q{tax}","$Q{payer_id}","$Q{payment_status}","$Q{first_name}","$Q{mc_fee}","$Q{personal_number}","$Q{business}","$Q{num_cart_items}","$Q{payer_email}","$Q{btn_id}","$Q{txn_id}","$Q{receipt_id}","$Q{payment_type}","$Q{last_name}","$Q{item_name}","$Q{receiver_email}","$Q{payment_fee}","$Q{quantity}","$Q{receiver_id}","$Q{txn_type}","$Q{mc_gross}","$Q{mc_currency}","$Q{residence_country}","$Q{transaction_subject}","$Q{payment_gross}","$Q{ipn_track_id}")];
my $result=SQL($SQL);
#
logger('LOG','PAYPAL-RESULT',"$result") if $CONF{debug}==4;
logger('LOGDB',"PAYPAL","$Q{txn_id}","$Q{btn_id}",'RESULT',"$result");
#
#send payment confirmation to email
#
if ($Q{payer_email}){
$email_text=uri_unescape(${SQL(qq[SELECT paypal("$Q{txn_id}","$result")],2)}[0]);
eval {use vars qw(%Q $email $email_pri $email_text);logger('LOG','PAYPAL-GET-EMAIL',"$Q{receipt_id} $Q{payer_email} $email") if $CONF{debug}==4;;
$email_pri=`echo "$email_text" | mail -vs 'Payment $Q{receipt_id}' $Q{payer_email} $email -- -F "CallMe! Payments" -f pay\@ruimtools.com`;
};warn $@ if $@;  logger('LOG',"PAYPAL-SEND-EMAIL-ERROR","$@") if $@;
}#if email
else{$email_pri="No email address"}#else email empty
#
logger('LOG','PAYPAL-SEND-EMAIL',"$email_pri") if $CONF{debug}==4;;
# send sms notification to primary phone number
my ($status,$code,$sms_pri)=CURL('sms_mt',${SQL(qq[SELECT get_uri2('sms_mt',NULL,"${SQL(qq[SELECT phone FROM cc_card WHERE username=$Q{'personal_number'}],2)}[0]","ruimtools",NULL,"${SQL(qq[SELECT paypal("$Q{txn_id}","$result")],2)}[0]")],2)}[0]) if $Q{'personal_number'};
# send sms notification to additional phone number
($status,$code,my $sms_add)=CURL('sms_mo',${SQL(qq[SELECT get_uri2('sms_mo',NULL,"+$rcpt","+447700079964","ruimtools","${SQL(qq[SELECT paypal("$Q{txn_id}","$result")],2)}[0]")],2)}[0]) if $rcpt;
#
logger('LOG','PAYPAL-SEND-RESULT',"$rcpt $sms_pri $sms_add") if $CONF{debug}==4;;
##
return "$result $email_pri $sms_pri $sms_add";
}#PAYPAL
## END sub PAYPAL ##################################################################		
#
########################### SMS section ############################################
### sub SMS ########################################################################
sub SMS{
use vars qw(%Q);#load global array
my ($sms_result,$sms_opt,$sms_to,$sms_from,$sms_text,$sms_long_text,$type,$SQL);#just declare
#
logger('LOG','SMS-REQ',"$Q{USSD_DEST} $Q{USSD_EXT}") if $CONF{debug}==3;
$Q{USSD_DEST}=~/(\d{1})(\d{1})(\d{1})/;#page number, pages amount, message number
my ($page,$pg_num,$seq)=($1,$2,$3);
#
return 4 if $seq eq '';#new format from 01.08
#
$Q{USSD_EXT}=~/^(\D|00)?([1-9]\d{7,15})\*(\w+)#?/;#parse msisdn
$sms_to='+'.$2;#international format
$sms_to="${SQL(qq[SELECT phone FROM cc_card WHERE useralias=2341800001$2],2)}[0]" if $Q{USSD_EXT}=~/^(\D)?([3-4][6-9]\d{3})\*(\w+)#?/;#check if internal
$sms_long_text=$3;#sms text
return 5 if length($sms_to)<5;
#
logger('LOG','SMS-REQ',"$sms_to") if $CONF{debug}==4;
my $sql_erorr_update_result=${SQL(qq[UPDATE cc_sms set status="-1" where src="$Q{msisdn}" and flag="$page$pg_num" and seq="$seq" and dst="$sms_to" and status=0 and imsi=$Q{imsi}],2)}[0];#to avoid double sms HFX-970
logger('LOG','SMS-REWRITE',"$sql_erorr_update_result") if $CONF{debug}==4;
#store page to db
my $INSERT_result=${SQL(qq[INSERT INTO cc_sms (`sms_id`,`src`,`dst`,`flag`,`seq`,`text`,`inner_tid`,`imsi`) values ("$Q{transactionid}","$Q{msisdn}","$sms_to","$page$pg_num","$seq","$sms_long_text","$Q{INNER_TID}","$Q{imsi}")],2)}[0];
logger('LOG','SMS-INSERT',"$INSERT_result") if $CONF{debug}==4;
#if insert ok
	if ($INSERT_result>0){#if insert ok
#if num page
		if ($pg_num eq $page){#if only one or last page - prepare sending
			($sms_long_text,$type,$sms_from)=split('::',${SQL(qq[SELECT get_sms_text2("$Q{msisdn}","$sms_to",$Q{imsi},$seq)],2)}[0]);#get text
			$sms_from=~s/\+//;#'+' is deprecated by C9 standart		
				if ($sms_long_text){#if return content
					my @multi_sms=($sms_long_text=~/.{1,168}/gs);#divide long text to 168 parts
					foreach $sms_text (@multi_sms){#foreach parth one sms
						logger('LOG','SMS-ENC-RESULT',"$sms_text") if $CONF{debug}==4;
						$sms_text=uri_escape($sms_text);#url encode
						logger('LOG','SMS-TEXT-ENC-RESULT',"$sms_text") if $CONF{debug}==4;
						logger('LOG','SMS-SEND-PARAM',"$sms_from,$sms_to") if $CONF{debug}==4;
#internal subscriber
							if ($type eq 'IN'){#internal subscriber
								logger('LOG','SMS-REQ',"INTERNAL") if $CONF{debug}==4;								
#MSG_CODE, IMSI_, DEST_, MSN_, OPT_1, OPT_2
my ($status,$code,$sms_result)=CURL('sms_mt',${SQL(qq[SELECT get_uri2('sms_mt',NULL,"$sms_to","$sms_from",NULL,"$sms_text")],2)}[0]);#send sms mt
					#bill_user($Q{imsi},'sms_mt');
								}#if internal
#external subscriber
							elsif($type eq 'OUT'){
								logger('LOG','SMS-REQ',"EXTERNAL") if $CONF{debug}==4;
my ($status,$code,$sms_result)=CURL('sms_mo',${SQL(qq[SELECT get_uri2('sms_mo',NULL,"$sms_to","$Q{msisdn}","$sms_from","$sms_text")],2)}[0]);#send sms mo
					#bill_user($Q{imsi},'sms_mt');
								}#else external
					}#foreach multisms
$SQL=qq[UPDATE cc_sms set status="$sms_result" where src="$Q{msisdn}" and dst="$sms_to" and seq="$seq" and status=0 and imsi=$Q{imsi}];
					my $sql_update_result=&SQL($SQL);#update status to sending result
					return $sms_result;		
				}#if long text
				else{#mark sms as error
my $sql_update_result=${SQL(qq[UPDATE cc_sms set status="-1" where src="$Q{msisdn}" and dst="$sms_to" and seq="$seq" and status=0 and imsi=$Q{imsi}],2)}[0];
return 3;#if cant get text set status to -1
					}#else mark sms
				}#if num_page==page
				else{#else multipage
					return 2;#multi page send ussd reply 'Wait...'
					}#end else multipage
					}#if insert
				else{#else not insert
						return -1;#it seems that double tid
					}#end else
}# END sub USSD_SMS #############################################################
#
### sub MO_SMS ##################################################################
# Authenticate outbound SMS request.
###
sub MO_SMS{
use vars qw(%Q);
logger('LOGDB','MO_SMS',$Q{transactionid},$Q{imsi},'RSP',"RuimTools 0");
return('MO_SMS',1,&response('MO_SMS','OK',$Q{transactionid},0,'RuimTools'));#By default reject outbound SMS MO
}#end sub MO_SMS
#
### sub MT_SMS ##################################################################
#
# Authenticate inbound SMS request ##############################################
###
sub MT_SMS{
logger('LOGDB','MT_SMS',$Q{transactionid},$Q{imsi},'RSP',"1");
return('MT_SMS',1,&response('MT_SMS','OK',$Q{transactionid},1));# By default we accept inbound SMS MT
}#end sub MT_SMS
#
### sub MOSMS_CDR ##################################################################
#
# MOSMS (Outbound) CDRs ############################################################
##
sub MOSMS_CDR{
	my $CDR_result=&SMS_CDR;
	logger('LOG','MOSMS_CDR',$CDR_result) if $CONF{debug}==4;
	logger('LOGDB','MOSMS_CDR',$Q{transactionid},$Q{imsi},'RSP',"$CDR_result");
	return('MOSMS_CDR',1,&response('MOSMS_CDR','OK',$Q{transactionid},$CDR_result));
}#end sub MOSMS_CDR ################################################################
#
### sub MTSMS_CDR ##################################################################
# MTSMS (Inbound) CDRs
###
sub MTSMS_CDR{
	my $CDR_result=&SMS_CDR;
	logger('LOG','MTSMS_CDR',$CDR_result) if $CONF{debug}==4;
	logger('LOGDB','MTSMS_CDR',$Q{transactionid},$Q{imsi},'RSP',"$CDR_result");
	return('MTSMS_CDR',1,&response('MTSMS_CDR','OK',$Q{transactionid},$CDR_result));
}#end sub MTSMS_CDR ################################################################
#
### sub SMSContent_CDR
# SMS Content CDRs #################################################################
##
sub SMSContent_CDR{
	use vars qw(%Q);#workaround #19 C9RFC
	$Q{'cdr_id'}='NULL';#workaround #19 C9RFC
	my $CDR_result=&SMS_CDR;
	logger('LOG','SMSContent_CDR',$CDR_result) if $CONF{debug}==4;
	logger('LOGDB','SMSContent_CDR',$Q{transactionid},$Q{imsi},'RSP',"$CDR_result");
	return('SMSContent_CDR',1,&response('MT_SMS','OK',$Q{transactionid},$CDR_result));
}#end sub SMSContent_CDR ############################################################
#
### SMS_CDR #########################################################################
# Processing CDRs for each type of SMS
###
sub SMS_CDR{
use vars qw(%Q);
#
my $SQL=qq[INSERT into `msrn`.`cc_sms_cdr` ( `id`, `msisdn`, `allow`, `reseller_charge`, `timestamp`, `smsc`, `user_charge`, `mnc`, `srcgt`, `request_type`, `smsfrom`, `IOT`, `client_charge`, `transactionid`, `route`, `imsi`, `user_balance`, `message_date`,`carrierid`,`message_status`,`service_id`,`sms_type`,`sender`,`message`,`original_cli`) values ( "$Q{cdr_id}", "$Q{msisdn}", "$Q{allow}", "$Q{reseller_charge}", "$Q{timestamp}", "$Q{smsc}", "$Q{user_charge}", "$Q{mnc}", "$Q{srcgt}", "$Q{request_type}", "$Q{smsfrom}", "$Q{IOT}", "$Q{client_charge}", "$Q{transactionid}", "$Q{route}", "$Q{imsi}", "$Q{user_balance}", "$Q{message_date}","$Q{carrierid}","$Q{message_status}","$Q{service_id}","$Q{sms_type}","$Q{sender}","$Q{message}","$Q{original_cli}")];
my $sql_result=&SQL($SQL);
logger('LOG','SMS_CDR',$sql_result) if $CONF{debug}==4;
return ('SMS_CDR',$sql_result); 
}#end sub SMS_CDR ##################################################################
# end SMS section ##################################################################
#
### sub DataAUTH ###################################################################
sub DataAUTH{
use vars qw(%Q);
my ($status,$code,$balance)=CURL('get_user_info',${SQL(qq[SELECT get_uri2('get_user_info',"$Q{imsi}",NULL,NULL,NULL,NULL)],2)}[0]);
my $data_auth=${SQL(qq[SELECT data_auth("$Q{MCC}","$Q{MNC}","$Q{TotalCurrentByteLimit}","$balance")],2)}[0];
$data_auth=0 if !$data_auth;
logger('LOG','DataAUTH',$data_auth) if $CONF{debug}==4;
#bill_user($Q{imsi},'DataAUTH');
return ('DataAUTH', $data_auth,&response('DataAUTH','OK',$data_auth));
}
### END sub DataAUTH ###############################################################
#
### sub POSTDATA ###################################################################
sub POSTDATA{
my ($status,$code,$result)=CURL('set_user_balance',${SQL(qq[SELECT get_uri2('set_user_balance',"$Q{imsi}",NULL,NULL,$Q{amount}*-1,NULL)],2)}[0]);
logger('LOG','POSTDATA',"$result ".$Q{amount}/1.25*-1) if $CONF{debug}==4;
return ('POSTDATA', $result, response('payment','PLAINTEXT','200'));
} 
### END sub POSTDATA ##############################################################
#
### sub msisdn_allocation #########################################################
# First LU with UK number allocation
###
sub msisdn_allocation{
use vars qw(%Q);
my $SQL=qq[UPDATE cc_card set phone="+$Q{msisdn}" where useralias=$Q{imsi} or firstname=$Q{imsi}];
my $sql_result=&SQL($SQL);
my ($status,$code,$new_user)=CURL('new_user',${SQL(qq[SELECT get_uri2('new_user',"$Q{imsi}",NULL,NULL,NULL,NULL)],2)}[0]);
logger('LOG','msisdn_allocation',$sql_result) if $CONF{debug}==4;
return ('msisdn_allocation',$sql_result,response('CDR_response','OK',$sql_result));
}#end sub msisdn_allocation #######################################################
#
### sub email #########################################################
###
sub email{
if ($Q{email_STATUS}){
		$Q{email}="denis\@ruimtools.com";
		$Q{email_sub}="Subscriber $Q{imsi} STATUS: $Q{email_STATUS}";
		$Q{email_text}="Receive request $Q{USSD_CODE} $Q{USSD_DEST} $Q{USSD_EXT} with incorrect subscriber status";
		$Q{email_FROM}="BILLING";
		$Q{email_from}="denis\@ruimtools.com";
	}#if status tmpl
eval {use vars qw(%Q);logger('LOG','EMAIL',"$Q{email} $Q{email_sub} $Q{email_text} $Q{email_from} $Q{email_FROM}") if $CONF{debug}==4;
my $email_result=`echo "$Q{email_text}" | mail -s '$Q{email_sub}' $Q{email} -- -F "$Q{email_FROM}" -f $Q{email_from}`;
return $email_result;
};warn $@ if $@;  logger('LOG',"SEND-EMAIL-ERROR","$@") if $@;
}
### sub XML #########################################################
###
sub XML{
use vars qw(%Q);
my $XML=XML::Smart->new(); 
$XML=$XML->{$Q{actions}}; 
$XML->{Authentication}{Username}->set_node();
$XML->{Authentication}{Password}->set_node();
$XML->{Authentication}{Username}=$Q{user};
$XML->{Authentication}{Password}=$Q{pass};
$XML->{$Q{request}}->set_node();
$XML->{$Q{request}}=$Q{imsi};
return $XML->data(nometagen=>1,nospace=>1,noheader=>1);
}
##
### sub redis #########################################################
###
sub redis{
use vars qw(%Q $redis_sock);
my $cmd=uc(shift);
my $n_elems = scalar(@_) + 1;
  my $buf = "\*$n_elems\r\n";
  for my $elem ($cmd, @_) {
    my $bin = $elem;
    $buf .= defined($bin) ? '$' . length($bin) . "\r\n$bin\r\n" : "\$-1\r\n";
  }
while ($buf) {
    my $len = syswrite $redis_sock, $buf, length $buf;
    confess("Could not write to Redis server: $!")
      unless $len;
    substr $buf, 0, $len, "";
  }
$redis_sock->recv(my $data,1024);
my ($a,$b)=split('\r',$data);
$b=~s/\n//g;
return $b;
}#end redis
##
### sub template #########################################################
##
sub template{
use vars qw($R);
my $template = Text::Template->new(TYPE => 'STRING',SOURCE => $R->hget('TEMPLATE',$_[0]));
my $text = $template->fill_in(HASH=>\%Q);
return $text;
}#end template
##
### sub bill #########################################################
##
sub bill{
use vars qw($R);
$R->HINCRBY("STAT:AGENT:$Q{SUB_AGENT_ID}",'['.substr($Q{timestamp},0,10)."]-[$Q{request_type}]-[$Q{code}$Q{USSD_CODE}]",1);
$R->HINCRBY("STAT:SUB:$Q{imsi}",'['.substr($Q{timestamp},0,10)."]-[$Q{request_type}]-[$Q{code}$Q{USSD_CODE}]",1) if $Q{imsi}>0;
$R->HINCRBYFLOAT("imsi:$Q{imsi}",'SUB_CREDIT',-$SIG{$_[0]}) if $Q{imsi}>0;
}## end bill
######### END #################################################	
