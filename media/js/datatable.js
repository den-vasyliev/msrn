// DataTable 03082014 18541
//	sSession="";
	var hHost="http://api.msrn.me";
	var PayHost="https://www.liqpay.com/?do=clickNbuy";
	var PayXML;
	var PayKEY;
$.getScript("media/js/Scroller.min.js", function(){});

	$( "#radioset" ).buttonset();
	$( "#tabs" ).tabs();
	$( "#tabs" ).tabs("option", "active", 1);
	$( function(){ $( "#pay_dialog" ).dialog( {autoOpen: false} ) } );
//
		$(document).ready(	function() {
//
		var sSession=$('#session').val();
		$("#tabs").tabs( {"activate": function(event, ui) {$( $.fn.dataTable.tables( true ) ).DataTable().columns.adjust();}} );	
		$( "#accordion" ).accordion( {heightStyle: "content"}, {active: 2}, {collapsible: "false"} );
		$( "#faq_content" ).accordion( {heightStyle: "content"}, {active: 7}, {collapsible: "false"} );	
//
// MSRN CARD
//
		var oTable= $("#msrn_card").DataTable( {
		"language": {"url": "media/json/Russian.json"},
		"scrollY": "270px",
        "scrollCollapse": true,
        "paging": false,
        "jQueryUI": true,
					"stateSave":1,
					"processing": 1,
		"ajax": hHost+"?request_type=api;code=ajax;sub_code=card;session="+sSession,
		"sDom": "frtiS",
		"deferRender": true,
			"columns": [
            { "title": "Номер счета [Страна Сеть]","width": "7%","className": "center" },
            { "title": "Номер карты","className": "center","width": "5%" },
            { "title": "Email","className": "center","width": "5%" },
            { "title": "Баланс $","className": "center","width": "5%" },
            { "title": "Интернет $", "className": "center","width": "4%","render":function(data){return 0}},
           { "title": "Прямой номер", "className": "center","width": "5%", "data": 5}
        ],"footerCallback": function ( nRow, data, iStart, iEnd, aiDisplay ) {
        var nCells = nRow.getElementsByTagName('th');
		nCells[3].innerHTML = (fnSummer(data, 3, iStart, iEnd, aiDisplay));
        }//footerCallback
				} );//dataTable
//
    $('#msrn_card tbody').on("click", 'tr', function () {

         if ( $(this).hasClass('selected') ) {
            $(this).removeClass('selected');
            $('#pay_radio').val('0');
        }
        else {
            oTable.$('tr.selected').removeClass('selected');
            $(this).addClass('selected');
            $('#pay_radio').val(oTable.cell( this, 1 ).data());
        }
    } );//click
//
    	$('#msrn_card').on("dblclick", 'tr', function () {
        var tr = $(this).closest('tr');
        var row = oTable.row( tr );
 $( '<div align="center">Email: <input type="text" id="email" value="'+row.data()[2]+'" maxlength=50 /></div>' ).dialog({title: "ПАРАМЕТРЫ "+row.data()[1], modal: true, buttons: { Ok: function() {
 	console.log(row.data()[2]);
	$('#email').val($('#email').val().replace(/[`~!#$%^&*()|+\-=?;:'",<>\{\}\[\]\\\/]/gi, '').substring(0,50));
//	console.log(hHost+'?request_type=api;code=ajax;sub_code=alias;session='+sSession+';aliastag='+row.data()[1]+";text="+$('#email').val());
	ajaxPost('request_type=api;code=ajax;sub_code=alias;session='+sSession+';aliastag='+row.data()[1]+";text="+$('#email').val());
	$(this).dialog( "close" );
	$(this).dialog( "destroy" );
 	$('#msrn_card').DataTable().ajax.reload();
 	}}});  
    } );//dblclick

//
// END MSRN CARD
// MSRN CALL
//   				
	var oTable_call= $("#msrn_call").DataTable( {
		"scrollY": "270px",
        "scrollCollapse": true,
        "paging": false,
        "jQueryUI": true,
					"stateSave":1,
					"processing": 1,
					"language": {"url": "media/json/Russian.json"},
					"ajax": hHost+"?request_type=api;code=ajax;sub_code=call;session="+sSession,
						"sDom": "frtiS",
						"deferRender": true,
					"order": [[ 0, "desc" ]],
			"columns": [
            { "title": "Дата","width": "5%","className": "center" },
            { "title": "Номер карты","width": "3%","className": "center","data":13 },
            { "title": "Страна - Тариф (Экстра), <font size=3>&cent</font>","width": "6%" },
            { "title": "Длительность","width": "5%","className": "center" },
            { "title": "Стоимость, <font size=3>&cent</font>","width": "5%","className": "center" },
            { "title": "Статус","render":function(data){ 
return data.search('Inbound')==0 ? "Входящий" : data.search('Outbound')==0 ? "Исходящий" : data.search('Not')==0 ? "Неотвеченный" : "Обратный вызов";
            	},"width": "5%","className": "center" },
            { "title": "Источник", "visible": false },
            { "title": "Назначение", "visible": false },
            { "title": "Общее время", "visible": false },
            { "title": "Тариф входящий", "visible": false },
            { "title": "Тариф назначения", "visible": false },
            { "title": "MSRN", "visible": false },
            { "title": "ID звонка", "visible": false },
            { "title": "Номер счета", "visible": false, "data":1 },
            { "title": "Транк", "visible": false }
        ],"footerCallback": function ( nRow, data, iStart, iEnd, aiDisplay ) {
       var nCells = nRow.getElementsByTagName('th');
     	nCells[1].innerHTML = "";
		nCells[3].innerHTML = (fnSummerTime(data, 3, iStart, iEnd, aiDisplay));
		nCells[4].innerHTML = (fnSummer(data, 4, iStart, iEnd, aiDisplay));
		nCells[5].innerHTML = "";
        }//footerCallback
				});//dataTable   
//        
		$('#msrn_call').on("dblclick", 'tr', function () {
			    var tr = $(this).closest('tr');
		        var row = oTable_call.row( tr );
	$( fnFormatDetails( row.data(), 2 ) ).dialog(
	{title: "ПОДРОБНОСТИ ЗВОНКА",modal: false, closeOnEscape: true, buttons: { Ok: function() { $( this ).dialog( "close" )}}
	}).dialog( 'open' ); 
  	}  );//click
//
// END MSRN CALL
// MSRN BILLING
//
	var oTable_billing= $("#msrn_billing").DataTable( {
		"scrollY": "270px",
        "scrollCollapse": true,
        "paging": false,
        "jQueryUI": true,
					"stateSave":1,
					"processing": 1,					
					"language": {"url": "media/json/Russian.json"},
					"ajax": hHost+"?request_type=api;code=ajax;sub_code=billing;session="+sSession,
						"sDom": "frtiS",
						"deferRender": true,
					"order": [[ 0, "desc" ]],
			"columns": [
            { "title": "Дата","className": "center","width": "4%" },
            { "title": "Номер карты","className": "center","width": "3%" },
            { "title": "Номер транзакции", "className": "center","width": "5%" },
            { "title": "Тип", "className": "left","width": "3%" },
            { "title": "Стоимость, <font size=3>&cent</font>","width": "4%", "className": "center"},
           { "data": null, "visible": false }
        ],"footerCallback": function ( nRow, data, iStart, iEnd, aiDisplay ) {
        var nCells = nRow.getElementsByTagName('th');
		nCells[4].innerHTML = (fnSummer(data, 4, iStart, iEnd, aiDisplay));
		}//footerCallback
				});//dataTable
//
// END MSRN BILLING
// MSRN DATA
//		
	var oTable_data= $("#msrn_data").DataTable( {
		"scrollY": "200px",
        "scrollCollapse": true,
        "paging": false,
        "jQueryUI": true,
					"stateSave":1,
					"processing": 1,				
					"language": {"url": "media/json/Russian.json"},
					"ajax": "media/ajax/data.ajax",
						"sDom": "frtiS",
						"deferRender": true,
				"columns": [
            { "title": "Страна","width": "5%", "className": "center" },
           { "title": "Оператор","width": "7%" },
            { "title": "Код оператора","width": "3%", "className": "center" },
            { "title": "Код страны-сети","width": "3%", "className": "center" },
            { "title": "Тариф, $","width": "3%", "className": "center" },
           { "title": "Инкремент, кБ","width": "3%", "className": "center" }
        ],"footerCallback": function ( nRow, data, iStart, iEnd, aiDisplay ) {
		}//footerCallback
				});//dataTable
//				
// END MSRN DATA
// MSRN MTC								
	var oTable_mtc= $("#msrn_mtc").DataTable( {
		"scrollY": "200px",
        "scrollCollapse": true,
        "paging": false,
        "jQueryUI": true,
					"stateSave":1,
					"processing": 1,					
					"language": {"url": "media/json/Russian.json"},
					"ajax": "media/ajax/mtc.ajax",
						"sDom": "frtiS",
						"deferRender": true,
			"columns": [
            { "title": "Страна","className": "center", "width": "5%" },
            { "title": "Оператор","className": "center", "width": "5%" },
            { "title": "Код PLMN","className": "center", "width": "5%" },
            { "title": "Код страны","className": "center", "width": "3%" },
            { "title": "Код сети","className": "center", "width": "3%" },
            { "title": "Экстра тариф, $","className": "center", "width": "5%" }
        ],"footerCallback": function ( nRow, data, iStart, iEnd, aiDisplay ) {
		}//footerCallback
				});//dataTable
//
// END MSRN MTC
// MSRN RATE			
//
	var oTable_rate= $("#msrn_rate").DataTable( {
		"scrollY": "200px",
        "scrollCollapse": true,
        "paging": false,
        "jQueryUI": true,
					"stateSave":1,
					"processing": 1,					
					"language": {"url": "media/json/Russian.json"},
					"ajax": "media/ajax/rate.ajax",
						"sDom": "frtiS",
						"deferRender": true,
			"columns": [
           { "title": "Направление","className": "center", "width": "10%" },
           { "title": "Префикс","className": "center", "width": "7%" },
           { "title": "Тариф, <font size=3>&cent</font>","className": "center", "width": "5%" }
        ],"footerCallback": function ( nRow, data, iStart, iEnd, aiDisplay ) {
		}//footerCallback
				});//dataTable
          
					$("#accordion").on("click", function() {
						var tables = $.fn.dataTable.tables(true);
						$( tables ).DataTable().columns.adjust();
					});//accordion click					
//
// END MSRN RATE
// MSRN MNO
//	
		var oTable_mno= $("#msrn_mno").DataTable( {
		"scrollY": "270px",
        "scrollCollapse": true,
        "paging": false,
        "jQueryUI": true,
					"stateSave":1,
					"processing": 1,					
					"language": {"url": "media/json/Russian.json"},
					"ajax": "media/ajax/mno.ajax",
					"sDom": "frtiS",
					"deferRender": true,
				"columns": [
            { "title": "Страна","className": "center","width": "7%" },
           { "title": "Оператор","width": "10%" },
            { "title": "Код страны","className": "center","width": "5%" },
            { "title": "Код сети","className": "center","width": "5%" },
            { "title": "Код ISO","className": "center","width": "5%" },
           { "title": "Префикс","className": "center","width": "7%" }
        ],"footerCallback": function ( nRow, data, iStart, iEnd, aiDisplay ) {
 		}//footerCallback
				});//dataTable
//			
// END MSRN MNO
// MSRN PAY		
//			
	var	oTable_pay= $("#msrn_pay").DataTable( {
		"scrollY": "270px",
        "scrollCollapse": true,
        "paging": false,
        "jQueryUI": true,
					"stateSave":1,
					"processing": 1,
					"language": {"url": "media/json/Russian.json"},
					"ajax": hHost+"?request_type=api;code=ajax;sub_code=pay;session="+sSession,
						"sDom": "frtiS",
						"deferRender": true,
				"columns": [
            { "title": "Дата","width": "5%","className": "center" },
           { "title": "Номер счета","width": "7%","className": "center" },
            { "title": "Платеж","width": "5%", "className": "center" },
            { "title": "Сумма, $","width": "3%", "className": "center" },
	          { "data": null, "visible": false },
    	       { "data": null, "visible": false }
		],"footerCallback": function ( nRow, data, iStart, iEnd, aiDisplay ) {
 		var nCells = nRow.getElementsByTagName('th');
		nCells[3].innerHTML = (fnSummer(data, 3, iStart, iEnd, aiDisplay));
		}//footerCallback
				});//dataTable
//
// END MSRN PAY
//
// RADIO BUTTONS
			$("#pay_radio").on("click", function() {
				if ($(this).val()>0){
	var payTag=$(this).val();
		$('#pay_dialog').dialog({ title:'ПОПОЛНИТЬ КАРТУ: '+payTag, modal: true, buttons: { Ok: function() { 
		PAY_SEND('session='+sSession+';paytag='+payTag+';pay_amount='+$( '#selectmenu' ).val());
		$( this ).dialog( "close" ); 
		} }
		}).dialog("open");
	$('#selectmenu').selectmenu();
				}else{
 $( '<div id="pay_radio_inform">Выберите пожалуйста карту</div>' ).dialog({ title:'ПОПОЛНИТЬ', modal: true, buttons: { Ok: function() { $( this ).dialog( "close" );}	}});
}//else					
	    					});//pay_radio click
//			
			$("#filterclear").on("click", function() {
				var tables = $.fn.dataTable.tables(true);
				$( tables ).DataTable().search( '' ).columns().search( '' ).draw();
				});
//
			$("#reloadTable").on("click", function() {
				var tables = $.fn.dataTable.tables(true);
						$( tables ).DataTable().ajax.reload();
		$( tables ).DataTable().on('xhr', function (set, json) {
//console.log(json);
	  if ( json.jqXHR.responseJSON.aaData.length == 0 ) {
	 $( '<div id="session_inform">Время сессии завершилось. Пожалуйста, перелогинься.</div>' ).dialog({ title:'СЕССИЯ ЗАВЕРШЕНА', modal: true, buttons: { Ok: function() { $( this ).dialog( "close" );location="";}	}});  }
	} );
				});
//				
	$("#logout").on("click", function() {
	ajaxPost("request_type=api;code=ajax;sub_code=logout;session="+sSession);
	$(function() { $( '<div id="logout"/>' ).dialog({ title:'Сессия завершена, спасибо!', height:10, modal: true, buttons: { Ok: function() { $( this ).dialog( "close" ); location="";}	}}); } );
	});	
//
// END RADIO BUTTONS
//XHR
//

//
// FILTER		
//
	$('#msrn_call tfoot th').each( function (cellIdx) {
    $(this).html( '<input type="text" id="filter_call'+cellIdx+'" placeholder="Фильтр" />' ); } );
//	
	$('#filter_call0').datepicker({ dateFormat: "yy-mm-dd" });
	$('#filter_call0').on( 'keyup change', function () {oTable_call.column( 0 ).search( this.value ).draw();} );
	$('#filter_call2').on( 'keyup change', function () {oTable_call.column( 2 ).search( this.value ).draw();} ); 
//    
	$('#msrn_billing tfoot th').each( function (cellIdx) {
    $(this).html( '<input type="text" id="filter_billing'+cellIdx+'" placeholder="Фильтр" />' ); } );
//
	$('#filter_billing0').datepicker({ dateFormat: "yy-mm-dd" });	
	$('#filter_billing0').on( 'keyup change', function () {oTable_billing.column( 0 ).search( this.value ).draw();} );
	$('#filter_billing1').on( 'keyup change', function () {oTable_billing.column( 1 ).search( this.value ).draw();} );
	$('#filter_billing2').on( 'keyup change', function () {oTable_billing.column( 2 ).search( this.value ).draw();} );
	 var Tags =["CALL","CALL REQUEST","LU_CDR","DATASESSION","IMEI","MSRN"];
	 $( "#filter_billing3" ).autocomplete({source: Tags});
    $('#filter_billing3').on( 'keyup change', function () {oTable_billing.column( 3 ).search( this.value ).draw();} ); 
//
// END FILTER	
// AJAX
	function ajaxPost(itemParam){
	$.ajax({
		type: "POST",
		url: hHost+"?",
		data: itemParam,
		complete: function(data) {		},
		success: function() {}	
	});
}//END ajaxPost
//
function PAY_SEND(itemParam){
	$.ajax({
		type: "POST",
		url: hHost+"?",
		data: itemParam,
		complete: function(data) {
	var Resp = data.responseText;
	var parsed_data = JSON.parse(Resp);
//		console.log(Resp);
//		console.log(parsed_data.xml);
//		console.log(parsed_data.sign);
		PayXML=parsed_data.xml;
		PayKEY=parsed_data.sign;
	$('<form action="'+PayHost+'" method="POST" target="_blank"><input name="signature" value="'+PayKEY+'"/><input name="operation_xml" value="'+PayXML+'"/></form>').submit();
		},
		success: function() {
		}
	});
}//END PAY SEND
// END AJAX
//		
// SummerTime
function fnSummerTime ( data, nRow, iStart, iEnd, iDisplay ) {
var i=s=h=H=M=S=0;
function Format ( f ) { f=String(f); if (f.length==1){ f ='0'+ f; return f }else{ return f} }
//
 for ( i ; i<iEnd ; i++ )
            {
                var ms = data[i][nRow].split(':');
                s += ms[2]*1;
                h += ms[0]*3600 + ms[1]*60 + ms[2]*1;
           };           
H=Math.floor(h/3600);
M=Math.floor(h%3600/60);
S=s%60;
//
tSUM = Format(H) + ':' + Format(M) + ':' + Format(S);
i=s=h=H=M=S=0;
for ( var i=iStart ; i<iEnd ; i++ )
            {
            	var ms = data[iDisplay[i]][nRow].split(':');
                s += ms[2]*1;
                h += ms[0]*3600 + ms[1]*60 + ms[2]*1;
//      
           }
//
H=Math.floor(h/3600);
M=Math.floor(h%3600/60);
S=s%60;           
//
pSUM = Format(H) + ':' + Format(M) + ':' + Format(S);
//return pSUM+' ('+tSUM+')';
return pSUM;
}//fnSummerTime
//
//
function fnSummer ( data, nRow, iStart, iEnd, iDisplay ) {
var pSUM=tSUM=mSUM=0;
function Format ( f ) { f=String(f); if (f.length==1){ f ='0'+ f; return f }else{ return f} }
//
	for ( var i=0; i<iEnd ; i++ ){ data[iDisplay[i]][3]==='PAY' ?  mSUM += data[iDisplay[i]][nRow]*1 : null; }
 //               
// for ( var i=0 ; i<iEnd ; i++ )  { tSUM += data[i][nRow]*1 }
 //                    
	for ( var i=iStart ; i<iEnd ; i++ ){ data[iDisplay[i]][3]==='TRF' ? null : pSUM += data[iDisplay[i]][nRow]*1; }
//
mSUM>0 ? pSUM=pSUM.toFixed(2) +' <span class=tooltip data-tooltip="Сумма пополнений"> ['+mSUM.toFixed(2)+']</span>' : pSUM=pSUM.toFixed(2);
return pSUM;
}//fnSummer
//
			/* Formating function for row details */
//
function fnFormatDetails ( data, jT )
{
    var didOrder;
	var didNum;
	var aliasText;
	var didDate;
   ( jT==1 && data[5]>0)? didNum=data[5] : didNum="N/A";
	didNum.match(38094) ? didOrder="Продлить $3" : didOrder="Заказать $3";
	didNum.match('N') ? didOrder="Заказать $3" : 0;
	(jT==1 && data[2]>0) ? aliasText=data[2] : aliasText="N/A";
	( jT==1 && data[6]) ? didDate="до "+data[6] : didDate="";
    var cOut=[];
		cOut[0] = '<table id=0 cellpadding="3" cellspacing="0" border="0">';
    cOut[0] += '</table>';
		cOut[1] = '<table id=1 cellpadding="3" cellspacing="0" border="0" class="test">';
    cOut[1] += '<tr><td>Email:</td><td><input id="alias" name="'+data[1]+'" type=text maxlength=25 value="'+data[2]+'"/><td></tr>';
    cOut[1] += '</table>';
          
    	cOut[2] = '<table id=2 cellpadding="3" cellspacing="0" border="0" style="">';
    cOut[2] += '<tr><td>Источник:</td><td>'+data[6]+'</td></tr>';
    cOut[2] += '<tr><td>Назначение:</td><td>'+data[7]+'</td></tr>';
    cOut[2] += '<tr><td>Длительность (общая):</td><td>'+data[8]+'</td></tr>';
    cOut[2] += '<tr><td>Тариф входящий:</td><td>'+data[9]+'</td></tr>';
    cOut[2] += '<tr><td>Тариф назначения:</td><td>'+data[10]+'</td></tr>';
    cOut[2] += '<tr><td>MSRN:</td><td>'+data[11]+'</td></tr>';
    cOut[2] += '<tr><td>ID звонка:</td><td>'+data[12]+'</td></tr>';
    cOut[2] += '<tr><td>Номер счета:</td><td>'+data[1]+'</td></tr>';
    cOut[2] += '<tr><td>Транк:</td><td>'+data[14]+'</td></tr>';
    cOut[2] += '</table>';
    
    return cOut[jT];
}//fnFormatDetails

		}) // DOCUMENT READY
// END