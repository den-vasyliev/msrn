#!/usr/bin/perl
#/usr/bin/perl
#/opt/local/bin/perl -T
#
########## VERSION AND REVISION ################################
## Copyright (C) 2012, RuimTools denis@ruimtools.com
##
my $rev='API Server 200613-rev.68.4 ~909 +337 ~761 ~1287 ~996 ~597 +5s +u111 +u129 +rid +zadarma ~auth +redis +curl (!)';
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
use XML::Simple;
use XML::Bare::SAX::Parser;
use XML::Smart;
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
$R0->hset('conf','rev',"$rev");
my %CONF=$R0->hgetall('conf');
my %SYS=$R0->hgetall('status');
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
our $xs = XML::Simple->new(ForceArray => 0,KeyAttr => {});
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
##################################################################
share($CONF{'ready_count'});
#share($CONF{'call_count'});
async(\&handler,$CONF{'redis'});#start redis thread
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
my @subscriptions=$R0->lrange($CONF{'subscriptions'},0,-1);
$R0->subscribe(@subscriptions,
		sub{
	my ($value,$topic,$subscribtions)=@_;
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
	$CONF{'debug'}=redis('hget','conf','debug');
	$CONF{'debug:imsi'}=redis('hget','debug','imsi');
#	$CONF{'memory'}='_memory' if redis('exists','redis_running');
	########### SET TIMER & INNER TID #####################################
	my ($t1,$t2,$td0);
#######################################################################
	&logger('LOG',"API-SOCKET-OPEN: $Q{REMOTE_ADDR} DEBUG:$CONF{debug} THID:$tid $redis_sock","################################");
########### IF POST REQUEST #####################################
	if ($env->{REQUEST_METHOD} eq 'POST'){$Q{REQUEST}=<STDIN>;}#if post
########### IF GET REQUEST ######################################
		elsif($env->{REQUEST_METHOD} eq 'GET'){$Q{REQUEST}=$env->{QUERY_STRING};}#elsif GET
########### IF VALID REQUEST #####################################
			if($Q{REQUEST}=~m/request_type|imsi|rc_api_cmd/g){#if valid request
				print main();
			}else{#else not valid request
			print &response('rc_api_cmd','PLAINTEXT',redis('hget','response', 'api_page'));
					}# if empty set
			$t2=Benchmark->new;
			$td0 = timediff($t2, $t0);	
	&logger('RDB',"COMMIT","API-SOCKET-CLOSE: TID:$tid $redis_sock IN: ".substr($td0->[0],0,8)." ##############################");
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
#
$dbh = DBI->connect_cached('DBI:mysql:msrn',$CONF{login},$CONF{pass});
#
our %XML_KEYS=&XML_PARSE($Q{REQUEST},'SIG_Get_KEYS');
my $qkeys= keys %XML_KEYS;
&logger('LOG','MAIN-PARSER-RETURN',$qkeys) if $CONF{debug}==4;
	if (keys %XML_KEYS){#if not empty set
		my $head="$XML_KEYS{request_type}";
		uri_unescape($Q{calldestination})=~/^\*(\d{3,9})(\*|\#)(\D{0,}\d{0,}).?(.{0,}).?/ if $Q{calldestination};
		$head="$1" if $Q{calldestination};
		$head="lu" if $XML_KEYS{request_type} eq 'LU_CDR';
		$head="payment" if $XML_KEYS{salt};
		$head="data" if $XML_KEYS{SessionID};
		$head="postdata" if $XML_KEYS{calllegid};
		$XML_KEYS{imsi}=$XML_KEYS{IMSI} if $XML_KEYS{request_type} eq 'msisdn_allocation';
		$XML_KEYS{transactionid}=$XML_KEYS{cdr_id} if $XML_KEYS{request_type} eq 'msisdn_allocation';
		$XML_KEYS{transactionid}=$XML_KEYS{SessionID} if $XML_KEYS{SessionID};#DATA
		$XML_KEYS{imsi}=$XML_KEYS{GlobalIMSI} if $XML_KEYS{SessionID};#DATA
			my $IN_SET="$head:";#need request type and : as first INFO
			$IN_SET=$IN_SET.uri_unescape($XML_KEYS{msisdn}).":$XML_KEYS{mcc}:$XML_KEYS{mnc}:$XML_KEYS{tadig}" if  $XML_KEYS{msisdn};#General
			$IN_SET=$IN_SET."$XML_KEYS{ident}:$XML_KEYS{amount}" if $XML_KEYS{salt};#PAYMNT
			$IN_SET=$IN_SET."$XML_KEYS{TotalCurrentByteLimit}" if $XML_KEYS{SessionID};#DATA AUTH
			$IN_SET=$IN_SET."$XML_KEYS{calllegid}:$XML_KEYS{bytes}:$XML_KEYS{seconds}:$XML_KEYS{mnc}:$XML_KEYS{mcc}:$XML_KEYS{amount}" if $XML_KEYS{calllegid};#POSTDATA
########### GET ACTION TYPE ######################################
		my $ACTION_TYPE_RESULT=&GET_TYPE($XML_KEYS{request_type});
##################################################################
########### CALL SUBREF ##########################################
	eval {
			our $subref=\&$ACTION_TYPE_RESULT;#referencing to sub
		};warn $@ if $@;  &logger('LOG',"MAIN-ACTION-SUBREF","ERROR $ACTION_TYPE_RESULT $@") if $@;
##################################################################
	&logger('LOG','MAIN-GET_TYPE',$ACTION_TYPE_RESULT) if $CONF{debug}==4;
########### OPEN IN REQUEST ######################################
	&logger('LOGDB',"$ACTION_TYPE_RESULT","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'IN',$IN_SET) if $ACTION_TYPE_RESULT ne '1';
##################################################################
	switch ($ACTION_TYPE_RESULT){#if we not understand action
		case 1 {#Incorrect URL
#			&logger('LOGDB',"$XML_KEYS{request_type}","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'ERROR','INCORRECT URL VARIABLES');
			return &response('LU_CDR','ERROR','INCORRECT PARMETERS #'.__LINE__);
		}#case 1
		case 2 {#Incorrect type
			&logger('LOGDB',"$XML_KEYS{request_type}","$XML_KEYS{transactionid}","$XML_KEYS{imsi}",'ERROR','INCORRECT ACTIONS TYPE');
			return &response('LU_CDR','ERROR','INCORRECT ACTIONS TYPE #'.__LINE__);
		}#case 2
		case 3 {#Not found at all
			&logger('LOG','MAIN-GET-TYPE','NOT FOUND') if $CONF{debug}==4;
			return &response('LU_CDR','ERROR','INCORRECT URI #'.__LINE__);}
	else {#else switch ACTION TYPE RESULT
		use vars qw($subref);

#USSD DIRECT CALL
if (!$Q{USSD_CODE} && $ACTION_TYPE_RESULT eq 'auth_callback_sig'){
uri_unescape($Q{calldestination})=~/^\*(\d{7,14})\#/;
$Q{USSD_DEST}=$1;
$Q{USSD_CODE}=112; 
}#if USSD DIRECT CALL
#
$Q{USSD_CODE}="NULL" if !$Q{USSD_CODE};
#
if ($Q{SUB_GRP_ID} ne '1'&&$Q{request_type} ne 'rc_api_cmd'){#if AGENT GROUP
	&logger('LOG','MAIN-ACTION-TYPE-AGENT',"FOUND $Q{SUB_AGENT_ID}") if $CONF{debug}==1;
		my $AGENT_response=agent();
		&logger('LOG',"MAIN-AGENT-ACTION-RESULT-$ACTION_TYPE_RESULT","$AGENT_response") if $CONF{debug}==1;
		return &response('auth_callback_sig','OK',$Q{transactionid},"$AGENT_response");
	}#if AGENT GROUP
		eval {
		our ($ACTION_STATUS,$ACTION_RESULT)=&$subref();#calling reference
		};warn $@ if $@;  &logger('LOG',"MAIN-ACTION-SUBREF","ERROR $ACTION_TYPE_RESULT $@") if $@;
		use vars qw($ACTION_RESULT $ACTION_STATUS);
			if($ACTION_STATUS){#action return result
				&logger('LOG',"MAIN-ACTION-RESULT-$ACTION_TYPE_RESULT","$ACTION_STATUS") if $CONF{debug}==4;
				&logger('LOGDB',$ACTION_TYPE_RESULT,"$Q{transactionid}","$Q{imsi}",'OK',"$ACTION_STATUS");
				return "$ACTION_RESULT";
			}#if ACTION RESULT
			else{
				&logger('LOG',"MAIN-ACTION-RESULT-$ACTION_TYPE_RESULT",'NO ACTION_RESULT') if $CONF{debug}==4;
				&logger('LOGDB',$ACTION_TYPE_RESULT,"$Q{transactionid}","$Q{imsi}",'ERROR',"$ACTION_STATUS");
				return &response('auth_callback_sig','OK','SORRY NO RESULT #'.__LINE__);
			}#no result returned
		}#else switch ACTION TYPE RESULT
##
	}#switch ACTION TYPE RESULT
}#if keys
else{#else if keys
	return &response('LU_CDR','ERROR','INCORRECT KEYS #'.__LINE__,0);
}#else if keys
$dbh->disconnect;
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
if ($REQUEST_LINE=~m/xml version/){
&logger('LOG',"XML-PARSE-REQUEST",$Q{REQUEST}) if $CONF{debug}==4;
my $backend="XML::Bare::SAX::Parser";
local $ENV{XML_SIMPLE_PREFERRED_PARSER}="$backend";
eval {#error exceprion
use vars qw($xs);
$Q{REQUEST}=$xs->XMLin($REQUEST_LINE);
our $DUMPER=Dumper ($xs->XMLin($REQUEST_LINE)) if $CONF{debug}>2;
};warn $@ if $@; return "XML not well-formed" if $@;
#
use vars qw($DUMPER);
&logger('LOG',"XML-PARSE-REQUEST-LINE-$REQUEST_OPTION","$REQUEST_LINE") if $CONF{debug}==4;
our $REMOTE_HOST=$Q{REQUEST}->{authentication}{host};# not needed (!)
}#if xml
else{#CGI REQUEST
	&logger('LOG',"CGI-PARSE-REQUEST",$Q{REQUEST}) if $CONF{debug}==4;
			$Q{REQUEST}=~tr/\&/\;/;
			foreach my $field (split(';',$Q{REQUEST})) {
    			if ($field=~/timestamp|message_date/){next;}
				my ($key,$value)=split('=',$field);
				chomp $value;
				$value=uri_unescape($value);
				$value=~s/\+//;
				$Q{$key}=$value;#foreach
			}#foreach field
			return %Q;
}#else cgi
#
switch ($REQUEST_OPTION){
	case 'SIG_Get_KEYS' {
		&logger('LOG',"XML-PARSE-DUMPER","$DUMPER") if $CONF{debug}==4;
##if request in 'query' format
		if ($Q{REQUEST}->{query}){
#			our %Q=();
			my @QUERY=split(';',$Q{REQUEST}->{query});
				foreach my $pair(@QUERY){
					my  ($key,$val)=split('=',$pair);
					$Q{$key}="$val";#All variables from request
				}#foreach
				#}#if
				&logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION",keys %Q) if $CONF{debug}==4;
				return %Q;
		}#if request
##if request in 'payments' format		
		elsif($Q{REQUEST}->{payment}){
			&logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION",'PAYMENTS') if $CONF{debug}==4;;
			our %Q=('request_type'=>'PAYMNT');
			$Q{'transactionid'}=$Q{REQUEST}->{payment}{id};
			my @KEYS= keys %{ $Q{REQUEST}->{payment} };
				foreach my $xml_keys (@KEYS){
					&logger('LOG',"XML-PARSE-RETURN-KEYS","$xml_keys=$Q{REQUEST}->{payment}{$xml_keys}") if $CONF{debug}==4;
					$Q{$xml_keys}=$Q{REQUEST}->{payment}{$xml_keys};
				}#foreach xml_keys
			return %Q;
		}#elsif payments
#if request in 'postdata' format
		elsif($Q{REQUEST}->{'complete-datasession-notification'}){
		&logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION",'POSTDATA') if $CONF{debug}==4;
		our %Q=('request_type'=>'POSTDATA');
		$Q{'transactionid'}=$Q{REQUEST}->{'complete-datasession-notification'}{callid};
		my @KEYS= keys %{ $Q{REQUEST}->{'complete-datasession-notification'}{callleg} };
		foreach my $xml_keys (@KEYS){#foreach keys
				if ((ref($Q{REQUEST}->{'complete-datasession-notification'}{callleg}{$xml_keys}) eq 'HASH')&&($xml_keys eq 'agentcost')){#if HASH
					my @SUBKEYS= keys %{ $Q{REQUEST}->{'complete-datasession-notification'}{callleg}{$xml_keys} } ;
					foreach my $sub_xml_keys (@SUBKEYS){# foreach subkeys
	&logger('LOG',"XML-PARSE-RETURN-KEYS","$sub_xml_keys=$Q{REQUEST}->{'complete-datasession-notification'}{callleg}{$xml_keys}{$sub_xml_keys}") if $CONF{debug}==4;
						$Q{$sub_xml_keys}=$Q{REQUEST}->{'complete-datasession-notification'}{callleg}{$xml_keys}{$sub_xml_keys};
					}#foreach sub xml_keys
				}#if HASH
					else{#else not HASH
					&logger('LOG',"XML-PARSE-RETURN-KEYS","$xml_keys=$Q{REQUEST}->{'complete-datasession-notification'}{callleg}{$xml_keys}") if $CONF{debug}==4;
					$Q{$xml_keys}=$Q{REQUEST}->{'complete-datasession-notification'}{callleg}{$xml_keys};
							}#else not HASH
					}#foreach xml_keys
				my $SQL=qq[select useralias from cc_card where phone like "%$Q{'number'}"];
				my @sql_records=&SQL($SQL);
				$Q{imsi}=$sql_records[0];
			return %Q;
		}#elsif postdata
		else{#unknown format
			&logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION",'UNKNOWN FORMAT') if $CONF{debug}==4;
			return;
		}#else unknown
	}#xml
	case /get_msrn/ {
		my $MSRN=$Q{REQUEST}->{MSRN_Response}{MSRN};
		$Q{iot}=$Q{REQUEST}->{MSRN_Response}{IOT};
		$Q{iot_charge}=$Q{REQUEST}->{MSRN_Response}{IOT_CHARGE};
		my $result=${SQL(qq[SELECT get_iot($MSRN,$Q{iot_charge})],2)}[0] if $Q{iot}==1;
		our $ERROR=$Q{REQUEST}->{Error_Message};
		$ERROR=0 if !$ERROR;
		$result=0 if !$result;
		&logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$MSRN IOT:$Q{iot} $result $ERROR") if $CONF{debug}==4;
		redis('hset',"$Q{imsi}:msrn",'msrn','OFFLINE') if $MSRN eq 'OFFLINE';
		redis('EXPIRE',"$Q{imsi}:msrn",300) if $MSRN eq 'OFFLINE';
		$MSRN=~s/\+//;#supress \+ from xml response (!)
		return $MSRN;
	}#msrn
	case 'send_ussd' {
		my $USSD=$Q{REQUEST}->{USSD_Response}{REQUEST_STATUS};
		our $ERROR=$Q{REQUEST}->{Error_Message};
		&logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$USSD $ERROR") if $CONF{debug}==4;
		return $USSD;
	}#ussd
	case /sms_m/ {
		my $SMS=$Q{REQUEST}->{SMS_Response}{REQUEST_STATUS};
		our $ERROR=$Q{REQUEST}->{Error_Message};
		&logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$SMS $ERROR") if $CONF{debug}==4;
		return "$ERROR$SMS";
	}#sms
	case /SIG_SendAgent/ {
		my $USSD=$Q{REQUEST}->{RESALE_Response}{RESPONSE};
		our $ERROR=$Q{REQUEST}->{Error_Message};
		&logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$USSD $ERROR") if $CONF{debug}==4;
		return $USSD;
	}#resale
	case 'get_session_time' {
		my $TIME=$Q{REQUEST}->{RESPONSE};
		our $ERROR=$Q{REQUEST}->{Error_Message};
		&logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$TIME $ERROR") if $CONF{debug}==4;
		return "$ERROR$TIME";
	}#get time
	case 'get_user_info' {
		my $BALANCE=$Q{REQUEST}->{Balance};
		our $ERROR=$Q{REQUEST}->{Reason};
		&logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$BALANCE $ERROR") if $CONF{debug}==4;
		return "$ERROR$BALANCE";
	}#get user info
	case 'set_user_balance' {
		my $BALANCE=$Q{REQUEST}->{Result};
		our $ERROR=$Q{REQUEST}->{Reason};
		&logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$BALANCE $ERROR") if $CONF{debug}==4;
		return "$ERROR$BALANCE";
	}#set user balance
	case 'new_user' {
		my $NEW=$Q{REQUEST}->{Result};
		our $ERROR=$Q{REQUEST}->{Reason};
		&logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","$NEW $ERROR") if $CONF{debug}==4;
		return "$ERROR$NEW";
	}#new user
	case /siminfo/i {
		$Q{PIN}=$Q{REQUEST}->{Sim}{Password};
		our $ERROR=$Q{REQUEST}->{Error};
		&logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION","xxxx $ERROR") if $CONF{debug}==4;
		return "xxxx$ERROR";
	}#sim info	
	else {
		print &logger('LOG',"XML-PARSE-RETURN-$REQUEST_OPTION",'NO OPTION FOUND $@') if $CONF{debug}==4;
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
#
#if ($CONF{debug}>2){
#	my @action_item=split('::',redis("hget request $request_type"));
#}#if debug >2
#
uri_unescape($Q{calldestination})=~/^\*(\d{3})(\*|\#)(\D{0,}\d{0,}).?(.{0,}).?/ if $Q{calldestination};
($Q{USSD_CODE},$Q{USSD_DEST},$Q{USSD_EXT})=($1,$3,$4);$Q{imsi}=0 if !$Q{imsi};$Q{imsi}=$Q{IMSI} if $Q{IMSI};
#(!) $Q{SUB_SET}=${SQL(qq[SELECT get_sub("$Q{imsi}")],2)}[0];
my $R = Redis->new(server => 'localhost:6379',encoding => undef,);
my %SUB=$R->hgetall("imsi:$Q{imsi}") if $Q{imsi}>0;
$R->quit;
map {$Q{$_}=$SUB{$_}} keys %SUB;
		foreach my $item(keys %Q){
#			if ($item ~~ @action_item){
				&logger('LOG','GET-TYPE',"$item=$Q{$item}") if $CONF{debug}==5;
#			}else{
#				&logger('LOG','GET-TYPE',"Warning:$item=$Q{$item}") ;
#		}#else
}#foreach item

#$Q{SUB_SET}=redis('hget','get_sub',$Q{imsi}) if $Q{imsi}>0;
#foreach my $pair (split(';',$Q{SUB_SET})){
#$Q{SUB_OPTIONS}=redis("hget subscribers $Q{imsi}");
#	foreach my $pair (split(';',$Q{SUB_OPTIONS})){
#	my ($key,$value)=split('=',$pair);
#	$Q{$key}=$value;#foreach
#}#foreach pair
	return $Q{request_type};
}########## END GET_TYPE ########################################
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
my $now = localtime;
#
my ($rc, $sth);
our (@result, $new_id,$error_str);
#
@result=();
if($SQL!~m/^SELECT/i){#INSERT/UPDATE request
&logger('LOG','SQL-MYSQL-GET',"DO $SQL") if $CONF{debug}==4;
	$rc=$dbh->do($SQL);#result code
	push @result,$rc;#result array
	$new_id = $dbh -> {'mysql_insertid'};#autoincrement id
}#if SQL INSERT UPDATE
else{#SELECT request
&logger('LOG','SQL-MYSQL-GET',"EXEC $SQL") if $CONF{debug}==4;
	$sth=$dbh->prepare($SQL);
	$rc=$sth->execute;#result code
	@result=$sth->fetchrow_array;
#	$sth->finish();
}#else SELECT
#
if($rc){#if result code
	our $sql_aff_rows =$rc;
	$new_id=0 if !$new_id;;
	&logger('LOG','SQL-MYSQL-RETURNED-[code/array/id]',"$rc/@result/$new_id") if $CONF{debug}==4;
	return \@result if $flag;
	return @result; 
}#if result code
else{#if no result code
	#$error_str=;
	&logger('LOG','SQL-MYSQL-RETURNED','Error: '.$dbh->errstr) if $CONF{debug}==4;
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
use vars qw($LOGFILE $t0);
#
#my $t3=Benchmark->new;
#my $td1=timediff($t3, $t0);
#my $timer=substr($td1->[0],0,8);
#my $now = localtime;
#
my ($ACTION_TYPE,$RESPONSE_TYPE,$R1,$R2,$R3,$R4)=@_;
my	($ROOT,$SUB1,$SUB2,$SUB3)=split('::',redis('hget','response',$ACTION_TYPE));
my $HEAD="Content-Type: text/xml\n\n";
#
switch ($RESPONSE_TYPE){
	case 'OK'{
	my	$OK=qq[<?xml version="1.0" ?><$ROOT><$SUB1>$R1</$SUB1><$SUB2>$R2</$SUB2><$SUB3>$R4</$SUB3></$ROOT>] if ($R4);
		$OK=qq[<?xml version="1.0" ?><$ROOT><$SUB1>$R1</$SUB1><$SUB2>$R2</$SUB2></$ROOT>] if (($R2 ne '')&&(!$R4));
		$OK=qq[<?xml version="1.0" ?><$ROOT><$SUB1>$R1</$SUB1></$ROOT>] if ($R2 eq '');
#		my $LOG="[$now]-[$Q{INNER_TID}]-[$timer]-[API-RESPONSE-SENT]:$ROOT,$SUB1,$SUB2,$SUB3"; 
		return $HEAD.$OK;
	}#case OK
	case 'ERROR'{
	my	$ERROR=qq[<?xml version="1.0" ?><Error><Error_Message>$R1</Error_Message></Error>\n];
#		my $LOG="[$now]-[$Q{INNER_TID}]-[$timer]-[API-RESPONSE-SENT]: $ERROR\n";
		return $HEAD.$ERROR;
	}#case ERROR
	case 'PLAINTEXT'{
#		my $LOG="[$now]-[$Q{INNER_TID}]-[$timer]-[API-RESPONSE-SENT]: $R1\n";
		$HEAD="Content-Type: text/html\n\n";
		return $HEAD.$R1;
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
my $now=strftime("%a %b %e %H:%M:%S", localtime).":$usec";
##
my ($ACTION_TYPE,$RESPONSE_TYPE,$R1,$R2,$R3,$R4)=@_;
my ($ROOT,$SUB1,$SUB2,$SUB3)=split('::',redis('hget','response',$ACTION_TYPE));
#
switch ($ACTION_TYPE){
case 'RDB'{
	redis('zadd',$Q{INNER_TID},$timer,"[$now]-[$Q{INNER_TID}]-[$timer]-[API-LOG-$RESPONSE_TYPE]:$R1") if $CONF{debug}>0 and $CONF{'debug:imsi'} eq $Q{imsi};
	redis('zadd','tid',$Q{INNER_TID},"[$now]-[$timer]-[$Q{imsi}]-[$Q{request_type}]-[$Q{USSD_CODE}]-[$Q{INNER_TID}]") if $RESPONSE_TYPE eq 'COMMIT' and $CONF{debug}>0;
}#redis DB
case 'LOG'{
 redis('zadd',$Q{INNER_TID},$timer,"[$now]-[$Q{INNER_TID}]-[$timer]-[API-LOG-$RESPONSE_TYPE]:$R1") if $CONF{debug}>0;
 # and $CONF{'debug:imsi'} eq $Q{imsi};
#	redis('publish',$CONF{'redis_subscription'},$Q{INNER_TID}) if $RESPONSE_TYPE eq 'COMMIT';
my	$LOG="[$now]-[$Q{INNER_TID}]-[$timer]-[$Q{imsi}]-[$RESPONSE_TYPE]: $R1" if $CONF{debug}==5;
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
use vars qw($new_sock %Q);
&logger('LOG','LU-REQUEST-IN',"$Q{imsi} $Q{msisdn}") if $CONF{debug}==4;
if ($Q{SUB_ID}>0){#if found subscriber
			my $UPDATE_result=${SQL(qq[SELECT set_country($Q{imsi},$Q{mcc},$Q{mnc},"$Q{msisdn}")],2)}[0];
			redis('hset',$Q{imsi},'msrn','ONLINE');
# Comment due activation proccess
#			if ($UPDATE_result){#if contry change
#			my $msrn=CURL('get_msrn_free',${SQL(qq[SELECT get_uri2('get_msrn',"$Q{imsi}",NULL,NULL,NULL,NULL)],2)}[0]);
#my $TRACK_result=CURL('sms_mt_free',${SQL(qq[SELECT get_uri2('mcc_new',"$Q{imsi}",NULL,"$Q{msisdn}",'ruimtools',"$Q{iot_charge}")],2)}[0]);
	#$TRACK_result=CURL('sms_mt',${SQL(qq[SELECT get_uri2('get_ussd_codes',NULL,NULL,"$Q{msisdn}",'ruimtools',NULL)],2)}[0]);
#				&logger('LOG','MAIN-LU-HISTORY-RETURN',"$TRACK_result");
#			}#if country change
			#&logger('LOGDB',"LU_CDR","$Q{transactionid}","$Q{imsi}",'OK',"$Q{SUB_ID} $Q{imsi} $Q{msisdn}");
			&logger('LOG','LU-REQUEST-OK',"$Q{imsi} $Q{msisdn} $Q{SUB_ID}") if $CONF{debug}==4;
			return ("LU $Q{SUB_ID}",&response('LU_CDR','OK',"$Q{SUB_ID}",'1'));
}else{#else no sub_id
	&logger('LOG','LU-SUB-ID',"SUBSCRIBER NOT FOUND $Q{imsi}") if $CONF{debug}==4;
	&logger('LOGDB','LU_CDR',"$Q{transactionid}","$Q{imsi}",'ERROR','SUBSCRIBER NOT FOUND');
	return ("LU -1",&response('LU_CDR','ERROR','SUBSCRIBER NOT FOUND #'.__LINE__));
	}#else not found
}########## END sub LU_CDR ######################################
#
########## AUTHENTICATION CALLBACK MOC_SIG ######################
## Processing CallBack and USSD requests
################################################################# 
#
sub auth_callback_sig{
use vars qw(%Q);
my @result;
&logger('LOG',"SIG-$Q{USSD_CODE}-REQUEST","$Q{imsi},$Q{USSD_CODE},$Q{USSD_DEST},$Q{USSD_EXT}") if $CONF{debug}==4;
if(($Q{SUB_STATUS}==1)||($Q{USSD_CODE}=~/^(123|100|000|110|111)$/)){#if subscriber active
	if (($Q{USSD_CODE}=~/112/)&&$Q{USSD_DEST}){@result=SPOOL()}
	else{@result=USSD()}
	return @result;
		}#if subscriber active
	else{#status not 1 or balance request
		&logger('LOG','auth_callback_sig-INCORRECT-STATUS',"$Q{SUB_STATUS} #".__LINE__) if $CONF{debug}==4;
		&logger('LOGDB','STATUS',"$Q{transactionid}","$Q{imsi}",'ERROR',"$Q{SUB_STATUS}");
		$Q{email_STATUS}="$Q{SUB_STATUS} $SYS{$Q{SUB_STATUS}}";
		email();
		return ('SIG 0', &response('auth_callback_sig','OK',$Q{transactionid},"$SYS{$Q{SUB_STATUS}}")) if $SYS{$Q{SUB_STATUS}};
		return ('SIG -1', &response('LU_CDR','ERROR','#'.__LINE__.' INCORRECT STATUS')) if !$SYS{$Q{SUB_STATUS}};
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
&logger('LOG','SPOOL-GET-INTERNAL-CALL',"$Q{USSD_DEST}") if $CONF{debug}==1;
		if ($Q{imsi} eq "2341800001".$1){#self call
&logger('LOG','SPOOL-GET-INTERNAL-SELF',"$Q{USSD_DEST}") if $CONF{debug}==1;
	return ("SPOOL WARN -4",&response('auth_callback_sig','OK',$Q{transactionid},${SQL("SELECT get_text(NULL,'spool','dest_self',NULL)",2)}[0]));
		}#if self call
		my $msrn=CURL('get_msrn_free',${SQL(qq[SELECT get_uri2('get_msrn',"2341800001$1",NULL,NULL,NULL,NULL)],2)}[0]);#get msrn for internal call
	$msrn=~s/\+//;#supress \+ from xml response
&logger('LOG','SPOOL-GET-INTERNAL-MSRN-RESULT',$msrn) if $CONF{debug}==1;
		if ($msrn eq 'OFFLINE'){#if dest offline
	return ("SPOOL WARN -5",&response('auth_callback_sig','OK',$Q{transactionid},${SQL("SELECT get_text(NULL,'spool','dest_offline',NULL)",2)}[0]));
		}#if offline
if ($msrn=~/\d{7,15}/){
	$Q{USSD_DEST}=$msrn; $internal=1;
	}else{
&logger('LOGDB','SPOOL',"$Q{transactionid}","$Q{imsi}",'ERROR',"MISSING MSRN $msrn $Q{USSD_DEST} $msrn");
	return ('SPOOL WARN -6', &response('auth_callback_sig','OK',$Q{transactionid},${SQL("SELECT get_text(NULL,'spool','dest_offline',NULL)",2)}[0]));
}#return offline or empty msrn  
}#if internal call
	elsif ($Q{USSD_DEST}=~/^(\+|00)?([1-9]\d{7,15})$/){#elsif outbound call destianation
&logger('LOG','SPOOL-GET-OUTBOUND-CALL',"$Q{USSD_DEST}") if $CONF{debug}==1;
	$Q{USSD_DEST}=$2;#set dest
}#elsif outbound call
else {#else incorrect dest
$Q{USSD_DEST}=0;
}#else incorrect dest
	&logger('LOG','SPOOL-GET-DEST',"$Q{USSD_DEST} in $USSD_dest") if $CONF{debug}==1;
	&logger('LOGDB','SPOOL',"$Q{transactionid}","$Q{imsi}",'CALL',"$msisdn to $Q{USSD_DEST}");
# END INTERNAL CALL
#
# PROCESSING CALL
if ($Q{USSD_DEST}){#if correct destination number process imsi msrn
	my	$msrn=$2 if (($Q{USSD_CODE}==128)&&($Q{USSD_EXT}=~/^(\+|00)?([1-9]\d{7,15})#?$/));#local number call
&logger('LOG','SPOOL-LOCAL-NUMBER-CALL',"$msrn $Q{USSD_EXT}") if $msrn and $CONF{debug}==1;
	$msrn=CURL('get_msrn',${SQL(qq[SELECT get_uri2('get_msrn',"$Q{imsi}",NULL,NULL,NULL,NULL)],2)}[0]) if !$msrn;
	my $offline=1 if $msrn eq 'OFFLINE';
	$msrn=~s/\+//;#supress \+ from xml response
&logger('LOG','SPOOL-GET-MSRN-RESULT',$msrn) if $CONF{debug}==1;
#(!)						my $get_uri=template('get_msrn');
#
if (($msrn=~/\d{7,15}/)and(!$offline)){
## Call SPOOL
	($Q{'DEST_RATE'},$Q{'MSRN_RATE'},$Q{'CB_TRUNKCODE'})=split(':',${SQL(qq[select get_limit($Q{USSD_DEST},$msrn)],2)}[0]);
	$Q{'CB_TRUNKPREFIX'}=$CONF{"trunk:$Q{'CB_TRUNKCODE'}"};
	$Q{'CALL_RATE'}=$Q{'DEST_RATE'}+$Q{'MSRN_RATE'};
	$Q{'CALL_LIMIT'}=floor(($Q{'SUB_CREDIT'}*100/$Q{'CALL_RATE'})*60);
&logger('LOG','SPOOL-GET-TRUNK-[trunk/prefix/rate/limit]',"$Q{SUB_TRUNKCODE}/$Q{'CB_TRUNKPREFIX'}/$Q{CALL_RATE}/$Q{CALL_LIMIT}") if $CONF{debug}==1;
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
#my $mv=`mv $CONF{'TMPDIR'}/$CALLFILE $CONF{'SPOOLDIR'}/$CALLFILE`;
chown 100,101,"$CONF{'TMPDIR'}/$CALLFILE";
my $mv=move("$CONF{'TMPDIR'}/$CALLFILE", "$CONF{'SPOOLDIR'}/$CALLFILE");
#
SQL(qq[select spool($msrn,"$uniqueid","$Q{SUB_TRUNK_TECH}/$Q{'CB_TRUNKPREFIX'}$msrn\@$Q{CB_TRUNKCODE}","$Q{USSD_DEST}","$Q{SUB_CN}","$Q{'MSRN_RATE'}","$Q{'DEST_RATE'}","$Q{'CB_TRUNKCODE'}")],2) if $CONF{'debug'}==4;
#			&logger('LOG','SPOOL-GET-SPOOL',"$uniqueid");
#			&logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'SPOOL',"$uniqueid");
			$Q{USSD_DEST}=$USSD_dest if $internal==1;
#return ("SPOOL-REPLY $mv",&response('auth_callback_sig','OK',$Q{transactionid},${SQL(qq[select get_text($Q{imsi},'spool','wait',"$msrn:$Q{USSD_DEST}")],2)}[0]));
return ("SPOOL-[CALL-ID-RATE] $mv:$uniqueid:$Q{CALL_RATE}",&response('auth_callback_sig','OK',$Q{transactionid},template('spool:wait')));
	}#if msrn and dest
	else{#else not msrn and dest
		&logger('LOGDB','SPOOL',"$Q{transactionid}","$Q{imsi}",'ERROR',"MISSING MSRN $msrn $Q{USSD_DEST} $offline $ERROR");
		return ("SPOOL WARN -2",&response('auth_callback_sig','OK',$Q{transactionid},${SQL("SELECT get_text(NULL,'spool','offline',NULL)",2)}[0]));
		}#else not msrn and dest
}#if dest
else{
		&logger('LOGDB','SPOOL',"$Q{transactionid}","$Q{imsi}",'ERROR',"MISSING DEST $USSD_dest");
		return ("SPOOL WARN -3",&response('auth_callback_sig','OK',$Q{transactionid},${SQL("SELECT get_text(NULL,'spool','nodest',NULL)",2)}[0]));
}#else dest	
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
		&logger('LOG','SIG-USSD-SUPPORT-REQUEST',"$Q{USSD_CODE}") if $CONF{debug}==4;
		#&logger('LOGDB','support',"$Q{transactionid}","$Q{imsi}",'OK',"$Q{USSD_CODE}");
		$Q{email}="denis\@ruimtools.com";
		$Q{email_sub}="NEW TT: [$Q{imsi}]";
		$Q{email_text}=${SQL(qq[NULL,'ussd',$Q{USSD_CODE},NULL],1)}[0];
		$Q{email_FROM}="SUPPORT";
		$Q{email_from}="denis\@ruimtools.com";
		email();
		return ("USSD 0",&response('auth_callback_sig','OK',$Q{transactionid},${SQL(qq[NULL,'ussd',$Q{USSD_CODE},NULL],1)}[0]));		
			}#case 000
###
	case "100"{#MYNUMBER request
		&logger('LOG','SIG-USSD-MYNUMBER-REQUEST',"$Q{USSD_CODE}") if $CONF{debug}==4;
		#&logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'OK',"$Q{USSD_CODE}");
#		my $number=uri_unescape("$Q{msisdn}");
#(!)		return ("USSD 0",&response('auth_callback_sig','OK',$Q{transactionid},${SQL(qq[$Q{imsi},'ussd',$Q{USSD_CODE},NULL],1)}[0]));
		return ("USSD 0",&response('auth_callback_sig','OK',$Q{transactionid},template('ussd:100')));		
	}#case 100
###
	case "110"{#IMEI request
		&logger('LOG','SIG-USSD-IMEI-REQUEST',"$Q{USSD_DEST}") if $CONF{debug}==4;
		#&logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'OK',"$Q{USSD_CODE} $Q{USSD_DEST}");
		if (length($Q{USSD_DEST})==15){
		my $SQL=qq[UPDATE cc_card set address="$Q{USSD_DEST} $Q{USSD_EXT}" where useralias="$Q{imsi}" or firstname="$Q{imsi}"];
		my $SQL_result=&SQL($SQL);}#if length
		return ("USSD $Q{USSD_DEST}",&response('auth_callback_sig','OK',$Q{transactionid},"RuimTools registered"));
		;
	}#case 110
###
	case "122"{#SMS request
		&logger('LOG','SIG-USSD-SMS-REQUEST',"$Q{USSD_CODE} $Q{USSD_DEST} $Q{USSD_EXT}") if $CONF{debug}==4;
		#&logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'OK',"$Q{USSD_CODE} $Q{USSD_DEST} $Q{USSD_EXT}");
		my $SMS_result=SMS();#process sms
		my $SMS_response=${SQL(qq[NULL,'ussd',$Q{USSD_CODE}$SMS_result,NULL],1)}[0];#get response text by sms result
		$SMS_response="Sorry, unknown result. Please call *000#" if $SMS_response eq '';#something wrong - need support
		&logger('LOG','SIG-USSD-SMS-RESULT',"$SMS_result") if $CONF{debug}==4;
		#&logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'RSP',"$SMS_result");
		return ("USSD $SMS_result", &response('auth_callback_sig','OK',$Q{transactionid},"$SMS_response"));
		
	}#case 122
###
	case [111,123]{#voucher refill request
		$Q{USSD_CODE}=123 if $Q{USSD_CODE}==111;
		&logger('LOG','SIG-USSD-BALANCE-REQUEST',"$Q{USSD_CODE}") if $CONF{debug}==4;
		my $balance=CURL('get_user_info',template('get_user_info'));
#(!)		my $balance=CURL('get_user_info',${SQL(qq[SELECT get_uri2('get_user_info',"$Q{imsi}",NULL,NULL,NULL,NULL)],2)}[0]);
		return ('USSD 0',&response('auth_callback_sig','OK',$Q{transactionid},${SQL(qq[$Q{imsi},'ussd',$Q{USSD_CODE},$balance*1.25],1)}[0])) if !$Q{USSD_DEST};
		my $voucher_add=${SQL(qq[SELECT voucher("$Q{SUB_CN}","$Q{USSD_DEST}")],2)}[0];
			&logger('LOG','SIG-USSD-VOUCHER-RESULT',"$voucher_add $Q{USSD_DEST}") if $CONF{debug}==4;
			#&logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'RSP',"$voucher_add $Q{USSD_CODE} $Q{USSD_DEST}");
my $result=CURL('set_user_balance',${SQL(qq[SELECT get_uri2('set_user_balance',"$Q{imsi}",NULL,NULL,$Q{USSD_DEST},NULL)],2)}[0]) if $voucher_add==11;
			$balance=CURL('get_user_info',${SQL(qq[SELECT get_uri2('get_user_info',"$Q{imsi}",NULL,NULL,NULL,NULL)],2)}[0]) if $voucher_add==11;
			return ("USSD $voucher_add $result", &response('auth_callback_sig','OK',$Q{transactionid},${SQL(qq[$Q{imsi},'ussd',$Q{USSD_CODE}$voucher_add,$balance*1.25],1)}[0]));
			
	}#case 123
###
#	case "124"{#support old sim configuration
#	$Q{USSD_CODE}="123";
#	return "USSD ".USSD();
#	}#case 124
###
	case "125"{#voip account
	&logger('LOG','SIG-USSD-VOIP-ACCOUNT-REQUEST',"$Q{USSD_CODE}") if $CONF{debug}==4;
	my $new_user=CURL('new_user',${SQL(qq[SELECT get_uri2('new_user',"$Q{imsi}",NULL,NULL,NULL,NULL)],2)}[0]) if !$Q{SUB_VOIP};
	#&logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'RSP',"$Q{USSD_CODE} $new_user") if !$Q{SUB_VOIP};
	return ("USSD 0", &response('auth_callback_sig','OK',$Q{transactionid},${SQL(qq[$Q{imsi},'ussd',$Q{USSD_CODE},NULL],1)}[0]));
	}#case 124
###
	case "126"{#RATES request
		&logger('LOG','SIG-USSD-RATES',"$Q{USSD_CODE} $Q{USSD_DEST}") if $CONF{debug}==4;
		#&logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'OK',"$Q{USSD_CODE} $Q{USSD_DEST}");
		return ("USSD -1",&response('auth_callback_sig','OK',$Q{transactionid},"Please check destination number!")) if $Q{USSD_DEST} eq '';
		$Q{USSD_DEST}=~/^(\+|00)?([1-9]\d{1,15})$/;
		my $dest=$2;
		my $msrn=CURL('get_msrn',${SQL(qq[SELECT get_uri2('get_msrn',"$Q{imsi}",NULL,NULL,NULL,NULL)],2)}[0]);
		my $rate=${SQL(qq[SELECT round(get_rate($msrn,$dest),2)],2)}[0] if $msrn=~/^(\+)?([1-9]\d{7,15})$/;
		&logger('LOG','SIG-USSD-RATES-RETURN',"$rate") if $CONF{debug}==4;
	return ("USSD 0",&response('auth_callback_sig','OK',$Q{transactionid},"Callback rate to $Q{USSD_DEST}: \$ $rate. Extra: ".substr($Q{iot_charge}/0.63,0,4))) if $rate=~/\d/;
		return ("USSD 0",&response('auth_callback_sig','OK',$Q{transactionid},"Sorry, number offline")) if $msrn=~/OFFLINE/;
	}#case 126
###
	case "127"{#CFU request
		&logger('LOG','SIG-USSD-CFU-REQUEST',"$Q{USSD_CODE} $Q{USSD_DEST}") if $CONF{debug}==4;
		if ($Q{USSD_DEST}=~/^(\+|00)?(\d{5,15})$/){#if prefix +|00 and number length 5-15 digits
			&logger('LOG','SIG-USSD-CFU-REQUEST',"Subcode processing $Q{USSD_DEST}") if $CONF{debug}==4;
				 my $CFU_number=$2;
				 my $SQL=qq[SELECT get_cfu_code($Q{imsi},"$CFU_number")];
					my $CODE=${SQL("$SQL",2)}[0];
$CODE=CURL('sms_mo',${SQL(qq[SELECT get_uri2('sms_mo',NULL,"+$CFU_number","$Q{msisdn}",'ruimtools',"$CODE")],2)}[0]) if $CODE=~/\d{5}/;
					$CFU_number='NULL' if $CODE!~/0|1|INUSE/;
					$SQL=qq[SELECT get_cfu_text("$Q{imsi}","$CODE",$CFU_number)];
					my $TEXT_result=${SQL("$SQL",2)}[0];
					return ("USSD $CODE",&response('auth_callback_sig','OK',$Q{transactionid},$TEXT_result));
					#&logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'RSP',"$CODE $Q{USSD_CODE} $Q{USSD_DEST}");
			}#if number length
			else{#else check activation
			&logger('LOG','SIG-USSD-CFU-REQUEST',"Code processing $Q{USSD_CODE} $Q{USSD_DEST}") if $CONF{debug}==4;
				my $SQL=qq[SELECT get_cfu_text("$Q{imsi}",'active',NULL)];
				#my @SQL_result=&SQL($SQL);
				my $TEXT_result=${SQL("$SQL",2)}[0]; 
				return ("USSD $Q{USSD_CODE} $Q{USSD_DEST}",&response('auth_callback_sig','OK',$Q{transactionid},"$TEXT_result"));
				#&logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'RSP',"$Q{USSD_CODE} $Q{USSD_DEST}");
				}
	}#case 127
###
	case "128"{#local call request
		&logger('LOG','SIG-LOCAL-CALL-REQUEST',"$Q{USSD_CODE}") if $CONF{debug}==4;
		#&logger('LOGDB','auth_callback_sig',"$Q{transactionid}","$Q{imsi}",'OK',"$Q{USSD_CODE}");
		my $SPOOL_result=SPOOL() if $Q{USSD_EXT};
		return "USSD 1, $SPOOL_result" if $Q{USSD_EXT};
		return ('USSD 0', &response('auth_callback_sig','OK',$Q{transactionid},${SQL(qq["$Q{imsi}",'ussd',$Q{USSD_CODE},$Q{mcc}],1)}[0]));
	}#case 128
###
	case "129"{#my did request
		&logger('LOG','SIG-DID-NUMBERS-REQUEST',"$Q{USSD_CODE} $Q{USSD_DEST} $Q{USSD_EXT}") if $CONF{debug}==4;#(!) hide pin
		$Q{USSD_DEST}=$Q{imsi} if ($Q{USSD_DEST}!~/^(\+|00)?([1-9]\d{7,15})$/);
		if ($Q{USSD_EXT}=~/^([0-9]\d{3})#?$/){# check pin
		$Q{-o}='-d';
		($Q{-h},$Q{user},$Q{pass})=@{SQL(qq[SELECT description,auth_login,auth_pass from cc_provider WHERE provider_name='C94'],2)};
		$Q{actions}='SimInformationByMSISDN'; $Q{request}='IMSI';
		CURL($Q{actions},XML());
		&logger('LOG','SIG-DID-NUMBERS-PIN-CHECK',"SUCCESS") if $1==$Q{PIN} and $CONF{debug}==4;;
		&logger('LOG','SIG-DID-NUMBERS-PIN-CHECK',"ERROR") if $1!=$Q{PIN} and $CONF{debug}==4;
		return ('USSD -1',&response('auth_callback_sig','OK',$Q{transactionid},"Please enter correct PIN")) if $1!=$Q{PIN};
		$Q{USSD_DEST}=$Q{SUB_ID};
		}#if pin
		my $did=${SQL(qq[SELECT set_did("$Q{USSD_DEST}")],2)}[0];
		return ('USSD 0', &response('auth_callback_sig','OK',$Q{transactionid},"$did"));
	}#case 128
###

	else{#switch ussd code
	return ('USSD -3',&response('auth_callback_sig','OK',$Q{transactionid},${SQL(qq["$Q{imsi}",'ussd',$Q{USSD_CODE},NULL],1)}[0]));
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
$DATA=$DATA.'&'.$Q{SUB_AGENT_METHOD}.'='.$Q{SUB_AGENT_AUTH} if $Q{SUB_AGENT_AUTH} ne '';
#
&logger('LOG',"API-CURL-$MSG-PARAM","$HOST $DATA") if $CONF{debug}==5;
#
return $CONF{'fake-msrn'} if $CONF{'debug'}==4&&$CONF{'fake-msrn'}&&$MSG eq 'get_msrn';
return 'OFFLINE' if redis('hget',"$Q{imsi}:msrn",'msrn') eq 'OFFLINE'&&$MSG eq 'get_msrn';
#
our $curl = WWW::Curl::Easy->new;
$curl->setopt (CURLOPT_SSL_VERIFYHOST, 0);
$curl->setopt( CURLOPT_SSL_VERIFYPEER, 0);
$curl->setopt( CURLOPT_POSTFIELDS, $DATA);
$curl->setopt( CURLOPT_POSTFIELDSIZE, length($DATA));
$curl->setopt( CURLOPT_POST, 1);
$curl->setopt( CURLOPT_CONNECTTIMEOUT,5);
$curl->setopt( CURLOPT_HEADER, 1);
$curl->setopt( CURLOPT_URL, $HOST);
$curl->setopt( CURLOPT_WRITEDATA, \$response_body);
#
$DATA=~/request_type=(\w{0,20})/;
&logger('LOGDB',"$MSG","$transaction_id","$Q{imsi}",'IN',"$MSG:CURL $1"); 
#
if ($DATA){
eval {use vars qw($curl $response_body %Q); &logger('LOG',"API-CURL-$MSG-REQ",$HOST.' '.length($DATA)) if $CONF{debug}==4;
my $retcode = $curl->perform;
my $response_code = $curl->getinfo(CURLINFO_HTTP_CODE) if $retcode==0;
&logger('LOG',"API-CURL-ERROR-BUF",$curl->strerror($retcode)) if $retcode!=0 and $CONF{debug}==4;
$Q{curl_error}=$curl->strerror($retcode) if $retcode!=0; 
};warn $@ if $@;  &logger('LOG',"API-CURL-ERROR","$@") if $@;
}#if URI
else{return 0}#else URI empty
#
use vars qw($response_body);
if ($response_body){
	&logger('LOG',"$MSG-RESPOND","$response_body") if $CONF{debug}==4;
	my $CURL_result=&XML_PARSE("$response_body",$MSG);
	&logger('LOGDB',$MSG,"$transaction_id","$Q{imsi}",'OK',"$CURL_result $Q{iot_charge}") if $CURL_result ne '';
	&logger('LOGDB',$MSG,"$transaction_id","$Q{imsi}",'ERROR','CURL NO RESPONSE') if $CURL_result eq '';
	return $CURL_result;
}#if CURL return
else{# timeout
	&logger('LOG',"$MSG-REQUEST","Timed out 5 sec with socket") if $CONF{debug}==4;
	&logger('LOGDB',$MSG,"$transaction_id","$Q{imsi}",'ERROR','Timed out 5 sec with socket:'.$Q{curl_error});
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
#use vars qw($INNER_TID);
my $auth_result=&auth('AGENT');#turn on auth for all types of api requests
$auth_result=0 if $Q{sub_code} eq 'get_card_number';
if ($auth_result==0){&logger('LOG','RC-API-CMD',"AUTH OK $auth_result") if $CONF{debug}==4;}#if auth
else{
&logger('LOGDB',"$Q{USSD_CODE}","$Q{transactionid}","$Q{imsi}",'ERROR',"NO AUTH $auth_result $Q{auth_key}");
&logger('LOG','RC-API-CMD',"AUTH ERROR $auth_result $Q{options}") if $CONF{debug}==4;
return ('CMD -1',&response('rc_api_cmd','OK',$Q{transactionid},"NO AUTH")) if $Q{options} ne 'cleartext';
return ('CMD -1',&response('rc_api_cmd','PLAINTEXT',"$Q{transactionid},ERROR,-3")) if $Q{options} eq 'cleartext';
}#else no auth				
my $result;
&logger('LOG','RC-API-CMD',"$Q{code}") if $CONF{debug}==4;
switch ($Q{code}){
	case 'ping' {#PING
		sleep 7 if $Q{options} eq 'sleep';
		return ('CMD 0', &response('rc_api_cmd','OK',$Q{transactionid},"PING OK ".time()." $Q{INNER_TID}"));
	}#case ping
	case 'get_msrn' {#GET_MSRN
		my $msrn;
		if ($Q{imsi}){#if imsi defined
			$msrn=CURL('get_msrn',${SQL(qq[SELECT get_uri2('get_msrn',"$Q{imsi}",NULL,NULL,NULL,NULL)],2)}[0]);
			return ('CMD 1',&response('rc_api_cmd','OK',$Q{transactionid},"$msrn")) if $Q{options} ne 'cleartext';
			$msrn=~s/\+// if $Q{options} eq 'cleartext';#cleartext for ${EXTEN} usage
			return ('CMD 1',&response('rc_api_cmd','PLAINTEXT',$msrn)) if $Q{options} eq 'cleartext';
		}#if imsi
		else{#if no imsi
			&logger('LOGDB',"$Q{code}","$Q{transactionid}","$Q{imsi}",'ERROR',"IMSI UNDEFINED $Q{imsi}");
			return ('CMD -1', &response('rc_api_cmd','ERROR',"IMSI UNDEFINED $Q{imsi} $msrn"));
		}#else no imsi
	}#case msrn
	case 'get_did' {#PROCESS DID number
		#
		&logger('LOG','RC-API-CMD-DID-[did/src]',"$Q{rdnis}/$Q{src}") if $CONF{debug}==4;
			if (length($Q{rdnis})==6){
				$Q{imsi}=$CONF{'imsi_prefix'}.$Q{rdnis};
				GET_TYPE();
				}#GROUP CALL
			else{#IMSI CALL
				$Q{imsi}=redis('hget',"did:$Q{rdnis}",'imsi');
				}#IMSI CALL
		if ($Q{imsi}=~/$CONF{'imsi_prefix'}/){#if did assigned to imsi
		GET_TYPE();
		my $msrn=CURL('get_msrn',template('get_msrn'));
			if ($msrn=~/\d{7,15}/){
				($Q{'MSRN_RATE'},$Q{'CB_TRUNK'})=split(':',${SQL(qq[select get_limit(NULL,$msrn)],2)}[0]);
				$msrn=$CONF{"trunk:$Q{'CB_TRUNK'}"}.$msrn;
				$Q{'CALL_LIMIT'}=floor(($Q{'SUB_CREDIT'}*100/$Q{'MSRN_RATE'})*60);
				return ('CMD 1',&response('rc_api_cmd','PLAINTEXT',"$Q{transactionid}:$Q{'SUB_CN'}:$msrn:$Q{'CALL_LIMIT'}:$Q{'CB_TRUNK'}"));
			}else{
				return ('CMD -1',&response('rc_api_cmd','PLAINTEXT',"$Q{transactionid}:OFFLINE:-1"));
				}#else msrn 7-15
		}#if imsi call
#		&logger('LOG','RC-API-CMD-DID-RESULT',"$did") if $CONF{debug}==4;
#			if ($did ne '-1'){#if did assigned
#				($Q{accountcode},$Q{imsi},$Q{SUB_CREDIT},$Q{rid},$Q{limit},$Q{trunk})=split(':',$did);	
#				if (($Q{rid})&&($Q{limit}>30)){#get redirect call
##	return ('CMD 1',&response('rc_api_cmd','PLAINTEXT',"$Q{transactionid}:$Q{accountcode}:$Q{rid}:$Q{limit}:$Q{trunk}"));
#				}elsif($Q{rid}==0){#get msrn call
#					&logger('LOGDB',"$Q{code}","$Q{transactionid}","$Q{imsi}",'IN',"get_did:$Q{rdnis}:$Q{src}");
#					my $msrn=CURL('get_msrn',${SQL(qq[SELECT get_uri2('get_msrn',"$Q{imsi}",NULL,NULL,NULL,NULL)],2)}[0]);
#					$msrn=~tr/\+//;
#					$Q{limit}=600;
# (!)					$Q{limit}=${SQL(qq[SELECT IFNULL(get_limit(NULL,"$msrn",$Q{SUB_CREDIT}),-1)],2)}[0] if $msrn=~/\d{7,15}/;
#						if (($msrn=~/\d{7,17}/)&&($Q{limit}>30)){
#	return ('CMD 1',&response('rc_api_cmd','OK',$Q{transactionid},"$Q{msrn}","$Q{accountcode}")) if $Q{options} ne 'cleartext';
#							$msrn=~tr/\+// if $Q{options} eq 'cleartext';#cleartext for ${EXTEN} usage
#	return ('CMD 1',&response('rc_api_cmd','PLAINTEXT',"$Q{transactionid}:$Q{accountcode}:$msrn:$Q{limit}:$Q{trunk}")) if $Q{options} eq 'cleartext';
#							}else{#if msrn
#	return ('CMD -1',&response('rc_api_cmd','OK',$Q{transactionid},"OFFLINE","CODE:-1")) if $Q{options} ne 'cleartext';
#	return ('CMD -1',&response('rc_api_cmd','PLAINTEXT',"$Q{transactionid}:OFFLINE:-1")) if $Q{options} eq 'cleartext';
#						}#else msrn
#				}#elseif imsi call		
#			}else{#else did
#	return ('CMD -2',&response('rc_api_cmd','OK',"$Q{transactionid}","NODID","CODE:-2")) if $Q{options} ne 'cleartext';
#	return ('CMD -2',&response('rc_api_cmd','PLAINTEXT',"$Q{transactionid}:NODID:-2")) if $Q{options} eq 'cleartext';
#			}#else did
	}#case get_did
	case 'get_stat' {#GET STAT
		my $SQL;
		switch ($Q{sub_code}){#switch CMD
			case 'get_card_number'{$SQL=qq[SELECT $Q{sub_code}($Q{card_number})]}
			else {$SQL=qq[SELECT -1]}
			return 'CMD -1';
			}#switch CMD
			$result=${SQL("$SQL",2)}[0];
			return ('CMD 1',&response('rc_api_cmd','OK',$Q{transactionid},"$result"));
		}#case get_stat
	case 'send_ussd' {#SEND_USSD
		$result=CURL('send_ussd',${SQL(qq[SELECT get_uri2("$Q{code}",NULL,NULL,"$Q{msisdn}","$Q{sub_code}",NULL)],2)}[0]);
		return ('CMD 1',&response('rc_api_cmd','OK',$Q{transactionid},"$Q{msisdn} $result"));
		}#case send_ussd
	case 'get_session_time' {#Get max session time
		$result=CURL('get_session_time',${SQL(qq[select get_uri2('get_session_time',$Q{imsi},NULL,$Q{msisdn},NULL,NULL)],2)}[0]);
		return ('CMD -1',&response('rc_api_cmd','PLAINTEXT',$result)) if $Q{options} eq 'cleartext';
		return ('CMD -1',&response('rc_api_cmd','OK',$Q{transactionid},"$result")) if $Q{options} ne 'cleartext';;
		}#case get_session_time
	else {
		&logger('LOG','RC-API-CMD-UNKNOWN',"$Q{code}") if $CONF{debug}==4;
		&logger('LOGDB','API-CMD',"$Q{transactionid}","$Q{imsi}",'ERROR',"$Q{code}");
		return ('CMD -1',&response('rc_api_cmd','OK',$Q{transactionid},"UNKNOWN CMD REQUEST"));
		}#else switch code
}#switch code
		&logger('LOG','RC-API-CMD',"$Q{code} $result") if $CONF{debug}==4;
		&logger('LOGDB',"$Q{code}","$Q{transactionid}","$Q{imsi}",'OK',"RESULT $result");
		return "CMD $result";
}##### END sub RC_API_CMD ########################################
#
##### AGENT ################################################
## Process agent request
## Accept request type, imsi, reseller auth_key, options
## Return message to subscriber
#################################################################
sub agent{
use vars qw(%Q);
my $CURL_result;
my $ussd_code='CB' if $Q{USSD_CODE} eq '112';
$ussd_code='UD' if $Q{USSD_CODE}!~/112|LU/;
$ussd_code=$Q{request_type} if $Q{request_type}=~/CDR|POSTDATA|DataAUTH|SMS/;
my $OPT1=$Q{USSD_CODE};
my $OPT2="$Q{USSD_DEST}";
#$OPT2="$Q{USSD_DEST}&$Q{iot}&$Q{iot_charge}" if $Q{iot}==1; #temporary commented but needed
if ($Q{request_type}=~/LU/){
$OPT1=$Q{mnc};
$OPT2=$Q{mcc};
}#if LU
&logger('LOG',"AGENT-REQUEST-$ussd_code-[agentid/auth]","$Q{SUB_AGENT_ID}/$Q{SUB_AGENT_AUTH}") if $CONF{debug}==4;
$CURL_result=CURL("SIG_SendAgent_$ussd_code",${SQL(qq[SELECT get_uri2("SIG_SendAgent_$ussd_code","$Q{imsi}",NULL,NULL,"$OPT1","$OPT2")],2)}[0]);
&logger('LOG',"AGENT-RESPONSE-$ussd_code","$CURL_result") if $CONF{debug}==4;
return "$CURL_result";
}# END sub AGENT
##################################################################
#
### SUB AUTH ########################################################
## Keys stored in cc_agent auth_key & cc_epaymntner auth_key
## On insert trigger cc_agent generate md5 hash and crypt it with AES
## ipay send email with keys one time. Crypted AES in db
## To decrypt AES we use KEY entered on start
## Agent send us auth_key
## Ipay send us solt and sign
#####################################################################
#
sub auth{
#use vars qw($KEY);
#my ($type,$data,$sign,$key)=@_;
#&logger('LOG',"RC-API-$type-AUTH","$Q{REMOTE_ADDR}:$Q{SUB_AGENT_DATA}:$Q{agent}:$data:$sign") if $CONF{debug}==4;
#&logger('LOG',"RC-API-$type-AUTH","$Q{REMOTE_ADDR} $Q{SUB_AGENT_DATA} $Q{agent}") if $CONF{debug}==4;;
#switch ($type){#select auth type
#	case "AGENT"{#resale auth
#		$Q{REMOTE_ADDR}=~s/\.//g;#cut dots
#		$data=$Q{REMOTE_ADDR};
#		$key=${SQL(qq[SELECT AES_DECRYPT(auth_key,"$CONF{key}") from cc_agent WHERE login="$Q{agent}"],2)}[0];# KEY was input on starting
#		$sign=$Q{auth_key};
#	}#case resale
#	case "PAYMNT"{#paymnt auth
#		$key=${SQL(qq[SELECT AES_DECRYPT(auth_key,"$CONF{key}") from cc_epaymnter WHERE name="IPAY"],2)}[0];# KEY was input on starting
#		$data=$Q{salt};
#	}#case paymnt
#else{
#	&logger('LOG',"RC-API-AUTH-RETURNED","Error: UNKNOWN TYPE $type") if $CONF{debug}==4;
#	}#end else switch type
#}#end switch type 
#&logger('LOG',"RC-API-$type-DIGEST","$data  $key") if $CONF{debug}==4;
my	$md5 = Digest::MD5->new;
	$md5->add($Q{REMOTE_ADDR}, $Q{auth_key}, $Q{agent});
my	$digest = $md5->hexdigest;
#my $digest=hmac_sha512_hex("$data","$key");#lets sign data with key
#my $dgst=substr($digest,0,7);#short format for logfile
#my $sgn=substr($sign,0,7);#short format for logfile
logger('LOG',"RC-API-DIGEST-CHECK","$digest") if $CONF{debug}==4;
if ($digest eq redis('hget',"agent:$Q{agent}",'key')){#if ok
&logger('LOG','RC-API-AUTH',"OK") if $CONF{debug}==4;
return 0;
}#end if ok
else{#digest != sign
&logger('LOG','RC-API-AUTH',"NO AUTH") if $CONF{debug}==4;
return -1;
	}#else if auth OK
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
&logger('LOG','PAYMNT-EPMTS-SQL-RESULT',"$SQL_P_result") if $CONF{debug}==4;
## AUTH
if (auth('PAYMNT',$Q{REQUEST}->{payment}{salt},$Q{REQUEST}->{payment}{sign})==0){
	&logger('LOG','PAYMNT-TR-RESULT',"@IDs") if $CONF{debug}==4;
		foreach my $TR (@{$Q{REQUEST}->{payment}{transactions}{transaction}}){#for each transaction id
			$TR->{desc}=~/(\d{1,12})/;
			$CARD_NUMBER=$1;
my $SQL=qq[INSERT INTO cc_epayments_transactions (`id`,`mch_id`, `srv_id`,`amount`,`currency`,`type`,`status`,`code`, `desc`,`info`) values("$TR->{id}","$TR->{mch_id}","$TR->{srv_id}","$TR->{amount}","$TR->{currency}","$TR->{type}","$TR->{status}","$TR->{code}","$TR->{desc}","$CARD_NUMBER")];
$SQL_T_result=&SQL($SQL);
&logger('LOG','PAYMNT-TR-SQL-RESULT',"$SQL_T_result") if $CONF{debug}==4;
		}#foreach tr
}#end if auth
else{#else if auth
	&logger('LOG','PAYMNT-AUTH-RESULT',"NO AUTH") if $CONF{debug}==4;
}#end esle if auth
	$Q{imsi}=${SQL(qq[SELECT useralias from cc_card WHERE username=$CARD_NUMBER],2)}[0];
	&logger('LOGDB',"PAYMNT","$Q{REQUEST}->{payment}{id}","$Q{imsi}",'RSP',"$CARD_NUMBER $SQL_T_result @IDs");
	return ('PAYMNT 1',&response('payment','PLAINTEXT',"200 $SQL_T_result"));
# we cant send this sms with no auth because dont known whom
	my $SMSMT_result=CURL('sms_mt',${SQL(qq[SELECT get_uri2("pmnt_$SQL_T_result","$CARD_NUMBER",NULL,NULL,"$CARD_NUMBER","$Q{REQUEST}->{payment}{id}")],2)}[0]);
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
&logger('LOG','PAYPAL-RESULT',"$result") if $CONF{debug}==4;
&logger('LOGDB',"PAYPAL","$Q{txn_id}","$Q{btn_id}",'RESULT',"$result");
#
#send payment confirmation to email
#
if ($Q{payer_email}){
$email_text=uri_unescape(${SQL(qq[SELECT paypal("$Q{txn_id}","$result")],2)}[0]);
eval {use vars qw(%Q $email $email_pri $email_text);&logger('LOG','PAYPAL-GET-EMAIL',"$Q{receipt_id} $Q{payer_email} $email") if $CONF{debug}==4;;
$email_pri=`echo "$email_text" | mail -vs 'Payment $Q{receipt_id}' $Q{payer_email} $email -- -F "CallMe! Payments" -f pay\@ruimtools.com`;
};warn $@ if $@;  &logger('LOG',"PAYPAL-SEND-EMAIL-ERROR","$@") if $@;
}#if email
else{$email_pri="No email address"}#else email empty
#
&logger('LOG','PAYPAL-SEND-EMAIL',"$email_pri") if $CONF{debug}==4;;
# send sms notification to primary phone number
my $sms_pri=CURL('sms_mt',${SQL(qq[SELECT get_uri2('sms_mt',NULL,"${SQL(qq[SELECT phone FROM cc_card WHERE username=$Q{'personal_number'}],2)}[0]","ruimtools",NULL,"${SQL(qq[SELECT paypal("$Q{txn_id}","$result")],2)}[0]")],2)}[0]) if $Q{'personal_number'};
# send sms notification to additional phone number
my $sms_add=CURL('sms_mo',${SQL(qq[SELECT get_uri2('sms_mo',NULL,"+$rcpt","+447700079964","ruimtools","${SQL(qq[SELECT paypal("$Q{txn_id}","$result")],2)}[0]")],2)}[0]) if $rcpt;
#
&logger('LOG','PAYPAL-SEND-RESULT',"$rcpt $sms_pri $sms_add") if $CONF{debug}==4;;
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
&logger('LOG','SMS-REQ',"$Q{USSD_DEST} $Q{USSD_EXT}") if $CONF{debug}==3;
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
&logger('LOG','SMS-REQ',"$sms_to") if $CONF{debug}==4;
my $sql_erorr_update_result=${SQL(qq[UPDATE cc_sms set status="-1" where src="$Q{msisdn}" and flag="$page$pg_num" and seq="$seq" and dst="$sms_to" and status=0 and imsi=$Q{imsi}],2)}[0];#to avoid double sms HFX-970
&logger('LOG','SMS-REWRITE',"$sql_erorr_update_result") if $CONF{debug}==4;
#store page to db
my $INSERT_result=${SQL(qq[INSERT INTO cc_sms (`sms_id`,`src`,`dst`,`flag`,`seq`,`text`,`inner_tid`,`imsi`) values ("$Q{transactionid}","$Q{msisdn}","$sms_to","$page$pg_num","$seq","$sms_long_text","$Q{INNER_TID}","$Q{imsi}")],2)}[0];
&logger('LOG','SMS-INSERT',"$INSERT_result") if $CONF{debug}==4;
#if insert ok
	if ($INSERT_result>0){#if insert ok
#if num page
		if ($pg_num eq $page){#if only one or last page - prepare sending
			($sms_long_text,$type,$sms_from)=split('::',${SQL(qq[SELECT get_sms_text2("$Q{msisdn}","$sms_to",$Q{imsi},$seq)],2)}[0]);#get text
			$sms_from=~s/\+//;#'+' is deprecated by C9 standart		
				if ($sms_long_text){#if return content
					my @multi_sms=($sms_long_text=~/.{1,168}/gs);#divide long text to 168 parts
					foreach $sms_text (@multi_sms){#foreach parth one sms
						&logger('LOG','SMS-ENC-RESULT',"$sms_text") if $CONF{debug}==4;
						$sms_text=uri_escape($sms_text);#url encode
						&logger('LOG','SMS-TEXT-ENC-RESULT',"$sms_text") if $CONF{debug}==4;
						&logger('LOG','SMS-SEND-PARAM',"$sms_from,$sms_to") if $CONF{debug}==4;
#internal subscriber
							if ($type eq 'IN'){#internal subscriber
								&logger('LOG','SMS-REQ',"INTERNAL") if $CONF{debug}==4;								
#MSG_CODE, IMSI_, DEST_, MSN_, OPT_1, OPT_2
$sms_result=CURL('sms_mt',${SQL(qq[SELECT get_uri2('sms_mt',NULL,"$sms_to","$sms_from",NULL,"$sms_text")],2)}[0]);#send sms mt
					#bill_user($Q{imsi},'sms_mt');
								}#if internal
#external subscriber
							elsif($type eq 'OUT'){
								&logger('LOG','SMS-REQ',"EXTERNAL") if $CONF{debug}==4;
$sms_result=CURL('sms_mo',${SQL(qq[SELECT get_uri2('sms_mo',NULL,"$sms_to","$Q{msisdn}","$sms_from","$sms_text")],2)}[0]);#send sms mo
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
&logger('LOGDB','MO_SMS',$Q{transactionid},$Q{imsi},'RSP',"RuimTools 0");
return('MO_SMS 1',&response('MO_SMS','OK',$Q{transactionid},0,'RuimTools'));#By default reject outbound SMS MO
}#end sub MO_SMS
#
### sub MT_SMS ##################################################################
#
# Authenticate inbound SMS request ##############################################
###
sub MT_SMS{
&logger('LOGDB','MT_SMS',$Q{transactionid},$Q{imsi},'RSP',"1");
return('MT_SMS 1',&response('MT_SMS','OK',$Q{transactionid},1));# By default we accept inbound SMS MT
}#end sub MT_SMS
#
### sub MOSMS_CDR ##################################################################
#
# MOSMS (Outbound) CDRs ############################################################
##
sub MOSMS_CDR{
	my $CDR_result=&SMS_CDR;
	&logger('LOG','MOSMS_CDR',$CDR_result) if $CONF{debug}==4;
	&logger('LOGDB','MOSMS_CDR',$Q{transactionid},$Q{imsi},'RSP',"$CDR_result");
	return('MOSMS_CDR 1',&response('MOSMS_CDR','OK',$Q{transactionid},$CDR_result));
}#end sub MOSMS_CDR ################################################################
#
### sub MTSMS_CDR ##################################################################
# MTSMS (Inbound) CDRs
###
sub MTSMS_CDR{
	my $CDR_result=&SMS_CDR;
	&logger('LOG','MTSMS_CDR',$CDR_result) if $CONF{debug}==4;
	&logger('LOGDB','MTSMS_CDR',$Q{transactionid},$Q{imsi},'RSP',"$CDR_result");
	return('MTSMS_CDR 1',&response('MTSMS_CDR','OK',$Q{transactionid},$CDR_result));
}#end sub MTSMS_CDR ################################################################
#
### sub SMSContent_CDR
# SMS Content CDRs #################################################################
##
sub SMSContent_CDR{
	use vars qw(%Q);#workaround #19 C9RFC
	$Q{'cdr_id'}='NULL';#workaround #19 C9RFC
	my $CDR_result=&SMS_CDR;
	&logger('LOG','SMSContent_CDR',$CDR_result) if $CONF{debug}==4;
	&logger('LOGDB','SMSContent_CDR',$Q{transactionid},$Q{imsi},'RSP',"$CDR_result");
	return('SMSContent_CDR 1',&response('MT_SMS','OK',$Q{transactionid},$CDR_result));
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
&logger('LOG','SMS_CDR',$sql_result) if $CONF{debug}==4;
return $sql_result; 
}#end sub SMS_CDR ##################################################################
# end SMS section ##################################################################
#
### sub DataAUTH ###################################################################
sub DataAUTH{
use vars qw(%Q);
my $balance=CURL('get_user_info',${SQL(qq[SELECT get_uri2('get_user_info',"$Q{imsi}",NULL,NULL,NULL,NULL)],2)}[0]);
my $data_auth=${SQL(qq[SELECT data_auth("$Q{MCC}","$Q{MNC}","$Q{TotalCurrentByteLimit}","$balance")],2)}[0];
$data_auth=0 if !$data_auth;
&logger('LOG','DataAUTH',$data_auth) if $CONF{debug}==4;
#bill_user($Q{imsi},'DataAUTH');
return ("DataAUTH $data_auth",&response('DataAUTH','OK',$data_auth));
}
### END sub DataAUTH ###############################################################
#
### sub POSTDATA ###################################################################
sub POSTDATA{
my $result=CURL('set_user_balance',${SQL(qq[SELECT get_uri2('set_user_balance',"$Q{imsi}",NULL,NULL,$Q{amount}*-1,NULL)],2)}[0]);
&logger('LOG','POSTDATA',"$result ".$Q{amount}/1.25*-1) if $CONF{debug}==4;
return ("POSTDATA $result",&response('payment','PLAINTEXT','200'));
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
my $new_user=CURL('new_user',${SQL(qq[SELECT get_uri2('new_user',"$Q{imsi}",NULL,NULL,NULL,NULL)],2)}[0]);
&logger('LOG','msisdn_allocation',$sql_result) if $CONF{debug}==4;
return ("msisdn_allocation $sql_result",&response('msisdn_allocation','OK',$Q{transactionid},$sql_result));
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
eval {use vars qw(%Q);&logger('LOG','EMAIL',"$Q{email} $Q{email_sub} $Q{email_text} $Q{email_from} $Q{email_FROM}") if $CONF{debug}==4;
my $email_result=`echo "$Q{email_text}" | mail -s '$Q{email_sub}' $Q{email} -- -F "$Q{email_FROM}" -f $Q{email_from}`;
&logger('LOG','EMAIL',$email_result) if $CONF{debug}==4;;
return $email_result;
};warn $@ if $@;  &logger('LOG',"SEND-EMAIL-ERROR","$@") if $@;
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
###
sub template{
my $template = Text::Template->new(TYPE => 'STRING',SOURCE => redis('hget','text',$_[0]));
my $text = $template->fill_in(HASH=>\%Q);
return $text;
}#end template
######### END #################################################	
