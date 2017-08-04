#!/usr/local/bin/perl
########## VERSION AND REVISION ################################
##
### Copyright (C) 2012-18, MSRN.ME 3.0 den@msrn.me
##
my $rev='MSRN.ME-3.5 rev.030817 HFX-FORK';
#
#################################################################
use FCGI;
use FCGI::ProcManager qw(pm_manage pm_pre_dispatch pm_post_dispatch);
use Net::Curl::Easy qw(:constants);
use Redis;
use DBI;
use DBD::SQLite;
use IO::Socket;
use XML::Bare;
use JSON::XS;
use Digest::SHA qw(hmac_sha512_hex sha1);
use MIME::Base64; 
use Digest::MD5 qw(md5_hex);
use URI::Escape;
use Text::Template;
use Net::SMTP;
use Email::Simple;
use Email::Send;
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
no warnings 'uninitialized';
print "All Modules Loaded Succesfully\n";
# [CONFIG] *********************************************************
our $R = Redis->new; #$ENV{REDIS_SERVER}
#$R->SLAVEOF('NO','ONE');
$R->hset('CONF','rev',unpack('H*',$rev));
my %CONF=$R->HGETALL('CONF');
if ( !$CONF{pidfile} ) {print "WARN: Configuration not found. Please check Redis\n\n"; exit 42};
map {$CONF{$_}=pack('H*',$CONF{$_})} keys %CONF;
my %SIG=$R->HGETALL('SIG');
$R->quit;
# [FORK] ***********************************************************
if($ARGV[0] eq "-fork"){
our $pid = fork;
exit if $pid;
die "Couldn't fork: $!" unless defined($pid);
POSIX::setsid() or die "Can't start a new session: $!";
my $PIDFILE = new IO::File;
$PIDFILE->open("> $CONF{pidfile}");
print $PIDFILE $$;
$PIDFILE->close();
#chdir "$CONF{rundir}" or die "CANT CHDIR: $CONF{rundir} $!";
#POSIX::setuid(501) or die "Can't set uid: $!";
}#if fork
DISPATCH(our %Q, our $t0);
#
sub DISPATCH {
print "$CONF{rev} Ready at $$ debug level $CONF{debug} backlog $CONF{fcgi_backlog} processes $CONF{fcgi_processes}\n";
# [CAPACITY] ************************************************************
#50/20 - 10k 19.289372 seconds 518.42 [#/sec] 38.579 [s] / 1.929 [ms]
#10/10 - 10k 18.939499 seconds 528.00 [#/sec] 18.939 [s] / 1.894 [ms]
#5/2	-10k 24.699049 seconds 404.87 [#/sec]  4.940 [s] / 2.470 [ms]			
# [OPEN SOCKET] *********************************************************
my $sock = FCGI::OpenSocket("0.0.0.0:$CONF{port}",$CONF{fcgi_backlog});
	my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV, $sock);
	    pm_manage(n_processes => $CONF{fcgi_processes});
	    		our $dbh = DBI->connect('DBI:SQLite:msrn.db','','');
		    		$dbh->do("PRAGMA synchronous = OFF");
		    		$dbh->do("PRAGMA journal_mode = MEMORY");
		    		$dbh->do("PRAGMA encoding = 'UTF-8'");
#	    		$R = Redis->new(encoding => undef);
				$R = Redis->new();
 		reopen_std();
# [ACCEPT CONNECTIONS] ****************************************
while ( $request->Accept() >= 0){
pm_pre_dispatch();
# [DISPATCH] ***************************************************
	%CONF=();%SIG=();%Q=();
	%SIG=$R->HGETALL('SIG');
	%CONF=$R->HGETALL('CONF');
	map {$CONF{$_}=pack('H*',$CONF{$_})} keys %CONF;
	my ($s, $usec) = gettimeofday();my $format = "%06d";$usec=sprintf($format,$usec);
	$Q{INNER_TID}=$s.$usec;$Q{TID}=int(rand(1000000));$Q{TIMESTAMP}=strftime("%Y-%m-%d %H:%M:%S", localtime);
	my $env = $request->GetEnvironment();
	$t0=Benchmark->new;
#**************************************************************************************
		$Q{REQUEST}= $env->{REQUEST_METHOD} eq 'POST' ? <STDIN> : $env->{QUERY_STRING};
#**************************************************************************************
			$Q{REMOTE_ADDR}=$env->{REMOTE_ADDR};
			$Q{REQUEST_TYPE}='GUI' if $Q{REQUEST}!~m/request_type|api|datasession/ig;
#**************************************************************************************
				print eval{main()} if not $R->SISMEMBER('BLACKLIST',"$Q{REMOTE_ADDR}");
				logger('DISPATCH-MAIN-ERROR: '.$@) if $@;
				print response('ERROR','ERROR','GENERAL ERROR #'.__LINE__) if $@;
					BILL($Q{REQUEST_TYPE}) if $Q{ACTION_CODE}>0;
					logger('LOGEXPIRE');
#**************************************************************************************
			my $t2=Benchmark->new;
			my $td0 = timediff($t2, $t0);	
			$R->PUBLISH('TIMER',$Q{INNER_TID}.':'.substr($td0->[0],0,8));
#**************************************************************************************
pm_post_dispatch();
	    		  }#while
sub reopen_std {   
    open(STDIN,  "+>/dev/null") or die "Can't open STDIN: $!";
    open(STDOUT, "+>&STDIN") or die "Can't open STDOUT: $!";
    open(STDERR, "+>&STDIN") or die "Can't open STDERR: $!";
}#while Accept
}########### END OF DISPATCH ####################################
#
########## MAIN #################################################
sub main {
#$R->SLAVEOF('NO','ONE');
	XML_PARSE($Q{REQUEST},'xml') ? undef : $Q{REQUEST_TYPE}=~/GUI/ ? return GUI() : return response('ERROR','ERROR','SORRY REQUEST NOT ACCEPTED #'.__LINE__);
# [GET SUB] ************************************************************************
!GET_SUB() && $Q{IMSI} ? return response('ERROR','ERROR','SORRY SUBSCRIBER NOT DEFINED #'.__LINE__) : undef;
# [STATISTIC] ************************************************************************
	$Q{AGENT} = $Q{SUB_HASH} ? $Q{SUB_HASH} : $Q{REMOTE_ADDR};
	$Q{REQUEST_CODE} = defined $Q{CODE} ? '-['.$Q{CODE}.']' : defined $Q{USSD_CODE} ? '-['.$Q{USSD_CODE}.']' : '';
	$R->HINCRBY("STAT:AGENT:$Q{AGENT}",'['.substr($Q{TIMESTAMP},0,10)."]-[$Q{REQUEST_TYPE}]$Q{REQUEST_CODE}",1) if $Q{AGENT};
	$R->HINCRBY("STAT:SUB:$Q{GIMSI}",'['.substr($Q{TIMESTAMP},0,10)."]-[$Q{REQUEST_TYPE}]$Q{REQUEST_CODE}",1) if $Q{IMSI}>0;
# [SUB REF] ************************************************************************
eval{ ($Q{ACTION_STATUS},$Q{ACTION_CODE},$Q{ACTION_RESULT}) = 
$Q{REQUEST_TYPE}=~/API/i ? API() : $R->HEXISTS("AGENT:$Q{SUB_HASH}",'host') ? AGENT() : $Q{REQUEST_TYPE}=~/(GUI|PAY)/ ? GUI() : SIG() }; 
		warn $@ if $@;  logger('LOG',"MAIN-ACTION-ERROR",$@) if $@;
	logger('LOG',"MAIN-ACTION-RESULT","$Q{REQUEST_TYPE}:$Q{ACTION_STATUS}:$Q{ACTION_CODE}");
			return response('ERROR','ERROR','GENERAL ERROR #'.__LINE__) if $@;
			return "$Q{ACTION_RESULT}" if $Q{ACTION_STATUS};
}########## END SUB MAIN ########################################
#
########## XML_PARSE ############################################
sub XML_PARSE {
($Q{REQUEST_LINE},$Q{REQUEST_OPTION})=@_;
return 0 if $Q{REQUEST_LINE} eq '';
$Q{REQUEST_LINE}=~s/\r|\n|\t//g;
#************************************************************************
logger('LOG',"PARSE-REQUEST-LINE",$Q{REQUEST_LINE}) if $CONF{debug}>2;
eval {
	my $xml=new XML::Bare(text=>$Q{REQUEST_LINE});
	$Q{REQUEST}=$xml->parse();
		};warn $@ if $@; 
	return undef if $@;
	map {$Q{REQUEST}=$Q{REQUEST}->{$_} if $_=~/wire9|api|data|response|error/i} keys %{ $Q{REQUEST} };
	map {$Q{REQUEST}->{uc $_}=$Q{REQUEST}->{$_};} keys %{ $Q{REQUEST} };#switch root keys to UPPERCASE
#************************************************************************
switch ($Q{REQUEST_OPTION}){
# [XML] ************************************************************************
	case 'xml' {
		if(ref $Q{REQUEST}->{API_CMD} eq 'HASH'&& ref $Q{REQUEST}->{API_AUTH} eq 'HASH'){
		logger('LOG',"XML-PARSE-KEYS", join(',',sort keys %{ $Q{REQUEST}->{API_CMD}	})) if $CONF{debug}>2;
	map {$Q{uc $_}=$Q{REQUEST}->{API_CMD}{$_}{value} if $_!~/^_(i|z|pos)$/i;} keys %{ $Q{REQUEST}->{API_CMD} };
	map {$Q{uc $_}=$Q{REQUEST}->{API_AUTH}{$_}{value} if $_!~/^_(i|z|pos)$/i;} keys %{ $Q{REQUEST}->{API_AUTH} };
		$Q{REQUEST_TYPE}='API';
		$Q{PARSE_RESULT}=scalar keys %Q;
		}
# [DATA] ************************************************************************
		elsif(defined $Q{REQUEST}->{REFERENCE}{value} and $Q{REQUEST}->{REFERENCE}{value} eq 'Data'){
		logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}",'DATASESSION') if $CONF{debug}>2;
	map {$Q{uc $_}=$Q{REQUEST}->{$_} if $_!~/^_(i|z|pos)$/} keys %{ $Q{REQUEST} };
	map {$Q{uc $_}=$Q{REQUEST}->{callleg}{$_}{value} if $_!~/^_(i|z|pos)$/} keys %{ $Q{REQUEST}->{CALLLEG} };
		$Q{REQUEST_TYPE}='DATASESSION';
		$Q{TRANSACTIONID}=$Q{CALLLEGID};
		$Q{COST}=$Q{AGENTTOTALCOST}{amount}{value};
		$Q{CURRENCY}=$Q{AGENTTOTALCOST}{currency}{value};
		$Q{GIMSI} = scalar ($Q{IMSI}=$R->HGET('DID',$Q{NUMBER}))>0 ? $CONF{imsi_prefix}.$Q{IMSI} :0;
		$Q{PARSE_RESULT}=scalar keys %Q;
		}#elsif POSTDATA
# [UNKNOWN FORMAT] ************************************************************************
		else{#URL ENCODED REQUEST
		$Q{REQUEST_LINE}=~tr/\&/\;/;
		my %Q_tmp=split /[;=]/,$Q{REQUEST_LINE}; 
		map {$Q{uc $_}=uri_unescape($Q_tmp{$_})} keys %Q_tmp;
		$Q{MTC} = ($Q{MCC} ? $R->HGET('MTC',$Q{MCC}.int $Q{MNC}) : 0) if (defined $Q{CODE} and $Q{CODE} ne 'cdr') || ($Q{REQUEST_TYPE}=~/AUTH_CALLBACK_SIG|LU_CDR/i);
		$Q{REQUEST_TYPE}='PAY' if $Q{OPERATION_XML};
		$Q{REQUEST_TYPE}='PAYPAL' if $Q{BUSINESS}&&$Q{PAYMENT_STATUS} eq 'Completed';
		$Q{TRANSACTIONID}=$Q{CDR_ID} if $Q{REQUEST_TYPE}=~/msisdn_allocation/i;
		($Q{USSD_CODE},$Q{USSD_DEST},$Q{USSD_EXT})=
		uri_unescape($Q{CALLDESTINATION})=~/^\*(\d{3})[\*|\#](\D{0,}\d{0,}).?(.{0,}).?/ if $Q{CALLDESTINATION};
		$Q{USSD_EXT}=~s/\#//;
		# [USSD DIRECT CALL] ************************************************************************
			if (!$Q{USSD_CODE} && $Q{REQUEST_TYPE}=~/AUTH_CALLBACK_SIG/i){
				uri_unescape($Q{CALLDESTINATION})=~/^\*(\+|00)?(\d{7,14})\#/;
				$Q{USSD_DEST}=$2;
				$Q{USSD_CODE}=112;
			}#if !USSD_CODE
		$Q{PARSE_RESULT}=scalar keys %Q;
		}#else URL ENCODED
	$Q{IMSI}= $Q{IMSI} ? substr($Q{IMSI},-6,6) :0;
	$Q{GIMSI}= $Q{IMSI} ? $CONF{imsi_prefix}.$Q{IMSI} :0;
	$R->HMSET('DID',"$Q{GLOBALMSISDN}","$Q{IMSI}","$Q{IMSI}","$Q{GLOBALMSISDN}") if $Q{GLOBALMSISDN};
	$R->HSET('SUB:'.$Q{IMSI},'SUB_MNO',$Q{MCC}.int $Q{MNC}) if $Q{MCC}>0;
	}#xml
# [TEXT] ************************************************************************
	case /PLAINTEXT/ {
	$Q{PARSE_RESULT}=$Q{REQUEST_LINE};
	}#TEXT
# [GET MSRN] ************************************************************************
	case /get_msrn/ {
		map {$Q{uc $_}=$Q{REQUEST}->{MSRN_Response}{$_}{value} if $_!~/^_?(i|z|pos|imsi|value)$/i} keys %{ $Q{REQUEST}->{MSRN_Response} };
		$Q{ERROR}=$Q{REQUEST}->{Error_Message} ? $Q{REQUEST}->{Error_Message}{value} : 0;
		$Q{MSRN}=~s/\+//;
		logger('LOG',"XML-PARSED-$Q{REQUEST_OPTION}","$Q{MSRN} $Q{MCC} $Q{MNC} $Q{TADIG} $Q{IOT} $Q{IOT_CHARGE} $Q{ERROR}") if $CONF{debug}>3;
		$Q{PARSE_RESULT}=$Q{MSRN};
	}#msrn
# [PAY] ******************************************************************************
	case /pay/ {
		map {$Q{uc 'PAY_'.$_}=$Q{REQUEST}->{$_}{value} if $_!~/^_?(i|z|pos|imsi|value)$/i} keys %{ $Q{REQUEST} };
		$Q{PAY_ERROR}=length ($Q{PAY_CODE})>0 ? $Q{PAY_CODE} : 0;
		logger('LOG',"XML-PARSED-$Q{REQUEST_OPTION}-[order:tid:error]","$Q{PAY_ORDER_ID}:$Q{PAY_TRANSACTION_ID}:$Q{PAY_ERROR}") if $CONF{debug}>3;
		$Q{PARSE_RESULT}=$Q{PAY_ERROR};
	}#pay
# [SEND USSD] ************************************************************************
	case 'send_ussd' {
		$Q{STATUS}=$Q{REQUEST}->{USSD_Response}{REQUEST_STATUS}{value};
		$Q{ERROR}=$Q{REQUEST}->{Error_Message}{value};
		logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}","$Q{STATUS} $Q{ERROR}") if $CONF{debug}>2;
		$Q{PARSE_RESULT}="$Q{STATUS}$Q{ERROR}";
	}#ussd
# [SEND SMS MO/MT] ************************************************************************
	case /send_sms_m/ {
		$Q{STATUS}=$Q{REQUEST}->{SMS_Response}{REQUEST_STATUS}{value};
		$Q{ERROR}=$Q{REQUEST}->{Error_Message}{value};
		logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}","$Q{STATUS} $Q{ERROR}") if $CONF{debug}>2;
		$Q{PARSE_RESULT}="$Q{STATUS}$Q{ERROR}";
	}#sms
