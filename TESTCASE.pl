####################################################
## Copyright (C) 2012, RuimTools denis@ruimtools.com
#
# Test Cases for RCPI SERVER 270612.rev.18.0
#
####################################################
#
<?xml version="1.0"?><Wire9_data><MSRN_Response><HLR_ID>2532</HLR_ID><IMSI>234180000000000</IMSI><MCC>234</MCC><MNC>18</MNC><MSISDN>+447700000000</MSISDN><MSRN>+447872201220</MSRN><REQUEST_STATUS>1</REQUEST_STATUS><TIME_STAMP>2012-10-17 11:54:45</TIME_STAMP><TRANSACTION_ID>1000</TRANSACTION_ID><USER_BALANCE>0.0000</USER_BALANCE><TADIG>GBWC9</TADIG><IOT>0</IOT><IOT_CHARGE>0.0000</IOT_CHARGE></MSRN_Response></Wire9_data>


print qq[<?xml version="1.0"?>
	<CB_data>
		<RESALE_Response>
			<RESPONSE>Calling 380674014759...</RESPONSE>
			<TID>23411</TID>
			<IMSI>234180000379608</IMSI>
		</RESALE_Response>
	</CB_data>
];
<?xml version="1.0"?>
	<api_cmd>
		<code>ping</code>
		<agent>CALLME</agent>
		<auth_key>fa9fec615bf0b68aa631c68b0f85628d</auth_key>
		<transactionid>1000<transactionid>
	</api_cmd>";
#
timestamp={$TIMESTAMP}&transactionid={$TID}&request_type={$REQUEST_TYPE}&imsi={$GIMSI}&destination={$USSD_DEST}&mcc={$MCC}&mnc={$MNC}&mts={$MTC}&tadig={$TADIG}

&bytes={$BYTES}&permegabyterate={$PERMEGABYTERATE}&cost={$TOTALCOST{AMOUNT}{value}}&currency={$TOTALCOST{CURRENCY}{value}}

http://194.54.172.115/WebAPI/C9API.aspx?carrier_id=1&password=RuimT00l5&agentusername=den.admin&request_type=get_msrn&query={$GIMSI}&timestamp={$TIMESTAMP}&transaction_id={$TID}

http://194.54.172.115/WebAPI/C9API.aspx?carrier_id=1&password=RuimT00l5&agentusername=den.admin&request_type=imsi_status_set&imsi_status={$IMSI_STATUS}&timestamp={$TIMESTAMP}&transaction_id={$TID}


http://api2.globalsimsupport.com/WebAPI/C9API.aspx?transaction_id=1003 &query=%2B447700000000&request_type=imsi_status_set&imsi_status=1&carrier_id=1 &password=test&timestamp=2007-03-08%2023:43:43

http://194.54.172.115/WebAPI/C9API.aspx?carrier_id=1&password=RuimT00l5&agentusername=den.admin&request_type=imsi_status_set&query={$IMSI}&imsi_status={$SUB_CODE}&timestamp={$TIMESTAMP}&transaction_id={$TID}

request_type=send_sms&timestamp={$TIMESTAMP}&transaction_id={$TID}&smsto=%2B{$SMS_TO}&smsfrom={$SMS_FROM}&message={$MESSAGE}

%26password%3DRuimT00l5%26agentusername%3Dden.admin%26request_type%3Dsend_sms%26timestamp%3D%7B%7D%26transactionid%3D%7B%7D%26smsto%3D%252B447924510004%26smsfrom%3Dzadarma_max13%26message%3D168%2520symbol%2520message%2520A-Z%2Ca-z%2C%2B1234567890.


request_type=MTSMS_CDR&timestamp=2013-07-11%2022:32:59&message_date=2013-07-11%2022:32:59&transactionid=20130711223259&cdr_id=183200&carrierid=&mcc=255&mnc=01&imsi=234180000139868&msisdn=447700027876&IOT=0&srcgt=447872200090&route=&allow=no&smsfrom=447872200090&smsc=UKRUM&reseller_charge=0.00&client_charge=0.00&user_charge=0.00&user_balance=6.00"

