#!/usr/bin/perl
#
my $rev='MSRN.ME REDIS POOL 180713-rev.1.0';
#
use Redis;
use DBI;
use warnings;
use strict;
no warnings 'once';
####### CONF ####################################
my $R0 = Redis->new;
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
					$CONF{$value}=$R->HGET('CONF',$value);
			}#if CONF
				$SQL=qq[INSERT INTO SDR values ($value)] if $topic eq 'SDR';
				$SQL=qq[INSERT INTO TID values ($value)] if $topic eq 'TID';
			$dbh->do($SQL) if $topic ne 'CONF';
			$R->ZADD('TID',$CONF{i}++,"[REDIS-SPOOL-$topic]: $value");
				}#sub
					);#subscribe
$R0->wait_for_messages($CONF{redis_sync_timeout}) while $CONF{redis_pool}>0;
########################################################################
$dbh->disconnect;
$R->quit;
print "$CONF{rev} FINISH at $$\n";