# [AGENT RESPONSE] ************************************************************************
	case /AGENT/ {
		$Q{RESULT}=$Q{REQUEST}->{RESPONSE}{value};
		$Q{ERROR}=$Q{REQUEST}->{ERROR_MESSAGE}{value};
		logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}","$Q{RESULT} $Q{ERROR}") if $CONF{debug}>2;
		$Q{PARSE_RESULT}="$Q{RESULT}$Q{ERROR}";
	}#AGENT
# [GET SESSION TIME] ************************************************************************
	case 'get_session_time' {
		my $TIME=$Q{REQUEST}->{RESPONSE}{value};
		our $ERROR=$Q{REQUEST}->{Error_Message}{value};
		logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}","$TIME $ERROR") if $CONF{debug}>2;
		$Q{PARSE_RESULT}="$ERROR$TIME";
	}#get time

# [VOIP USER INFO] ************************************************************************
	case 'voip_user_info' {
		my $BALANCE=$Q{REQUEST}{GetUserInfo}->{Balance}{value};
		our $ERROR=$Q{REQUEST}{GetUserInfo}->{Reason}{value};
		logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}","$BALANCE $ERROR") if $CONF{debug}>2;
		$Q{PARSE_RESULT}="$ERROR$BALANCE";
	}#get user info
# [VOIP USER BALANCE] ************************************************************************
	case 'voip_user_balance' {
		my $BALANCE=$Q{REQUEST}{Transaction}->{Result}{value};
		our $ERROR=$Q{REQUEST}{Transaction}->{Reason}{value};
		logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}","$BALANCE $ERROR") if $CONF{debug}>2;
		$Q{PARSE_RESULT}="$ERROR$BALANCE";
	}#set user balance
# [VOIP USER NEW] ************************************************************************
	case 'voip_user_new' {
		$Q{STATUS}= ref $Q{REQUEST}->{CreateAccount}{Result} eq 'ARRAY' ? $Q{REQUEST}->{CreateAccount}{Result}[0]{value} : $Q{REQUEST}->{CreateAccount}{Result}{value};
		my $ERROR= ref $Q{REQUEST}->{CreateAccount}{Reason} eq 'ARRAY' ? $Q{REQUEST}->{CreateAccount}{Reason}[1]{value} : $Q{REQUEST}->{CreateAccount}{Reason}{value};
		logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}","$Q{STATUS} $ERROR") if $CONF{debug}>2;
		$Q{PARSE_RESULT}="$Q{STATUS}$ERROR";
	}#new user
# [SIM INFO] ************************************************************************
	case /siminfo/i {
		$Q{PIN}=$Q{REQUEST}->{Sim}{Password}{value};
		our $ERROR=$Q{REQUEST}->{Error}{value};
		logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}","$Q{PIN} $ERROR") if $CONF{debug}>2;
		$Q{PARSE_RESULT}="$Q{PIN}$ERROR";
	}#sim info	
# [SET ISER] ************************************************************************
	case 'set_user' {
		 $Q{STATUS}=$Q{REQUEST}->{status}{value};
		 $Q{ERROR}=$Q{REQUEST}->{error}{value};
		logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}","$Q{STATUS} $Q{ERROR}") if $CONF{debug}>2;
		$Q{PARSE_RESULT}="$Q{STATUS}$Q{ERROR}";
	}#set user
# [SET USER STATUS] ************************************************************************
	case 'set_user_status' {
		$Q{STATUS}=$Q{REQUEST}->{STATUS_Response}{IMSI_STATUS}{value};
		$Q{ERROR}=$Q{REQUEST}->{Error_Message} ? $Q{REQUEST}->{Error_Message}{value} : undef;
		logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}","$Q{STATUS} $Q{ERROR}") if $CONF{debug}>2;
		$Q{PARSE_RESULT}="$Q{STATUS}$Q{ERROR}";
	}#set userstatus