timestamp=&imsi=&transactionid=&destination=447700027876&from=447872200090&mcc=255&mnc=01&request_type=MT_SMS&user_balance=0.0000&carrierid=&tadig=UKRUM&globalmsisdn=447700027876&globalimsi=234180000139868&iccid=89234183800000001009
# PING
curl -d '<?xml version="1.0"?><api><api_cmd><Code>ping</Code><transactionid>1000</transactionid></api_cmd><api_auth><AGENT>CALLME</AGENT><auth_key>fa9fec615bf0b68aa631c68b0f85628d</auth_key></api_auth></api>' http://127.0.0.1
#<?xml version="1.0">
curl -d '<?xml version="1.0"?><api><api_cmd><code>stat</code><date>2013-06</date><agent>CALLME</agent><auth_key>fa9fec615bf0b68aa631c68b0f85628d</auth_key><transactionid>1000</transactionid></api_cmd></api>' http://127.0.0.1
# STAT
curl -d '<?xml version="1.0"?><api><api_cmd><code>stat</code><imsi>234180000379604</imsi><date>2013-0</date><agent>CALLME</agent><auth_key>fa9fec615bf0b68aa631c68b0f85628d</auth_key><transactionid>1000</transactionid></api_cmd></api>' http://127.0.0.1
# GET_MSRN
curl -d '<?xml version="1.0"?><api><api_cmd><code>get_msrn</code><transactionid>1000</transactionid><imsi>234180000139868</imsi></api_cmd><api_auth><agent>CALLME</agent><auth_key>fa9fec615bf0b68aa631c68b0f85628d</auth_key></api_auth></api>' http://127.0.0.1
# SET_USER DATA DISABLE
curl -d '<?xml version="1.0"?><api><api_cmd><code>set_user</code><sub_code>DataDisable</sub_code><agent>CALLME</agent><auth_key>fa9fec615bf0b68aa631c68b0f85628d</auth_key><transactionid>1000</transactionid><imsi>234180000139868</imsi></api_cmd></api>' http://127.0.0.1
# SET USER ENABLE
curl -d '<?xml version="1.0"?><api><api_cmd><code>set_user</code><sub_code>Enable</sub_code><transactionid>1000</transactionid><timestamp>1</timestamp><imsi>234180000139868</imsi></api_cmd><api_auth><agent>CALLME</agent><auth_key>fa9fec615bf0b68aa631c68b0f85628d</auth_key></api_auth></api>' http://127.0.0.1
# SEND SMS
curl -d '<?xml version="1.0"?><api><api_cmd><code>send_sms</code><sms_to>447700027876</sms_to><sms_from>callme</sms_from><message>test message 12345</message><agent>CALLME</agent><auth_key>fa9fec615bf0b68aa631c68b0f85628d</auth_key><transactionid>1000</transactionid><imsi>234180000139868</imsi></api_cmd></api>' http://127.0.0.1
# SEND USSD
curl -d '<?xml version="1.0"?><api><api_cmd><code>send_ussd</code><ussd_to>447700027876</ussd_to><message>test ussd 12345</message><agent>CALLME</agent><auth_key>fa9fec615bf0b68aa631c68b0f85628d</auth_key><transactionid>1000</transactionid><imsi>234180000139868</imsi></api_cmd></api>' http://127.0.0.1
# STAT
curl 'http://127.0.0.1?request_type=api_cmd;code=stat;imsi=234180000379604;transactionid=999;agent=CALLME;auth_key=fa9fec615bf0b68aa631c68b0f85628d'
# URL 112
curl 'http://127.0.0.1?calldestination=%2A112%2A380674014759%2A82F010001F00CF%23;timestamp=2012-06-13%2017%3A53%3A45;imsi=234180000379604;transactionid=164390;carrierid=;request_type=auth_callback_sig;mcc=255;mnc=03;msisdn=%2B447700055360;tadig=TEST;iot=0;iot_charge=0.0000;ecc=0;globalmsisdn=447700055360;globalimsi=234180000379605;iccid=89234189720000000005'
#
Card Number:{$SUB_CN} Phone:{$SUB_DID} Inter:{$SUB_INTER} SMS:{$globalmsisdn} Balance:${$SUB_CREDIT}
# URL 100
curl -d 'calldestination=%2A100%23;timestamp=2012-06-13%2017%3A53%3A45;imsi=234180000379604;transactionid=000000;request_type=auth_callback_sig;mcc=255;mnc=03;tadig=TEST;iot=0;iot_charge=0.0000' http://127.0.0.1
# URL 154
curl 'http://127.0.0.1?calldestination=%2A154%23;timestamp=2012-06-13%2017%3A53%3A45;imsi=234180000379604;transactionid=164390;carrierid=;request_type=auth_callback_sig;mcc=302;mnc=220;msisdn=%2B447700055360;tadig=TEST;iot=0;iot_charge=0.0000;ecc=0;globalmsisdn=447700055360;globalimsi=234180000379605;iccid=89234189720000000005'
# URL 111
curl -d 'calldestination=%2A111%2A123456789%2A1234%23;timestamp=2012-05-18%2017%3A07%3A46;globalmsisdn=447700055360;imsi=234180000379605;transactionid=000000;carrierid=;request_type=auth_callback_sig;tadig=TEST' http://127.0.0.1
# URL THRU CALL
curl -k -d 'calldestination=%2A380674014759%23;timestamp=2012-05-18%2017%3A07%3A46;imsi=234180000139868;transactionid=000000;carrierid=;request_type=auth_callback_sig;tadig=TEST' https://127.0.0.1
# URL 110
curl -k -d 'calldestination=%2A110%2A012027006225758%23;timestamp=2012-05-18%2017%3A07%3A46;imsi=234180000379604;transactionid=000000;carrierid=;request_type=auth_callback_sig;tadig=TEST' http://127.0.0.1
# URL 125
curl -k -d 'calldestination=%2A125%23;timestamp=2012-05-18%2017%3A07%3A46;imsi=234180000139868;transactionid=000000;carrierid=;request_type=auth_callback_sig;tadig=TEST' https://127.0.0.1
# URL 111
curl -k -d 'calldestination=%2A111%23;timestamp=2012-05-18%2017%3A07%3A46;imsi=234180000139868;transactionid=000000;carrierid=;request_type=auth_callback_sig;tadig=TEST' https://127.0.0.1
#
curl -k -d 'request_type=MTSMS_CDR&timestamp=2013-07-16%2009:45:04&message_date=2013-07-16%2009:45:04&transactionid=20130716094504&cdr_id=160003&carrierid=&mcc=255&mnc=01&imsi=234180000139868&msisdn=447700027876&IOT=0&srcgt=447872200090&route=&allow=yes&smsfrom=447872200090&smsc=UKRUM&reseller_charge=0.00&client_charge=0.00&user_charge=0.00&user_balance=6.00' https://127.0.0.1
#
sub SIG CALLBACK {}
#
curl 'http://127.0.0.1?calldestination=%2A100%2A380674014759%2A82F010001F00CF%23;timestamp=2012-06-13%2017%3A53%3A45;imsi=234180000379604;transactionid=164390;carrierid=;request_type=auth_callback_sig;mcc=255;mnc=03;msisdn=%2B447700055360;tadig=TEST;iot=0;iot_charge=0.0000;ecc=0;globalmsisdn=447700055360;globalimsi=234180000379605;iccid=89234189720000000005'
#
curl 'http://127.0.0.1?calldestination=%2A112%2A380674014759%2A82F010001F00CF%23;timestamp=2012-06-13%2017%3A53%3A45;imsi=234180000379604;transactionid=164390;carrierid=;request_type=auth_callback_sig;mcc=255;mnc=03;msisdn=%2B447700055360;tadig=TEST;iot=0;iot_charge=0.0000;ecc=0;globalmsisdn=447700055360;globalimsi=234180000379605;iccid=89234189720000000005'
#
### END SIG CALLBACK
#
sub SMS-MP {}
#
curl 'http://127.0.0.1/cgi-bin/api.pl?calldestination=%2A122%2A220%2A%2B380674014759%2A00480065006C006C006F00200074%23;timestamp=2012-06-01%2013%3A47%3A16;imsi=234180000379604;carrierid=;request_type=auth_callback_sig;mcc=255;mnc=06;msisdn=%2B447700079964;tadig=UKRAS;iot=0;iot_charge=0.0000;ecc=0;globalmsisdn=447700079964;globalimsi=234180000379608;iccid=89234189720000000088;transactionid=121053';;curl 'http://127.0.0.1/cgi-bin/api.pl?calldestination=%2A122%2A11%2A%2B380674014759%2A00480065006C006C006F00200074%23;timestamp=2012-06-01%2013%3A47%3A16;imsi=234180000379605;carrierid=;request_type=auth_callback_sig;mcc=255;mnc=06;msisdn=%2B447700079964;tadig=UKRAS;iot=0;iot_charge=0.0000;ecc=0;globalmsisdn=447700079964;globalimsi=234180000379608;iccid=89234189720000000088;transactionid=121013'; curl 'http://127.0.0.1/cgi-bin/api.pl?calldestination=%2A122%2A22%2A0065007300740020006D0075006C00740069002000700061006700650020006D0065007300730061%23;timestamp=2012-06-01%2013%3A47%3A16;imsi=234180000379605;carrierid=;request_type=auth_callback_sig;mcc=255;mnc=06;msisdn=%2B447700079964;tadig=UKRAS;iot=0;iot_charge=0.0000;ecc=0;globalmsisdn=447700079964;globalimsi=234180000379608;iccid=89234189720000000088;transactionid=1208018'
### END SMS-MP
#
sub SMSContent_CDR{}
#
curl 'http://127.0.0.1?request_type=SMSContent_CDR;sms_type=MO;timestamp=2012-06-19%2019%3A29%3A02;message_date=2012-06-19%2019%3A29%3A02;transactionid=20120619192902;cdr_id=1;carrierid=;sender=RuimTools;destination=380674014759;original_cli=447700079964;message=%D0%A2%D0%B5%D1%81%D1%825'
### END SMSContent_CDR
#
sub GET DID {}
#
curl 'http://127.0.0.1?request_type=api_cmd&code=get_did&rdnis=380947112288&transactionid=6758765&agent=CALLME;auth_key=fa9fec615bf0b68aa631c68b0f85628d&options=cleartext'
#
### END SUB GET DID
#
### SQL INJECTION
curl 'http://127.0.0.1?request_type=api_cmd;msisdn=1;imsi=234180000379608;code=1;sub_code=0;transactionid=999;reseller=test;auth_key=char(1)union(select(auth_key)from(cc_resale))--'
#<?xml version="1.0" ?><API_response><transaction_id>999</transaction_id><display_message>NO AUTH</display_message></API_response>
### END SQL INJECTION
#
sub PING{ }
#
curl -d 'request_type=api_cmd;code=ping;agent=CALLME;transactionid=1;auth_key=fa9fec615bf0b68aa631c68b0f85628d' http://127.0.0.1
curl 'http://127.0.0.1?request_type=api_cmd;code=ping;agent=CALLME;transactionid=1;auth_key=fa9fec615bf0b68aa631c68b0f85628d'
#<?xml version="1.0" ?><API_response><transaction_id>0</transaction_id><display_message>PING OK</display_message></API_response>
### END CMD PING
#
sub LU_CDR{}
#
curl 'http://127.0.0.1?request_type=LU_CDR;imsi=234180000379604;mcc=255;mnc=03;carrierid=;transactionid=194872;tadig=TEST;errorcode=0;cdr_id=59526930'
<?xml version="1.0" ?><CDR_response><cdr_id>59526930</cdr_id><cdr_status>1</cdr_status></CDR_response>
#
curl 'http://127.0.0.1:8008/roamingcenter/?request_type=LU_CDR;timestamp=2012-05-18%2006%3A59%3A18;msisdn=%2B447700079964;vlr=%2B380672054436;imsi=234180000079890;mcc=255;mnc=03;carrierid=;transactionid=194872;tadig=TEST;errorcode=0;cdr_id=59526930'
### END SIG LU_CDR
#
sub USSD Your number{}
#
curl 'http://127.0.0.1:8080/api?calldestination=%2A100%23;timestamp=2012-05-18%2017%3A07%3A46;imsi=234180000139825;transactionid=184863;carrierid=;request_type=auth_callback_sig;mcc=255;mnc=03;msisdn=%2B447700079964;tadig=TEST;iot=0;iot_charge=0.0000;ecc=0;globalmsisdn=447700079964;globalimsi=234180000379605;iccid=89234189720000000088'

