#!/usr/bin/perl
#/usr/bin/perl
#/opt/local/bin/perl -T
#
########## VERSION AND REVISION ################################
## Copyright (C) 2012, RuimTools denis@ruimtools.com
##
my $rev='MSRN.ME 310713-rev.74.3';
##
#################################################################
## 
########## MODULES ##############################################
use FCGI;
use FCGI::ProcManager qw(pm_manage pm_pre_dispatch pm_post_dispatch);
use WWW::Curl::Easy;
use Redis;
use DBI;
use Data::Dumper;
use IO::Socket;
use XML::Bare;
use JSON::XS;
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
########## CONFIG STRINGS #######################################
my $R0 = Redis->new;
$R0->hset('CONF','rev',unpack('H*',$rev));
my %CONF=$R0->HGETALL('CONF');
map {$CONF{$_}=pack('H*',$CONF{$_})} keys %CONF;
my %SYS=$R0->HGETALL('STATUS');
my %SIG=$R0->HGETALL('SIG');
$R0->quit;
####### FORK ####################################
our $pid = fork;
exit if $pid;
die "Couldn't fork: $!" unless defined($pid);
POSIX::setsid() or die "Can't start a new session: $!";
my $PIDFILE = new IO::File;
$PIDFILE->open(">$CONF{pidfile}");# change to programm path (!)
print $PIDFILE $$;
$PIDFILE->close();
chdir "$CONF{rundir}" or die "Can't chdir: $!";
#POSIX::setuid(501) or die "Can't set uid: $!";
print "$CONF{rev} Ready at $$ debug level $CONF{debug} becklog $CONF{fcgi_backlog} processes $CONF{fcgi_processes}\n";
#####################################################################
#50/20 - 10k 19.289372 seconds 518.42 [#/sec] 38.579 [s] / 1.929 [ms]
#10/10 - 10k 18.939499 seconds 528.00 [#/sec] 18.939 [s] / 1.894 [ms]
#5/2	-10k 24.699049 seconds 404.87 [#/sec]  4.940 [s] / 2.470 [ms]			
########## OPEN SOCKET ##############################################
my $sock = FCGI::OpenSocket("$CONF{host}:$CONF{port}",$CONF{fcgi_backlog});
	my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV, $sock);
	    pm_manage(n_processes => $CONF{fcgi_processes});
	    		our $dbh = DBI->connect('DBI:mysql:msrn',$CONF{db_user},$CONF{db_pass});
	    		our $R = Redis->new(server => 'localhost:6379',encoding => undef,);
	    		my $t0; my %Q;
 		reopen_std();
########## ACCEPT CONNECTIONS ###################################
while ( $request->Accept() >= 0){
pm_pre_dispatch();
	%CONF=();%SIG=();%Q=();
	%SIG=$R->HGETALL('SIG');
	%CONF=$R->HGETALL('CONF');
	map {$CONF{$_}=pack('H*',$CONF{$_})} keys %CONF;
	my ($s, $usec) = gettimeofday();my $format = "%06d";$usec=sprintf($format,$usec);$Q{INNER_TID}=$s.$usec;$Q{TID}=int(rand(1000000));
	my $env = $request->GetEnvironment();
	$t0=Benchmark->new;
		$Q{REQUEST}= $env->{REQUEST_METHOD} eq 'POST' ? <STDIN> : $env->{QUERY_STRING};
			$Q{REMOTE_ADDR}=$env->{REMOTE_ADDR};
			$Q{HTTP_USER_AGENT}=$env->{HTTP_USER_AGENT};
			$Q{REQUEST_TYPE}='GUI' if $Q{REQUEST}!~m/request_type|api_cmd|datasession/ig;
				print main();
			my $t2=Benchmark->new;
			my $td0 = timediff($t2, $t0);	
		$R->PUBLISH('TIMER',substr($td0->[0],0,8));
		logger('RDB','LOG') if $CONF{debug}>0;
pm_post_dispatch();
	    		  }#while
