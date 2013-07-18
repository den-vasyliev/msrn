#!/usr/bin/perl
#
my $rev='MSRN.ME REDIS POOL 180713-rev.1.0';
#
use FCGI;
use FCGI::ProcManager qw(pm_manage pm_pre_dispatch pm_post_dispatch);
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
####### CONF ####################################
my $R0 = Redis->new;
$R0->hset('CONF','rev',"$rev");
my %CONF=$R0->HGETALL('CONF');
#
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
#################################################
print "$CONF{rev} READY at $$ debug level $CONF{debug}\n";
####### DB #####################################	    		
		my $dbh = DBI->connect_cached('DBI:mysql:msrn',$CONF{db_user},$CONF{db_pass});
		my $R = Redis->new(server => 'localhost:6379',encoding => undef,);
############ REDIS SYNC TRANSACTIONS ####################################
	$R0->subscribe($R0->lrange('subscriptions',0,-1),
		sub{ my ($value,$topic,$subscribtions)=@_;
		undef my $SQL;
			if ($topic eq 'CONF'){
					$CONF{$value}=$R->hget('CONF',$value);
					$R->ZADD('TID',$redis_start++,"[API-COMMAND-$topic]: $value -> $CONF{$value}");
					$SQL=qq[UPDATE CONF a SET a.val="$CONF{$value}" WHERE a.key=\'$value\' limit 1];
			}#if CONF
				$SQL=qq[INSERT INTO SDR values ($value)] if $topic eq 'SDR';
				$SQL=qq[INSERT INTO TID values ($value)] if $topic eq 'TID';
			$dbh->do($SQL);
				}#sub
					);#subscribe
$R0->wait_for_messages($CONF{redis_sync_timeout}) while $CONF{redis_pool}>0;
########################################################################
$dbh->disconnect;
$R->quit;
print "$CONF{rev} FINISH at $$\n";