curl 'http://127.0.0.1:8008/roamingcenter/?calldestination=%2A100%23;timestamp=2012-05-18%2017%3A07%3A46;imsi=23418000037960[1-9];transactionid=184863;carrierid=;request_type=auth_callback_sig;mcc=255;mnc=03;msisdn=%2B447700079964;tadig=TEST;iot=0;iot_charge=0.0000;ecc=0;globalmsisdn=447700079964;globalimsi=234180000379605;iccid=89234189720000000088'

curl 'http://127.0.0.1/cgi-bin/api.pl?calldestination=%2A100%23;timestamp=2012-05-18%2017%3A07%3A46;imsi=234180000139868;transactionid=184863;carrierid=;request_type=auth_callback_sig;tadig=TEST'
#<?xml version="1.0" ?><MOC_response><transaction_id>184863</transaction_id><display_message>Unknown USSD request</display_message></MOC_response>
#
curl 'http://127.0.0.1:8008/roamingcenter/?calldestination=%2A100%23;timestamp=2012-05-18%2017%3A07%3A46;imsi=234180000079890;transactionid=184863;carrierid=;request_type=auth_callback_sig;mcc=255;mnc=03;msisdn=%2B447700079964;tadig=TEST;iot=0;iot_charge=0.0000;ecc=0;globalmsisdn=447700079964;globalimsi=234180000379608;iccid=89234189720000000088'
### END USSD Your number
#
sub USSD Balance{}
#
curl 'http://127.0.0.1/cgi-bin/api.pl?calldestination=%2A123%23;timestamp=2012-05-18%2017%3A07%3A46;imsi=234180000379604;transactionid=184863;request_type=auth_callback_sig;mcc=255;mnc=03;msisdn=%2B447700079966;tadig=TEST;iot=0;iot_charge=0.0000;ecc=0;globalmsisdn=447700079964;globalimsi=234180000379605;iccid=89234189720000000058'