sub reopen_std {   
    open(STDIN,  "+>/dev/null") or die "Can't open STDIN: $!";
    open(STDOUT, "+>&STDIN") or die "Can't open STDOUT: $!";
    open(STDERR, "+>&STDIN") or die "Can't open STDERR: $!";
};#while Accept
########## MAIN #################################################
sub main{
use vars qw(%Q $dbh $R);
	if (XML_PARSE($Q{REQUEST},'xml')>0){#if not empty set
		my $head=$Q{REQUEST_TYPE};
		($Q{USSD_CODE},$Q{USSD_DEST},$Q{USSD_EXT})=uri_unescape($Q{CALLDESTINATION})=~/^\*(\d{3})[\*|\#](\D{0,}\d{0,}).?(.{0,}).?/ if $Q{CALLDESTINATION};
#		($Q{USSD_CODE},$Q{USSD_DEST},$Q{USSD_EXT})=($1,$3,$4);
		$Q{IMSI}=$Q{IMSI} ? substr($Q{IMSI},-6,6) :0;
		$Q{GIMSI}=$CONF{imsi_prefix}.$Q{IMSI};
		$Q{TIMESTAMP}=strftime("%Y-%m-%d %H:%M:%S", localtime);
		$Q{BILL_TYPE}=$Q{CODE} ? $Q{CODE} :$Q{REQUEST_TYPE};
		$head=$Q{USSD_CODE} if $Q{CALLDESTINATION};
		$Q{REQUEST_TYPE}="payment" if $Q{SALT};
		$Q{TRANSACTIONID}=$Q{CDR_ID} if $Q{REQUEST_TYPE} eq 'msisdn_allocation';
		$Q{TRANSACTIONID}=$Q{SESSIONID} if $Q{SESSIONID};#DATA
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
my $ACTION_TYPE = $Q{REQUEST_TYPE}=~/API_CMD/ ? uc $Q{REQUEST_TYPE} : $R->HEXISTS('AGENT:'.$Q{SUB_HASH},'host') ? 'AGENT' : uc $Q{REQUEST_TYPE};
logger('LOG',"MAIN-ACTION-TYPE",$ACTION_TYPE);
	eval {our $subref=\&$ACTION_TYPE;};warn $@ if $@;  
logger('LOG',"MAIN-ACTION-SUBREF","ERROR $ACTION_TYPE $@") if $@;
return &response('ERROR','DEFAULT','SORRY NO RESULT #'.__LINE__) if $@;
##################################################################
use vars qw($subref);
#
########### USSD DIRECT CALL ###########
if (!$Q{USSD_CODE} && $Q{REQUEST_TYPE} eq 'auth_callback_sig'){
uri_unescape($Q{CALLDESTINATION})=~/^\*(\+|00)?(\d{7,14})\#/;
$Q{USSD_DEST}=$2;
$Q{USSD_CODE}=112; 
}#if USSD DIRECT CALL
########################################
our ($ACTION_STATUS,$ACTION_CODE,$ACTION_RESULT,%LOG);
		logger('LOGDB',"$ACTION_TYPE",0,'IN',$IN_SET);
	$R->HINCRBY("STAT:AGENT:$Q{SUB_HASH}",'['.substr($Q{TIMESTAMP},0,10)."]-[$Q{REQUEST_TYPE}]-[$Q{CODE}$Q{USSD_CODE}]",1);
	$R->HINCRBY("STAT:SUB:$Q{GIMSI}",'['.substr($Q{TIMESTAMP},0,10)."]-[$Q{REQUEST_TYPE}]-[$Q{CODE}$Q{USSD_CODE}]",1) if $Q{IMSI}>0;
eval {	($ACTION_STATUS,$ACTION_CODE,$ACTION_RESULT)=&$subref();
			};warn $@ if $@;  logger('LOG',"MAIN-ACTION-SUBREF","ERROR $ACTION_TYPE $@") if $@;
			return &response('ERROR','ERROR','GENERAL ERROR #'.__LINE__) if $@;
		logger('LOG',"MAIN-ACTION-RESULT-$ACTION_TYPE","$ACTION_STATUS $ACTION_CODE". substr($ACTION_RESULT,0,10)) if $CONF{debug}>3;
		logger('LOG',"MAIN-ACTION-RESULT-$ACTION_TYPE","$ACTION_STATUS $ACTION_CODE") if $CONF{debug}<=3;
		logger('LOGDB',"$ACTION_TYPE",0,"$ACTION_STATUS","$ACTION_CODE");
		BILL($Q{BILL_TYPE}) if $ACTION_CODE>0;
		return "$ACTION_RESULT" if $ACTION_STATUS;
		return &response('ERROR','DEFAULT','SORRY NO RESULT #'.__LINE__) if !$ACTION_STATUS;
}#if keys
else{#else if keys
	return GUI();
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
($Q{REQUEST_LINE},$Q{REQUEST_OPTION})=@_;
$Q{REQUEST_LINE}=~s/\r|\n|\t|\+//g;
#
logger('LOG',"PARSE-REQUEST-LINE",$Q{REQUEST_LINE}) if $CONF{debug}>2;

if ($Q{REQUEST_LINE}=~m/xml version/){#XML REQUEST
eval {
	my $xml=new XML::Bare(text=>$Q{REQUEST_LINE});
	$Q{REQUEST}=$xml->parse();
		};warn $@ if $@;  logger('LOG',"XML-PARSE-REQUEST","ERROR $@") if $@; $Q{ERROR_NUMBER}='error:238' if $@;	
	return 0 if ( ref $Q{REQUEST} ne 'HASH');
	map {$Q{REQUEST}=$Q{REQUEST}->{$_} if $_=~/wire9|api|data|response|error/i} keys $Q{REQUEST};
	map {$Q{REQUEST}->{uc $_}=$Q{REQUEST}->{$_};} keys $Q{REQUEST};#switch root keys to UPPERCASE
}#if xml
else{#CGI REQUEST
	logger('LOG',"CGI-PARSE-REQUEST",$Q{REQUEST_LINE}) if $CONF{debug}>1;
		return 0 if $Q{REQUEST_LINE} eq '';
		$Q{REQUEST_LINE}=~tr/\&/\;/;
		my %Q_tmp=split /[;=]/,$Q{REQUEST_LINE}; 
		map {$Q{uc $_}=uri_unescape($Q_tmp{$_})} keys %Q_tmp;
		if ($Q{MCC}){eval {$Q{MTC}=${SQL(qq[CALL get_mtc("$Q{TADIG}",$Q{MCC},$Q{MNC})],'array')}[0]}; warn $@ if $@;  logger('LOG',"CGI-PARSE-REQUEST","ERROR $@") if $@}
		return scalar keys %Q;
}#else cgi
#
switch ($Q{REQUEST_OPTION}){
	case 'xml' {
		if(ref $Q{REQUEST}->{API_CMD} eq 'HASH'&& ref $Q{REQUEST}->{API_AUTH} eq 'HASH'){
		logger('LOG',"XML-PARSE-KEYS", join(',',sort keys $Q{REQUEST}->{API_CMD})) if $CONF{debug}>2;
	map {$Q{uc $_}=$Q{REQUEST}->{API_CMD}{$_}{value} if $_!~/^_(i|z|pos)$/i;} keys $Q{REQUEST}->{API_CMD};
	map {$Q{uc $_}=$Q{REQUEST}->{API_AUTH}{$_}{value} if $_!~/^_(i|z|pos)$/i;} keys $Q{REQUEST}->{API_AUTH};
		$Q{REQUEST_TYPE}='API_CMD';
		return scalar keys %Q;
		}
##if request in 'payments' format		
#		elsif($Q{REQUEST}->{payment}){
#			logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}",'PAYMENTS') if $CONF{debug}==4;;
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
		elsif($Q{REQUEST}->{REFERENCE}{value} eq 'Data'){
		logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}",'datasession') if $CONF{debug}>2;
	map {$Q{uc $_}=$Q{REQUEST}->{$_} if $_!~/^_(i|z|pos)$/} keys $Q{REQUEST};
	map {$Q{uc $_}=$Q{REQUEST}->{callleg}{$_}{value} if $_!~/^_(i|z|pos)$/} keys $Q{REQUEST}->{CALLLEG};
		$Q{REQUEST_TYPE}='DataSession';
		$Q{TRANSACTIONID}=$Q{CALLLEGID};
		$Q{COST}=$Q{TOTALCOST}{amount}{value};
		$Q{CURRENCY}=$Q{TOTALCOST}{currency}{value};
		$Q{IMSI} = scalar ($Q{IMSI}=$R->HGET('DID',$Q{NUMBER}))>0 ? $CONF{imsi_prefix}.$Q{IMSI} :0;
	return scalar keys %Q;
		}#elsif postdata
		else{#unknown format
		$Q{ERROR_NUMBER}='error:238';
			logger('LOG',"XML-PARSE-ERROR-$Q{REQUEST_OPTION}",$Q{ERROR_NUMBER}) if $CONF{debug}>2;
	return 0;
		}#else unknown
	}#xml
	case /get_msrn/ {
		map {$Q{uc $_}=$Q{REQUEST}->{MSRN_Response}{$_}{value} if $_!~/^_?(i|z|pos|imsi|value)$/i} keys $Q{REQUEST}->{MSRN_Response};
		$Q{ERROR}=$Q{REQUEST}->{Error_Message} ? $Q{REQUEST}->{Error_Message}{value} : 0;
		if ($Q{MCC}){eval {$Q{MTC}=${SQL(qq[CALL get_mtc("$Q{TADIG}",$Q{MCC},$Q{MNC})],'array')}[0]};warn $@ if $@;  logger('LOG',"CGI-PARSE-REQUEST","ERROR $@") if $@;}
#$Q{MTC}= scalar @{$R->KEYS('PLMN:'.$Q{TADIG}.':*')} ? $R->GET($R->KEYS('PLMN:'.$Q{TADIG}.':*') ) : scalar @{$R->KEYS('PLMN:*:'.$Q{MCC}.':'.int $Q{MNC})} ? $R->GET($R->KEYS('PLMN:*:'.$Q{MCC}.':'.int $Q{MNC}) ) : 0;
		$Q{MSRN}=~/\d{7,15}/ ? $R->SETEX('MSRN_CACHE:'.$Q{IMSI},60,$Q{MSRN}) : $R->SETEX('MSRN_CACHE:'.$Q{IMSI},300,'OFFLINE');
		logger('LOG',"XML-PARSED-$Q{REQUEST_OPTION}","$Q{MSRN} $Q{MCC} $Q{MNC} $Q{TADIG} $Q{MTC} $Q{ERROR}") if $CONF{debug}>3;
		return $Q{MSRN};
	}#msrn
	case 'send_ussd' {
		$Q{STATUS}=$Q{REQUEST}->{USSD_Response}{REQUEST_STATUS}{value};
		$Q{ERROR}=$Q{REQUEST}->{Error_Message}{value};
		logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}","$Q{STATUS} $Q{ERROR}") if $CONF{debug}>2;
		return "$Q{STATUS}$Q{ERROR}";
	}#ussd
#	case /sms_m/ {
#		my $SMS=$Q{REQUEST}->{SMS_Response}{REQUEST_STATUS}{value};
#		our $ERROR=$Q{REQUEST}->{Error_Message}{value};
#		logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}","$SMS $ERROR") if $CONF{debug}==4;
#		return "$ERROR$SMS";
#	}#sms
	case /send_sms_m/ {
		$Q{STATUS}=$Q{REQUEST}->{SMS_Response}{REQUEST_STATUS}{value};
		$Q{ERROR}=$Q{REQUEST}->{Error_Message}{value};
		logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}","$Q{STATUS} $Q{ERROR}") if $CONF{debug}>2;
		return "$Q{STATUS}$Q{ERROR}";
	}#sms
	case /AGENT/ {#AGENT
		$Q{RESULT}=$Q{REQUEST}->{RESPONSE}{value};
		$Q{ERROR}=$Q{REQUEST}->{ERROR_MESSAGE}{value};
		logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}","$Q{RESULT} $Q{ERROR}") if $CONF{debug}>2;
		return "$Q{RESULT}$Q{ERROR}";
	}#AGENT
	case 'get_session_time' {
		my $TIME=$Q{REQUEST}->{RESPONSE}{value};
		our $ERROR=$Q{REQUEST}->{Error_Message}{value};
		logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}","$TIME $ERROR") if $CONF{debug}>2;
		return "$ERROR$TIME";
	}#get time
	case 'voip_user_info' {
		my $BALANCE=$Q{REQUEST}{GetUserInfo}->{Balance}{value};
		our $ERROR=$Q{REQUEST}{GetUserInfo}->{Reason}{value};
		logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}","$BALANCE $ERROR") if $CONF{debug}>2;
		return "$ERROR$BALANCE";
	}#get user info
	case 'set_user_balance' {
		my $BALANCE=$Q{REQUEST}->{Result}{value};
		our $ERROR=$Q{REQUEST}->{Reason}{value};
		logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}","$BALANCE $ERROR") if $CONF{debug}>2;
		return "$ERROR$BALANCE";
	}#set user balance
	case 'voip_user_new' {
		$Q{STATUS}= ref $Q{REQUEST}->{CreateAccount}{Result} eq 'ARRAY' ? $Q{REQUEST}->{CreateAccount}{Result}[0]{value} : $Q{REQUEST}->{CreateAccount}{Result}{value};
		my $ERROR= ref $Q{REQUEST}->{CreateAccount}{Reason} eq 'ARRAY' ? $Q{REQUEST}->{CreateAccount}{Reason}[1]{value} : $Q{REQUEST}->{CreateAccount}{Reason}{value};
		logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}","$Q{STATUS} $ERROR") if $CONF{debug}>2;
		return "$Q{STATUS}$ERROR";
	}#new user
	case /siminfo/i {
		$Q{PIN}=$Q{REQUEST}->{Sim}{Password}{value};
		our $ERROR=$Q{REQUEST}->{Error}{value};
		logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}","$Q{PIN} $ERROR") if $CONF{debug}>2;
		return "$Q{PIN}$ERROR";
	}#sim info	
	case 'set_user' {
		 $Q{STATUS}=$Q{REQUEST}->{status}{value};
		 $Q{ERROR}=$Q{REQUEST}->{error}{value};
		logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}","$Q{STATUS} $Q{ERROR}") if $CONF{debug}>2;
		return "$Q{STATUS}$Q{ERROR}";
	}#set user
	case 'set_user_status' {
		$Q{STATUS}=$Q{REQUEST}->{STATUS_Response}{IMSI_STATUS}{value};
		$Q{ERROR}=$Q{REQUEST}->{Error_Message} ? $Q{REQUEST}->{Error_Message}{value} : undef;
		logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}","$Q{STATUS} $Q{ERROR}") if $CONF{debug}>2;
		return "$Q{STATUS}$Q{ERROR}";
	}#set userstatus
	else {
		print logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}",'NO OPTION FOUND $@') if $CONF{debug}>1;
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
$dbh=DBI->connect('DBI:mysql:msrn',$CONF{db_user},$CONF{db_pass}) if $dbh->ping==0;
#
if($SQL!~m/^[SELECT|CALL]/i){#INSERT/UPDATE request
logger('LOG','SQL-MYSQL-GET',"DO $SQL") if $CONF{debug}==5;
	$rc=$dbh->do($SQL);#result code
	push @result,$rc;#result array
	$new_id = $dbh -> {'mysql_insertid'};#autoincrement id
}#if SQL INSERT UPDATE
else{#SELECT request
logger('LOG','SQL-MYSQL-GET',"EXEC $SQL") if $CONF{debug}==5;
	$sth=$dbh->prepare($SQL);
	$rc=$sth->execute;#result code
	@result=$sth->fetchrow_array if $flag eq 'array';
	$result=$sth->fetchrow_hashref if $flag eq 'hash';
	$result=$sth->fetchall_arrayref if $flag eq 'ajax';
}#else SELECT
#
if($rc){#if result code
	logger('LOG','SQL-MYSQL-RETURNED-[code/array/hash/id]',"$rc/@result/$result/$new_id") if $CONF{debug}==5;
	return \@result if $flag eq 'array';
	return  $result if $flag =~/hash|ajax/;
	return @result; 
}#if result code
else{#if no result code
	logger('LOG','SQL-MYSQL-RETURNED','Error: '.$dbh->errstr) if $CONF{debug}>1;
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
use vars qw($t0 $R);
$Q{TRANSACTION_ID}=$Q{TRANSACTIONID};
my ($ACTION_TYPE, $RESPONSE_TYPE, $RESPONSE, $SUB_RESPONSE)=@_;
my $HEAD=qq[Content-Type: text/xml\n\n<?xml version="1.0" ?>];
#
switch ($RESPONSE_TYPE){
	case 'XML'{
		$Q{USSDMESSAGETOHANDSET}=$Q{CDR_STATUS}=$Q{ALLOW}=$Q{DISPLAY_MESSAGE}=$RESPONSE;
		$Q{USSDMESSAGETOHANDSET}=$SUB_RESPONSE if $SUB_RESPONSE;
		my $xml=new XML::Bare(simple=>1);
		my %HASH;
	map { $HASH{uc $ACTION_TYPE}{$_}={value=>$Q{$_}} if defined $Q{$_} } @{$R->SMEMBERS('RESPONSE:'.uc $ACTION_TYPE)};
		return $HEAD.$xml->xml(\%HASH);
	}#case XML
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
use vars qw($t0 %LOG);
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
#	$R->PUBLISH('LOG',$LOG{$Q{INNER_TID}}->{$_}, sub{}) for sort keys $LOG{$Q{INNER_TID}};
#	$R->wait_one_response;
}#redis DB
case 'LOG'{
#	$LOG{$Q{INNER_TID}}->{$timer}=
	$R->PUBLISH('LOG',"[$now]-[$Q{INNER_TID}]-[$timer]-[API-LOG-$RESPONSE_TYPE]:$LOG") if $CONF{debug}>0;
	}#case LOG
case 'LOGDB'{
	$R->PUBLISH('TID',"NULL,NULL,'$RESPONSE_TYPE',$Q{INNER_TID},'$Q{TRANSACTIONID}','$Q{GIMSI}','$STATUS','$INFO','$timer'");
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
			SQL(qq[UPDATE cc_card SET country=CONCAT_WS(' ',(SELECT country from cc_mnc WHERE mcc=$Q{MCC} limit 1),"$Q{TADIG}") WHERE username=$Q{SUB_CN} limit 1]);
			$R->EXPIRE('OFFLINE:'.$Q{IMSI},0);
#			$R->HMSET("SUB:$Q{IMSI}",'SUB_MCC',$Q{MCC},'SUB_MNC',$Q{MNC},'SUB_TADIG',$Q{TADIG});
			$Q{CDR_STATUS}=1;
#			$Q{MTC}= scalar @{$R->KEYS("PLMN:$Q{TADIG}:*")} ? $R->GET($R->keys("PLMN:$Q{TADIG}:*")) : 0;
# Comment due activation proccess
#			if ($UPDATE_result){#if contry change
#			my $msrn=CURL('get_msrn_free',${SQL(qq[SELECT get_uri2('get_msrn',"$Q{imsi}",NULL,NULL,NULL,NULL)],2)}[0]);
#my $TRACK_result=CURL('sms_mt_free',${SQL(qq[SELECT get_uri2('mcc_new',"$Q{imsi}",NULL,"$Q{msisdn}",'ruimtools',"$Q{iot_charge}")],2)}[0]);
	#$TRACK_result=CURL('sms_mt',${SQL(qq[SELECT get_uri2('get_ussd_codes',NULL,NULL,"$Q{msisdn}",'ruimtools',NULL)],2)}[0]);
#				logger('LOG','MAIN-LU-HISTORY-RETURN',"$TRACK_result");
#			}#if country change
			#logger('LOGDB',"LU_CDR","$Q{transactionid}","$Q{imsi}",'OK',"$Q{SUB_ID} $Q{imsi} $Q{msisdn}");
#			logger('LOG','LU-REQUEST-OK',"$Q{imsi} $Q{msisdn} $Q{SUB_ID}") if $CONF{debug}==4;
			return ('OK',"$Q{SUB_ID}:$Q{MCC}:$Q{MNC}:$Q{TADIG}",response('CDR_RESPONSE','XML',1));
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
sub AUTH_CALLBACK_SIG{
use vars qw(%Q);
$R->EXPIRE('OFFLINE:'.$Q{IMSI},0);
my @result;
logger('LOG',"SIG-$Q{USSD_CODE}-REQUEST","$Q{IMSI},$Q{USSD_CODE},$Q{USSD_DEST},$Q{USSD_EXT}") if $CONF{debug}>1;
if(($Q{SUB_STATUS}==1)||($Q{USSD_CODE}=~/^(123|100|000|110|111)$/)){#if subscriber active
	if (($Q{USSD_CODE}=~/112/)&&$Q{USSD_DEST}){@result=SPOOL()}
	else{@result=USSD()}
	return @result;
		}#if subscriber active
	else{#status not 1 or balance request
		logger('LOG','auth_callback_sig-INCORRECT-STATUS',"$Q{SUB_STATUS} #".__LINE__) if $CONF{debug}>1;
#		logger('LOGDB','STATUS',"$Q{transactionid}","$Q{imsi}",'ERROR',"$Q{SUB_STATUS}");
		$Q{EMAIL_STATUS}="$Q{SUB_STATUS} $SYS{$Q{SUB_STATUS}}";
		email();
		return ('OK',1, response('MOC_RESPONSE','XML',"$SYS{$Q{SUB_STATUS}}")) if $SYS{$Q{SUB_STATUS}};
#		return ('INCORRECT STATUS',0, response('LU_CDR','ERROR','#'.__LINE__.' INCORRECT STATUS')) if !$SYS{$Q{SUB_STATUS}};
	}#else status
}## END sub auth_callback_sig
#
########## AUTHORIZATION CALLBACK OutboundAUTH ######################
sub OUTBOUNDAUTH{
	$Q{USSD_DEST}=$Q{DESTINATION};
	$Q{USSDMESSAGETOHANDSET}=TEMPLATE('spool:wait');
	SPOOL();
	return ('OK',1, response('RESPONSE','XML',0,$Q{USSDMESSAGETOHANDSET}));
}#END OutboundAUTH
################################################################# 

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
#	}else{ return ('OFFLINE DEST', -5,response('MOC_RESPONSE','OK',template('spool:dest_offline'))) }#return offline or empty msrn  
#}#if internal call
#	elsif ($Q{USSD_DEST}=~/^(\+|00)?([1-9]\d{7,15})$/){#elsif outbound call destianation
#			logger('LOG','SPOOL-GET-OUTBOUND-CALL',"$Q{USSD_DEST}") if $CONF{debug}==4;
#			$Q{USSD_DEST}=$2;#set dest
#	}#elsif outbound call
#else {#else incorrect dest
#			logger('LOG','SPOOL-GET-INTERNAL-SELF',"$Q{USSD_DEST}") if $CONF{debug}==4 and $Q{imsi} eq $Q{USSD_DEST};
#			return ('CALL SELF',-4,response('MOC_RESPONSE','OK',template('spool:dest_self'))) if $Q{imsi} eq $Q{USSD_DEST};
#$Q{USSD_DEST}=0;
#}#else incorrect dest
#	logger('LOG','SPOOL-GET-DEST',"$Q{USSD_DEST} in $USSD_dest") if $CONF{debug}==4;
#
# PROCESSING CALL
if ($Q{USSD_DEST}=~/^(\+|00)?([1-9]\d{7,15})$/){#if correct destination number - process imsi msrn
#	my	$msrn=$2 if (($Q{USSD_CODE}==128)&&($Q{USSD_EXT}=~/^(\+|00)?([1-9]\d{7,15})#?$/));#local number call
#logger('LOG','SPOOL-LOCAL-NUMBER-CALL',"$msrn $Q{USSD_EXT}") if $msrn and $CONF{debug}==4;
	(my $status,my $code,$Q{MSRN})=CURL('get_msrn',TEMPLATE('get_msrn'),$CONF{api2});
#	my $offline=1 if $msrn} eq 'OFFLINE';
#logger('LOG','SPOOL-GET-MSRN-RESULT',$msrn) if $CONF{debug}==4;
#
if ($Q{MSRN}=~/\d{7,15}/){
## Call SPOOL
foreach my $type ('USSD_DEST','MSRN'){
my %HASH=%{CALL_RATE($Q{$type})};
map {$Q{$type.'_'.uc($_)}=$HASH{$_}} keys %HASH;
}#foreach number
#	$Q{'MTC'}=$Q{MTC}*100;#from $ to c
	$Q{'MSRN_RATE'}=$Q{'MSRN_RATE'}+$Q{'MTC'};#msrn in c + mtc in c= c RATEA
	$Q{'USSD_DEST_RATE'}=ceil($Q{'USSD_DEST_RATE'}*$CONF{'markup_rate'});#rate+markup% RATEB
	$Q{'CALL_RATE'}=($Q{'USSD_DEST_RATE'}+$Q{'MSRN_RATE'})/100;#show user in $
	$Q{'CALL_LIMIT'}=($Q{'CALL_LIMIT'}=floor(($Q{'SUB_CREDIT'}/$Q{'CALL_RATE'})*60))>$CONF{'max-call-time'} ? $CONF{'max-call-time'} : $Q{'CALL_LIMIT'};
##(sub_credit in $ / call_rate in $) * 60 = seconds to call
## if limit > max_call_time set to max_call_time
	$Q{'SUB_CREDIT'}=sprintf '%.2f',$Q{'SUB_CREDIT'};#format $0.2
	$Q{'CALL_RATE'}=sprintf '%.2f',$Q{'CALL_RATE'};#format $0.2
#
logger('LOG','SPOOL-GET-TRUNK-[dest/msrn/prefix/rate/limit]',"$Q{USSD_DEST_TRUNK}/$Q{MSRN_TRUNK}/$Q{'MSRN_PREFIX'}/$Q{CALL_RATE}/$Q{CALL_LIMIT}") if $CONF{debug}>2;
#
	$Q{UNID}=$Q{TID}.'-'.$Q{IMSI};#976967-139868
	$Q{CALLFILE}=$Q{UNID}.'-'.$Q{MSRN};#976967-139868-380507942751
	my $CALL = IO::File->new("$CONF{tmpdir}/".$Q{CALLFILE}, "w");#write to tmp/976967-139868-380507942751
	print $CALL TEMPLATE('spool:call');#filling template
	close $CALL;
chown 100,101,"$CONF{tmpdir}/".$Q{CALLFILE};
#chown 100 0666 ,"$CONF{tmpdir}/".$Q{CALLFILE};
my $mv= $CONF{'fake-call'}==0 ? move("$CONF{'tmpdir'}/".$Q{CALLFILE}, "$CONF{'spooldir'}/".$Q{CALLFILE}) : $CONF{'fake-call'};
#
return ("SPOOL-[move/uniqid/rate] $mv:$Q{UNID}:$Q{CALL_RATE}",$mv,response('MOC_RESPONSE','XML',TEMPLATE('spool:wait')));
	}#if msrn and dest
	else{#else not msrn and dest
		return ('OFFLINE',-2,response('MOC_RESPONSE','XML',TEMPLATE('spool:offline')));
		}#else not msrn and dest
}#if dest
else{
		return ('NO DEST',-3,response('MOC_RESPONSE','XML',TEMPLATE('spool:nodest')));
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
		logger('LOG','USSD-SUPPORT-REQUEST',"$Q{USSD_CODE}") if $CONF{debug}==4;
		$Q{EMAIL}="denis\@ruimtools.com";
		$Q{EMAIL_SUB}="NEW TT: [$Q{IMSI}:$Q{TID}]";
		$Q{EMAIL_TEXT}='USSD-SUPPORT-REQUEST: '.$Q{USSD_DEST};
		$Q{EMAIL_FROM}="SUPPORT";
		$Q{EMAIL_FROM_ADDRESS}="denis\@ruimtools.com";
		email();
		return ('OK',1,response('MOC_RESPONSE','DEFAULT',"SUPPORT TICKET #$Q{TID} REGISTERED"));		
			}#case 000
###
	case "100"{#MYNUMBER request
		logger('LOG','USSD-MYNUMBER-REQUEST',"$Q{USSD_CODE}") if $CONF{debug}==4;
#		$Q{SUB_DID}= scalar ($Q{SUB_DID}=$R->HGET('DID',$Q{GIMSI})) ? $Q{SUB_DID} : $Q{GLOBALMSISDN};
#		$Q{SUB_CREDIT}=sprintf '%.2f',$Q{SUB_CREDIT};
		return ('OK',1,response('MOC_RESPONSE','XML',TEMPLATE("ussd:$Q{USSD_CODE}")));		
	}#case 100
###
	case "110"{#IMEI request
		logger('LOG','USSD-IMEI-REQUEST',"$Q{USSD_DEST}") if $CONF{debug}==4;
		$R->HSET("SUB:$Q{IMSI}",'SUB_HANDSET',"$Q{USSD_DEST} $Q{USSD_EXT}");
		return ('OK',$Q{USSD_DEST},response('MOC_RESPONSE','XML',TEMPLATE("ussd:$Q{USSD_CODE}")));
	}#case 110
###
	case "122"{#SMS request
		logger('LOG','USSD-SMS-REQUEST',"$Q{USSD_CODE} $Q{USSD_DEST}") if $CONF{debug}==4;
		my $SMS_result=SMS();#process sms
		logger('LOG','USSD-SMS-RESULT',"$SMS_result") if $CONF{debug}==4;
		return ('OK',$SMS_result, response('MOC_RESPONSE','XML',TEMPLATE('ussd:'.$Q{USSD_CODE}.$SMS_result)));
	}#case 122
###
	case [111,123,124]{#voucher refill request
		logger('LOG','USSD-BALANCE-REQUEST',"$Q{USSD_CODE}") if $CONF{debug}==4;
		$Q{SUB_CREDIT_INET}=sprintf '%.2f',(CURL('get_user_info',TEMPLATE('voip_user_info'),$CONF{api3})*$CONF{euro_currency});
		$Q{TOPUP}=$R->SREM('VOUCHER',$Q{USSD_DEST}) ? $CONF{voucher_amount} :0;
		$Q{SUB_CREDIT}=$Q{SUB_CREDIT}+$Q{TOPUP};
		return ('OK',$Q{SUB_CREDIT},response('MOC_RESPONSE','XML',TEMPLATE("ussd:111")));
	}#case 111
###
	case "125"{#voip account
	$Q{SUB_PIN} ? return ('OK',1,response('MOC_RESPONSE','DEFAULT','LOGIN:sim'.$Q{SUB_CN}.'*'.$CONF{voip_domain}.' PIN:'.$Q{SUB_PIN}.TEMPLATE('voip_user_help'))) : return ('WARNING',0,response('MOC_RESPONSE','DEFAULT','NEED TO SET NEW PIN. CALL *000*5#'));
#	my ($status,$code,$new_user)=CURL('voip_user_new',TEMPLATE('voip_user_pin'),$CONF{api3});
#	my ($status,$code,$new_user)=CURL('voip_user_new',TEMPLATE('voip_user_status'),$CONF{api3});
	}#case 125
###
	case "126"{#RATES request
	$Q{USSD_DEST}=~/^(\+|00)?([1-9]\d{1,15})$/ ? return ('OK',1,response('MOC_RESPONSE','DEFAULT',TEMPLATE('ussd:126:rate').sprintf '%.2f',${CALL_RATE($2)}{RATE}/100*$CONF{'markup_rate'})) : return ('NO DEST',-1,response('MOC_RESPONSE','DEFAULT',TEMPLATE('ussd:126:nodest')));
	}#case 126
###
	case "127"{#CFU request
		logger('LOG','USSD-CFU-REQUEST',"$Q{USSD_CODE} $Q{USSD_DEST}") if $CONF{debug}==4;
		if ($Q{USSD_DEST}=~/^(\+|00)?(\d{5,15})$/){#if prefix +|00 and number length 5-15 digits
			logger('LOG','SIG-USSD-CFU-REQUEST',"Subcode processing $Q{USSD_DEST}") if $CONF{debug}==4;
				 my $CFU_number=$2;
				 my $SQL=qq[SELECT get_cfu_code($Q{IMSI},"$CFU_number")];
					my $CODE=${SQL("$SQL",'array')}[0];
(my $status,my $code,$CODE)=CURL('sms_mo',${SQL(qq[SELECT get_uri2('sms_mo',NULL,"+$CFU_number","$Q{MSISDN}",'ruimtools',"$CODE")],'array')}[0]) if $CODE=~/\d{5}/;
					$CFU_number='NULL' if $CODE!~/0|1|INUSE/;
					$SQL=qq[SELECT get_cfu_text("$Q{IMSI}","$CODE",$CFU_number)];
					my $TEXT_result=${SQL("$SQL",'array')}[0];
					return ('OK',$CODE,&response('auth_callback_sig','XML',$Q{TRANSACTIONID},$TEXT_result));
					#logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'RSP',"$CODE $Q{USSD_CODE} $Q{USSD_DEST}");
			}#if number length
			else{#else check activation
			logger('LOG','SIG-USSD-CFU-REQUEST',"Code processing $Q{USSD_CODE} $Q{USSD_DEST}") if $CONF{debug}==4;
				my $SQL=qq[SELECT get_cfu_text("$Q{IMSI}",'active',NULL)];
				#my @SQL_result=&SQL($SQL);
				my $TEXT_result=${SQL("$SQL",'array')}[0]; 
				return ('OK', $Q{USSD_CODE},&response('auth_callback_sig','XML',$Q{TRANSACTIONID},"$TEXT_result"));
				#logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'RSP',"$Q{USSD_CODE} $Q{USSD_DEST}");
				}
	}#case 127
###
	case "128"{#local call request
		logger('LOG','LOCAL-CALL-REQUEST',"$Q{USSD_CODE}") if $CONF{debug}==4;
		#logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'OK',"$Q{USSD_CODE}");
		my $SPOOL_result=SPOOL() if $Q{USSD_EXT};
		return ('OK',1, $SPOOL_result) if $Q{USSD_EXT};
		return ('OK', 1, &response('auth_callback_sig','XML',$Q{TRANSACTIONID},${SQL(qq["$Q{IMSI}",'ussd',$Q{USSD_CODE},$Q{MCC}],1)}[0]));
	}#case 128
###
	case "129"{#my did request
		logger('LOG','DID-NUMBERS-REQUEST',"$Q{USSD_CODE} $Q{USSD_DEST} $Q{USSD_EXT}") if $CONF{debug}==4;#(!) hide pin
		$Q{USSD_DEST}=$Q{IMSI} if ($Q{USSD_DEST}!~/^(\+|00)?([1-9]\d{7,15})$/);
		if ($Q{USSD_EXT}=~/^([0-9]\d{3})#?$/){# check pin
		$Q{-O}='-d';
		($Q{-H},$Q{USER},$Q{PASS})=@{SQL(qq[SELECT description,auth_login,auth_pass from cc_provider WHERE provider_name='C94'],'array')};
		$Q{ACTIONS}='SimInformationByMSISDN'; $Q{REQUEST}='IMSI';
#		CURL($Q{ACTIONS},XML());
		logger('LOG','DID-NUMBERS-PIN-CHECK',"SUCCESS") if $1==$Q{PIN} and $CONF{debug}==4;;
		logger('LOG','DID-NUMBERS-PIN-CHECK',"ERROR") if $1!=$Q{PIN} and $CONF{debug}==4;
		return ('PIN INCORRECT',-1,&response('auth_callback_sig','XML',$Q{transactionid},"Please enter correct PIN")) if $1!=$Q{PIN};
		$Q{USSD_DEST}=$Q{SUB_ID};
		}#if pin
		my $did=${SQL(qq[SELECT set_did("$Q{USSD_DEST}")],'array')}[0];
		return ('OK',1, &response('auth_callback_sig','XML',$Q{TRANSACTIONID},"$did"));
	}#case 129
###
#
	else{#switch ussd code
	return ('CODE NOT DEFINED',-3,&response('MOC_RESPONSE','XML','UNKNOWN CODE '.$Q{USSD_CODE}));
	}#end else switch ussd code (no code defined)
}#end switch ussd code
}## END sub USSD ###################################
#
########### CURL #############################################
## Process all types of requests
## Return MSRN or NULL, Status
#################################################################
sub CURL{
($Q{MSG},$Q{DATA},$Q{API})=@_;
return ('MSRN_CACHE',0,$R->GET('MSRN_CACHE:'.$Q{IMSI})) if $R->EXISTS('MSRN_CACHE:'.$Q{IMSI}) && $Q{MSG}=~/get_msrn/;
#
my %HASH=$R->HGETALL('AGENT:'.$Q{API});
$Q{DATA}=$Q{DATA}.'&'.$HASH{auth};
$Q{HOST}=$HASH{host};
#
logger('LOG',"API-CURL-$Q{MSG}-PARAMS","$Q{HOST} $Q{DATA}") if $CONF{debug}>2;
#
####### DEBUG OPTIONS #########
return ('FAKE-XML',1,XML_PARSE($CONF{'fake-xml'},$Q{MSG})) if $CONF{'fake-xml'} && $CONF{'debug-imsi'} eq $Q{GIMSI};
###############################
#
####### CURL OPTIONS ##########
our $response_body='';
our $curl = WWW::Curl::Easy->new;
$curl->setopt (CURLOPT_SSL_VERIFYHOST, 0);
$curl->setopt( CURLOPT_SSL_VERIFYPEER, 0);
$curl->setopt( CURLOPT_POSTFIELDS, $Q{DATA});
$curl->setopt( CURLOPT_POSTFIELDSIZE, length($Q{DATA}));
$curl->setopt( CURLOPT_POST, 1);
$curl->setopt( CURLOPT_CONNECTTIMEOUT,5);
$curl->setopt( CURLOPT_HEADER, 0);
$curl->setopt( CURLOPT_URL, $Q{HOST});
$curl->setopt( CURLOPT_WRITEDATA, \$response_body);
#######
if ($Q{DATA}){
eval {use vars qw($curl $response_body %Q); logger('LOG',"API-CURL-$Q{MSG}-REQ",$Q{HOST}.' '.length($Q{DATA})) if $CONF{debug}==4;
my $retcode = $curl->perform;
my $response_code = $curl->getinfo(CURLINFO_HTTP_CODE) if $retcode==0;
logger('LOG',"API-CURL-ERROR-BUF",$curl->strerror($retcode)) if $retcode!=0 and $CONF{debug}>1;
$Q{CURL_ERROR}=$curl->strerror($retcode) if $retcode!=0; 
};warn $@ if $@;  logger('LOG',"API-CURL-ERROR","$@") if $@;
}#if URI
else{return ('NO URI',0)}#else URI empty
#
use vars qw($response_body);
if ($response_body){
	logger('LOG',"$Q{MSG}-RESPOND","$response_body") if $CONF{debug}==4;
	$Q{CURL_RESULT}=&XML_PARSE("$response_body",$Q{MSG});
	return ('OK',1,$Q{CURL_RESULT});
}#if CURL return
else{# timeout
	logger('LOG',"CURL-$Q{MSG}-REQUEST","Socket Timed Out") if $CONF{debug}>1;
	return ('TIMEOUT',0);
}#end else
}########## END sub GET_MSRN ####################################
#
##### RC_API_CMD ################################################
## Process all types of commands to RC
## Accept CMD, Options
## Return message
#################################################################
sub API_CMD{
if ($R->SISMEMBER('AGENT_SESSION',AUTH())){logger('LOG','API-CMD',"AUTH OK") if $CONF{debug}>1;}#if auth
elsif($R->EXISTS('SESSION:'.$Q{SESSION}.':'.$Q{REMOTE_ADDR}.$Q{HTTP_USER_AGENT})&&$Q{CODE}=~/ajax|js/){logger('LOG','API-CMD-AJAX',"AUTH OK") if $CONF{debug}>1;}
else{
	logger('LOG','API-CMD',"AUTH ERROR") if $CONF{debug}>1;
	my %HASH=(aaData=>'');
	return GUI() if $Q{CODE}=~/ajax/;
	return ('NO AUTH',-1,response('api_response','JSON',\%HASH)) if $Q{CODE}=~/ajax/;
	return ('NO AUTH',-1,response('api_response','ERROR',"NO AUTH"));
}#else no auth				
my $result;
logger('LOG','API-CMD',"$Q{CODE}") if $CONF{debug}>2;
switch ($Q{CODE}){
	case 'ping' {#PING
		sleep 2 if defined $Q{SUB_CODE};
		return ('OK', 1, response('ping','HTML',"PONG")) if defined $Q{SUB_CODE};
		return ('OK', 1, response('api_response','XML',"PONG"));
	}#case ping
	case 'get_msrn' {#GET_MSRN
		if ($Q{IMSI}){#if imsi defined
			(my $status,my $code, $Q{MSRN})=CURL('get_msrn',TEMPLATE('get_msrn'),$CONF{api2});
			return ('OK', $code,response('api_response','XML')) if $Q{SUB_CODE} ne 'plaintext'&&$Q{MSRN};
			return ('OK',$code,response('get_msrn','HTML',$Q{MSRN})) if $Q{SUB_CODE} eq 'plaintext';
		}#if imsi
		else{#if no imsi
			return ('IMSI UNDEFINED',-1,response('get_msrn','ERROR',"IMSI UNDEFINED $Q{IMSI} $Q{MSRN}"));
		}#else no imsi
	}#case msrn
	case 'get_did' {#PROCESS DID number
		logger('LOG','API-CMD-DID-[did/src]',"$Q{RDNIS}/$Q{SRC}") if $CONF{debug}>2;
				$Q{IMSI} = length($Q{RDNIS})==6 ? $Q{RDNIS} : $R->HGET('DID',$Q{RDNIS});
				($Q{IMSI},$Q{MSRN},$Q{RDNIS_ALLOW})=$Q{IMSI}=~/(\d+)\:?(\d+)?\:?(.*)?/;
				$Q{GIMSI}= $CONF{'imsi_prefix'}.$Q{IMSI};
				GET_SUB();#if no DID no SUB_STATUS
#		(my $status, my $code,$Q{MSRN})=CURL('get_msrn_did',TEMPLATE('get_msrn'),$CONF{api2}) if $Q{SUB_STATUS}==1 and (not defined $Q{MSRN}||$Q{RDNIS_ALLOW}=~/$Q{SRC}/);
				(my $status, my $code,$Q{MSRN})=CURL('get_msrn_did',TEMPLATE('get_msrn'),$CONF{api2}) if $Q{SUB_STATUS}==1 and not defined $Q{MSRN};#	||$Q{RDNIS_ALLOW}=~/$Q{SRC}/);
				$Q{DID_RESULT}=$Q{MSRN}=~/\d{7,15}/;
				CALL_RATE($Q{MSRN}) if $Q{DID_RESULT};
				$Q{RATE}=$Q{RATE}+$Q{MTC};
				BILL('get_msrn_did') if $Q{DID_RESULT};
				logger('LOG','API-CMD-DID-[status/code/msrn/rate]',"$status $code $Q{MSRN} $Q{RATE}") if $CONF{debug}>2;
				return ('OK',$Q{DID_RESULT},response('get_did','HTML',TEMPLATE('did:'.$Q{DID_RESULT})));
	}#case get_did
	case 'send_ussd' {#SEND_USSD
		if ($Q{SUB_HASH}=~/$Q{TOKEN}/&&$Q{SMS_TO}=~/$Q{SUB_PHONE}/){
		return ('OK',1,response('api_response','XML',CURL('send_ussd',TEMPLATE('send_ussd'),$CONF{api2})));
	}else{
		return ('ERROR',1,response('api_response','ERROR','NOT YOUR SIM'));
	}#else AUTH
		}#case send_ussd		
	case /send_sms/i {#SEND SMS MT	
	if ($Q{SUB_HASH}=~/$Q{TOKEN}/&&$Q{SMS_TO}=~/$Q{SUB_PHONE}/){
		return ('OK',1,response('api_response','XML',undef,CURL('send_sms_mt',TEMPLATE('send_sms_mt'),$CONF{api2})));
	}else{
		return ('ERROR',1,response('api_response','ERROR','NOT YOUR SIM'));
	}#else AUTH
		}#case send sms mt	
	case 'stat' {#STAT
		my ($i,@s);
		my @k=$R->HKEYS('STAT:AGENT:'.$R->HGET('AGENT',$Q{DIGEST})) if $Q{IMSI}==0;
		my @v=$R->HVALS('STAT:AGENT:'.$R->HGET('AGENT',$Q{DIGEST})) if $Q{IMSI}==0;
		   @k=$R->HKEYS("STAT:SUB:$Q{IMSI}") if $Q{IMSI}>0;
		   @v=$R->HVALS("STAT:SUB:$Q{IMSI}") if $Q{IMSI}>0;
		map {$_=~/.*-\[(.*)\]-/; my $c=$1; push @s,$_.':'.$v[$i++]*$SIG{$c} if $_=~/$Q{DATE}/} @k;
		$Q{STAT}=join("\n\r",@s);
		return ('OK',1,response('API_RESPONSE','XML',$Q{STAT}));
		}#case stat
	case 'ajax' {#AJAX
		$Q{TOKEN}=$R->GET('SESSION:'.$Q{SESSION}.':'.$Q{REMOTE_ADDR}.$Q{HTTP_USER_AGENT});
		$R->HEXISTS('TEMPLATE','ajax:'.$Q{SUB_CODE}) ? my %HASH=(aaData=>SQL(TEMPLATE('ajax:'.$Q{SUB_CODE}),'ajax')) : return GUI($R->EXPIRE('SESSION:'.$Q{SESSION}.':'.$Q{REMOTE_ADDR}.$Q{HTTP_USER_AGENT},1),$Q{SESSION}=0);
		logger('LOG','API-CMD-AJAX',$Q{SUB_CODE}) if $CONF{debug}>2;
		return ('OK',1,response('api_response','JSON',\%HASH));
		}#case ajax
	case 'js' {#JS
		logger('LOG','API-CMD-JS',$Q{SUB_CODE}) if $CONF{debug}>2;
		return ('OK',1,response('api_response','HTML',TEMPLATE('js:'.$Q{SUB_CODE})));
		}#case js
	case /set_user/i {#API C9
	if ($Q{SUB_HASH}=~/$Q{TOKEN}/){		
	$Q{SUB_CODE} = $Q{SUB_CODE}=~/^enable$/i ? 1 : $Q{SUB_CODE}=~/^disable$/i ? 0 : $Q{SUB_CODE};
	return ('OK',1, response('api_response','XML',undef,CURL('set_user_status',TEMPLATE('set_user_status'),$R->HGET('AGENT:'.$CONF{api1},'host')))) if $Q{SUB_CODE}!~/^Data/i;
	return ('OK',1, response('api_response','XML',undef,CURL('set_user',XML($Q{SUB_CODE}),TEMPLATE('set_user'),$R->HGET('AGENT:'.$CONF{api1},'host'))));
	}else{
	return ('ERROR',1,response('api_response','ERROR','NOT YOUR SIM'));
	}#else AUTH
	}#API C9
	else {
		logger('LOG','API-CMD-UNKNOWN',"$Q{CODE}") if $CONF{debug}>1;
		return ('API CMD',-1,response('api_response','ERROR',"UNKNOWN CMD REQUEST"));
		}#else switch code
}#switch code
		logger('LOG','API-CMD',"$Q{CODE} $result") if $CONF{debug}>1;
		return ('API CMD',$result);
}##### END sub RC_API_CMD ########################################
#
##### AGENT ################################################
sub AGENT{
use vars qw(%Q);
my	%RESPONSE_TYPE=('auth_callback_sig'=>'MOC_RESPONSE','DataAUTH'=>'RESPONSE','LU_CDR'=>'CDR_RESPONSE','OutboundAUTH'=>);	
my $response_type= $RESPONSE_TYPE{$Q{REQUEST_TYPE}} ? $RESPONSE_TYPE{$Q{REQUEST_TYPE}} : 0;
my $response_options= $RESPONSE_TYPE{$Q{REQUEST_TYPE}} ? 'XML' : 'HTML';
$Q{REQUEST_TYPE}='USSD' if $Q{REQUEST_TYPE} eq 'auth_callback_sig';#unknown USSD CODES set as USSD
$Q{REQUEST_TYPE}=$SYS{$Q{USSD_CODE}} if $SYS{$Q{USSD_CODE}}; #wellknown USSD CODES name for 100 110 111 112 122 123 125 126
$Q{REQUEST_TYPE}='CB' if $Q{REQUEST_TYPE} eq 'OutboundAUTH';# OutboundAUTH set as CB
$Q{USSD_DEST}=$Q{DESTINATION} if $Q{REQUEST_TYPE} eq 'CB';
$Q{USSD_DEST}=uri_escape($Q{CALLDESTINATION}) if $Q{REQUEST_TYPE} eq 'USSD';
$Q{IMEI}=$Q{DESTINATION}=uri_escape($Q{USSD_DEST}) if $Q{REQUEST_TYPE}=~/(CB|IMEI)/;
($Q{PAGE},$Q{PAGES},$Q{SEQ})=split(undef,$Q{USSD_DEST}) if $Q{REQUEST_TYPE} eq 'SMS'; 
($Q{DESTINATION},$Q{MESSAGE})=split('\*',uri_unescape($Q{USSD_EXT})) if $Q{REQUEST_TYPE} eq 'SMS';
$Q{MESSAGE}=~s/\#// if $Q{REQUEST_TYPE} eq 'SMS';
#$Q{MTC}= scalar @{$R->KEYS("PLMN:*:$Q{MCC}:".int $Q{MNC})} ? $R->GET($R->KEYS("PLMN:*:$Q{MCC}:".int $Q{MNC})) : 0;
$Q{AGENT_URI}= $Q{CALLLEGID} ? TEMPLATE('agent').TEMPLATE('datasession') : $Q{TOTALCURRENTBYTELIMIT} ? TEMPLATE('agent').TEMPLATE('dataauth') : $Q{MESSAGE} ? TEMPLATE('agent').TEMPLATE('smslite') : TEMPLATE('agent') ;
$Q{AGENT_URI}=XML() if $Q{SUB_AGENT_FORMAT} eq 'xml';
my ($status, $code,$result)=CURL('AGENT',$Q{AGENT_URI},$Q{SUB_HASH});
defined $Q{ERROR} ? $response_options='ERROR' : undef;
return ($status,$code,response($response_type,$response_options,$result));
}# END sub AGENT
##################################################################
#
### SUB AUTH ########################################################
sub AUTH{
logger('LOG',"API-AUTH-[addr/token/session]","$Q{REMOTE_ADDR} $Q{TOKEN} $Q{SESSION}") if $CONF{debug}>2;
	$Q{DIGEST}=$Q{SESSION}=$Q{SESSION} ? $Q{SESSION} :0;
	$Q{HTTP_USER_AGENT}=unpack("H*",$Q{HTTP_USER_AGENT});
return 2 if $R->EXPIRE('SESSION:'.$Q{SESSION}.':'.$Q{REMOTE_ADDR}.$Q{HTTP_USER_AGENT},$CONF{html_session_expire}); # index page or ajax
	my	$md5 = Digest::MD5->new;
	$md5->add( pack( "C4", split /\./, $Q{REMOTE_ADDR} ), $Q{TOKEN});
	$Q{DIGEST} = $md5->hexdigest if $Q{TOKEN};
	$md5->add( pack( "C4", split /\./, $Q{REMOTE_ADDR} ), $Q{TOKEN}, $Q{INNER_TID});
logger('LOG',"API-AUTH-DIGEST","$Q{DIGEST} $Q{REQUEST_TYPE}") if $CONF{debug}>2;
return $Q{DIGEST} if $Q{REQUEST_TYPE}=~/API_CMD/i; # api
	$Q{LOGIN_STATUS}= $CONF{login_status} if $Q{SESSION};#if we here and session is defined = timeout 
	$Q{TOKEN}= $Q{TOKEN} ? $Q{TOKEN} :0;
	$Q{TOKEN_NAME}=$R->HGET('AGENT:'.$Q{TOKEN},'name') if $Q{TOKEN};
	$Q{DIGEST}=$md5->hexdigest if $Q{TOKEN_NAME};
	$Q{SESSION}=$R->SETEX('SESSION:'.$Q{DIGEST}.':'.$Q{REMOTE_ADDR}.$Q{HTTP_USER_AGENT},$CONF{html_session_expire},$Q{TOKEN}) if $Q{TOKEN_NAME};
	$Q{SESSION}=$Q{DIGEST} if $Q{SESSION};
return 2 if $R->HGET('AGENT:'.($Q{TOKEN} ? $Q{TOKEN} :0),$Q{PIN} ? $Q{PIN} :0); # index page if CN & PIN
return 1 if $Q{SESSION}&&$Q{TOKEN_NAME}; # redirect page
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
	$Q{imsi}=${SQL(qq[SELECT useralias from cc_card WHERE username=$CARD_NUMBER],'array')}[0];
#	logger('LOGDB',"PAYMNT","$Q{REQUEST}->{payment}{id}","$Q{imsi}",'RSP',"$CARD_NUMBER $SQL_T_result @IDs");
	return ('PAYMNT 1',&response('payment','HTML',"200 $SQL_T_result"));
# we cant send this sms with no auth because dont known whom
my ($status,$code,$SMSMT_result)=CURL('sms_mt',${SQL(qq[SELECT get_uri2("pmnt_$SQL_T_result","$CARD_NUMBER",NULL,NULL,"$CARD_NUMBER","$Q{REQUEST}->{payment}{id}")],'array')}[0]);
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
$email_text=uri_unescape(${SQL(qq[SELECT paypal("$Q{txn_id}","$result")],'array')}[0]);
eval {use vars qw(%Q $email $email_pri $email_text);logger('LOG','PAYPAL-GET-EMAIL',"$Q{receipt_id} $Q{payer_email} $email") if $CONF{debug}==4;;
$email_pri=`echo "$email_text" | mail -vs 'Payment $Q{receipt_id}' $Q{payer_email} $email -- -F "CallMe! Payments" -f pay\@ruimtools.com`;
};warn $@ if $@;  logger('LOG',"PAYPAL-SEND-EMAIL-ERROR","$@") if $@;
}#if email
else{$email_pri="No email address"}#else email empty
#
logger('LOG','PAYPAL-SEND-EMAIL',"$email_pri") if $CONF{debug}==4;;
# send sms notification to primary phone number
my ($status,$code,$sms_pri)=CURL('sms_mt',${SQL(qq[SELECT get_uri2('sms_mt',NULL,"${SQL(qq[SELECT phone FROM cc_card WHERE username=$Q{'personal_number'}],'array')}[0]","ruimtools",NULL,"${SQL(qq[SELECT paypal("$Q{txn_id}","$result")],'array')}[0]")],'array')}[0]) if $Q{'personal_number'};
# send sms notification to additional phone number
($status,$code,my $sms_add)=CURL('sms_mo',${SQL(qq[SELECT get_uri2('sms_mo',NULL,"+$rcpt","+447700079964","ruimtools","${SQL(qq[SELECT paypal("$Q{txn_id}","$result")],'array')}[0]")],'array')}[0]) if $rcpt;
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
logger('LOG','SMS-REQ',"$Q{USSD_DEST} $Q{USSD_EXT}") if $CONF{debug}==3;
#
($Q{PAGE},$Q{PAGES},$Q{SEQ})=split(undef,$Q{USSD_DEST}); 
($Q{SMS_TO},$Q{MESSAGE})=split('\*',uri_unescape($Q{USSD_EXT}));
$Q{MESSAGE}=~s/\#//;
$Q{MSISDN}=~s/\+//;
($Q{SMS_PREFIX},$Q{SMS_TO})=$Q{SMS_TO}=~/^(\D|00)?([1-9]\d{5,12})/;
$Q{SMS_TO}=$R->HGET('DID',$Q{SMS_TO}) if length($Q{SMS_TO})==6;
return 3 if length($Q{SMS_TO})<6;
#
	my	$md5 = Digest::MD5->new;
	$md5->add( $Q{GIMSI}, $Q{SMS_TO}, $Q{PAGES}, $Q{SEQ} );
	$Q{DIGEST} = $md5->hexdigest;
