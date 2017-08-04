$( function() {
$("#pin").hide();
	$("input[id='token']").keyup(function count(){
	$("#pin").hide();$("#status").text('')
	if( $("input[id='token']").val().length==10){$("#pin").show();$("#status").text('Pin code:')}
		});
});
