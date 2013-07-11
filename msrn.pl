#!/usr/bin/perl
#/usr/bin/perl
#/opt/local/bin/perl -T
#
########## VERSION AND REVISION ################################
## Copyright (C) 2012, RuimTools denis@ruimtools.com
##
my $rev='MSRN.ME 120713-rev.71.5';
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
use JSON::XS;
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
# use REDIS CONF (H)
# use REDIS TEMPLATE (H)
# use REDIS RESPONSE (S)
# use REDIS STATUS (H)
# use REDIS SIG (H)
# use REDIS AGENT (H)
# use REDIS imsi (H)
# use REDIS did (L)
# use REDIS subscriptions (L)
# use REDIS STAT_SUB (K)
# use REDIS STAT_AGENT (K)
# use REDIS PLMN (K)
# use REDIS VOUCHER (H)
# use REDIS TID (Z)
# use REDIS SDR (P)
# use REDIS TID (P)
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
$PIDFILE->open(">$CONF{pidfile}");# change to programm path (!)
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
our $LOGFILE = IO::File->new("$CONF{logfile}", "a+");
#################################################################
#
########## CONNECT TO MYSQL #####################################
our $dbh = DBI->connect_cached("DBI:mysql:$CONF{db_name}",$CONF{db_user},$CONF{db_pass});die "No auth!" unless defined($dbh);
##################################################################
#
########## OPEN SOCKET ###########################################
our $sock = FCGI::OpenSocket("$CONF{host}:$CONF{port}",10);
########## REV PRINT #############################################
print "$CONF{rev} Ready at $$ debug level $CONF{debug}\n";
####################### MULTITHREADING ###########################
#default min_ready_count = 10 // limit amount of connections to db
#default max_request_count = 500 // max connectons
#default redis_sync_timeout =5 // redis sync freq
########### WRITEBLE PARAMETRS #################################
share($CONF{'debug'});
share($CONF{'rate_cache_len'});
share($CONF{'debug-imsi'});
share($CONF{'fake-msrn'});
share($CONF{'fake-xml'});
share($CONF{'fake-agent-xml'});
share($CONF{'fake-call'});
share($CONF{'max-call-time'});
share($CONF{'sms_mt_allow'});
share($CONF{'ready_count'});
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
	$R0->subscribe($R0->lrange('subscriptions',0,-1),
		sub{ my ($value,$topic,$subscribtions)=@_;
		undef my $SQL;
		my $dbh = DBI->connect_cached('DBI:mysql:msrn',$CONF{db_user},$CONF{db_pass});
			if ($topic eq 'CONF'){
				my $R = Redis->new(server => 'localhost:6379',encoding => undef,);
					$CONF{$value}=$R->hget('CONF',$value);
					$R->zadd('TID',$redis_start++,"[API-COMMAND-$topic]: $value -> $CONF{$value}");
					$SQL=qq[UPDATE CONF a SET a.val="$CONF{$value}" WHERE a.key=\'$value\' limit 1];
					$R->quit;
			}#if CONF
				$SQL=qq[INSERT INTO SDR values ($value)] if $topic eq 'SDR';
				$SQL=qq[INSERT INTO TID values ($value)] if $topic eq 'TID';
			$dbh->do($SQL);
			$dbh->disconnect;
				}#sub
					);#subscribe
$R0->wait_for_messages($CONF{redis_sync_timeout}) while 1;
}#if tid 1
########################################################################
########## PROCCESING CONNECTIONS ######################################
  while ($request_count++ < $CONF{'max_request_count'} && $request->Accept() >= 0){
 	%Q=();
my ($s, $usec) = gettimeofday();my $format = "%06d";$usec=sprintf($format,$usec);$Q{INNER_TID}=$s.$usec;
$Q{TID}=int(rand(1000000));
our $redis_sock = new IO::Socket::INET (PeerAddr =>'127.0.0.1',PeerPort => 6379,Proto => 'tcp',blocking=>0);
our $R = Redis->new;
    clear_ready_flag;
	my $env = $request->GetEnvironment();
 $t0=Benchmark->new;
	$Q{REMOTE_ADDR}=$env->{REMOTE_ADDR};
	########### SET TIMER & INNER TID #####################################
	my ($t1,$t2,$td0);
########### IF POST/GET REQUEST #####################################
		$Q{REQUEST}= $env->{REQUEST_METHOD} eq 'POST' ? <STDIN> : $env->{QUERY_STRING};
########### IF VALID REQUEST #####################################
			$Q{REQUEST_TYPE}='gui' if $Q{REQUEST}!~m/request_type|api_cmd|datasession/g;
				print main();
			$t2=Benchmark->new;
			$td0 = timediff($t2, $t0);	
	logger('RDB',"COMMIT","DONE:$Q{REMOTE_ADDR} DEBUG:$CONF{debug} TID:$tid: ".substr($td0->[0],0,8)." ##########");
#
$redis_sock->close;
$R->quit;
set_ready_flag;
  }#while < max_request_count
  clear_ready_flag;
  threads->self->detach();
}#handler
#
########## MAIN #################################################
sub main{
use vars qw(%Q $dbh $R);
#
$dbh = DBI->connect_cached("DBI:mysql:$CONF{db_name}",$CONF{db_user},$CONF{db_pass});
#
	if (XML_PARSE($Q{REQUEST},'xml')>0){#if not empty set
#		my $head= redis('KEYS',"REQUEST_TYPE:$Q{request_type}") ? $Q{request_type} : return response('MAIN','ERROR','REQUEST TYPE UNKNOWN');
		my $head=$Q{REQUEST_TYPE};
		uri_unescape($Q{CALLDESTINATION})=~/^\*(\d{3})(\*|\#)(\D{0,}\d{0,}).?(.{0,}).?/ if $Q{CALLDESTINATION};
		($Q{USSD_CODE},$Q{USSD_DEST},$Q{USSD_EXT})=($1,$3,$4);
		$Q{IMSI}=$Q{IMSI} ? substr($Q{IMSI},-6,6) :0;
		$Q{GIMSI}=$CONF{imsi_prefix}.$Q{IMSI};
		$Q{TIMESTAMP}=strftime("%Y-%m-%d %H:%M:%S", localtime);
		$Q{BILL_TYPE}=$Q{CODE} ? $Q{CODE} :$Q{REQUEST_TYPE};
		$head=$Q{USSD_CODE} if $Q{CALLDESTINATION};
		$Q{REQUEST_TYPE}="payment" if $Q{SALT};
#		$Q{request_type}="datauth" if $Q{SessionID};
#		$Q{request_type}="postdata" if $Q{calllegid};
#		$Q{imsi}=$Q{IMSI} if $Q{request_type} eq 'msisdn_allocation';
		$Q{TRANSACTIONID}=$Q{CDR_ID} if $Q{REQUEST_TYPE} eq 'msisdn_allocation';
		$Q{TRANSACTIONID}=$Q{SESSIONID} if $Q{SESSIONID};#DATA
#		$Q{IMSI}=$Q{GLOBALIMSI} if $Q{SESSIONID};#DATA
			my $IN_SET="$head:";#need request type and : as first INFO
			$IN_SET=$IN_SET.uri_unescape($Q{MSISDN}).":$Q{mcc}:$Q{mnc}:$Q{tadig}" if  $Q{MSISDN};#General
			$IN_SET=$IN_SET."$Q{USSD_DEST}:$Q{CODE}" if $Q{USSD_DEST}; 
			$IN_SET=$IN_SET."$Q{IDENT}:$Q{AMOUNT}" if $Q{SALT};#PAYMNT
			$IN_SET=$IN_SET."$Q{TOTALCURRENTBYTELIMIT}" if $Q{SESSIONID};#DATA AUTH
			$IN_SET=$IN_SET."$Q{CALLLEGID}:$Q{BYTES}:$Q{SECONDS}:$Q{MNC}:$Q{MCC}:$Q{AMOUNT}" if $Q{CALLLEGID};#POSTDATA
#
########### GET SUB ##########################################
if(!GET_SUB()&&$Q{IMSI}){return &response('ERROR','DEFAULT','SORRY SIM NOT FOUND #'.__LINE__)}
########### SET SUBREF ##########################################
my	$ACTION_TYPE=$Q{REQUEST_TYPE}; 
	$ACTION_TYPE='agent' if ($Q{SUB_GRP_ID}>1&&$Q{REQUEST_TYPE} ne 'api_cmd');
	eval {our $subref=\&$ACTION_TYPE;};warn $@ if $@;  logger('LOG',"MAIN-ACTION-SUBREF","ERROR $ACTION_TYPE $@") if $@;
##################################################################
use vars qw($subref);
#
########### USSD DIRECT CALL ###########
if (!$Q{USSD_CODE} && $Q{REQUEST_TYPE} eq 'auth_callback_sig'){
uri_unescape($Q{CALLDESTINATION})=~/^\*(\d{7,14})\#/;
$Q{USSD_DEST}=$1;
$Q{USSD_CODE}=112; 
}#if USSD DIRECT CALL
########################################
our ($ACTION_STATUS,$ACTION_CODE,$ACTION_RESULT,%LOG);
		logger('LOGDB',"$ACTION_TYPE",0,'IN',$IN_SET) if $CONF{debug}==4;
eval {	($ACTION_STATUS,$ACTION_CODE,$ACTION_RESULT)=&$subref();
			};warn $@ if $@;  logger('LOG',"MAIN-ACTION-SUBREF","ERROR $ACTION_TYPE $@") if $@;
		logger('LOG',"MAIN-ACTION-RESULT-$ACTION_TYPE","$ACTION_STATUS $ACTION_CODE". substr($ACTION_RESULT,0,100)) if $CONF{debug}==4;
		logger('LOGDB',"$ACTION_TYPE",0,"$ACTION_STATUS","$ACTION_CODE") if $CONF{debug}==4;
		bill($Q{BILL_TYPE}) if $ACTION_CODE>0;
		$dbh->disconnect;
		return "$ACTION_RESULT" if $ACTION_STATUS;
		return &response('ERROR','DEFAULT','SORRY NO RESULT #'.__LINE__) if !$ACTION_STATUS;
}#if keys
else{#else if keys
	return &response('DEFAULT','ERROR','INCORRECT KEYS #'.__LINE__,0);
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
my ($REQUEST_LINE,$REQUEST_OPTION,@QUERY)=@_;
$REQUEST_LINE=~s/\r|\n|\t//g;
#
logger('LOG',"XML-PARSE-REQUEST",$REQUEST_LINE) if $CONF{debug}==4;
if ($REQUEST_LINE=~m/xml version/){
my $xml=new XML::Bare(text=>$REQUEST_LINE, simple =>1);
$Q{REQUEST}=$xml->parse();
return 0 if !(keys $Q{REQUEST});
map {$Q{REQUEST}=$Q{REQUEST}->{"$_"} if $_=~/Wire9_data|api|data|response/} keys $Q{REQUEST};
}#if xml
else{#CGI REQUEST
	logger('LOG',"CGI-PARSE-REQUEST",$Q{REQUEST}) if $CONF{debug}==4;
		$Q{REQUEST}=~tr/\&/\;/;
		my %Q_tmp=split /[;=]/,$Q{REQUEST}; map {$Q{uc $_}=uri_unescape($Q_tmp{$_})} keys %Q_tmp;
		return scalar keys %Q;
}#else cgi
#
switch ($REQUEST_OPTION){
	case 'xml' {
		if($Q{REQUEST}->{api_cmd}){
		logger('LOG',"XML-PARSE-KEYS", join(',',sort keys $Q{REQUEST}->{api_cmd})) if $CONF{debug}==4;
	map {$Q{uc $_}=$Q{REQUEST}->{api_cmd}{$_}{value} if $_!~/^_(i|z|pos)$/;} keys $Q{REQUEST}->{api_cmd};
		$Q{REQUEST_TYPE}='api_cmd';
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
		elsif($Q{REQUEST}->{reference}{value} eq 'Data'){
		logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION",'datasession') if $CONF{debug}==4;
	map {$Q{uc $_}=$Q{REQUEST}->{$_} if $_!~/^_(i|z|pos)$/} keys $Q{REQUEST};
	map {$Q{uc $_}=$Q{REQUEST}->{callleg}{$_}{value} if $_!~/^_(i|z|pos)$/} keys $Q{REQUEST}->{callleg};
		$Q{REQUEST_TYPE}='DataSession';
		$Q{TRANSACTIONID}=$Q{calllegid};
		$Q{IMSI} = scalar ($Q{IMSI}=$R->HGET('DID',$Q{NUMBER}))>0 ? $CONF{imsi_prefix}.$Q{IMSI} :0;
	return scalar keys %Q;
		}#elsif postdata
		else{#unknown format
			logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION",'UNKNOWN FORMAT') if $CONF{debug}==4;
	return 0;
		}#else unknown
	}#xml
	case /get_msrn/ {
		$Q{MSRN}=$Q{REQUEST}->{MSRN_Response}{MSRN}{value};
		$Q{MCC}=$Q{REQUEST}->{MSRN_Response}{MCC}{value};
		$Q{MNC}=$Q{REQUEST}->{MSRN_Response}{MNC}{value};
		$Q{TADIG}=$Q{REQUEST}->{MSRN_Response}{TADIG}{value};
		$Q{MSRN}=~s/\+//;#supress \+ from xml response (!)
		our $ERROR=$Q{REQUEST}->{Error_Message} ? $Q{REQUEST}->{Error_Message}{value} : 0;
		logger('LOG',"XML-PARSER-DONE","$Q{MSRN} $Q{MCC} $Q{MNC} $Q{TADIG} $Q{MTC} $ERROR") if $CONF{debug}==4;
		$Q{MTC}= redis('keys',"PLMN:$Q{TADIG}:*") ? redis('get',$R->keys("PLMN:$Q{TADIG}:*")) : 0;
		$R->SETEX('OFFLINE:'.$Q{IMSI},600,0) if $Q{MSRN} eq 'OFFLINE';
		logger('LOG',"XML-PARSED-$REQUEST_OPTION","$Q{MSRN} $Q{MCC} $Q{MNC} $Q{TADIG} $Q{MTC} $ERROR") if $CONF{debug}==4;
		return $Q{MSRN};
	}#msrn
	case 'send_ussd' {
		$Q{STATUS}=$Q{REQUEST}->{USSD_Response}{REQUEST_STATUS}{value};
		$Q{ERROR}=$Q{REQUEST}->{Error_Message}{value};
		logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$Q{STATUS} $Q{ERROR}") if $CONF{debug}==4;
		return "$Q{STATUS}$Q{ERROR}";
	}#ussd
#	case /sms_m/ {
#		my $SMS=$Q{REQUEST}->{SMS_Response}{REQUEST_STATUS}{value};
#		our $ERROR=$Q{REQUEST}->{Error_Message}{value};
#		logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$SMS $ERROR") if $CONF{debug}==4;
#		return "$ERROR$SMS";
#	}#sms
	case 'send_sms_mt' {
		$Q{STATUS}=$Q{REQUEST}->{SMS_Response}{REQUEST_STATUS}{value};
		$Q{ERROR}=$Q{REQUEST}->{Error_Message}{value};
		logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$Q{STATUS} $Q{ERROR}") if $CONF{debug}==4;
		return "$Q{STATUS}$Q{ERROR}";
	}#sms
	case /agent/ {
		my $RESULT=$Q{REQUEST}->{RESALE_Response}{RESPONSE}{value};
		our $ERROR=$Q{REQUEST}->{Error_Message}{value};
		logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$RESULT $ERROR") if $CONF{debug}==4;
		return $RESULT;
	}#resale
	case 'get_session_time' {
		my $TIME=$Q{REQUEST}->{RESPONSE}{value};
		our $ERROR=$Q{REQUEST}->{Error_Message}{value};
		logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$TIME $ERROR") if $CONF{debug}==4;
		return "$ERROR$TIME";
	}#get time
	case 'get_user_info' {
		my $BALANCE=$Q{REQUEST}{GetUserInfo}->{Balance}{value};
		our $ERROR=$Q{REQUEST}{GetUserInfo}->{Reason}{value};
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
		$Q{STATUS}= ref $Q{REQUEST}->{CreateAccount}{Result} eq 'ARRAY' ? $Q{REQUEST}->{CreateAccount}{Result}[0]{value} : $Q{REQUEST}->{CreateAccount}{Result}{value};
		my $ERROR= ref $Q{REQUEST}->{CreateAccount}{Reason} eq 'ARRAY' ? $Q{REQUEST}->{CreateAccount}{Reason}[1]{value} : $Q{REQUEST}->{CreateAccount}{Reason}{value};
		logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$Q{STATUS} $ERROR") if $CONF{debug}==4;
		return "$Q{STATUS}$ERROR";
	}#new user
	case /siminfo/i {
		$Q{PIN}=$Q{REQUEST}->{Sim}{Password}{value};
		our $ERROR=$Q{REQUEST}->{Error}{value};
		logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","xxxx $ERROR") if $CONF{debug}==4;
		return "xxxx$ERROR";
	}#sim info	
	case 'set_user' {
		 $Q{STATUS}=$Q{REQUEST}->{status}{value};
		 $Q{ERROR}=$Q{REQUEST}->{error}{value};
		logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$Q{STATUS} $Q{ERROR}") if $CONF{debug}==4;
		return "$Q{STATUS}$Q{ERROR}";
	}#set user
	case 'set_user_status' {
		$Q{STATUS}=$Q{REQUEST}->{STATUS_Response}{IMSI_STATUS}{value};
		$Q{ERROR}=$Q{REQUEST}->{Error_Message} ? $Q{REQUEST}->{Error_Message}{value} : undef;
		logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$Q{STATUS} $Q{ERROR}") if $CONF{debug}==4;
		return "$Q{STATUS}$Q{ERROR}";
	}#set userstatus
	else {
		print logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION",'NO OPTION FOUND $@') if $CONF{debug}==4;
		return "Error: $@";}
}#switch OPTION
}#END sub XML_PARSE
#
########## GET SUB #############################################
## Resolve request type action with cc_actions
## Checks each parameter with database definition 
## Returns code of request type or 2 (no such type) or 3 (error)
#################################################################
sub GET_SUB{
use vars qw(%Q $R);
my %HASH;
if ($Q{IMSI}&&$R->HLEN("SUB:$Q{IMSI}")>10){
	%HASH=$R->HGETALL("SUB:$Q{IMSI}");
	map {$Q{$_}=$HASH{$_}} keys %HASH;
	logger('LOG','OK','SUB FROM CACHE');
return scalar %HASH;	
	}#if
elsif($Q{IMSI}){
eval {
	%HASH = %{SQL(qq[CALL get_sub($Q{GIMSI})],'hash')};
	$R->HSET('SUB:'.$Q{IMSI},$_,$HASH{$_}, sub{}) for keys %HASH;
	$R->wait_all_responses;
	$R->EXPIRE('SUB:'.$Q{IMSI},86400);

map {$Q{uc($_)}=$HASH{$_}} keys %HASH;

	logger('LOG','OK','SUB WAS CACHED');
				};warn $@ if $@;  logger('LOG',"GET-SUB","ERROR $Q{IMSI} $@") if $@;

return scalar %HASH;
	}#if imsi
else{
return 0;
}#else
}########## END GET_SUB ########################################
#
########## SQL ##################################################
## Performs SQL request to database
## Accept SQL input
## Return SQL records or mysql error
#################################################################
sub SQL{ 
use vars qw($dbh);
my $SQL=qq[$_[0]];
my $flag=$_[1] ? $_[1] : -1;
$SQL=qq[SELECT get_text($SQL)] if $flag eq '1';
my ($rc, $sth, @result, $result, $new_id);
#
@result=(); $new_id=0;
#
if($SQL!~m/^[SELECT|CALL]/i){#INSERT/UPDATE request
logger('LOG','SQL-MYSQL-GET',"DO $SQL") if $CONF{debug}==4;
	$rc=$dbh->do($SQL);#result code
	push @result,$rc;#result array
	$new_id = $dbh -> {'mysql_insertid'};#autoincrement id
}#if SQL INSERT UPDATE
else{#SELECT request
logger('LOG','SQL-MYSQL-GET',"EXEC $SQL") if $CONF{debug}==4;
	$sth=$dbh->prepare($SQL);
	$rc=$sth->execute;#result code
	@result=$sth->fetchrow_array if $flag eq '2';
	$result=$sth->fetchrow_hashref if $flag eq 'hash';
	$result=$sth->fetchall_arrayref if $flag eq 'ajax';
}#else SELECT
#
if($rc){#if result code
	logger('LOG','SQL-MYSQL-RETURNED-[code/array/hash/id]',"$rc/@result/$result/$new_id") if $CONF{debug}==4;
	return \@result if $flag eq '2';
	return  $result if $flag =~/hash|ajax/;
#	return  $result if $flag eq 'ajax';
	return @result; 
}#if result code
else{#if no result code
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
$Q{TRANSACTION_ID}=$Q{TRANSACTIONID};
my ($ACTION_TYPE, $RESPONSE_TYPE, $RESPONSE)=@_;
my $HEAD=qq[Content-Type: text/xml\n\n<?xml version="1.0" ?>];
#
switch ($RESPONSE_TYPE){
	case 'OK'{
		$Q{ALLOW}=$Q{DISPLAY_MESSAGE}=$RESPONSE;
		my $xml=new XML::Bare(simple=>1);
		my %HASH;
	map { $HASH{uc $ACTION_TYPE}{$_}={value=>$Q{$_}} if defined $Q{$_} } @{$R->SMEMBERS('RESPONSE:'.uc $ACTION_TYPE)};
		return $HEAD.$xml->xml(\%HASH);
	}#case OK
	case 'ERROR'{
	my	$ERROR=qq[<Error><Error_Message>$RESPONSE</Error_Message></Error>\n];
		return $HEAD.$ERROR;
	}#case ERROR
	case 'DEFAULT'{
	my	$ERROR=qq[<MOC_RESPONSE><TRANSACTION_ID>$Q{TRANSACTIONID}</TRANSACTION_ID><DISPLAY_MESSAGE>$RESPONSE</DISPLAY_MESSAGE></MOC_RESPONSE>\n];
		return $HEAD.$ERROR;
	}#case DEFAULT
	case 'HTML'{
		$HEAD=qq[Content-Type: text/html\n\n];
		return $HEAD.$RESPONSE;
	}#case HTML
	case 'JSON'{
		$HEAD="Content-Type: text/html\n\n";
#		$RESPONSE=\@ARESPONSE
		return $HEAD.encode_json $RESPONSE;
	}#case JSON
}#switch
}########## RESPONSE #############################################
########## LOGGER ##############################################
sub logger{
use vars qw($LOGFILE $t0 %LOG);
## SET TIMERS
my $t3=Benchmark->new;
my $td1=timediff($t3, $t0);
my $timer=substr($td1->[0],0,8);
my ($s, $usec) = gettimeofday();
my $format = "%06d";$usec=sprintf($format,$usec);
my $now=strftime("%Y-%m-%d %H:%M:%S", localtime).":$usec";
##
my ($LOG_TYPE,$RESPONSE_TYPE,$LOG,$STATUS,$INFO)=@_;
#
switch ($LOG_TYPE){
case 'RDB'{
	$LOG{$Q{INNER_TID}}->{$timer}="[$now]-[$Q{INNER_TID}]-[$timer]-[API-LOG-$RESPONSE_TYPE]:$LOG";# if $CONF{debug}>0 and $CONF{'debug-imsi'} eq $Q{imsi};
	if ($RESPONSE_TYPE eq 'COMMIT'){
	$R->ZADD($Q{INNER_TID},$_,$LOG{$Q{INNER_TID}}->{$_},sub {}) for sort keys $LOG{$Q{INNER_TID}};
	$R->wait_one_response;
	redis('zadd','TID',$Q{INNER_TID},"[$now]-[$timer]-[$Q{GIMSI}]-[$Q{REQUEST_TYPE}]-[$Q{CODE}$Q{USSD_CODE}]-[$Q{INNER_TID}]");
	}#if COMMIT
}#redis DB
case 'LOG'{
	$LOG{$Q{INNER_TID}}->{$timer}="[$now]-[$Q{INNER_TID}]-[$timer]-[API-LOG-$RESPONSE_TYPE]:$LOG" if $CONF{debug}>0;
	}#case LOG
case 'LOGDB'{
	redis('publish','TID',"NULL,NULL,'$RESPONSE_TYPE',$Q{INNER_TID},'$Q{TRANSACTIONID}','$Q{GIMSI}','$STATUS','$INFO','$timer'") if $CONF{debug}==4;
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
#			my $UPDATE_result=${SQL(qq[SELECT set_country($Q{imsi},$Q{mcc},$Q{mnc},"$Q{msisdn}")],2)}[0];
			$R->EXPIRE('OFFLINE:'.$Q{IMSI},0);
			$R->HMSET("SUB:$Q{IMSI}",'SUB_MCC',$Q{MCC},'SUB_MNC',$Q{MNC},'SUB_TADIG',$Q{TADIG});
			$Q{CDR_STATUS}=1;
			$Q{MTC}= redis('keys',"PLMN:$Q{TADIG}:*") ? redis('get',$R->keys("PLMN:$Q{TADIG}:*")) : 0;
# Comment due activation proccess
#			if ($UPDATE_result){#if contry change
#			my $msrn=CURL('get_msrn_free',${SQL(qq[SELECT get_uri2('get_msrn',"$Q{imsi}",NULL,NULL,NULL,NULL)],2)}[0]);
#my $TRACK_result=CURL('sms_mt_free',${SQL(qq[SELECT get_uri2('mcc_new',"$Q{imsi}",NULL,"$Q{msisdn}",'ruimtools',"$Q{iot_charge}")],2)}[0]);
	#$TRACK_result=CURL('sms_mt',${SQL(qq[SELECT get_uri2('get_ussd_codes',NULL,NULL,"$Q{msisdn}",'ruimtools',NULL)],2)}[0]);
#				logger('LOG','MAIN-LU-HISTORY-RETURN',"$TRACK_result");
#			}#if country change
			#logger('LOGDB',"LU_CDR","$Q{transactionid}","$Q{imsi}",'OK',"$Q{SUB_ID} $Q{imsi} $Q{msisdn}");
#			logger('LOG','LU-REQUEST-OK',"$Q{imsi} $Q{msisdn} $Q{SUB_ID}") if $CONF{debug}==4;
			return ('OK',"$Q{SUB_ID}:$Q{MCC}:$Q{MNC}:$Q{TADIG}",response('CDR_RESPONSE','OK',1));
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
$R->EXPIRE('OFFLINE:'.$Q{IMSI},0);
my @result;
logger('LOG',"SIG-$Q{USSD_CODE}-REQUEST","$Q{IMSI},$Q{USSD_CODE},$Q{USSD_DEST},$Q{USSD_EXT}") if $CONF{debug}==4;
if(($Q{SUB_STATUS}==1)||($Q{USSD_CODE}=~/^(123|100|000|110|111)$/)){#if subscriber active
	if (($Q{USSD_CODE}=~/112/)&&$Q{USSD_DEST}){@result=SPOOL()}
	else{@result=USSD()}
	return @result;
		}#if subscriber active
	else{#status not 1 or balance request
		logger('LOG','auth_callback_sig-INCORRECT-STATUS',"$Q{SUB_STATUS} #".__LINE__) if $CONF{debug}==4;
#		logger('LOGDB','STATUS',"$Q{transactionid}","$Q{imsi}",'ERROR',"$Q{SUB_STATUS}");
		$Q{EMAIL_STATUS}="$Q{SUB_STATUS} $SYS{$Q{SUB_STATUS}}";
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
use vars qw(%Q %CONF);
my (%RATE,%cache,$type);
#my $msisdn=uri_unescape($Q{msisdn});
#my $uniqueid=timelocal(localtime())."-".int(rand(1000000));
#my $USSD_dest=$Q{USSD_DEST};
#my $internal=0;
#
# INTERNAL CALL
#if(length($Q{USSD_DEST})=6&&$Q{imsi} ne $Q{USSD_DEST}){#if internal call destination
#		logger('LOG','SPOOL-GET-INTERNAL-CALL',"$Q{USSD_DEST}") if $CONF{debug}==4;
#		my ($status,$code,$Q{msrn})=CURL('get_msrn',template('get_msrn'));#get msrn for internal call
#		logger('LOG','SPOOL-GET-INTERNAL-MSRN-RESULT',$Q{msrn}) if $CONF{debug}==4;
#	if ($msrn=~/\d{7,15}/){	$Q{USSD_DEST}=$Q{msrn};	$internal=1;
#	}else{ return ('OFFLINE DEST', -5,response('MOC_response','OK',template('spool:dest_offline'))) }#return offline or empty msrn  
#}#if internal call
#	elsif ($Q{USSD_DEST}=~/^(\+|00)?([1-9]\d{7,15})$/){#elsif outbound call destianation
#			logger('LOG','SPOOL-GET-OUTBOUND-CALL',"$Q{USSD_DEST}") if $CONF{debug}==4;
#			$Q{USSD_DEST}=$2;#set dest
#	}#elsif outbound call
#else {#else incorrect dest
#			logger('LOG','SPOOL-GET-INTERNAL-SELF',"$Q{USSD_DEST}") if $CONF{debug}==4 and $Q{imsi} eq $Q{USSD_DEST};
#			return ('CALL SELF',-4,response('MOC_response','OK',template('spool:dest_self'))) if $Q{imsi} eq $Q{USSD_DEST};
#$Q{USSD_DEST}=0;
#}#else incorrect dest
#	logger('LOG','SPOOL-GET-DEST',"$Q{USSD_DEST} in $USSD_dest") if $CONF{debug}==4;
#
# PROCESSING CALL
if ($Q{USSD_DEST}=~/^(\+|00)?([1-9]\d{7,15})$/){#if correct destination number - process imsi msrn
#	my	$msrn=$2 if (($Q{USSD_CODE}==128)&&($Q{USSD_EXT}=~/^(\+|00)?([1-9]\d{7,15})#?$/));#local number call
#logger('LOG','SPOOL-LOCAL-NUMBER-CALL',"$msrn $Q{USSD_EXT}") if $msrn and $CONF{debug}==4;
	(my $status,my $code,$Q{MSRN})=CURL('get_msrn',template('get_msrn'));
#	my $offline=1 if $msrn} eq 'OFFLINE';
#logger('LOG','SPOOL-GET-MSRN-RESULT',$msrn) if $CONF{debug}==4;
#
if ($Q{MSRN}=~/\d{7,15}/){
## Call SPOOL
foreach my $type ('USSD_DEST','MSRN'){
my %HASH=%{call_rate($Q{$type})};
map {$Q{$type.'_'.uc($_)}=$HASH{$_}} keys %HASH;
}#foreach number
	$Q{'CALL_RATE'}=($Q{USSD_DEST_RATE}+$Q{USSD_DEST_RATE}/$CONF{'markup'}+$Q{MSRN_RATE})/100+$Q{MTC};
	$Q{'CALL_LIMIT'}=($Q{'CALL_LIMIT'}=floor(($Q{'SUB_CREDIT'}/$Q{'CALL_RATE'})*60))>$CONF{'max-call-time'} ? $CONF{'max-call-time'} : $Q{'CALL_LIMIT'};
#
	$Q{'SUB_CREDIT'}=sprintf '%.2f',$Q{'SUB_CREDIT'};
	$Q{'CALL_RATE'}=sprintf '%.2f',$Q{'CALL_RATE'};
#
logger('LOG','SPOOL-GET-TRUNK-[dest/msrn/prefix/rate/limit]',"$Q{USSD_DEST_TRUNK}/$Q{MSRN_TRUNK}/$Q{'MSRN_PREFIX'}/$Q{CALL_RATE}/$Q{CALL_LIMIT}") if $CONF{debug}==4;
#
	$Q{UNID}=$Q{TID}.'-'.$Q{IMSI};
	my $CALL = IO::File->new("$CONF{tmpdir}/".$Q{UNID}.'-'.$Q{MSRN}, "w");
	print $CALL template('spool:call');
	close $CALL;
chown 100,101,"$CONF{tmpdir}/".$Q{UNID}.$Q{MSRN};
my $mv= $CONF{'fake-call'}==0 ? move("$CONF{'tmpdir'}/".$Q{UNID}.$Q{MSRN}, "$CONF{'spooldir'}/".$Q{UNID}.$Q{MSRN}) : $CONF{'fake-call'};
#
return ("SPOOL-[move/uniqid/rate] $mv:$Q{UNID}:$Q{CALL_RATE}",$mv,response('MOC_response','OK',template('spool:wait')));
	}#if msrn and dest
	else{#else not msrn and dest
		return ('OFFLINE',-2,response('MOC_response','OK',template('spool:offline')));
		}#else not msrn and dest
}#if dest
else{
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
		$Q{EMAIL}="denis\@ruimtools.com";
		$Q{EMAIL_SUB}="NEW TT: [$Q{IMSI}]";
		$Q{EMAIL_TEXT}=${SQL(qq[NULL,'ussd',$Q{USSD_CODE},NULL],1)}[0];
		$Q{EMAIL_FROM}="SUPPORT";
		$Q{EMAIL_FROM_ADDRESS}="denis\@ruimtools.com";
		email();
		return ('OK',1,response('MOC_response','OK',${SQL(qq[NULL,'ussd',$Q{USSD_CODE},NULL],1)}[0]));		
			}#case 000
###
	case "100"{#MYNUMBER request
		logger('LOG','SIG-USSD-MYNUMBER-REQUEST',"$Q{USSD_CODE}") if $CONF{debug}==4;
		$Q{SUB_DID}= scalar ($Q{SUB_DID}=$R->HGET('SUB:'.$Q{IMSI},'SUB_DID')) ? $Q{SUB_DID} : $Q{GLOBALMSISDN};
#		$Q{SUB_CREDIT}=sprintf '%.2f',$Q{SUB_CREDIT};
		return ('OK',1,response('MOC_response','OK',template("ussd:$Q{USSD_CODE}")));		
	}#case 100
###
	case "110"{#IMEI request
		logger('LOG','SIG-USSD-IMEI-REQUEST',"$Q{USSD_DEST}") if $CONF{debug}==4;
		redis('hset',"SUB:$Q{IMSI}",'SUB_HANDSET',"$Q{USSD_DEST} $Q{USSD_EXT}");
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
		return ('OK',$SMS_result, &response('auth_callback_sig','OK',$Q{TRANSACTIONID},"$SMS_response"));
		
	}#case 122
###
	case [111,123]{#voucher refill request
		logger('LOG','SIG-USSD-BALANCE-REQUEST',"$Q{USSD_CODE}") if $CONF{debug}==4;
		$Q{SUB_CREDIT_INET}=sprintf '%.2f',(CURL('get_user_info',template('get_user_info'))*1.25);
		$Q{SUB_CREDIT}=$R->SREM('VOUCHER',$Q{USSD_DEST}) ? sprintf '%.2f', $R->HINCRBYFLOAT("SUB:$Q{IMSI}",'SUB_CREDIT',+$CONF{voucher_amount}) : $Q{SUB_CREDIT};
		return ('OK',$Q{SUB_CREDIT},response('MOC_response','OK',template("ussd:111")));
	}#case 111
#
	case "125"{#voip account
	logger('LOG','SIG-USSD-VOIP-ACCOUNT-REQUEST',"$Q{USSD_CODE}") if $CONF{debug}==4;
	my ($status,$code,$new_user)=CURL('new_user',${SQL(qq[SELECT get_uri2('new_user',"$Q{IMSI}",NULL,NULL,NULL,NULL)],2)}[0]) if !$Q{SUB_VOIP};
	#logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'RSP',"$Q{USSD_CODE} $new_user") if !$Q{SUB_VOIP};
	return ('OK',1, &response('auth_callback_sig','OK',$Q{TRANSACTIONID},${SQL(qq[$Q{IMSI},'ussd',$Q{USSD_CODE},NULL],1)}[0]));
	}#case 124
###
	case "126"{#RATES request
		logger('LOG','SIG-USSD-RATES',"$Q{USSD_CODE} $Q{USSD_DEST}") if $CONF{debug}==4;
		#logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'OK',"$Q{USSD_CODE} $Q{USSD_DEST}");
		return ('NO DEST',-1,&response('auth_callback_sig','OK',$Q{TRANSACTIONID},"Please check destination number!")) if $Q{USSD_DEST} eq '';
		$Q{USSD_DEST}=~/^(\+|00)?([1-9]\d{1,15})$/;
		my $dest=$2;
		my ($status, $code, $msrn)=CURL('get_msrn',${SQL(qq[SELECT get_uri2('get_msrn',"$Q{IMSI}",NULL,NULL,NULL,NULL)],2)}[0]);
		my $rate=${SQL(qq[SELECT round(get_rate($msrn,$dest),2)],2)}[0] if $msrn=~/^(\+)?([1-9]\d{7,15})$/;
		logger('LOG','SIG-USSD-RATES-RETURN',"$rate") if $CONF{debug}==4;
	return ('OK',1,&response('auth_callback_sig','OK',$Q{TRANSACTIONID},"Callback rate to $Q{USSD_DEST}: \$ $rate. Extra: ".substr($Q{IOT_CHARGE}/0.63,0,4))) if $rate=~/\d/;
		return ('OFFLINE',0,&response('auth_callback_sig','OK',$Q{TRANSACTIONID},"Sorry, number offline")) if $msrn=~/OFFLINE/;
	}#case 126
###
	case "127"{#CFU request
		logger('LOG','SIG-USSD-CFU-REQUEST',"$Q{USSD_CODE} $Q{USSD_DEST}") if $CONF{debug}==4;
		if ($Q{USSD_DEST}=~/^(\+|00)?(\d{5,15})$/){#if prefix +|00 and number length 5-15 digits
			logger('LOG','SIG-USSD-CFU-REQUEST',"Subcode processing $Q{USSD_DEST}") if $CONF{debug}==4;
				 my $CFU_number=$2;
				 my $SQL=qq[SELECT get_cfu_code($Q{IMSI},"$CFU_number")];
					my $CODE=${SQL("$SQL",2)}[0];
(my $status,my $code,$CODE)=CURL('sms_mo',${SQL(qq[SELECT get_uri2('sms_mo',NULL,"+$CFU_number","$Q{MSISDN}",'ruimtools',"$CODE")],2)}[0]) if $CODE=~/\d{5}/;
					$CFU_number='NULL' if $CODE!~/0|1|INUSE/;
					$SQL=qq[SELECT get_cfu_text("$Q{IMSI}","$CODE",$CFU_number)];
					my $TEXT_result=${SQL("$SQL",2)}[0];
					return ('OK',$CODE,&response('auth_callback_sig','OK',$Q{TRANSACTIONID},$TEXT_result));
					#logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'RSP',"$CODE $Q{USSD_CODE} $Q{USSD_DEST}");
			}#if number length
			else{#else check activation
			logger('LOG','SIG-USSD-CFU-REQUEST',"Code processing $Q{USSD_CODE} $Q{USSD_DEST}") if $CONF{debug}==4;
				my $SQL=qq[SELECT get_cfu_text("$Q{IMSI}",'active',NULL)];
				#my @SQL_result=&SQL($SQL);
				my $TEXT_result=${SQL("$SQL",2)}[0]; 
				return ('OK', $Q{USSD_CODE},&response('auth_callback_sig','OK',$Q{TRANSACTIONID},"$TEXT_result"));
				#logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'RSP',"$Q{USSD_CODE} $Q{USSD_DEST}");
				}
	}#case 127
###
	case "128"{#local call request
		logger('LOG','SIG-LOCAL-CALL-REQUEST',"$Q{USSD_CODE}") if $CONF{debug}==4;
		#logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'OK',"$Q{USSD_CODE}");
		my $SPOOL_result=SPOOL() if $Q{USSD_EXT};
		return ('OK',1, $SPOOL_result) if $Q{USSD_EXT};
		return ('OK', 1, &response('auth_callback_sig','OK',$Q{TRANSACTIONID},${SQL(qq["$Q{IMSI}",'ussd',$Q{USSD_CODE},$Q{MCC}],1)}[0]));
	}#case 128
###
	case "129"{#my did request
		logger('LOG','SIG-DID-NUMBERS-REQUEST',"$Q{USSD_CODE} $Q{USSD_DEST} $Q{USSD_EXT}") if $CONF{debug}==4;#(!) hide pin
		$Q{USSD_DEST}=$Q{IMSI} if ($Q{USSD_DEST}!~/^(\+|00)?([1-9]\d{7,15})$/);
		if ($Q{USSD_EXT}=~/^([0-9]\d{3})#?$/){# check pin
		$Q{-O}='-d';
		($Q{-H},$Q{USER},$Q{PASS})=@{SQL(qq[SELECT description,auth_login,auth_pass from cc_provider WHERE provider_name='C94'],2)};
		$Q{ACTIONS}='SimInformationByMSISDN'; $Q{REQUEST}='IMSI';
		CURL($Q{ACTIONS},XML());
		logger('LOG','SIG-DID-NUMBERS-PIN-CHECK',"SUCCESS") if $1==$Q{PIN} and $CONF{debug}==4;;
		logger('LOG','SIG-DID-NUMBERS-PIN-CHECK',"ERROR") if $1!=$Q{PIN} and $CONF{debug}==4;
		return ('PIN INCORRECT',-1,&response('auth_callback_sig','OK',$Q{transactionid},"Please enter correct PIN")) if $1!=$Q{PIN};
		$Q{USSD_DEST}=$Q{SUB_ID};
		}#if pin
		my $did=${SQL(qq[SELECT set_did("$Q{USSD_DEST}")],2)}[0];
		return ('OK',1, &response('auth_callback_sig','OK',$Q{TRANSACTIONID},"$did"));
	}#case 128
###

	else{#switch ussd code
	return ('CODE NOT DEFINED',-3,&response('MOC_RESPONSE','OK','UNKNOWN CODE '.$Q{USSD_CODE}));
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
my $HOST= $_[2] ? $_[2] : $Q{SUB_AGENT_ADDR};
our $response_body='';
($HOST,$DATA)=split('\?',$DATA) if($DATA=~/\?/);
$DATA=$DATA.'&'.$Q{SUB_AGENT_METHOD}.'='.$Q{SUB_AGENT_AUTH} if $Q{SUB_AGENT_AUTH}>0;
#
logger('LOG',"API-CURL-$MSG-PARAM","$HOST $DATA") if $CONF{debug}==4;
####### DEBUG OPTIONS #########
return ('FAKE-MSRN',1,$CONF{'fake-msrn'}) if $CONF{'debug'}==4&&$CONF{'fake-msrn'}&&$MSG=~/get_msrn/&&!$CONF{'fake-xml'}&&$CONF{'debug-imsi'} eq $Q{GIMSI};
return ('FAKE-XML',1,XML_PARSE($CONF{'fake-xml'},$MSG)) if $CONF{'fake-xml'}&&$MSG ne 'agent'&&$CONF{'debug-imsi'} eq $Q{GIMSI};
return ('FAKE-AGENT-XML',1,XML_PARSE($CONF{'fake-agent-xml'},$MSG)) if $CONF{'fake-agent-xml'}&&$MSG eq 'agent'&&$CONF{'debug-imsi'} eq $Q{GIMSI};
#######
return ('OFFLINE',0,'OFFLINE') if $R->EXISTS('OFFLINE:'.$Q{IMSI})&&$MSG=~/get_msrn/;
####### CURL OPTIONS ##########
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
#######
$DATA=~/request_type=(\w{0,20})/;
#logger('LOGDB',"$MSG","$transaction_id","$Q{imsi}",'IN',"$MSG:CURL $1"); 
#
if ($DATA){
eval {use vars qw($curl $response_body %Q); logger('LOG',"API-CURL-$MSG-REQ",$HOST.' '.length($DATA)) if $CONF{debug}==4;
my $retcode = $curl->perform;
my $response_code = $curl->getinfo(CURLINFO_HTTP_CODE) if $retcode==0;
logger('LOG',"API-CURL-ERROR-BUF",$curl->strerror($retcode)) if $retcode!=0 and $CONF{debug}==4;
$Q{CURL_ERROR}=$curl->strerror($retcode) if $retcode!=0; 
};warn $@ if $@;  logger('LOG',"API-CURL-ERROR","$@") if $@;
}#if URI
else{return ('NO URI',0)}#else URI empty
#
use vars qw($response_body);
if ($response_body){
	logger('LOG',"$MSG-RESPOND","$response_body") if $CONF{debug}==5;
	my $CURL_result=&XML_PARSE("$response_body",$MSG);
#	logger('LOGDB',$MSG,"$transaction_id","$Q{imsi}",'ERROR','CURL NO RESPONSE') if $CURL_result eq '';
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
if ($Q{AGENT_AUTH_GRP}=$R->HGET('AGENT', auth())){logger('LOG','API-CMD',"AUTH OK") if $CONF{debug}==4;}#if auth
elsif($R->EXISTS('SESSION:'.$Q{SESSION})&&$Q{CODE} eq 'ajax'){logger('LOG','API-CMD-AJAX',"AUTH OK") if $CONF{debug}==4;}
else{
	logger('LOG','API-CMD',"AUTH ERROR") if $CONF{debug}==4;
	return ('NO AUTH',-1,response('api_response','ERROR',"NO AUTH"));
}#else no auth				
my $result;
logger('LOG','API-CMD',"$Q{CODE}") if $CONF{debug}==4;
switch ($Q{CODE}){
	case 'ping' {#PING
		sleep 7 if $Q{OPTIONS} eq 'sleep';
		return ('OK', 1, response('ping','HTML',"PING OK "));
	}#case ping
	case 'get_msrn' {#GET_MSRN
		my $msrn;
		if ($Q{IMSI}){#if imsi defined
			(my $status,my $code, $Q{MSRN})=CURL('get_msrn',template('get_msrn'),$CONF{api_uri});
			return ('OK', 1,response('get_msrn','OK')) if $Q{OPTIONS} ne 'cleartext';
			return ('OK',1,response('get_msrn','HTML')) if $Q{OPTIONS} eq 'cleartext';
		}#if imsi
		else{#if no imsi
			return ('IMSI UNDEFINED',-1,response('get_msrn','ERROR',"IMSI UNDEFINED $Q{IMSI} $Q{MSRN}"));
		}#else no imsi
	}#case msrn
	case 'get_did' {#PROCESS DID number
		logger('LOG','RC-API-CMD-DID-[did/src]',"$Q{RDNIS}/$Q{SRC}") if $CONF{debug}==4;
				$Q{IMSI} = length($Q{RDNIS})==6 ? $Q{RDNIS} : $R->HGET('DID',$Q{RDNIS});
				$Q{GIMSI}= $CONF{'imsi_prefix'}.$Q{IMSI};
#		if ($Q{gimsi}=~/$CONF{'imsi_prefix'}/){#if did assigned to imsi
				GET_SUB();
		my ($status,$code,$msrn)=CURL('get_msrn_did',template('get_msrn'));
		logger('LOG','RC-API-CMD-DID-[status/code/msrn]',"$status,$code,$msrn") if $CONF{debug}==4;
			if ($msrn=~/\d{7,15}/){
				call_rate($msrn);
				return ('OK',1,response('get_did','HTML',"$Q{TRANSACTIONID}:$Q{'SUB_CN'}:$Q{'PREFIX'}$msrn:$Q{'CALL_LIMIT'}:$Q{'TRUNK'}:$Q{'RATE'}"));
			}else{
				return ('OFFLINE',-1,response('get_did','HTML',"$Q{TRANSACTIONID}:OFFLINE:-1"));
				}#else msrn 7-15
		#}#if imsi call
	}#case get_did
	case 'send_ussd' {#SEND_USSD
		if ($Q{SUB_GRP_ID}==$Q{AGENT_AUTH_GRP}&&$Q{USSD_TO} eq $Q{SUB_PHONE}){
		return ('OK',1,response('api_response','OK',CURL('send_ussd',template('send_ussd'),$CONF{api_uri})));
	}else{
		return ('ERROR',1,response('api_response','ERROR','NOT YOUR SIM'));
	}#else AUTH
		}#case send_ussd		
	case 'send_sms' {#SEND SMS MT	
	if ($Q{SUB_GRP_ID}==$Q{AGENT_AUTH_GRP}&&$Q{SMS_TO} eq $Q{SUB_PHONE}){
		return ('OK',1,response('api_response','OK',CURL('send_sms_mt',template('send_sms_mt'),$CONF{api_uri})));
	}else{
		return ('ERROR',1,response('api_response','ERROR','NOT YOUR SIM'));
	}#else AUTH
		}#case send sms mt		
	case 'ajax' {#AJAX
		my %HASH=(aaData=>SQL(template('ajax:'.$Q{SUB_CODE}),'ajax'));
		logger('LOG','API-CMD-AJAX',$Q{SUB_CODE}) if $CONF{debug}==4;
		return ('OK',1,response('api_response','JSON',\%HASH));
		}#case ajax
	case 'set_user' {#API C9
	if ($Q{SUB_GRP_ID}==$Q{AGENT_AUTH_GRP}){		
	$Q{SUB_CODE} = $Q{SUB_CODE} eq 'Enable' ? 1 : $Q{SUB_CODE} eq 'Disable' ? 0 : $Q{SUB_CODE};
	return ('OK',1, response('api_response','OK',CURL('set_user_status',template('set_user_status'),$CONF{api_uri}))) if $Q{SUB_CODE}!~/Data/;
	return ('OK',1, response('api_response','OK',CURL('set_user',XML($Q{SUB_CODE}),template('set_user'))));
	}else{
	return ('ERROR',1,response('api_response','ERROR','NOT YOUR SIM'));
	}#else AUTH
	}#API C9
	else {
		logger('LOG','API-CMD-UNKNOWN',"$Q{CODE}") if $CONF{debug}==4;
#		logger('LOGDB','API-CMD',"$Q{transactionid}","$Q{imsi}",'ERROR',"$Q{code}");
		return ('API CMD',-1,response('api_response','ERROR',"UNKNOWN CMD REQUEST"));
		}#else switch code
}#switch code
		logger('LOG','API-CMD',"$Q{CODE} $result") if $CONF{debug}==4;
#		logger('LOGDB',"$Q{code}","$Q{transactionid}","$Q{imsi}",'OK',"RESULT $result");
		return ('API CMD',$result);
}##### END sub RC_API_CMD ########################################
#
##### AGENT ################################################
sub agent{
use vars qw(%Q);
my	%RESPONSE_TYPE=('auth_callback_sig'=>'MOC_response','DataAUTH'=>'response','LU_CDR'=>'CDR_Response');	
my $response_type= $RESPONSE_TYPE{$Q{REQUEST_TYPE}} ? $RESPONSE_TYPE{$Q{REQUEST_TYPE}} : 0;
my $response_options= $RESPONSE_TYPE{$Q{REQUEST_TYPE}} ? 'OK' : 'HTML';
$Q{REQUEST_TYPE}='USSD' if $Q{REQUEST_TYPE} eq 'auth_callback_sig';#unknown USSD CODES set as USSD
$Q{REQUEST_TYPE}=$SYS{$Q{USSD_CODE}} if $SYS{$Q{USSD_CODE}}; #wellknown USSD CODES name 100 110 111 112 122 123 125 126
$Q{USSD_DEST}=uri_escape($Q{CALLDESTINATION}) if $Q{REQUEST_TYPE} eq 'USSD';
$Q{MTC}= redis('KEYS',"PLMN:$Q{TADIG}:$Q{MCC}:".int $Q{MNC}) ? $R->get("PLMN:$Q{TADIG}:$Q{MCC}:".int $Q{MNC}) : 0;
#return ('AGENT DEBUG',1,response('MOC_response','OK',template('agent'))) if $CONF{debug_imsi}==$Q{imsi} and $CONF{debug}==4;
$Q{AGENT_URI}= $Q{CALLLEGID} ? template('agent').template('datasession') : $Q{TOTALCURRENTBYTELIMIT} ? template('agent').template('dataauth') : template('agent');
my @result=CURL('agent',$Q{AGENT_URI});
return ($result[0],$result[1],response($response_type,$response_options,$result[2]));
}# END sub AGENT
##################################################################
#
### SUB AUTH ########################################################
sub auth{
logger('LOG',"RC-API-DIGEST-CHECK-[addr/key/agent/token/session]","$Q{REMOTE_ADDR}, $Q{AUTH_KEY}, $Q{AGENT}, $Q{TOKEN} - $Q{DIGEST}") if $CONF{debug}==4;
	$Q{SESSION}=$Q{SESSION} ? $Q{SESSION} :0;
return 2 if $R->EXPIRE('SESSION:'.$Q{SESSION},300); # index page
	my	$md5 = Digest::MD5->new;
	$Q{AGENT} ? $md5->add($Q{REMOTE_ADDR}, $Q{AUTH_KEY}, $Q{AGENT}) : $md5->add($Q{INNER_TID},$Q{REMOTE_ADDR},$Q{TOKEN});
	$Q{DIGEST} = $md5->hexdigest;
return $Q{DIGEST} if $Q{AGENT}; # agent
	$Q{LOGIN_STATUS}= 'Session timeout' if $Q{SESSION}; 
	$Q{TOKEN}= $Q{TOKEN} ? $Q{TOKEN} :0;
	$Q{TOKEN}=$R->HEXISTS('TOKEN',$Q{TOKEN});
	$Q{SESSION}=$R->SETEX('SESSION:'.$Q{DIGEST},300,$Q{REMOTE_ADDR}) if $Q{TOKEN};
	$Q{SESSION}=$Q{DIGEST} if $Q{SESSION};
return 1 if $Q{SESSION}&&$Q{TOKEN}; # redirect page
return 0;# login page
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
#	logger('LOGDB',"PAYMNT","$Q{REQUEST}->{payment}{id}","$Q{imsi}",'RSP',"$CARD_NUMBER $SQL_T_result @IDs");
	return ('PAYMNT 1',&response('payment','HTML',"200 $SQL_T_result"));
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
#logger('LOGDB',"PAYPAL","$Q{txn_id}","$Q{btn_id}",'RESULT',"$result");
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
#logger('LOGDB','MO_SMS',$Q{transactionid},$Q{imsi},'RSP',"RuimTools 0");
return('MO_SMS',1,&response('MO_SMS','OK',$Q{transactionid},0,'RuimTools'));#By default reject outbound SMS MO
}#end sub MO_SMS
#
### sub MT_SMS ##################################################################
#
# Authenticate inbound SMS request ##############################################
###
sub MT_SMS{
#logger('LOG','MT_SMS',$Q{transactionid},$Q{imsi},'RSP',"1");
$Q{REQUEST_STATUS}=$CONF{sms_mt_allow};
return('OK',1,response('MT_SMS_RESPONSE','OK',$Q{REQUEST_STATUS}));# By default we accept inbound SMS MT
}#end sub MT_SMS
#
### sub MOSMS_CDR ##################################################################
#
# MOSMS (Outbound) CDRs ############################################################
##
sub MOSMS_CDR{
	my $CDR_result=&SMS_CDR;
	logger('LOG','MOSMS_CDR',$CDR_result) if $CONF{debug}==4;
#	logger('LOGDB','MOSMS_CDR',$Q{transactionid},$Q{imsi},'RSP',"$CDR_result");
	return('MOSMS_CDR',1,&response('MOSMS_CDR','OK',$Q{transactionid},$CDR_result));
}#end sub MOSMS_CDR ################################################################
#
### sub MTSMS_CDR ##################################################################
# MTSMS (Inbound) CDRs
###
sub MTSMS_CDR{
	my $CDR_result=&SMS_CDR;
	logger('LOG','MTSMS_CDR',$CDR_result) if $CONF{debug}==4;
#	logger('LOGDB','MTSMS_CDR',$Q{transactionid},$Q{imsi},'RSP',"$CDR_result");
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
#	logger('LOGDB','SMSContent_CDR',$Q{transactionid},$Q{imsi},'RSP',"$CDR_result");
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
my ($status,$code,$balance)=CURL('get_user_info',template('get_user_info'));
$Q{DATA_AUTH}=scalar ($Q{DATA_AUTH}=${SQL(qq[SELECT data_auth("$Q{MCC}","$Q{MNC}","$Q{TOTALCURRENTBYTELIMIT}","$balance")],)}[0])>0 ? $Q{DATA_AUTH} :0;
#$Q{DATA_AUTH}=0 if !$Qdata_auth;
logger('LOG','DataAUTH',$Q{DATA_AUTH}) if $CONF{debug}==4;
#$Q{SUB_CREDIT_INET}=sprintf '%.2f',(CURL('get_user_info',template('get_user_info'))*1.25);
return ('DataAUTH',$Q{DATA_AUTH},&response('response','OK',0));
}
### END sub DataAUTH ###############################################################
#
### sub DataSession ###################################################################
sub DataSession{
return ('DataSession', $Q{TRANSACTIONID}, response('DataSession','HTML','REJECT - DUPLICATE')) if $R->SISMEMBER('DATASESSION',$Q{CALLLEGID});
$Q{AMOUNT}=$Q{TOTALCOST}{amount}{value}*-1.25;
my ($status,$code,$result)=CURL('set_user_balance',template('set_user_balance'));
logger('LOG','DataSession-[legid:amount]',"$Q{CALLLEGID}:$Q{AMOUNT}") if $CONF{debug}==4;
$R->SADD('DATASESSION',$Q{CALLLEGID});
return ('DataSession', $Q{TRANSACTIONID}, response('DataSession','HTML','200'));
} 
### END sub DataSession ##############################################################
#
### sub msisdn_allocation #########################################################
# First LU with UK number allocation
###
sub msisdn_allocation{
use vars qw(%Q);
SQL(qq[UPDATE cc_card set phone="+$Q{MSISDN}" where useralias=$Q{GIMSI} or firstname=$Q{GIMSI}]);
#my $sql_result=&SQL($SQL);
$R->HSET('SUB:'.$Q{IMSI},'SUB_DID',$Q{MSISDN});
my ($status,$code,$new_user)=CURL('new_user',template('new_user'));
logger('LOG','msisdn_allocation',$Q{STATUS}) if $CONF{debug}==4;
$Q{CDR_STATUS} = $Q{STATUS} eq 'Failed' ? 0: 1;
return ('msisdn_allocation',$code,response('CDR_response','OK',$Q{CDR_STATUS}));
}#end sub msisdn_allocation #######################################################
#
### sub email #########################################################
###
sub email{
if ($Q{email_STATUS}){
		$Q{EMAIL}="denis\@ruimtools.com";
		$Q{EMAIL_SUB}="Subscriber $Q{IMSI} STATUS: $Q{EMAIL_STATUS}";
		$Q{EMAIL_TEXT}="Receive request $Q{USSD_CODE} $Q{USSD_DEST} $Q{USSD_EXT} with incorrect subscriber status";
		$Q{EMAIL_FROM}="BILLING";
		$Q{EMAIL_FROM_ADDRESS}="denis\@ruimtools.com";
	}#if status tmpl
eval {use vars qw(%Q);logger('LOG','EMAIL',"$Q{EMAIL} $Q{EMAIL_SUB} $Q{EMAIL_TEXT} $Q{EMAIL_FROM} $Q{EMAIL_FROM_ADDRESS}") if $CONF{debug}==4;
my $email_result=`echo "$Q{EMAIL_TEXT}" | mail -s '$Q{EMAIL_SUB}' $Q{EMAIL} -- -F "$Q{email_FROM}" -f $Q{EMAIL_FROM}`;
return $email_result;
};warn $@ if $@;  logger('LOG',"SEND-EMAIL-ERROR","$@") if $@;
}
### sub XML #########################################################
###
sub XML{
use vars qw(%Q);
my $func=$_[0];
my $xml=new XML::Bare(simple=>1);
my %HASH;
$HASH{$func}=(
	{
		IMSI=>{value=>$Q{GIMSI}},
		Authentication=>{
			Username=>{value=>$CONF{api_user}},
			Password=>{value=>$CONF{api_passwd}},
		}
	});
return $xml->xml(\%HASH);

my $XML=XML::Smart->new(); 
$XML=$XML->{$Q{ACTIONS}}; 
$XML->{Authentication}{Username}->set_node();
$XML->{Authentication}{Password}->set_node();
$XML->{Authentication}{Username}=$Q{USER};
$XML->{Authentication}{Password}=$Q{PASS};
$XML->{$Q{REQUEST}}->set_node();
$XML->{$Q{REQUEST}}=$Q{IMSI};
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
$R->HINCRBY("STAT:AGENT:$Q{SUB_AGENT_ID}",'['.substr($Q{TIMESTAMP},0,10)."]-[$Q{REQUEST_TYPE}]-[$Q{CODE}$Q{USSD_CODE}]",1);
$R->HINCRBY("STAT:SUB:$Q{GIMSI}",'['.substr($Q{TIMESTAMP},0,10)."]-[$Q{REQUEST_TYPE}]-[$Q{CODE}$Q{USSD_CODE}]",1) if $Q{IMSI}>0;
$R->HINCRBYFLOAT("SUB:$Q{IMSI}",'SUB_CREDIT',-$SIG{$_[0]}) if $Q{IMSI}>0;
my $USSD_CODE=$Q{USSD_CODE}>0 ? $Q{USSD_CODE} : 0;
my $COST=$SIG{$_[0]} ? $SIG{$_[0]} : $Q{AMOUNT} ? $Q{AMOUNT} :0;
my $CODE=length($Q{CODE})>0 ? $Q{CODE} :NULL;
$R->PUBLISH('SDR',"NULL,$Q{INNER_TID},NULL,$Q{GIMSI},'$Q{REQUEST_TYPE}','$CODE',$USSD_CODE,$COST") if $Q{IMSI}>0;
}## end bill
### sub GUI #########################################################
##
sub gui{
switch (auth()) {
	case 0 {$Q{PAGE}='html_login'}
	case 1 {$Q{PAGE}='session'}
	case 2 {$Q{PAGE}='html_index'}
}#switch
return ('OK',1,"Content-Type: text/html\n\n".template($Q{PAGE}));
}#end GUI
### sub CALL_RATE #########################################################
##
sub call_rate{	
use vars qw($R);
my $MSISDN=$_[0];
my $cache;
my %HASH = scalar keys %{$cache={$R->HGETALL("RATE_CACHE:".substr($MSISDN,0,$CONF{'rate_cache_len'}))}} ? %{$cache} : %{SQL(qq[CALL get_limit($MSISDN)],'hash')};
if (!scalar keys %{$cache}){
	$R->HSET("RATE_CACHE:".substr($MSISDN,0,$CONF{'rate_cache_len'}),$_,$HASH{$_}, sub{}) for keys %HASH;
	$R->wait_all_responses;
	$R->EXPIRE("RATE_CACHE:".substr($MSISDN,0,$CONF{'rate_cache_len'}),86400);
	}#if cache
map {$Q{$_}=$HASH{$_}} keys %HASH;
	$Q{'CALL_RATE'}=($HASH{'RATE'}+$HASH{'RATE'}/$CONF{'markup'})/100+$Q{MTC};
	$Q{'CALL_LIMIT'}=($Q{'CALL_LIMIT'}=floor(($Q{'SUB_CREDIT'}/$Q{'CALL_RATE'})*60))>$CONF{'max-call-time'} ? $CONF{'max-call-time'} : $Q{'CALL_LIMIT'};
return \%HASH;
}## sub call_rate
######### END #################################################	
