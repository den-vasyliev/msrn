#!/usr/local/bin/perl
#
####################################################
## Copyright (C) 2012, RuimTools denis@ruimtools.com
#
# 
$REV='AMI for RCPI 270712rev.2.0';
#
####################################################
#
use POE qw( Component::Client::Asterisk::Manager );

$pid = fork;
exit if $pid;
die "Couldn't fork: $!" unless defined($pid);
POSIX::setsid() or die "Can't start a new session: $!";
my $PIDFILE = new IO::File;
$PIDFILE->open(">/opt/ruimtools/tmp/ami.pid");
print $PIDFILE $$;
$PIDFILE->close();
#
my $LOGFILE = new IO::File;
$LOGFILE->open(">>/opt/ruimtools/log/ami.log");
print $LOGFILE "$REV Ready on $$\n";
print STDERR "$REV Ready on $$\n";
close $LOGFILE;
%reason=(0 => 'no such extension or number',1 => 'no answer',2 => 'local ring',3 => 'ring',4 => 'answered',5 => 'busy',6 => 'off hook',7 => 'line off hook',8 => 'circuits busy');
  POE::Component::Client::Asterisk::Manager->new(
  		Alias		=> 'monitor',
        Username 	=> 'admin',
        RemoteHost	=> '127.0.0.1',
        RemotePort	=> 5038,
        Password	=> 'admin',
        CallBacks	=> {spool_status => {'Event' => 'OriginateResponse',},},
        inline_states => {
                spool_status => sub {
my $input = $_[ARG0];
$LOGFILE->open(">>/opt/ruimtools/log/ami.log");
my $sql_result=-1;
$time=time();
$sql_result=`/usr/bin/curl -k -f -s -m 10 "http://127.0.0.1/cgi-bin/api.pl?request_type=rc_api_cmd;code=cb_status;agent=RUIMTOOLS;auth_key=17b9490d926b314b54189e1d71f95745a7272a8af30b37d6ca6de37567dcff3b7224a3c4235cbe111478987e2a52a43180b74b6672de8bf22885563620b4f5f5;sub_code=$input->{ActionID};options=$input->{Response};options1=$reason{$input->{Reason}}"`;
print $LOGFILE "
[$time]-[SQL]: $sql_result
[$time]-[EVENT]: $input->{Event}
[$time]-[CHANNEL]: $input->{Channel}
[$time]-[UNIQUEID]: $input->{ActionID}
[$time]-[STATUS]: $input->{Response}
[$time]-[REASON]: $reason{$input->{Reason}}\n";
close $LOGFILE;
                },      
        },
  );

  $poe_kernel->run();