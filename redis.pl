#!/usr/bin/perl
#
my $rev='MSRN.ME REDIS POOL 180713-rev.1.0';
#
use Redis;
use DBI;
use POSIX;
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
$PIDFILE->open(">$CONF{pidfile}.redis");# change to programm path (!)
print $PIDFILE $$;
$PIDFILE->close();
chdir "$CONF{rundir}" or die "Can't chdir: $!";
#################################################
print "$CONF{rev} READY at $$ debug level $CONF{debug} $CONF{subscripts}\n";
####### DB #####################################	    		
		my $dbh = DBI->connect_cached('DBI:mysql:msrn',$CONF{db_user},$CONF{db_pass});
		my $R = Redis->new(server => 'localhost:6379',encoding => undef,);
		my $LOGFILE = new IO::File;
		$LOGFILE->open(">>$CONF{logfile}");
############ REDIS SYNC TRANSACTIONS ####################################
	$R0->subscribe($R0->SMEMBERS('SUBSCRIPTS'),
		sub{ my ($value,$topic)=@_;
eval{
				undef my $SQL;
				$SQL=qq[INSERT INTO SDR values ($value)] if $topic eq 'SDR';
				$SQL=qq[INSERT INTO TID values ($value)] if $topic eq 'TID';
				$SQL=qq[CALL get_sub($value)] if $topic eq 'SUB';
	if ($topic eq 'CONF'){ $CONF{$value}=$R->HGET('CONF',$value) }#if CONF
	if ($topic eq 'LOG'){ print $LOGFILE $value,"\n";}#if LOG
	if ($topic eq 'SUB'){
	my	$sth=$dbh->prepare($SQL);
	$sth->execute;
		my %HASH = %{$sth->fetchrow_hashref};
		$R->HSET('SUB:'.substr($value,-6,6),$_,$HASH{$_}, sub{}) for keys %HASH;
		$R->wait_one_response;
					undef my $SQL;
			}#if SUB
			$dbh->do($SQL) if defined $SQL;
			$R->ZADD('TID',$CONF{i}++,"[REDIS-POOL-$topic]: $value");
			$LOGFILE->flush();
				};warn $@ if $@;
				}#sub
					);#subscribe
$R0->wait_for_messages($CONF{redis_sync_timeout}) while $CONF{redis_pool}>0;
########################################################################
$dbh->disconnect;
$R->quit;
print "$CONF{rev} FINISH at $$\n";