curl 'http://127.0.0.1/cgi-bin/api.pl?calldestination=%2A123%2A685027809114789%23;timestamp=2012-05-18%2017%3A07%3A46;imsi=234180000379605;transactionid=184863;request_type=auth_callback_sig;mcc=255;mnc=03;msisdn=%2B447700079966;tadig=TEST;iot=0;iot_charge=0.0000;ecc=0;globalmsisdn=447700079964;globalimsi=234180000379605;iccid=89234189720000000058'
### END USSD Rates
#
sub PAYMNT{}
#
curl -k -d 'xml=<?xml version="1.0" encoding="utf-8"?><payment id="82602"><ident>83f70c0184f79eea7c14a5d5b0e33dae5aa2992e</ident><status>5</status><amount>100</amount><currency>UAH</currency><timestamp>1339709504</timestamp><transactions><transaction id="117702"><mch_id>230</mch_id><srv_id>0</srv_id><amount>80</amount><currency>UAH</currency><type>10</type><status>11</status><code>00</code><desc>Лицевой счет 0921945786</desc><info>{"acc":"0921945786","amount":1}</info></transaction><transaction id="117704"><mch_id>230</mch_id><srv_id>0</srv_id><amount>80</amount><currency>UAH</currency><type>11</type><status>11</status><code>00</code><desc>Лицевой счет 0921945786</desc><info>{"acc":"0921945786","amount":1}</info></transaction></transactions><salt>1777e98da1bbfb143df54e7efc8ebd1210258d21</salt><sign>d19beb1368e8540d303134822f43babfda39548ae486719e2b0f4d201e805ae90665f0dc44913139c02c3f244528d2cadc8ee85d03633f659a4ba63ac6def0e1</sign></payment>' https://127.0.0.1/cgi-bin/api.pl
### END PAYMNT
#
sub CHECK CARD NUMBER {}
#
curl 'http://127.0.0.1?card_number=9671645459'
### END CHECK CARD NUMBER
#
sub MSISDN allocation {}
#
http://127.0.0.1?request_type=msisdn_allocation;cdr_id=43137;timestamp=2012-05-22%2007%3A47%3A35;carrierid=;IMSI=234180000379608;MSISDN=447700079965