# [ELSE SWITCH] ************************************************************************
	else {
		print logger('LOG',"XML-PARSE-RETURN-$Q{REQUEST_OPTION}",'NO OPTION FOUND $@') if $CONF{debug}>1;
		return "Error: $@";}
}#switch OPTION
return $Q{PARSE_RESULT};
}#END sub XML_PARSE
#
########## GET_SUB #############################################
sub GET_SUB {
my (%HASH, %CARD_HASH);
if ($Q{IMSI}&&$R->HLEN("SUB:$Q{IMSI}")>0){
	%HASH=$R->HGETALL("SUB:$Q{IMSI}");
	map {$Q{$_}=$HASH{$_}} keys %HASH;
	%CARD_HASH=$R->HGETALL("CARD:".$Q{SUB_CN});
	map {$Q{CARD_BALANCE_RESERVE}+=$CARD_HASH{$_} if $_=~/RESERVE/;$Q{$_}=sprintf '%.2f',$CARD_HASH{$_}} keys %CARD_HASH;
		$Q{CARD_BALANCE_AVAIL} = sprintf '%.2f',($Q{CARD_BALANCE}-$Q{CARD_BALANCE_RESERVE});
	return scalar %HASH;
}#if
else{ return 0 }#else
}########## END SUB GET_SUB ########################################
#
########## SQL ##################################################
sub SQL { 
use vars qw($dbh);
my $SQL=qq[$_[0]];
my $flag=$_[1] ? $_[1] : undef;
my ($rc, $sth, @result, $result);
#
@result=(); 
#
$dbh=DBI->connect('DBI:SQLite:msrn.db','','') if $dbh->ping==0;
#
if($SQL!~m/^[SELECT|CALL]/i){#INSERT/UPDATE request
	logger('LOG','SQL-GET',"DO $SQL $_[2] $_[3] $_[4]") if $CONF{debug}>3;
	$sth=$dbh->prepare($SQL);
$rc= defined $_[2] ? $sth->execute($_[2],$_[3],$_[4]) : $dbh->do($SQL); #result code
	#result code
	push @result,$rc;#result array
}#if SQL INSERT UPDATE
else{#SELECT request
logger('LOG','SQL-GET',"EXEC $SQL") if $CONF{debug}>3;
	$sth=$dbh->prepare($SQL);
	$rc=$sth->execute; #result code
	@result=$sth->fetchrow_array if $flag eq 'array';
	$result=$sth->fetchrow_hashref if $flag eq 'hash';
	$result=$sth->fetchall_arrayref if $flag eq 'ajax';
}#else SELECT
#
if($rc){#if result code
	logger('LOG','SQL-RETURNED-[code/array/hash]',"$rc/@result/$result") if $CONF{debug}>4;
	return \@result if $flag eq 'array';
	return  $result if $flag =~/hash|ajax/;
	return @result; 
}#if result code
else{#if no result code
	logger('LOG','SQL-RETURNED','Error: '.$dbh->errstr) if $CONF{debug}>1;
	return -1;
}#else MYSQL ERROR
}########## END SUB SQL	#########################################
#
############## SUB SPOOL ############################################################
sub SPOOL {
# [INTERNAL CALL] *******************************************************************
if (length($Q{USSD_DEST})==6 && $Q{IMSI}!~/^$Q{USSD_DEST}/){
	$Q{IMSIB}=$Q{USSD_DEST}; #set cardnumber for B
	$Q{SUB_B_BALANCE}=$R->HGET("CARD:".$R->HGET('SUB:'.$Q{USSD_DEST},'SUB_CN'),"CARD_BALANCE"); #get balance for B
return ('OFFLINE',-2,response('MOC_RESPONSE','XML',TEMPLATE('spool:offline'))) if $Q{SUB_B_BALANCE} < $CONF{balance_threshold};
# [RESET IMSI] *********************************************************************
	$Q{GIMSI}=$CONF{imsi_prefix}.$Q{IMSIB}; #set temp GIMSI for BILL insert
	$Q{CALLED}=$Q{IMSI}; #set callerid
	$Q{CALLING}=$Q{IMSIB}; #set CDR dst
	$Q{IMSI}=$Q{IMSIB}; #set imsi for GET_MSRN
# [GET INTERNAL MSRN] **************************************************************
$Q{USSD_DEST} = GET_MSRN(); #set USSD_DEST to msrn
return ('OFFLINE',-2,response('MOC_RESPONSE','XML',TEMPLATE('spool:offline'))) if $Q{USSD_DEST}!~/^(\+|00)?([1-9]\d{7,15})$/;
# [GET INTERNAL RATE] **************************************************************
CALL_RATE($Q{USSD_DEST},'MSRN'); #get MTC for B
# [SET INTERNAL VAR] ***************************************************************
	$Q{RATEIDB}=$Q{RATEID}; #set CDR rateidb for B
	$Q{MTCB}=$Q{MTC}; #set CDR mtcb for B
	$Q{CALL_B_LIMIT}=($Q{CALL_B_LIMIT}=floor(($Q{SUB_B_BALANCE}/$Q{RATE})*60))>$CONF{'max-call-time'} ? $CONF{'max-call-time'} : $Q{CALL_B_LIMIT};
	$CONF{'max-call-time'}=$Q{CALL_B_LIMIT}; #set max-call-time for B: takes minimal time for A and B
# [SET BACK IMSI] ******************************************************************
	$Q{GIMSI}=$Q{GLOBALIMSI}; #set back GIMSI
	$Q{IMSI}=substr($Q{GIMSI},-6,6); #set back IMSI
	$Q{MSRN}=undef; #undef msrn for next request
}#if INTERNAL
# [PROCESSING CALL] ****************************************************************
if ($Q{USSD_DEST}=~/^(\+|00)?([1-9]\d{7,15})$/){#if correct destination number - process imsi msrn
	$Q{MSRN}=$Q{USSD_EXT} if $Q{USSD_CODE}==128; #local number call
	$Q{MTC}=0 if $Q{USSD_CODE}==128; #local number call reset MTC
# [GET MSRN] ************************************************************************
	$Q{MSRN}=GET_MSRN() if not defined $Q{MSRN};
# [IF MSRN] *************************************************************************
if ($Q{MSRN}=~/\d{7,15}/){
	foreach my $type ('USSD_DEST','MSRN'){
		my %HASH=%{CALL_RATE($Q{$type},$type)};
		map {$Q{$type.'_'.uc($_)}=$HASH{$_}} keys %HASH;
	}#foreach number
# [ MSRN,c + MTC,c = RATEA,c ] ******************************************************
#		$Q{'MSRN_RATE'}=$Q{'MSRN_RATE'};
# [ RATEB,c*markup,% = RATEB,c ] ****************************************************
		$Q{'USSD_DEST_RATE'}=ceil($Q{'USSD_DEST_RATE'}*$CONF{'markup_rate'});
# [ CALL RATE ] *********************************************************************
		$Q{'CALL_RATE'}=($Q{'USSD_DEST_RATE'}+$Q{'MSRN_RATE'}+$Q{'MTC'})/100; #show user in $
# [ (CARD_BALANCE,$ / CALL_RATE,$) * 60 = CALL LIMIT,sec if limit > max_call_time -> max_call_time ] ***
		$Q{'CALL_LIMIT'}=($Q{'CALL_LIMIT'}=floor( ($Q{'CARD_BALANCE_AVAIL'}/$Q{'CALL_RATE'})*60))>$CONF{'max-call-time'} ? $CONF{'max-call-time'} : $Q{'CALL_LIMIT'};
		$Q{'CARD_BALANCE'}=sprintf '%.2f',$Q{'CARD_BALANCE'}; #format $0.2
		$Q{'CALL_RATE'}=sprintf '%.2f',$Q{'CALL_RATE'}; #format $0.2
		$R->HSET('CARD:'.$Q{SUB_CN},'CARD_BALANCE_RESERVE_'.$Q{IMSI}, abs($Q{'CALL_LIMIT'}*($Q{'CALL_RATE'}/60) ) );#balace reserve on limit*rate
		$Q{CALLED}=$Q{MSRN} if not defined $Q{CALLED}; #set callerid
		$Q{CALLING}=$Q{USSD_DEST} if not defined $Q{CALLING}; #set CDR dst
#***********************************************************************************
logger('LOG','SPOOL-GET-TRUNK-[dest/msrn/prefix/rate/limit]',"$Q{USSD_DEST_TRUNK}/$Q{MSRN_TRUNK}/$Q{'MSRN_PREFIX'}/$Q{CALL_RATE}/$Q{CALL_LIMIT}") if $CONF{debug}>2;
# [976967-139868] ******************************************************************
	$Q{UNID}=$Q{TID}.'-'.$Q{IMSI};
# [976967-139868-380507942751] *****************************************************
	$Q{CALLFILE}=$Q{UNID}.'-'.$Q{MSRN};
# [/tmp/976967-139868-380507942751] ************************************************
	my $CALL = IO::File->new("$CONF{tmpdir}/".$Q{CALLFILE}, "w");
	print $CALL TEMPLATE('spool:call');
	close $CALL;
		chown 100,101,"$CONF{tmpdir}/".$Q{CALLFILE};
		my $mv= $CONF{'fake-call'}==0 ? move("$CONF{'tmpdir'}/".$Q{CALLFILE}, "$CONF{'spooldir'}/".$Q{CALLFILE}) : $CONF{'fake-call'};
#***********************************************************************************
		return ("SPOOL-[move/uniqid/rate] $mv:$Q{UNID}:$Q{CALL_RATE}",$mv,response('MOC_RESPONSE','XML',TEMPLATE('spool:wait')));
	}#if msrn
	else{ return ('OFFLINE',-2,response('MOC_RESPONSE','XML',TEMPLATE('spool:offline'))) }#else not msrn and dest 
}#if dest
else{ return ('NO DEST',-3,response('MOC_RESPONSE','XML',TEMPLATE('spool:nodest'))) }#else dest	
}########## END SUB SPOOL ##############################################################
#
############# SUB USSD #########################
sub USSD {
use vars qw(%Q $R);
#
switch ($Q{USSD_CODE}){
# [SUPPORT] ************************************************************************
	case "000"{
		($Q{EMAIL_FROM},$Q{EMAIL_TO},$Q{EMAIL_SUBJ},$Q{EMAIL_BODY})=split(',',TEMPLATE('email:support'));			
			$Q{EMAIL_RESULT}=EMAIL();
	logger('LOG','USSD-SUPPORT-REQUEST',"$Q{USSD_CODE} $Q{EMAIL_RESULT}") if $CONF{debug}==4;
		return ('OK',1,response('MOC_RESPONSE','DEFAULT',"SUPPORT TICKET #$Q{TID} REGISTERED"));		
			}#case 000
# [MYNUMBER] ************************************************************************
	case "100"{
		logger('LOG','USSD-MYNUMBER-REQUEST',"$Q{USSD_CODE}") if $CONF{debug}==4;
		return ('OK',1,response('MOC_RESPONSE','XML',TEMPLATE("ussd:$Q{USSD_CODE}")));		
	}#case 100
# [IMEI] ************************************************************************
	case "110"{
		logger('LOG','USSD-IMEI-REQUEST',"$Q{USSD_DEST}") if $CONF{debug}==4;
		$R->HSET("SUB:$Q{IMSI}",'SUB_HANDSET',"$Q{USSD_DEST} $Q{USSD_EXT}");
		return ('OK',1,response('MOC_RESPONSE','XML',TEMPLATE("ussd:$Q{USSD_CODE}")));
	}#case 110
# [SMS] ************************************************************************
	case "122"{
		logger('LOG','USSD-SMS-REQUEST',"$Q{USSD_CODE} $Q{USSD_DEST}") if $CONF{debug}==4;
		my $SMS_result=SMS();#process sms
		BILL('SMS',$SIG{'SMS'}) if $SMS_result>0;
		logger('LOG','USSD-SMS-RESULT',"$SMS_result") if $CONF{debug}==4;
		return ('OK',$SMS_result, response('MOC_RESPONSE','XML',TEMPLATE('ussd:'.$Q{USSD_CODE}.$SMS_result)));
	}#case 122
# [BALANCE] ************************************************************************
	case [111,123,124]{
	logger('LOG','USSD-BALANCE-REQUEST',"$Q{USSD_CODE}") if $CONF{debug}>0;
if ($Q{USSD_DEST}>0) {#если трансфер
	if ( $Q{CARD_BALANCE}>($Q{COST}=$Q{USSD_DEST}) ) {#если баланс больше суммы трансфера
				if ($Q{USSD_EXT}>0) { #если указан саб назначения
					if (($Q{SUB_CN}=$R->HGET('SUB:'.$Q{USSD_EXT},'SUB_CN'))>0) {#если саб назначения существует
						if ($Q{USSD_CODE} eq "124") {#если код 124 тарифицируем свою карту и его инет
							$Q{GIMSI}=$CONF{imsi_prefix}.$Q{USSD_EXT};
								BILL('TRF',$Q{COST});#плюс кост ему инет
							$Q{SUB_CN}=$R->HGET('SUB:'.$Q{IMSI},'SUB_CN');
							$Q{GIMSI}=$CONF{imsi_prefix}.$Q{IMSI};
								BILL('BALANCE',$Q{COST});#минус кост себе карта
							#обнуляем кост для обычной тарификации
								return (  'OK',1,response('MOC_RESPONSE','XML',TEMPLATE("ussd:111_voucher_trf") ),undef $Q{COST}  );
						}else{#тарифицируем его и свою карту
							$Q{GIMSI}=$CONF{imsi_prefix}.$Q{USSD_EXT};
								BILL('PAY',$Q{COST});#пополняем его карту на кост
							$Q{SUB_CN}=$R->HGET('SUB:'.$Q{IMSI},'SUB_CN');
							$Q{GIMSI}=$CONF{imsi_prefix}.$Q{IMSI};
								BILL('BALANCE',$Q{COST});#минус кост себе
							#обнуляем кост для обычной тарификации
								return (  'OK',1,response('MOC_RESPONSE','XML',TEMPLATE("ussd:111_voucher_trf") ),undef);
						}#тарифицируем его и свою карту
					}else{#если саб назначения не существует
					$Q{SUB_CN}=$R->HGET('SUB:'.$Q{IMSI},'SUB_CN');
					return (  'OK',1,response('MOC_RESPONSE','XML',TEMPLATE("ussd:111_not_found") )  );
					}#возвращаем себя и отвечаем ошибкой
				}else{#если не указан саб назначения минус карта плюс инет
								BILL('BALANCE',$Q{COST});#минус кост себе карта
								BILL('TRF',$Q{COST});#плюс кост себе инет
				}#трансфер себе
	}elsif( $Q{COST}=$R->HGET('VOUCHER_CACHE',"$Q{USSD_DEST}") ) {#если баланс меньше суммы перевода проверяем ваучер
					if ($Q{USSD_EXT}>0) {#если определен саб назначения ваучера
						if ( ($Q{SUB_CN}=$R->HGET('SUB:'.$Q{USSD_EXT},'SUB_CN'))>0 ) { #если саб назначения существует
							if ($Q{USSD_CODE} eq "124") {#bill+Binet пополняем его инет
							$Q{GIMSI}=$CONF{imsi_prefix}.$Q{USSD_EXT};
								BILL('TRF',$Q{COST});#плюс кост ему инет
								$R->HDEL('VOUCHER_CACHE',"$Q{USSD_DEST}") ;#удаляем ваучер
								#обнуляем кост для обычной тарификации (получателя!)
									return (  'OK',1,response('MOC_RESPONSE','XML',TEMPLATE("ussd:111_voucher_trf") ),undef );
							}else{#bill+B пополняем его карту
									$Q{GIMSI}=$CONF{imsi_prefix}.$Q{USSD_EXT};
								BILL('PAY',$Q{COST});#пополняем его карту на кост
									$R->HDEL('VOUCHER_CACHE',"$Q{USSD_DEST}");#удаляем ваучер
								#обнуляем кост для обычной тарификации (получателя!)
									return (  'OK',1,response('MOC_RESPONSE','XML',TEMPLATE("ussd:111_voucher_trf") ), undef );
								}#пополняем его карту
						}else{#если саб назначения не существует отвечаем ошибкой
								$Q{SUB_CN}=$R->HGET('SUB:'.$Q{IMSI},'SUB_CN');#вернем себя для тарификации
									return (  'OK',1,response('MOC_RESPONSE','XML',TEMPLATE("ussd:111_not_found") )  );
							}#отказ с уведомлением
					}elsif($Q{USSD_CODE} eq "124") {#bill+Ainet пополняем только свой инет
						$Q{SUB_CN}=$R->HGET('SUB:'.$Q{IMSI},'SUB_CN');#вернем себя для тарификации
							BILL('TRF',$Q{COST});#пополняем инет на кост
								$R->HDEL('VOUCHER_CACHE',"$Q{USSD_DEST}") ;#удаляем ваучер
					}else{#bill+A пополняем только себя
						$Q{SUB_CN}=$R->HGET('SUB:'.$Q{IMSI},'SUB_CN');#вернем себя для тарификации
							BILL('PAY',$Q{COST});#пополняем карту на кост
								$R->HDEL('VOUCHER_CACHE',"$Q{USSD_DEST}") ;#удаляем ваучер
					}#пополняем только себя
	}else{ 	
				return (  'OK',1,response('MOC_RESPONSE','XML',TEMPLATE("ussd:111_no_balance") )  ) if $Q{USSD_DEST}=~/^\d{1,2}$/;
				return (  'OK',1,response('MOC_RESPONSE','XML',TEMPLATE("ussd:voucher_error") )  );
				}#если ваучера нет возвращаем ошибку
}else{ 	
			return (  'OK',1,response('MOC_RESPONSE','XML',TEMPLATE("ussd:111") )  ) 
	}#если не трансфер возвращаем текущий баланс
#
		return ('OK',1,response('MOC_RESPONSE','XML',TEMPLATE("ussd:111")));
	}#case 111
# [VOIP] ************************************************************************
	case "x125"{
	$Q{SUB_PIN} ? return ('OK',1,response('MOC_RESPONSE','DEFAULT','LOGIN:sim'.$Q{SUB_CN}.'*'.$CONF{voip_domain}.' PIN:'.$Q{SUB_PIN}.TEMPLATE('voip:user_help'))) : return ('WARNING',1,response('MOC_RESPONSE','DEFAULT','NEED TO SET NEW PIN. CALL *000*5#'));
	}#case 125
# [CALL RATE] ************************************************************************
	case "x126"{
	$Q{INCOMING_RATE}=sprintf '%.2f',${CALL_RATE($Q{USSD_DEST})}{RATE}/100;
	$Q{OUTGOING_RATE}=sprintf '%.2f',$Q{INCOMING_RATE}+$R->HGET('RATE_CACHE:'.$Q{MCC}.$Q{MNC},'RATE')/100*$CONF{'markup_rate'};
	$Q{USSD_DEST}=~/^(\+|00)?([1-9]\d{1,15})$/ ? return ('OK',1,response('MOC_RESPONSE','DEFAULT',TEMPLATE('ussd:126:rate'))) : return ('NO DEST',1,response('MOC_RESPONSE','DEFAULT',TEMPLATE('ussd:126:nodest')));
	}#case 126
# [CALLERID] ************************************************************************
	case "127"{
		logger('LOG','USSD-CID-REQUEST',"$Q{USSD_CODE} $Q{USSD_DEST}") if $CONF{debug}>0;
		if ($Q{USSD_DEST}=~/^(\+|00)?($CONF{country_code}\d{6,15})$/){#if prefix +|00 country code and number length 7-15 digits
			logger('LOG','SIG-USSD-CID-REQUEST',"$Q{USSD_DEST}") if $CONF{debug}>0;
				 $Q{SMS_TO}=$2; $Q{MESSAGE}=int(rand(10000))+10000;#sms_to and code
					 $R->HSET('CID:'.$Q{IMSI}, $Q{MESSAGE}, $Q{USSD_DEST});#code
					 $R->EXPIRE('CID:'.$Q{IMSI}, $CONF{html_session_expire}/4 );#15 min for code
						 logger('LOG','USSD-CID-CURL',TEMPLATE('api:send_sms_mo'));
#						 CURL('send_sms_mo',TEMPLATE('api:send_sms_mo'),$CONF{api2});#send code
#						 BILL('SMS');#bill sms
					return ('OK',1,response('MOC_RESPONSE','XML',TEMPLATE("ussd:$Q{USSD_CODE}") ) );
			}#if number length
			else{#else check code
			logger('LOG','SIG-USSD-CID-REQUEST',$Q{USSD_DEST}) if $CONF{debug}>0;			
			 $Q{SUB_NEW_DID}=$R->HGET('CID:'.$Q{IMSI}, "$Q{USSD_DEST}");
			 $R->HSET('SUB:'.$Q{IMSI},'SUB_DID', $Q{SUB_NEW_DID} ? $Q{SUB_NEW_DID} : $Q{SUB_DID});
			return ('OK',1,response( 'MOC_RESPONSE','XML',TEMPLATE("ussd:".$Q{USSD_CODE}. ($Q{SUB_NEW_DID} ? ':1' : ':0') ) ) );
			}#else code
	}#case 127
# [LOCAL CALL] ************************************************************************
	case "128"{
		logger('LOG','LOCAL-CALL-REQUEST',"$Q{USSD_CODE}") if $CONF{debug}==4;
	#	$Q{SPOOL_RESULT}=SPOOL() if $Q{USSD_EXT};
		$Q{USSD_EXT}=~/^(\+|00)?([1-9]\d{7,15})$/ ? return (SPOOL()) : return ('OK',1,response('MOC_RESPONSE','XML',TEMPLATE("ussd:128")));
	}#case 128
# [GUI PIN] ***************************************************************************
	case "129"{
		logger('LOG','GUI-PIN-REQUEST',"$Q{USSD_CODE} $Q{USSD_DEST} $Q{USSD_EXT}") if $CONF{debug}==4;
			$Q{GUI_PIN}=CURL('SimInformationByMSISDN',XML('SimInformationByMSISDN'),$CONF{api1});
			$R->HMSET('AGENT:'."$Q{SUB_CN}"*"$Q{GUI_PIN}", 'name', $Q{SUB_CN}, 'gui', 1, $Q{GUI_PIN}, 1) if $Q{GUI_PIN}=~/^\d{4}$/;
			return ('OK',1,response('MOC_RESPONSE','XML',TEMPLATE("ussd:$Q{USSD_CODE}")));
	}#case 129
# [ELSE SWITCH] ************************************************************************
	else{
	return ('OK',1,response('MOC_RESPONSE','XML',TEMPLATE('ussd:default')));		
	}#end else switch ussd code (no code defined)
}#end switch ussd code
}## END SUB USSD ###################################
#
########### CURL #############################################
sub CURL {
($Q{MSG},$Q{DATA},$Q{API})=@_;
#************************************************************************
my %HASH=$R->HGETALL('AGENT:'.$Q{API});
defined $HASH{auth} ? $Q{DATA}=$Q{DATA}.'&'.$HASH{auth} : undef;
$Q{HOST}=$HASH{host};
#********************************************************************************
logger('LOG',"API-CURL-$Q{MSG}-PARAMS","$Q{HOST} $Q{DATA}") if $CONF{debug}>3;
# [CURL OPTIONS] *****************************************************************
our $response_body='';
our $curl = Net::Curl::Easy->new();
$curl->setopt (CURLOPT_SSL_VERIFYHOST, 0);
$curl->setopt( CURLOPT_SSL_VERIFYPEER, 0);
$curl->setopt( CURLOPT_POSTFIELDS, $Q{DATA});
$curl->setopt( CURLOPT_POSTFIELDSIZE, length($Q{DATA}));
$curl->setopt( CURLOPT_POST, 1);
$curl->setopt( CURLOPT_CONNECTTIMEOUT,5);
$curl->setopt( CURLOPT_HEADER, 0);
$curl->setopt( CURLOPT_URL, $Q{HOST});
$curl->setopt( CURLOPT_WRITEDATA, \$response_body);
#*******************************************************************************
if ($Q{DATA}){
eval {use vars qw($curl $response_body %Q); logger('LOG',"API-CURL-$Q{MSG}-REQ",$Q{HOST}.' '.length($Q{DATA})) if $CONF{debug}==4;
my $retcode = $curl->perform;
my $response_code = $curl->getinfo(CURLINFO_HTTP_CODE) if $retcode==0;
logger('LOG',"API-CURL-ERROR-BUF",$curl->strerror($retcode)) if $retcode!=0;
$Q{CURL_ERROR}= $retcode ? $curl->strerror($retcode) : 0; 
};warn $@ if $@;  logger('LOG',"API-CURL-ERROR","$@") if $@;
}#if DATA
else{return ('NO URI',0)}#else URI empty
#*******************************************************************************
use vars qw($response_body);
if ($response_body){
	logger('LOG',"$Q{MSG}-RESPOND","$response_body") if $CONF{debug}==4;
	$Q{CURL_RESULT}=&XML_PARSE("$response_body",$Q{MSG});
	return ('OK',$Q{CURL_ERROR},$Q{CURL_RESULT});
}#if CURL return
else{# timeout
	logger('LOG',"CURL-$Q{MSG}-REQUEST","Socket Timed Out") if $CONF{debug}>1;
	return ('TIMEOUT',0);
}#end else
}########## END sub CURL ####################################
#
sub GET_MSRN {
return $R->GET('MSRN_CACHE:'.$Q{IMSI}) if $R->EXISTS('MSRN_CACHE:'.$Q{IMSI});
	$Q{MSRN_TYPE} = $_[0] ? $_[0] : 'get_msrn';
		$R->SETNX("STAT:AGENT:$Q{REMOTE_ADDR}:".substr($Q{TIMESTAMP},0,13).":$Q{MSRN_TYPE}","$CONF{api_threshold}");
		$R->DECR("STAT:AGENT:$Q{REMOTE_ADDR}:".substr($Q{TIMESTAMP},0,13).":$Q{MSRN_TYPE}")>0 ? undef : return ('ERROR',-1,response('api_response','ERROR',"API $Q{MSRN_TYPE} THRESHOLD REACHED"));	
	(my $status,my $code, $Q{MSRN})=CURL('get_msrn',TEMPLATE('api:'.$Q{MSRN_TYPE}),$CONF{api2});
	($Q{IOT}==1 and $Q{MCC}>0) ? $R->HSET('MTC',"$Q{MCC}".int $Q{MNC}, (sprintf '%.2f',"$Q{IOT_CHARGE}")*100) : undef;
	$Q{MTC} = $Q{MCC}>0 ? $R->HGET('MTC',$Q{MCC}.int $Q{MNC}) : $Q{SUB_MNO}>0 ? $R->HGET('MTC',$Q{SUB_MNO}) : 0;
	$Q{MSRN}=~/\d{7,15}/ ? $R->SETEX('MSRN_CACHE:'.$Q{IMSI},10,$Q{MSRN}) : $R->SETEX('MSRN_CACHE:'.$Q{IMSI},300,'OFFLINE');
	CALL_RATE($Q{MSRN},'MSRN') if $Q{MSRN} ne 'OFFLINE';
	BILL('MSRN');
	return $Q{MSRN};
}## END SUB GET_MSRN ####
#
##### AGENT ################################################
sub AGENT {
	AUTH($Q{REMOTE_ADDR}) ? undef : return ('NO AUTH',-1,response('api_response','ERROR',"NO AUTH"));
my	%RESPONSE_TYPE=('auth_callback_sig'=>'MOC_RESPONSE','DataAUTH'=>'RESPONSE','LU_CDR'=>'CDR_RESPONSE','OutboundAUTH'=>'MOC_RESPONSE');	
my  %REQUEST_NAME=('112'=>'CB','000'=>'SUPPORT','110'=>'IMEI','122'=>'SMS','123'=>'BALANCE','111'=>'BALANCE',);
my $response_type= $RESPONSE_TYPE{$Q{REQUEST_TYPE}} ? $RESPONSE_TYPE{$Q{REQUEST_TYPE}} : 0;
my $response_options= $RESPONSE_TYPE{$Q{REQUEST_TYPE}} ? 'XML' : 'HTML';
#************************************************************************
	$Q{REQUEST_TYPE}='USSD' if $Q{REQUEST_TYPE} eq 'auth_callback_sig';#unknown USSD CODES set as USSD
	$Q{REQUEST_TYPE}=$REQUEST_NAME{$Q{USSD_CODE}} if $REQUEST_NAME{$Q{USSD_CODE}}; #well-known USSD CODES name for 100 110 111 112 122 123 125 126
	$Q{USSD_DEST}=$Q{DESTINATION} if $Q{REQUEST_TYPE} eq 'OutboundAUTH';#OutboundAUTH send us DESTINATION parameter
	$Q{REQUEST_TYPE}='CB' if $Q{REQUEST_TYPE} eq 'OutboundAUTH';# OutboundAUTH set as CB
	$Q{TRANSACTIONID}=$Q{SESSIONID} if $Q{SESSIONID};#DataAuth SESSIONID= DataSession CALLLEGID
#************************************************************************
		$Q{USSD_DEST}=$Q{DESTINATION}=uri_escape($Q{CALLDESTINATION}) if $Q{REQUEST_TYPE} eq 'USSD';
		$Q{IMEI}=$Q{DESTINATION}=uri_escape($Q{USSD_DEST}) if $Q{REQUEST_TYPE}=~/(CB|IMEI)/;#set destination parameter for CB or IMEI
		($Q{IMEI}, undef)=split / /,$Q{SUB_HANDSET} if $Q{REQUEST_TYPE}=~/CB/;#set IMEI if SUB_HANDSET
		($Q{PAGE},$Q{PAGES},$Q{SEQ})=split(undef,$Q{USSD_DEST}) if $Q{REQUEST_TYPE} eq 'SMS'; 
		($Q{DESTINATION},$Q{MESSAGE})=split('\*',uri_unescape($Q{USSD_EXT})) if $Q{REQUEST_TYPE} eq 'SMS';
		$Q{MESSAGE}=~s/\#// if $Q{REQUEST_TYPE} eq 'SMS';
		$Q{DATA_RATE} = $R->HGET('DATA',$Q{MCC}.int $Q{MNC});
#************************************************************************
	$Q{AGENT_URI}= $Q{CALLLEGID} ? TEMPLATE('api:agent').TEMPLATE('api:datasession') : $Q{TOTALCURRENTBYTELIMIT} ? TEMPLATE('api:agent').TEMPLATE('api:dataauth') : $Q{MESSAGE} ? TEMPLATE('api:agent').TEMPLATE('api:smslite') : TEMPLATE('api:agent') ;
	$Q{AGENT_URI}=XML() if $R->HEXISTS('AGENT:'.$Q{SUB_HASH},'xml');#set response_options xml
my ($status, $code, $result)=CURL('AGENT',$Q{AGENT_URI},$Q{SUB_HASH});
#************************************************************************
	defined $Q{ERROR} ? $response_options='ERROR' : undef;
return ($status, 1, response($response_type,$response_options,$result));
}# END SUB AGENT
##################################################################
#
### SUB AUTH ########################################################
sub AUTH {
# [SIG ONLY] ****************************************************************************
$_[0] ? return $R->SISMEMBER('ACCESS_LIST',"$_[0]") : undef;
# [INDEX or AJAX] ************************************************************************
return 2 if $R->EXPIRE('SESSION:'."$Q{SESSION}".':'.$Q{REMOTE_ADDR},$CONF{html_session_expire});
#************************************************************************
	$Q{TOKEN} ? undef : return -1;
	my	$md5 = Digest::MD5->new;
	$md5->add( pack( "C4", split /\./, $Q{REMOTE_ADDR} ), $Q{TOKEN});
	$Q{DIGEST} = $md5->hexdigest;
	$md5->add( pack( "C4", split /\./, $Q{REMOTE_ADDR} ), $Q{TOKEN}, $Q{INNER_TID});
logger('LOG',"API-AUTH-DIGEST","$Q{REMOTE_ADDR} $Q{DIGEST} $Q{REQUEST_TYPE}") if $CONF{debug}>1;
# [API REQUEST] ************************************************************************
return $R->SISMEMBER('ACCESS_LIST',"$Q{DIGEST}") if $Q{REQUEST_TYPE}=~/API/i;
# [TIMEOUT or NEW SESSION] ************************************************************************
	$Q{TOKEN_PIN} = $Q{PIN} ? "$Q{TOKEN}"*"$Q{PIN}" : $Q{TOKEN};
	$Q{TOKEN_NAME} = $R->HGET('AGENT:'.$Q{TOKEN_PIN},'name') ? $Q{DIGEST}=$md5->hexdigest : return -1;
$R->SETEX('SESSION:'.$Q{DIGEST}.':'.$Q{REMOTE_ADDR},$CONF{html_session_expire},$Q{TOKEN}) ? $Q{SESSION}=$Q{DIGEST} : return -1;
# [REDIRECT] ************************************************************************
return 1;
}#END SUB AUTH ##################################################################
#
########################### PAY #################################################
sub PAY {
$Q{PAY_SERVER}=$CONF{pay_server}; $Q{PAY_AMOUNT}= $CONF{'pay_amount_'.$Q{PAY_AMOUNT}}>0 ? $CONF{'pay_amount_'.$Q{PAY_AMOUNT}} : $CONF{pay_amount}; $Q{PAY_CURRENCY}=$CONF{pay_currency}; $Q{PAY_WAY}=$CONF{pay_way};
# [OUTGOING]**********************************************************************
if ($Q{PAYTAG}){
scalar ($Q{SUB_CN}=$R->HGET('SUB:'.$Q{PAYTAG},'SUB_CN')) ? $Q{XML}=TEMPLATE('html:pay_ua') : return 0;
$Q{PAYMENT}={ sign=>encode_base64(sha1($CONF{msign}.$Q{XML}.$CONF{msign}),''), xml=>encode_base64($Q{XML},'') };
logger('LOG','PAY-OUT-XML',"$Q{XML}") if $CONF{debug}>3;
$R->SETEX('PAY_CACHE:'.$Q{INNER_TID},86400,"$Q{PAYTAG}") ? return 1 : return 0;}
# [INCOMING]**********************************************************************
$Q{XML_DECODE}=decode_base64($Q{OPERATION_XML}); $Q{PAY_SIGN}=encode_base64(sha1($CONF{msign}.$Q{XML_DECODE}.$CONF{msign})); chop $Q{PAY_SIGN};
$Q{SIGNATURE} eq $Q{PAY_SIGN} ? XML_PARSE($Q{XML_DECODE},'pay') : return ('NO AUTH',-1,response('api_response','ERROR',"PAYMENT SIGNATURE REJECTED #".__LINE__));
# [PAY_ORDER_ID]******************************************************************
scalar ( $Q{PAY_TAG}=$R->GET('PAY_CACHE:'.$Q{PAY_ORDER_ID}) ) ? undef : 
	return ('UNKNOWN PAYMENT',0,response('api_response','HTML',TEMPLATE('html:pay_unknown')));
#[REMOTE_ADDR]*******************************************************************
AUTH('PAY:'.$Q{REMOTE_ADDR})&&($Q{PAY_STATUS}=~/success/) ? undef : 
	return ( 'PAYMENT CONFIRMATION',0,response('api_response','HTML',TEMPLATE('html:pay_'.$Q{PAY_STATUS})) );
#[PROCESSING]********************************************************************
$Q{PAY_STATUS}=~/success/ ? $Q{PAY_RESULT}=BILL( 'PAY',$Q{PAY_AMOUNT}*$CONF{pay_exchange},
							$Q{PAY_ORDER_ID},
							$Q{GIMSI}=$CONF{imsi_prefix}.$Q{PAY_TAG},
							$Q{IMSI}=$Q{PAY_TAG},
							$R->DEL('PAY_CACHE:'.$Q{PAY_ORDER_ID}) ) : undef;
#[RESULT]***********************************************************************
map{$R->HMSET('PAY_DONE:'.$Q{PAY_ORDER_ID},"$_","$Q{$_}") if $_=~/^PAY_/} keys %Q;
	($Q{EMAIL_FROM},$Q{EMAIL_TO},$Q{EMAIL_SUBJ})=split(',',TEMPLATE('email:pay')); EMAIL();
logger('LOG','PAY-PROCESSING-PAYMENT',"$Q{XML_DECODE}");
return('OK',0,response('api_response','XML',"PAYMENT $Q{PAY_ORDER_ID} PROCESSED"));
}#END SUB PAY
#
########################### PAYPAL section #######################################
sub PAYPAL {
	$Q{REQUEST_LINE}=~tr/\;/\&/;
	if ((CURL('PLAINTEXT', $Q{REQUEST_LINE}.'&cmd=_notify-validate', $CONF{api_paypal}) eq 'VERIFIED')&&($R->SISMEMBER('PAYPAL_PEYMENTS',"$Q{TXN_ID}") == 0)){
		$Q{VOUCHER_CODE}=int(rand(10000000000))+1000000000;
			$R->HSET('VOUCHER_CACHE', "$Q{VOUCHER_CODE}", "$Q{MC_GROSS}");
			($Q{EMAIL_FROM},$Q{EMAIL_TO},$Q{EMAIL_CC},$Q{EMAIL_SUBJ},$Q{EMAIL_BODY})=split(',',TEMPLATE('email:paypal'));
				$Q{EMAIL_RESULT}=EMAIL();
				$R->SADD('PAYPAL_PEYMENTS',"$Q{TXN_ID}");
		}#if VERIFIED
	logger('LOG','PAYPAL-RESULT',"$Q{VOUCHER_CODE} $Q{MC_GROSS} $Q{EMAIL_RESULT}") if $CONF{debug}>0;
return ('PayPal', 0, response('PayPal','HTML',"$Q{EMAIL_RESULT}"));
}#PAYPAL
## END SUB PAYPAL ##################################################################		
#
### SUB EMAIL #########################################################
sub EMAIL {
	my $email = Email::Simple->create(
      header => [
        From    => "$Q{EMAIL_FROM}",
        To      => "$Q{EMAIL_TO}",
		BCC      => "$Q{EMAIL_CC}",
        Subject => "$Q{EMAIL_SUBJ}", ],
 		     body => "$Q{EMAIL_BODY}",);
#
my $result = send SMTP => $email, 'localhost';
return $result;
}## END SUB EMAIL ####################################################
#
### SUB XML #########################################################
sub XML {
use vars qw(%Q $R);
my $func=$_[0];
my %HASH;
#************************************************************************
$HASH{$func}=(
	{
		IMSI=>{value=>$Q{GIMSI}},
		Authentication=>{
			Username=>{value=>$R->HGET('AGENT:'.$CONF{api1},'username')},
			Password=>{value=>$R->HGET('AGENT:'.$CONF{api1},'password')},
		}
	}) if $func;
#************************************************************************
return XML::Bare->xml(\%HASH) if $func;#to C4
#************************************************************************
$Q{IMSI}=$Q{GIMSI};
map { $HASH{api}{api_request}{$_}={ value=>$Q{$_} } if defined $Q{$_}}  @{ $R->SMEMBERS('REQUEST:'.uc $Q{REQUEST_TYPE}) };
#************************************************************************
$HASH{api}{api_auth}{auth_key}={ value=>$R->HGET('AGENT:'.$Q{SUB_HASH},'auth') };
#************************************************************************
return XML::Bare->xml(\%HASH);#to agent
}#END SUB XML
#
### SUB TEMPLATE #########################################################
##
sub TEMPLATE {
use vars qw($R);
my $template = Text::Template->new(TYPE => 'STRING',SOURCE => pack( "H*",$R->HGET('TEMPLATE',$_[0]) )  );
my $text = $template->fill_in(HASH=>\%Q);
return $text;
}#END SUB TEMPLATE
##
### SUB BILL #########################################################
sub BILL {
$Q{TYPE}=uc $_[0];
return 0 if $Q{TYPE} eq 'NULL';
$Q{INNER_TID} = $_[2] if defined $_[2];
$Q{SUB_CN} = defined $Q{SUB_CN} ? $Q{SUB_CN} : $R->HGET('SUB:'.$Q{IMSI},'SUB_CN');
$Q{USSD} = defined $Q{USSD_CODE} ? $Q{USSD_CODE} : 0;
$Q{USSD_NAME} = ($SIG{$Q{USSD}.':name'}) ? uc $SIG{$Q{USSD}.':name'} : $Q{TYPE};
$Q{COST}= defined $_[1] ? abs($_[1]) : $SIG{$Q{USSD}} ? abs($SIG{$Q{USSD}}) : $SIG{$Q{TYPE}} ? abs($SIG{$Q{TYPE}}) : 0;
$Q{BALANCE_TYPE} = $Q{TYPE}=~/DATASESSION|TRF/ ? 'INET_BALANCE' : 'CARD_BALANCE';
logger('LOG','BILLING:[BALANCE|TYPE|NAME|USSD|COST]',"$Q{BALANCE_TYPE}:$Q{TYPE}:$Q{USSD_NAME}:$Q{USSD}:$Q{COST}") if $CONF{debug}>2;
$Q{"$Q{BALANCE_TYPE}"}=$Q{SUB_NEW_BALANCE}=sprintf '%.2f',$R->HINCRBYFLOAT('CARD:'.$Q{SUB_CN},"$Q{BALANCE_TYPE}", ($Q{TYPE}=~/PAY|TRF/ ? abs($Q{COST}) : abs($Q{COST})*-1 ) );
return (SQL(TEMPLATE('sql:bill')) ) if defined $Q{GIMSI};
}## END SUB BILL
#
### SUB CALL_RATE #####################################################
sub CALL_RATE {	
use vars qw($R);
$Q{MSISDN}=$_[0];
#my $cache;
my %HASH = scalar keys %{$Q{CACHE}={$R->HGETALL('RATE_CACHE:'.substr($Q{MSISDN},0,$CONF{'rate_cache_len'}))}} ? %{$Q{CACHE}} : %{ SQL(TEMPLATE('sql:get_rate'),'hash') };
#************************************************************************
if (!scalar keys %{$Q{CACHE}}){
	$R->HSET('RATE_CACHE:'.substr($Q{MSISDN},0,$CONF{'rate_cache_len'}),$_,$HASH{$_}, sub{}) for keys %HASH;
	$R->wait_one_response;
	$R->EXPIRE('RATE_CACHE:'.substr($Q{MSISDN},0,$CONF{'rate_cache_len'}),defined $CONF{'rate_cache_ttl'} ? $CONF{'rate_cache_ttl'} :86400 );
	}#if cache
	$R->HSET('RATE_CACHE:'.$Q{MCC}.$Q{MNC},'RATE',$HASH{RATE}) if $_[1];
#************************************************************************
map {$Q{$_}=$HASH{$_}} keys %HASH; #map for DID call
	$Q{'CALL_RATE'}=($HASH{'RATE'}*$CONF{'markup_rate'}+$Q{MTC})/100; #notation 1.2
	$Q{'CALL_LIMIT'}=($Q{'CALL_LIMIT'}=floor(($Q{'CARD_BALANCE_AVAIL'})/$Q{'CALL_RATE'})*60)>$CONF{'max-call-time'} ? $CONF{'max-call-time'} : $Q{'CALL_LIMIT'}; #notation seconds
#************************************************************************
logger('LOG','CALL_RATE-[rate|limit|mtc]:',"$Q{'CALL_RATE'}:$Q{'CALL_LIMIT'}:$Q{MTC}") if $CONF{debug}>2;
return \%HASH;# return for SPOOL
}## END SUB CALL_RATE
#
########## RESPONSE #############################################
sub response {
#use vars qw($t0 $R);
$Q{TRANSACTION_ID}=$Q{TRANSACTIONID};
my ($ACTION_TYPE, $RESPONSE_TYPE, $RESPONSE, $SUB_RESPONSE)=@_;
my $HEAD=qq[Content-Type: text/xml\n\n<?xml version="1.0" ?>];
#
switch ($RESPONSE_TYPE){
	case 'XML'{
		$Q{USSDMESSAGETOHANDSET}=$Q{CDR_STATUS}=$Q{ALLOW}=$Q{DISPLAY_MESSAGE}=$RESPONSE;
		$Q{USSDMESSAGETOHANDSET}=$SUB_RESPONSE if $SUB_RESPONSE;
		my %HASH;
	map { $HASH{uc $ACTION_TYPE}{$_}={value=>$Q{$_}} if defined $Q{$_} } @{$R->SMEMBERS('RESPONSE:'.uc $ACTION_TYPE)};
		return $HEAD.XML::Bare->xml(\%HASH);
	}#case XML
	case 'ERROR'{
	my	$ERROR=qq[<Error><Error_Message>$RESPONSE</Error_Message></Error>\n];
		return $HEAD.$ERROR;
	}#case ERROR
	case 'DEFAULT'{
	my	$ERROR=qq[<MOC_RESPONSE><TRANSACTION_ID>$Q{TRANSACTIONID}</TRANSACTION_ID><DISPLAY_MESSAGE>$RESPONSE</DISPLAY_MESSAGE></MOC_RESPONSE>\n];
		return $HEAD.$ERROR;
	}#case DEFAULT
	case 'JS'{
		$HEAD=qq[Content-Type: application/javascript\n\n];
		return $HEAD.$RESPONSE;
	}#case JS
	case 'HTML'{
		$HEAD=qq[Content-Type: text/html\n\n];
		return $HEAD.$RESPONSE;
	}#case HTML
	case 'JSON'{
		$HEAD="Content-Type: text/html\n\n";
		return $HEAD.encode_json $RESPONSE;
	}#case JSON
}#switch
}########## RESPONSE #############################################
########## LOGGER ##############################################
sub logger {
#use vars qw($t0);
my $t3=Benchmark->new;
my $td1=timediff($t3, $t0);
my $timer=substr($td1->[0],0,8);
my $now=strftime("%Y-%m-%d %H:%M:%S", localtime);
##
my ($LOG_TYPE,$RESPONSE_TYPE,$LOG,$STATUS,$INFO)=@_;
#
switch ($LOG_TYPE){
case 'LOG'{
	$R->RPUSH('LOG:'.$Q{INNER_TID},"[$now]-[$timer]-[API-LOG-$RESPONSE_TYPE]:$LOG") if $CONF{debug}>0;
	}#case LOG
case 'LOGEXPIRE'{
	$R->EXPIRE('LOG:'.$Q{INNER_TID},$CONF{logexpire});
	}#case LOGEX
}#switch
}########## END sub logger ######################################
#
### SUB SMS ########################################################################
sub SMS{
logger('LOG','SMS-REQ',"$Q{USSD_DEST} $Q{USSD_EXT}") if $CONF{debug}==3;
#
($Q{PAGE},$Q{PAGES},$Q{SEQ})=split(undef,$Q{USSD_DEST}); 
($Q{SMS_TO},$Q{MESSAGE})=split('\*',uri_unescape($Q{USSD_EXT}));
($Q{SMS_PREFIX},$Q{SMS_TO})=$Q{SMS_TO}=~/^(\D|00)?([1-9]\d{5,12})/;
$Q{SMS_TO}=$R->HGET('DID',$Q{SMS_TO}) if length($Q{SMS_TO})==6;
return 3 if length($Q{SMS_TO})<6;
#************************************************************************
	my	$md5 = Digest::MD5->new;
	$md5->add( $Q{GIMSI}, $Q{SMS_TO}, $Q{PAGES}, $Q{SEQ} );
	$Q{DIGEST} = $md5->hexdigest;
#************************************************************************
$R->RPUSH('SMS:'.$Q{DIGEST}, "$Q{MESSAGE}");
$R->EXPIRE('SMS:'.$Q{DIGEST}, 60);
$R->SETEX("MO_SMS:%2B".$Q{SMS_TO},60,"$Q{DIGEST}");
$Q{MESSAGE}=uri_escape( substr( decode('ucs2',pack("H*",join('',$R->LRANGE('SMS:'.$Q{DIGEST},0,-1)))) ,0,168) );
#
return (CURL('send_sms_mo',TEMPLATE('api:send_sms_mo'),$CONF{api2})) if $Q{PAGE}==$Q{PAGES};
return 2;
#my @multi_sms=($sms_long_text=~/.{1,168}/gs);#divide long text to 168 parts
}# END sub USSD_SMS #############################################################
#
##### API #######################################################################
sub API {
if (AUTH()>0){logger('LOG','API',"AUTH OK")}#if auth
elsif($R->EXISTS('SESSION:'.$Q{SESSION}.':'.$Q{REMOTE_ADDR})&&$Q{CODE}=~/ajax|js/){logger('LOG','APIAJAX',"AUTH OK")}
else{
	return ('OK',0,response('api_response','HTML',FEEDBACK())) if $Q{CODE}=~/feedback/&&$Q{MESSAGE}&&$Q{EMAIL}&&$Q{SUBJECT};
	logger('LOG','API',"AUTH ERROR");
	my %HASH=(aaData=>'');
	return ('OK',0,response('api_response','JSON',\%HASH)) if $Q{CODE}=~/ajax/;
	return ('NO AUTH',-1,response('api_response','ERROR',"NO AUTH"));
}#else no auth		
logger('LOG','API',"$Q{CODE}") if $CONF{debug}>2;
switch ($Q{CODE}){
# [VERSION] *******************************************************************************************************
	case 'version' {
		return ('OK', 0, response('version','HTML',$CONF{rev}));
	}#case version
# [PING] **********************************************************************************************************
	case 'ping' {
		sleep 2 if defined $Q{SUB_CODE};
		return ('OK', 0, response('ping','HTML',"PONG")) if defined $Q{SUB_CODE};
		return ('OK', 0, response('api_response','XML',"PONG"));
	}#case ping
# [GET_MSRN] *******************************************************************************************************
	case 'get_msrn' {
		if ($Q{IMSI}){#if imsi defined
			$Q{MSRN}=GET_MSRN();
			return ('OK',0,response('api_response','XML')) if $Q{SUB_CODE} ne 'plaintext' && $Q{MSRN};
			return ('OK',0,response('get_msrn','HTML',$Q{MSRN})) if $Q{SUB_CODE} eq 'plaintext';
		}#if imsi
		else{#if no imsi
			return ('IMSI UNDEFINED',-1,response('get_msrn','ERROR',"IMSI UNDEFINED $Q{IMSI}"));
		}#else no imsi
	}#case msrn
# [GET DID] ********************************************************************************************************
	case 'get_did' {
		logger('LOG','API-CMD-DID-[did/src]',"$Q{RDNIS}/$Q{SRC}") if $CONF{debug}>2;
				$Q{RDNIS}=~s/\+//;
				$Q{IMSI} = length($Q{RDNIS})==6 ? $Q{RDNIS} : $R->HGET('DID',$Q{RDNIS});
				$Q{GIMSI}= $CONF{'imsi_prefix'}.$Q{IMSI};
					GET_SUB();#if no DID no CARD_BALANCE
						$Q{MSRN}=GET_MSRN() if ($Q{CARD_BALANCE_AVAIL}>$CONF{balance_threshold}) and not defined $Q{MSRN};
				$Q{DID_RESULT}= $Q{MSRN}=~/\d{7,15}/ ?				
				(CALL_RATE($Q{MSRN},'MSRN'),
			$R->HSET('CARD:'.$Q{SUB_CN},'CARD_BALANCE_RESERVE_'.$Q{IMSI}, abs($Q{'CALL_LIMIT'}*(($Q{RATE}+$Q{MTC})/100/60) ) ),1 ) : 0;
				logger('LOG','API-DID-[msrn|rate|mtc|limit]',"$Q{MSRN} $Q{RATE} $Q{MTC} $Q{'CALL_LIMIT'}") if $CONF{debug}>2;
				return ('OK',0,response('get_did','HTML',TEMPLATE('api:did:'.$Q{DID_RESULT}) ) );
	}#case get_did
# [SEND USSD] **********************************************************************************************************
	case 'send_ussd' {#SEND_USSD
		if ($Q{SUB_HASH}=~/$Q{TOKEN}/){
			$Q{USSD_TO}=$R->HGET('DID',"$Q{IMSI}");
		return ('OK',0,response('api_response','XML',CURL('send_ussd',TEMPLATE('api:send_ussd'),$CONF{api2})));
	}else{
		return ('ERROR',-1,response('api_response','ERROR','NOT YOUR SIM'));
	}#else AUTH
		}#case send_ussd
# [SEND SMS] **********************************************************************************************************		
	case /send_sms/i {#SEND SMS MT	
	if ($Q{SUB_HASH}=~/$Q{TOKEN}/){
		$Q{SMS_TO}=$R->HGET('DID',"$Q{IMSI}");
		$R->SETEX("MT_SMS:".$Q{SMS_TO},60,"$Q{TOKEN}");
		return ('OK',0,response('api_response','XML',undef,CURL('send_sms_mt',TEMPLATE('api:send_sms_mt'),$CONF{api2})));
	}else{
		return ('ERROR',-1,response('api_response','ERROR','NOT YOUR SIM'));
	}#else AUTH
		}#case send sms mt
# [STAT] **********************************************************************************************************
	case 'stat' {#STAT
		$Q{AGENT}=$Q{IMSI} ? 'STAT:SUB:'.$Q{GIMSI} : 'STAT:AGENT:'.$Q{TOKEN};
	my	%HASH=$R->HGETALL($Q{AGENT});
		map{ delete $HASH{$_} if $_!~/$Q{FILTER}/} keys %HASH;
		return ('OK',0,response('api_response','JSON',\%HASH));
		}#case stat
# [AJAX] **********************************************************************************************************
	case 'ajax' {#AJAX
		$Q{TOKEN}=$R->GET('SESSION:'.$Q{SESSION}.':'.$Q{REMOTE_ADDR});
		$R->HEXISTS('TEMPLATE','ajax:'.$Q{SUB_CODE}) ? my %HASH=(aaData=>SQL(TEMPLATE('ajax:'.$Q{SUB_CODE}),'ajax',$Q{TEXT},$Q{ALIASTAG},$Q{TOKEN})) : return GUI($R->DEL('SESSION:'.$Q{SESSION}.':'.$Q{REMOTE_ADDR}),$Q{SESSION}=0);
		logger('LOG','API-AJAX',$Q{SUB_CODE}) if $CONF{debug}>2;
		return ('OK',0,response('api_response','JSON',\%HASH));
		}#case ajax
# [SQL] **********************************************************************************************************
	case 'sql' {#SQL
		return ('ERROR',-1,response('api_response','HTML','FORBIDDEN')) if not defined $R->HGET('AGENT:'.$Q{TOKEN},'admin');
		$R->HEXISTS('TEMPLATE','sql:'.$Q{SUB_CODE}) ? $Q{RESULT}=SQL(TEMPLATE('sql:'.$Q{SUB_CODE})) : return ('ERROR',-1,response('api_response','ERROR','UNKNOWN SUB_CODE'));
		logger('LOG','API-SQL',$Q{SUB_CODE}) if $CONF{debug}>2;
		return ('OK',0,response('api_response','HTML',$Q{RESULT}-1));
		}#case sql
# [CDR] **********************************************************************************************************
		case 'cdr' {#CDR
		return ('ERROR',-1,response('api_response','HTML','FORBIDDEN')) if not defined $R->HGET('AGENT:'.$Q{TOKEN},'admin');
#-- STANDARD CALL
if ($Q{DCONTEXT} eq "callme_reg" and $Q{LASTAPP} eq 'Dial' and $Q{DISPOSITION} eq 'ANSWERED' and ($Q{BILLSEC}>0 or $Q{MTC}>0)){
#-- charging (LegA duration full min * MTC + LegA duration sec * RATEA/60  + LegB billsec * RATEB/60)/100 = call cost in $
$Q{COST} =sprintf '%.2f', ( (  ( (ceil($Q{DURATION}/60)* ($Q{MTC}?$Q{MTC}:0) ) )+$Q{DURATION}*($Q{RATEA}/60?$Q{RATEA}/60:0) )+$Q{BILLSEC}*($Q{RATEB}/60?$Q{RATEB}/60:0) ) /100;
		logger('LOG','CDR-STANDARD',$Q{COST});
}#-- DID call
elsif ($Q{DCONTEXT} eq "did_reg" and $Q{LASTAPP} eq 'Dial' and $Q{DISPOSITION} eq "ANSWERED" and $Q{BILLSEC}>0){
$Q{COST} = sprintf '%.2f', ( ((ceil(($Q{BILLSEC}/60)* ($Q{MTC}?$Q{MTC}:0) )))+($Q{BILLSEC}*($Q{RATEA}/60?$Q{RATEA}/60:0)) )/100;
		logger('LOG','CDR-DID',$Q{COST});
}#-- CALLBACK call with MTC
elsif ($Q{DCONTEXT} eq "callme_reg" and $Q{LASTAPP} eq 'ForkCDR'){
$Q{COST} =sprintf '%.2f', ( (ceil( $Q{BILLSEC}/60)* ($Q{MTC}?$Q{MTC}:0) ) )/100;
		logger('LOG','CDR-NOTANSWERED',$Q{COST});
}else {$Q{COST}=0; logger('LOG','CDR-UNKNOWN',$Q{COST});}
#STANDARD
$Q{IMSI}=$Q{ACCOUNTCODE};
$Q{GIMSI}=$CONF{imsi_prefix}.$Q{IMSI};
$Q{USERFIELD}=$Q{IMSI};
$Q{SUB_CN}=$Q{ACCOUNTCODE}=$R->HGET('SUB:'.$Q{IMSI},'SUB_CN');
BILL('CALL',$Q{COST}) if $Q{COST}>0;
SQL(TEMPLATE('sql:cdr')) if $Q{COST}>0;
$Q{COSTA}=$Q{COST};
	$Q{USSD_TO}=$R->HGET('DID',"$Q{IMSI}"); $Q{MESSAGE}=(strftime( "\%H:\%M:\%S", gmtime($Q{BILLSEC}) ) )." \$$Q{COST}";
	CURL('send_ussd',TEMPLATE('api:send_ussd'),$CONF{api2}) if $Q{COST}>0 && $R->HEXISTS('SUB:'.$Q{IMSI},'SUB_NOTIFY');
#-- INTERNAL
if ($Q{DCONTEXT} eq 'callme_reg' and $Q{LASTAPP} eq 'Dial' and $Q{DISPOSITION} eq 'ANSWERED' and ($Q{BILLSEC}>0 or $Q{MTC}>0) and $Q{DSTCHANNEL} ne '' and $Q{ACCOUNTCODEB} ne ''){
$Q{COST} = sprintf '%.2f', ( (ceil ($Q{BILLSEC}/60)* ($Q{MTCB}?$Q{MTCB}:0) ) + ($Q{BILLSEC}*$Q{RATEB}/60?$Q{RATEB}:0) )/100;
$Q{IMSI}=$Q{ACCOUNTCODEB};
$Q{GIMSI}=$CONF{imsi_prefix}.$Q{IMSI};
$Q{DCONTEXT}='did_reg';
$Q{USERFIELD}=$Q{IMSI};
$Q{SUB_CN}=$Q{ACCOUNTCODE}=$R->HGET('SUB:'.$Q{IMSI},'SUB_CN');
BILL('CALL',$Q{COST}) if $Q{COST}>0;
SQL(TEMPLATE('sql:cdr_inner')) if $Q{COST}>0;
	$Q{USSD_TO}=$R->HGET('DID',"$Q{IMSI}"); $Q{MESSAGE}=(strftime( "\%H:\%M:\%S", gmtime($Q{BILLSEC}) ) )." \$$Q{COST}";
	CURL('send_ussd',TEMPLATE('api:send_ussd'),$CONF{api2}) if $Q{COST}>0 && $R->HEXISTS('SUB:'.$Q{IMSI},'SUB_NOTIFY');
logger('LOG','CDR-INTERNAL',$Q{COST});
}#INTERNAL
	$R->HDEL("CARD:".$Q{SUB_CN},'CARD_BALANCE_RESERVE_'.$Q{IMSI});
		return ('OK',0,response('api_response','HTML',"$Q{COST}:$Q{COSTA}" ) );
		}#case sql
# [JS] **********************************************************************************************************
	case 'js' {#JS
		logger('LOG','API-JS',$Q{SUB_CODE}) if $CONF{debug}>2;
		return ('OK',0,response('api_response','JS',TEMPLATE('js:'.$Q{SUB_CODE})));
		}#case js
# [SET USER] **********************************************************************************************************
	case /set_user/i {#set_user API C9
	if ($Q{SUB_HASH}=~/$Q{TOKEN}/){		
	$Q{SUB_CODE} = $Q{SUB_CODE}=~/^enable$/i ? 1 : $Q{SUB_CODE}=~/^disable$/i ? 0 : $Q{SUB_CODE};
	return ('OK',0, response('api_response','XML',undef,CURL('set_user_status',TEMPLATE('api:set_user_status'),$CONF{api2}))) if $Q{SUB_CODE}!~/^Data/i;
	return ('OK',0, response('api_response','XML',undef,CURL('set_user',XML($Q{SUB_CODE}),$CONF{api1})));
	}else{
	return ('ERROR',-1,response('api_response','ERROR','NOT YOUR SIM'));
	}#else AUTH
	}#set_user API C9
# [ELSE SWITCH] **********************************************************************************************************
	else {
		logger('LOG','API-UNKNOWN',"$Q{CODE}") if $CONF{debug}>1;
		return ('API CMD',-1,response('api_response','ERROR',"UNKNOWN CMD REQUEST"));
		}#else switch code
}#switch code
}##### END sub API ########################################
#
### SUB GUI #########################################################
sub GUI {
switch (AUTH()) {
	case 0 {$Q{PAGE}='html:login'}
	case 1 {$Q{PAGE}='js:session'}
	case 2 {$Q{PAGE}='html:index';
$Q{TOKEN_NAME}=$R->HGET('AGENT:'.$R->GET('SESSION:'.$Q{SESSION}.':'.$Q{REMOTE_ADDR}),'name') if not defined $Q{TOKEN_NAME};
$Q{PAYTAG}=~/^\d{6}$/ && PAY() ? return('OK',0,response('PAY','JSON',$Q{PAYMENT})) :undef;
	}# 2 index
	else {
		$Q{REQUEST_TYPE} eq "PAY" ? return PAY() :undef;
		$Q{REQUEST_TYPE} eq "PAYPAL" ? return PAYPAL() :undef;
		return ('OK',0,"Content-Type: text/html\n\n".TEMPLATE('html:login'))}
}#switch page
return ('OK',-1,"Content-Type: text/html\n\n".TEMPLATE('html:login'),$R->EXPIRE('SESSION:'."$Q{SESSION}".':'.$Q{REMOTE_ADDR},0) ) if $Q{TOKEN_PIN} && ( not $R->HEXISTS('AGENT:'.$Q{TOKEN_PIN},'gui') || $R->HEXISTS('AGENT:'.$Q{TOKEN_PIN},"$Q{REMOTE_ADDR}") );
return ('OK',0,"Content-Type: text/html\n\n".TEMPLATE($Q{PAGE}));
}#end GUI
#
########## FEEDBACK ############################################# 
sub FEEDBACK {
return 403 if $R->SETNX('FEEDBACK:'.$Q{REMOTE_ADDR},"$Q{EMAIL}")==0;
	($Q{EMAIL_FROM},$Q{EMAIL_TO},$Q{EMAIL_SUBJ},$Q{EMAIL_BODY})=split(';',TEMPLATE('email:feedback'));
	$Q{EMAIL_RESULT}=EMAIL();
logger('LOG','API-FEEDBACK',"$Q{EMAIL} $Q{EMAIL_BODY} $Q{EMAIL_RESULT}") if $CONF{debug}>2;
	$R->EXPIRE('FEEDBACK:'.$Q{REMOTE_ADDR},"$CONF{feedback_timeout}");
	return 200;
}#end FEEDBACK
########## SIGNALING ############################################
sub SIG {
	my $sig=uc $Q{REQUEST_TYPE};
	my $coderef=\&$sig;
	AUTH($Q{REMOTE_ADDR}) ? return &$coderef() : return ('NO AUTH',-1,response('api_response','ERROR',"NO AUTH"));
#
########## LU_CDR ###############################################
sub LU_CDR { 
	SQL(TEMPLATE('sql:lu'));
	$R->EXPIRE('OFFLINE:'.$Q{IMSI},0);	
	$Q{CDR_STATUS}=1;
	$Q{REQUEST_TYPE}='LU_CDR_FREE' if $R->HGET("STAT:SUB:$Q{GIMSI}",'['.substr($Q{TIMESTAMP},0,10)."]-[LU_CDR]") > 25;
	return ('OK',"$Q{SUB_ID}:$Q{MCC}:$Q{MNC}:$Q{TADIG}",response('CDR_RESPONSE','XML',1));
}########## END sub LU_CDR ######################################
#
########## AUTHENTICATION CALLBACK MOC_SIG ######################
## Processing CallBack and USSD requests
################################################################# 
#
sub AUTH_CALLBACK_SIG {
$R->EXPIRE('OFFLINE:'.$Q{IMSI},0);
logger('LOG',"SIG-$Q{USSD_CODE}-REQUEST","$Q{IMSI},$Q{USSD_CODE},$Q{USSD_DEST},$Q{USSD_EXT}") if $CONF{debug}>1;
if(($Q{CARD_BALANCE_AVAIL}>$CONF{balance_threshold})||($Q{USSD_CODE}=~/^(123|100|000|110|111|129)$/)){#check balance
	if (($Q{USSD_CODE}=~/112/)&&$Q{USSD_DEST}){return SPOOL()}#if call
	else{ return USSD()} #if ussd
			}#if balance
	else{#no balance
		logger('LOG','auth_callback_sig-LOW-BALANCE',"$Q{CARD_BALANCE} #".__LINE__) if $CONF{debug}>1;
		return ('OK',1, response('MOC_RESPONSE','XML',TEMPLATE('ussd:no_balance') ) );
	}#else status
}## END sub auth_callback_sig
#
########## AUTHORIZATION CALLBACK OutboundAUTH ######################
sub OUTBOUNDAUTH {
AUTH($Q{REMOTE_ADDR}) ? undef : return ('NO AUTH',-1,response('api_response','ERROR',"NO AUTH"));	
	$Q{USSD_DEST}=$Q{DESTINATION};
	$Q{USSDMESSAGETOHANDSET}=TEMPLATE('spool:wait');
($Q{CARD_BALANCE_AVAIL}>$CONF{balance_threshold}) ? SPOOL() : return ('OK',1, response('MOC_RESPONSE','XML', TEMPLATE('ussd:no_balance') ));
	return ('OK',1, response('RESPONSE','XML',0,$Q{USSDMESSAGETOHANDSET}));
}#END OUTBOUNDAUTH
################################################################# 
#
### SUB DataAUTH ###################################################################
sub DATAAUTH {
$Q{DATA_RATE} = $R->HGET('DATA',$Q{MCC}.int $Q{MNC});
logger('LOG','DATA_RATE',"$Q{DATA_RATE}") if $CONF{debug}>0;
BILL('DATASESSION',$Q{DATA_RATE}) if ($Q{TOTALCURRENTBYTELIMIT}/1048576)>1;
$Q{DATA_AUTH} = (($Q{INET_BALANCE} > ($Q{DATA_RATE}+$CONF{balance_threshold}) )&&$Q{DATA_RATE}>0) ? 1 : 0;
logger('LOG','DATAAUTH-[auth|balance|limit]:',"$Q{DATA_AUTH}:$Q{INET_BALANCE}:$Q{TOTALCURRENTBYTELIMIT}") if $CONF{debug}>0;
return ('DATAAUTH',0,response('RESPONSE','XML',$Q{DATA_AUTH}));
}
### END sub DataAUTH ###############################################################
#
### SUB DataSession ###################################################################
sub DATASESSION {
$R->SISMEMBER('DATASESSION',$Q{CALLLEGID}) ? return ('DATASESSION', 0, response('DATASESSION','HTML','REJECT - DUPLICATE')) : undef;
$Q{COST}=sprintf '%.2f', ( abs($Q{AGENTTOTALCOST}{amount}{value})-floor($Q{BYTES}/1048576)*abs($Q{AGENTPERMEGABYTERATE}) );
$R->HSET('DATA',$Q{MCC}.int $Q{MNC},abs("$Q{AGENTPERMEGABYTERATE}"));#set actual rate
GET_SUB();#GET SUB_CN
BILL('DATASESSION',$Q{COST});
$Q{USSD_TO}=$Q{NUMBER}; $Q{MESSAGE}=(sprintf "%.3f",($Q{BYTES}/1048576))."Mb \$".abs($Q{AGENTTOTALCOST}{amount}{value})." Balance:\$".$Q{SUB_NEW_BALANCE};
CURL('send_ussd',TEMPLATE('api:send_ussd'),$CONF{api2}) if $Q{SUB_NOTIFY}&&$Q{COST}>0;#notify with data cost
logger('LOG','DATASESSION-[callid:rate:cost]',"$Q{CALLLEGID}:$Q{AGENTPERMEGABYTERATE}:$Q{COST}") if $CONF{debug}>0;
$R->SADD('DATASESSION',$Q{CALLLEGID});
return ('DATASESSION', 0, response('DATASESSION','HTML','200'));
} 
### END sub DataSession ##############################################################
#
### sub msisdn_allocation ############################################################
sub MSISDN_ALLOCATION {
SQL(TEMPLATE('sql:msisdn'));
$R->HMSET('DID',$Q{IMSI},$Q{MSISDN},$Q{MSISDN},$Q{IMSI},$Q{SUB_CN},$Q{IMSI});#sms & datasession & sip
$R->HSET('SUB:'.$Q{IMSI},'SUB_DID',$Q{MSISDN});
return ('MSISDN_ALLOCATION',$Q{CODE},response('CDR_response','XML',$Q{CDR_STATUS}));
}#end sub msisdn_allocation #######################################################
#
#
### Authenticate outbound SMS request ###########################################
sub MO_SMS {
$Q{REQUEST_STATUS}=$R->EXPIRE("MO_SMS:".$Q{DESTINATION},0);
return('OK',1,response('MO_SMS_RESPONSE','XML',0));#reject outbound / accept MO_SMS Lite
}#end sub MO_SMS
#
### SUB MT_SMS ##################################################################
#
# Authenticate inbound SMS request ##############################################
###
sub MT_SMS {
$Q{REQUEST_STATUS}=$R->EXPIRE("MT_SMS:".$Q{DESTINATION},0);
return('OK',0,response('MT_SMS_RESPONSE','XML',$Q{REQUEST_STATUS}));#accept only API MT_SMS
}#end sub MT_SMS
#
### sub MOSMS_CDR ##################################################################
#
# SUB MOSMS (Outbound) CDRs ############################################################
sub MOSMS_CDR {
return('OK',0,response('CDR_RESPONSE','XML',1));
}#end sub MOSMS_CDR ################################################################
#
### SUB MTSMS_CDR ##################################################################
sub MTSMS_CDR {
return('OK',0,response('CDR_RESPONSE','XML',1));
}#end sub MTSMS_CDR ################################################################
#
### SUB SMSContent_CDR
sub SMSCONTENT_CDR {
return('OK',0,response('CDR_RESPONSE','XML',1));
}#end sub SMSContent_CDR ############################################################
#
### SMS_CDR #########################################################################
sub SMS_CDR {
return('OK',0,response('CDR_RESPONSE','XML',1));
}#end sub SMS_CDR ##################################################################
#
}# END SIGNALING
######### END #################################################	
