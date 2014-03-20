#!/usr/bin/perl
## https://www.sandbox.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=U7ZMZ6ATMWX4C
# callme!! -  callme_1358797364_biz@gmail.com
# denis_user - den.va_1358781520_per@gmail.com den.vasyliev@gmail.com
# Visa   4503056978636302 Exp Date:  1/2018
##
use LWP::UserAgent 6;
use Time::Local;
#
$LOGFILE='/opt/ruimtools/log/paypal.log';
#
## LOGG ######################################
sub logg{
$now=localtime;
my $MESSAGE=$_[0];
open(LOGFILE,">>","$LOGFILE") or die $!;
my $LOG="[$now]-[API-LOG]: $MESSAGE\n";	
print STDOUT $LOG if $debug==1;
print LOGFILE $LOG;
close LOGFILE;
}## END LOGG #################################
#
# read post from PayPal system and add 'cmd'
read (STDIN, $query, $ENV{'CONTENT_LENGTH'});
$query .= '&cmd=_notify-validate';
#
&logg("GET QUERY $query");
#
#
# post back to PayPal system to validate
$ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 1 });
$req = HTTP::Request->new('POST', 'https://www.paypal.com/cgi-bin/webscr');
$req->content_type('application/x-www-form-urlencoded');
$req->header(Host => 'www.paypal.com');
$req->content($query);
$res = $ua->request($req);
#
# split posted variables into pairs
@pairs = split(/&/, $query);
$count = 0;
foreach $pair (@pairs) {
 ($name, $value) = split(/=/, $pair);
 $value =~ tr/+/ /;
 $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
 $variable{$name} = $value;
 $count++;
}
#
# assign posted variables to local variables
$item_name = $variable{'item_name'};
$item_number = $variable{'item_number'};
$payment_status = $variable{'payment_status'};
$payment_amount = $variable{'mc_gross'};
$payment_currency = $variable{'mc_currency'};
$txn_id = $variable{'txn_id'};
$receiver_email = $variable{'receiver_email'};
$payer_email = $variable{'payer_email'};
#
#
if ($res->is_error) {
 # HTTP error
&logg("ERROR HTTP");
}
elsif ($res->content eq 'VERIFIED') {
 # check the $payment_status=Completed
&logg("CHECK STATUS $payment_status");
#
if ($payment_status eq 'Completed'){
$URI='http://127.0.0.1/cgi-bin/api.pl?request_type=PAYPAL&'.$query;
eval {&logg("CURL-REQ $URI");
@XML = `/usr/bin/curl -k -f -s -m 10 "$URI"`;
};warn $@ if $@;  logg("CURL-ERROR $@") if $@;
logg(@XML);
}#if Completed
 # check that $txn_id has not been previously processed
&logg("CHECK TNX_ID $txn_id");
 # check that $receiver_email is your Primary PayPal email
&logg("CHECK EMAIL $receiver_email");
 # check that $payment_amount/$payment_currency are correct
&logg("CHECK AMOUNT $payment_amount/$payment_currency");
#send email notification
$email_pri=`echo "$item_name $payment_status $txn_id $payment_amount/$payment_currency" | mail -s 'New payment $txn_id $item_name' denis\@ruimtools.com -- -F "CallMe! New Payment" -f no-reply\@callme.ruimtools.com`;
 # process payment
}
elsif ($res->content eq 'INVALID') {
 # log for manual investigation
&logg("ERROR CONTENT");
$email_pri=`echo "Error payment validation" | mail -s 'Error payment $txn_id $item_name' denis\@ruimtools.com -- -F "CallMe! Error Payment" -f no-reply\@callme.ruimtools.com`;
}
else {
 # error
&logg("UNKNOWN ERROR");
}
print "content-type: text/plain\n\n";