curl "http://127.0.0.1?request_type=msisdn_allocation;cdr_id=43137;timestamp=2012-05-22%2007%3A47%3A35;carrierid=;IMSI=234180000379604;MSISDN=44770000000"
### END MSISDN allocation
#
sub DataAUTH {}
#
curl "http://127.0.0.1?AgentID=1024;CallID=83092271;GlobalIMSI=234180000379604;GlobalMSISDN=447700014169;ICCID=8923418380000000169;IMSI=234180000379604;MCC=286;MNC=002;MSISDN=447700014169;SessionID=7573477;TotalCurrentByteLimit=1048576;request_type=DataAUTH"
# 
curl "http://127.0.0.1?request_type=DataAUTH&CallID=123456&MSISDN=447700056231&IMSI=234180000139868&MCC=234&MNC=123&TotalCurrentByteLimit=10000000 &AgentID=176&SessionID=54321&GlobalMSISDN=447700056129&GlobalIMSI=234180000139868 &ICCID=892341845000008962"
#
curl "http://127.0.0.1/cgi-bin/api.pl?request_type=DataAUTH;CallID=67100200;MSISDN=447700055498;IMSI=234180000139868;MCC=260;MNC=002;TotalCurrentByteLimit=1048576;AgentID=1024;SessionID=3901571;GlobalMSISDN=447700055498;GlobalIMSI=234180000139868;ICCID=8923418972000000005"
### END DataAUTH
#
sub DataSession {}
#
curl -d '<?xml version="1" ?><complete-datasession-notification callid="48981764"><createtime>2011-05-11T08:27:23</createtime><reference>Data</reference><userid>528594</userid><username>447700086788</username><customerid>510163</customerid><companyname>Silliname</companyname> <totalcost amount="0.1400" currency="USD">0.1400</totalcost><agenttotalcost amount="0.1400" currency="USD">0.1400</agenttotalcost><agentid>234</agentid><callleg calllegid="89357336"><number>447700086788</number><description>China, Peoples Republic of - China Unicom (CU-GSM)</description><mcc>460</mcc><mnc>001</mnc><seconds>32</seconds><bytes>4558</bytes><permegabyterate currency="USD">1.3330</permegabyterate><cost amount="0.1400" currency="USD">0.1400</cost><agentpermegabyterate currency="USD">1.3330</agentpermegabyterate><agentcost amount="0.1400" currency="USD">0.1400</agentcost></callleg></complete-datasession-notification>' http://127.0.0.1