#
$R->RPUSH('SMS:'.$Q{DIGEST}, $Q{MESSAGE});
$R->EXPIRE('SMS:'.$Q{DIGEST}, 60);
$Q{MESSAGE}=uri_escape( substr( decode('ucs2',pack("H*",join('',$R->LRANGE('SMS:'.$Q{DIGEST},0,-1)))) ,0,168) );
#
return (CURL('send_sms_mo',TEMPLATE('send_sms_mo'),$CONF{api2})) if $Q{PAGE}==$Q{PAGES};
return 2;
#my @multi_sms=($sms_long_text=~/.{1,168}/gs);#divide long text to 168 parts
}# END sub USSD_SMS #############################################################
#
### sub MO_SMS ##################################################################
# Authenticate outbound SMS request.
###
sub MO_SMS{
use vars qw(%Q);
#logger('LOGDB','MO_SMS',$Q{transactionid},$Q{imsi},'RSP',"RuimTools 0");
return('OK',1,&response('MO_SMS_RESPONSE','XML',0));#By default reject outbound SMS MO
}#end sub MO_SMS
#
### sub MT_SMS ##################################################################
#
# Authenticate inbound SMS request ##############################################
###
sub MT_SMS{
#logger('LOG','MT_SMS',$Q{transactionid},$Q{imsi},'RSP',"1");
$Q{REQUEST_STATUS}=$R->SISMEMBER('MTS_SMS',$Q{TRANSACTIONID});
return('OK',1,response('MT_SMS_RESPONSE','XML',$Q{REQUEST_STATUS}));# By default we accept inbound SMS MT
}#end sub MT_SMS
#
### sub MOSMS_CDR ##################################################################
#
# MOSMS (Outbound) CDRs ############################################################
##
sub MOSMS_CDR{
#	my $CDR_result=&SMS_CDR;
#	logger('LOG','MOSMS_CDR',$CDR_result) if $CONF{debug}==4;
#	logger('LOGDB','MOSMS_CDR',$Q{transactionid},$Q{imsi},'RSP',"$CDR_result");
#	return('MOSMS_CDR',1,&response('MOSMS_CDR','XML',$Q{transactionid},$CDR_result));
return('OK',1,response('CDR_RESPONSE','XML',1));# By default we accept inbound SMS MT
#	return ('OK',1,response('CDR_RESPONSE','XML',1));
}#end sub MOSMS_CDR ################################################################
#
### sub MTSMS_CDR ##################################################################
# MTSMS (Inbound) CDRs
###
sub MTSMS_CDR{
#	my $CDR_result=&SMS_CDR;
#	logger('LOG','MTSMS_CDR',$CDR_result) if $CONF{debug}==4;
#	logger('LOGDB','MTSMS_CDR',$Q{transactionid},$Q{imsi},'RSP',"$CDR_result");
return('OK',1,response('CDR_RESPONSE','XML',1));# By default we accept inbound SMS MT
#	return ('OK',1,response('CDR_RESPONSE','XML',1));
	#	return('MTSMS_CDR',1,&response('MTSMS_CDR','XML',$Q{transactionid},$CDR_result));
}#end sub MTSMS_CDR ################################################################
#
### sub SMSContent_CDR
# SMS Content CDRs #################################################################
##
sub SMSCONTENT_CDR{
	use vars qw(%Q);#workaround #19 C9RFC
	$Q{'cdr_id'}='NULL';#workaround #19 C9RFC
	my $CDR_result=&SMS_CDR;
	logger('LOG','SMSContent_CDR',$CDR_result) if $CONF{debug}==4;
#	logger('LOGDB','SMSContent_CDR',$Q{transactionid},$Q{imsi},'RSP',"$CDR_result");
	return('SMSContent_CDR',1,&response('MT_SMS','XML',$Q{transactionid},$CDR_result));
}#end sub SMSContent_CDR ############################################################
#
### SMS_CDR #########################################################################
# Processing CDRs for each type of SMS
###
sub SMS_CDR{
use vars qw(%Q);
#
#my $SQL=qq[INSERT into `msrn`.`cc_sms_cdr` ( `id`, `msisdn`, `allow`, `reseller_charge`, `timestamp`, `smsc`, `user_charge`, `mnc`, `srcgt`, `request_type`, `smsfrom`, `IOT`, `client_charge`, `transactionid`, `route`, `imsi`, `user_balance`, `message_date`,`carrierid`,`message_status`,`service_id`,`sms_type`,`sender`,`message`,`original_cli`) values ( "$Q{cdr_id}", "$Q{msisdn}", "$Q{allow}", "$Q{reseller_charge}", "$Q{timestamp}", "$Q{smsc}", "$Q{user_charge}", "$Q{mnc}", "$Q{srcgt}", "$Q{request_type}", "$Q{smsfrom}", "$Q{IOT}", "$Q{client_charge}", "$Q{transactionid}", "$Q{route}", "$Q{imsi}", "$Q{user_balance}", "$Q{message_date}","$Q{carrierid}","$Q{message_status}","$Q{service_id}","$Q{sms_type}","$Q{sender}","$Q{message}","$Q{original_cli}")];
#my $sql_result=&SQL($SQL);
#logger('LOG','SMS_CDR',$sql_result) if $CONF{debug}==4;
return ('CDR_RESPONSE','XML',1); 
}#end sub SMS_CDR ##################################################################
# end SMS section ##################################################################
#
### SUB DataAUTH ###################################################################
sub DATAAUTH{
use vars qw(%Q);
my ($status,$code,$balance)=CURL('get_user_info',TEMPLATE('get_user_info'));
$Q{DATA_AUTH}=scalar ($Q{DATA_AUTH}=${SQL(qq[SELECT data_auth("$Q{MCC}","$Q{MNC}","$Q{TOTALCURRENTBYTELIMIT}","$balance")],'array')}[0])>0 ? $Q{DATA_AUTH} :0;
#$Q{DATA_AUTH}=0 if !$Qdata_auth;
logger('LOG','DataAUTH',$Q{DATA_AUTH}) if $CONF{debug}==4;
#$Q{SUB_CREDIT_INET}=sprintf '%.2f',(CURL('get_user_info',TEMPLATE('get_user_info'))*1.25);
return ('DataAUTH',$Q{DATA_AUTH},&response('RESPONSE','XML',0));
}
### END sub DataAUTH ###############################################################
#
### sub DataSession ###################################################################
sub DATASESSION{
return ('DataSession', 0, response('DataSession','HTML','REJECT - DUPLICATE')) if $R->SISMEMBER('DATASESSION',$Q{CALLLEGID});
$Q{AMOUNT}=$Q{TOTALCOST}{amount}{value}/$CONF{euro_currency}*-1;#CONVERT TO EURO
my ($status,$code,$result)=CURL('set_user_balance',TEMPLATE('set_user_balance'));
logger('LOG','DataSession-[legid:amount]',"$Q{CALLLEGID}:$Q{AMOUNT}") if $CONF{debug}==4;
$R->SADD('DATASESSION',$Q{CALLLEGID});
return ('DataSession', $Q{TRANSACTIONID}, response('DataSession','HTML','200'));
} 
### END sub DataSession ##############################################################
#
### sub msisdn_allocation #########################################################
# First LU with UK number allocation
###
sub MSISDN_ALLOCATION{
use vars qw(%Q);
SQL(qq[UPDATE cc_card set phone="+$Q{MSISDN}",loginkey="$Q{TID}" where useralias=$Q{GIMSI}]);
$R->HSET('DID',$Q{IMSI},$Q{MSISDN});
my ($status,$code,$new_user)=CURL('voip_user_new',TEMPLATE('voip_user_new'),$CONF{api3});
logger('LOG','msisdn_allocation',$Q{STATUS}) if $CONF{debug}==4;
$Q{CDR_STATUS} = $Q{STATUS} eq 'Failed' ? 0: 1;
return ('msisdn_allocation',$code,response('CDR_response','XML',$Q{CDR_STATUS}));
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
use vars qw(%Q $R);
my $func=$_[0];
my $xml=new XML::Bare(simple=>1);
my %HASH;
$HASH{$func}=(
	{
		IMSI=>{value=>$Q{GIMSI}},
		Authentication=>{
			Username=>{value=>$R->HGET('AGENT:'.$CONF{api1},'username')},
			Password=>{value=>$R->HGET('AGENT:'.$CONF{api1},'password')},
		}
	}) if $func;

return $xml->xml(\%HASH) if $func;#to C4
$Q{IMSI}=$Q{GIMSI};
map { $HASH{api}{api_request}{$_}={ value=>$Q{$_} } if defined $Q{$_}}  @{ $R->SMEMBERS('REQUEST:'.uc $Q{REQUEST_TYPE}) };

$HASH{api}{api_auth}{auth_key}={ value=>$Q{SUB_AGENT_AUTH} } if defined $Q{SUB_AGENT_AUTH};

return $xml->xml(\%HASH);#to agent
}#XML
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
### sub TEMPLATE #########################################################
##
sub TEMPLATE{
use vars qw($R);
my $template = Text::Template->new(TYPE => 'STRING',SOURCE => pack( "H*",$R->HGET('TEMPLATE',$_[0]) )  );
my $text = $template->fill_in(HASH=>\%Q);
return $text;
}#end TEMPLATE
##
### sub BILL #########################################################
##
sub BILL{
use vars qw($R);
my $USSD_CODE= defined $Q{USSD_CODE} ? $Q{USSD_CODE} : 0;
my $COST=$Q{TOPUP} ? -$Q{TOPUP} : $SIG{$_[0]} ? $SIG{$_[0]} :0;
my $CODE=defined $Q{CODE} ? $Q{CODE} : $Q{AMOUNT} ? $Q{AMOUNT} :NULL;
$R->PUBLISH('SDR',"NULL,$Q{INNER_TID},NULL,$Q{GIMSI},'$_[0]','$CODE',$USSD_CODE,$COST") if $Q{IMSI}>0;
}## end BILL
### sub GUI #########################################################
##
sub GUI{
return ('OK',3,"Content-Type: text/html\n\n".TEMPLATE($Q{ERROR_NUMBER})) if $Q{ERROR_NUMBER};
switch (AUTH()) {
	case 0 {$Q{PAGE}='html_login'}
	case 1 {$Q{PAGE}='js:session'}
	case 2 {$Q{PAGE}='html_index'}
	else {$Q{PAGE}='html_login'}
}#switch page
$Q{TOKEN_NAME}=$R->HGET('AGENT:'.$R->GET('SESSION:'.$Q{SESSION}.':'.$Q{REMOTE_ADDR}.$Q{HTTP_USER_AGENT}),'name') if not defined $Q{TOKEN_NAME};
return ('OK',$Q{LOGIN_STATUS}=$CONF{login_not_active},"Content-Type: text/html\n\n".TEMPLATE('html_login')) if $Q{TOKEN}&&!$R->HEXISTS('AGENT:'.$Q{TOKEN},'gui');
return ('OK',1,"Content-Type: text/html\n\n".TEMPLATE($Q{PAGE}));
}#end GUI
### sub CALL_RATE #########################################################
##
sub CALL_RATE{	
use vars qw($R);
my $MSISDN=$_[0];
my $cache;
my %HASH = scalar keys %{$cache={$R->HGETALL("RATE_CACHE:".substr($MSISDN,0,$CONF{'rate_cache_len'}))}} ? %{$cache} : %{SQL(qq[CALL get_limit($MSISDN)],'hash')};
#rates from cc_rates_memory
if (!scalar keys %{$cache}){
	$R->HSET("RATE_CACHE:".substr($MSISDN,0,$CONF{'rate_cache_len'}),$_,$HASH{$_}, sub{}) for keys %HASH;
	$R->wait_all_responses;
	$R->EXPIRE("RATE_CACHE:".substr($MSISDN,0,$CONF{'rate_cache_len'}),86400);
	}#if cache
map {$Q{$_}=$HASH{$_}} keys %HASH;#map for DID
	$Q{'CALL_RATE'}=($HASH{'RATE'}*$CONF{'markup_rate'}+$Q{MTC})/100;
	$Q{'CALL_LIMIT'}=($Q{'CALL_LIMIT'}=floor(($Q{'SUB_CREDIT'}/$Q{'CALL_RATE'})*60))>$CONF{'max-call-time'} ? $CONF{'max-call-time'} : $Q{'CALL_LIMIT'};
return \%HASH;# return for SPOOL
}## sub call_rate
######### END #################################################	