curl 'http://127.0.0.1/cgi-bin/api.pl?POSTDATA=%3Ccomplete-datasession-notification%20callid%3D%2268313515%22%3E%3Ccreatetime%3E2012-07-03T13%3A19%3A38%3C%2Fcreatetime%3E%3Creference%3EData%3C%2Freference%3E%3Ccalltype%20calltypeid%3D%2211%22%3Edata%3C%2Fcalltype%3E%3Cuserid%3E878385%3C%2Fuserid%3E%3Cusername%3E447700079964%3C%2Fusername%3E%3Ccustomerid%3E874855%3C%2Fcustomerid%3E%3Ccompanyname%3E972000000008%3C%2Fcompanyname%3E%3Ctotalcost%20amount%3D%220.0000%22%20currency%3D%22USD%22%3E0.0000%3C%2Ftotalcost%3E%3Cagenttotalcost%20amount%3D%220.1961%22%20currency%3D%22USD%22%3E0.1961%3C%2Fagenttotalcost%3E%3Cagentid%3E1024%3C%2Fagentid%3E%3Ccallleg%20calllegid%3D%22124387376%22%20calllegtype%3D%22data%22%3E%3Cnumber%3E447700027876%3C%2Fnumber%3E%3Cratedforuseras%3EZero%20Bill%20Customer%3C%2Fratedforuseras%3E%3Cdescription%3EZero%20Bill%20Customer%3C%2Fdescription%3E%3Cmcc%3E255%3C%2Fmcc%3E%3Cmnc%3E003%3C%2Fmnc%3E%3Cseconds%3E61%3C%2Fseconds%3E%3Cbytes%3E2148%3C%2Fbytes%3E%3Cpermegabyterate%20currency%3D%22USD%22%3E0.0000%3C%2Fpermegabyterate%3E%3Ccost%20amount%3D%220.0000%22%20currency%3D%22USD%22%3E0.0000%3C%2Fcost%3E%3Cagentpermegabyterate%20currency%3D%22USD%22%3E20.0836%3C%2Fagentpermegabyterate%3E%3Cagentcost%20amount%3D%220.03%22%20currency%3D%22USD%22%3E0.03%3C%2Fagentcost%3E%3C%2Fcallleg%3E%3C%2Fcomplete-datasession-notification%3E'
### END POSTDATA

#
sub SMS MT {}
#
curl "http://127.0.0.1?timestamp2012-06-23%2017%3A56%3A11=;imsi=234180000379604;transactionid=114927;destination=447700079964;from=393358840009361;mcc=255;mnc=03;request_type=MT_SMS;user_balance=0.0000;carrierid=;tadig=UKRKS;globalmsisdn=447700079964;globalimsi=234180000379605;iccid=89234189720000000058"
### END SMS MT
#
sub MTSMS_CDR
#
curl "http://127.0.0.1?request_type=MTSMS_CDR&timestamp=2013-07-16%2009:45:04&message_date=2013-07-16%2009:45:04&transactionid=20130716094504&cdr_id=160003&carrierid=&mcc=255&mnc=01&imsi=234180000379604&msisdn=447700027876&IOT=0&srcgt=447872200090&route=&allow=yes&smsfrom=447872200090&smsc=UKRUM&reseller_charge=0.00&client_charge=0.00&user_charge=0.00&user_balance=6.00"
#
sub MOSMS_CDR
#
curl "http://127.0.0.1?request_type=MOSMS_CDR&timestamp=2013-07-16%2009:45:04&message_date=2013-07-16%2009:45:04&transactionid=20130716094504&cdr_id=160003&carrierid=&mcc=255&mnc=01&imsi=234180000379604&msisdn=447700027876&IOT=0&srcgt=447872200090&route=&allow=yes&smsfrom=447872200090&smsc=UKRUM&reseller_charge=0.00&client_charge=0.00&user_charge=0.00&user_balance=6.00"

#
sub SMS Content CDR {}
#
curl "http://127.0.0.1/cgi-bin/api.pl?request_type=SMSContent_CDR;sms_type=MO;timestamp=2012-06-23%2021%3A14%3A15;message_date=2012-06-23%2021%3A14%3A15;transactionid=20120623211415;cdr_id=1;carrierid=;sender=RuimTools;destination=380635644216;original_cli=447700079964;message=%D0%A2%D0%B5%D1%81%D1%824"
### END SMS Content CDR
#
sub CFU {}
#
curl 'http://127.0.0.1/cgi-bin/api.pl?calldestination=%2A127%23;timestamp=2012-05-18%2017%3A07%3A46;imsi=234180000379605;transactionid=184863;carrierid=;request_type=auth_callback_sig;mcc=255;mnc=03;msisdn=%2B447700079964;tadig=TEST;iot=0;iot_charge=0.0000;ecc=0;globalmsisdn=447700079964;globalimsi=234180000379608;iccid=89234189720000000088' 
#<?xml version="1.0" ?><MOC_response><transaction_id>184863</transaction_id><display_message>Unknown USSD request</display_message></MOC_response>
### END  CFU
#
sub GET RATE TO DEST 126 {}
#
curl 'http://127.0.0.1/cgi-bin/api.pl?request_type=rc_api_cmd;msisdn=39330;options=38067;imsi=234180000379605;code=get_stat;sub_code=get_rate;transactionid=321;agent=RUIMTOOLS;auth_key=17b9490d926b314b54189e1d71f95745a7272a8af30b37d6ca6de37567dcff3b7224a3c4235cbe111478987e2a52a43180b74b6672de8bf22885563620b4f5f5'
### END GET RATE TO DEST
#
#
sub GET MSRN {}
#
curl -d 'request_type=api_cmd;msisdn=1;imsi=234180000379604;code=get_msrn;sub_code=0;transactionid=999;agent=CALLME;auth_key=fa9fec615bf0b68aa631c68b0f85628d' http://127.0.0.1
## LAB
curl -k -d 'request_type=rc_api_cmd;imsi=234180000140002;code=get_msrn;sub_code=0;transactionid=999;agent=ZADARMA;auth_key=0ba62eb6dd75a3c97e1cfd739aaa7112eb13b4b0b4163a3c94d84adfce5b9dcdaed46cd8d5045f076138df88024c02ae86f352f5394dd42e4a3cef25dda9a252' https://91.218.212.209:4030/cgi-bin/api.pl
## ORIG
curl -k -d 'request_type=rc_api_cmd;imsi=234180000140002;code=get_msrn;sub_code=0;transactionid=999;agent=ZADARMA;auth_key=891938096fbb33106b0ced3089bd1632347463e32270344e098afcad5415da43b497df19cd6d3d7b08663e1f3d442bba1fe68cf7de6e2defe0dbde180a5dc306' https://91.218.212.209/cgi-bin/api.pl
### END RESELLER MSRN
#
sub SEND USSD {}
#
curl 'http://127.0.0.1/cgi-bin/api.pl?request_type=rc_api_cmd;msisdn=%2B447700027833;code=send_ussd;sub_code=Your%20balance%20was%20updated;agent=RUIMTOOLS;auth_key=17b9490d926b314b54189e1d71f95745a7272a8af30b37d6ca6de37567dcff3b7224a3c4235cbe111478987e2a52a43180b74b6672de8bf22885563620b4f5f5'
## STAT
curl 'http://127.0.0.1/cgi-bin/api.pl?request_type=rc_api_cmd;msisdn=1359572892.1421;code=send_ussd;sub_code=stat;agent=RUIMTOOLS;auth_key=17b9490d926b314b54189e1d71f95745a7272a8af30b37d6ca6de37567dcff3b7224a3c4235cbe111478987e2a52a43180b74b6672de8bf22885563620b4f5f5'
#SELECT CONCAT(REPLACE(REPLACE(a.response,'_TIME_',sessiontime),'_BILL_',round(sum(sessionbill),2))) stat from cc_actions a, cc_card c, cc_call cc WHERE c.id=cc.card_id and cc.uniqueid='1359893998.1448' and a.code='send_ussd_stat' limit 1

#<?xml version="1.0" ?><API_response><transaction_id>0</transaction_id><display_message>PING OK</display_message></API_response>
### END CMD SEND USSD
#
#
sub CMD PAYPAL {}
#payer_id::payment_date::txn_id::first_name::last_name::payer_email::payer_status::payment_type::item_name::item_number::quantity::mc_gross::mc_fee::tax	decimal::mc_currency::payer_business_name::payment_status::pending_reason::reason_code::txn_type::verify_sign::num_cart_items::residence_country::receiver_email
curl "http://127.0.0.1/cgi-bin/api.pl?request_type=PAYPAL;mc_gross=1.00;item_number1=CM101;tax=0.00;payer_id=3V6EJWUKTXVHA;payment_date=10%3A08%3A03+Dec+17%2C+2012+PST;payment_status=Completed;first_name=Denis;mc_fee=3.20;custom=24049694;payer_status=unverified;business=callme_1355756705_biz%40gmail.com;num_cart_items=1;payer_email=den.va_1355756786_per%40gmail.com;btn_id1=2669880;txn_id=83B480530Y8701555;payment_type=instant;last_name=V;item_name1=Voucher;receiver_email=callme_1355756705_biz%40gmail.com;payment_fee=3.20;quantity1=1;receiver_id=6VCH9PAQ93BMU;txn_type=cart;mc_gross_1=1.00;mc_currency=USD;residence_country=US;transaction_subject=Shopping+CartVoucher;payment_gross=1.00;ipn_track_id=49aeabcfcfe1e;test=test"
### END CMD PAYPAL
#
sub SEND SMS {}
https://www.voicetrading.com/myaccount/sendsms.php?username=RUIMTOOLS&password=psw4lxz&from=_380674014759&to=+380674014759&text=testvt
### END SUB SEND SMS
#EOF
