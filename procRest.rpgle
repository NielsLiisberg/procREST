<%@ free="*YES" language="RPGLE" runasowner="*YES" owner="QPGMR"%>
<%
ctl-opt copyright('System & Method (C), 2019');
ctl-opt decEdit('0,') datEdit(*YMD.) main(main); 
ctl-opt bndDir('NOXDB':'ICEUTILITY':'QC2LE');

/* -----------------------------------------------------------------------------
	Service . . . : Stored procedure router 
	Author  . . . : Niels Liisberg 
	Company . . . : System & Method A/S

	procREST is a simple way to expose stored procedures as RESTservice. 
	Note - you might contain the services you expose either by access security
	or by user defined access rules added to this code - Whatever serves you best.


	Procedures can be used if they have:
		a) Only inputparameters
		b) Return one dynamic result set:



	1) Copy this code to your own server root and 
	compile this stored procedure router - Supply your file and serverid:

	CRTICEPGM STMF('/www/MicroServices/procRest.rpgle') SVRID(microserv)

	2) Procedures can be used if they have:
		a) Only inputparameters
		b) Return one dynamic result set:
	
	Example:
	
	Build a test stored procedure - paste this into ACS:

	-- Procedure returns a resultset
	--------------------------------
	CREATE or REPLACE PROCEDURE  qgpl.custlist  (
	   in custName varchar(20) default null
	)
	LANGUAGE SQL 
	DYNAMIC RESULT SETS 1

	BEGIN

		declare c1 cursor with return for
		select * 
		from   qiws.QCUSTCDT
		where  custName is null 
		or     upper(lstnam) like '%' concat upper(custName) concat '%';
		
		open c1;

	END; 

	comment on procedure qgpl.custlist is 'Customer list';
	comment on parameter qgpl.custlist (custname is 'Search customers by name');


	3) Test the procedure works in ACS:

	call qgpl.custList (custName => 'j');
	call qgpl.custList ();
 
	
	4) Enable procREST in your web config:
	
	Add the procREST in the routing section in you webconfig.xml file in your server root:

	<routing strict="false">
		<map pattern="^procREST/" pgm="procrest" lib="*LIBL" />
	</routing>

	</routing>



	5) Get description of every compatible procedure in QGPL:

	http://myibmi:8003/procRest/qgpl


	6) Run the custList service:

	http://myibmi:8003/procRest/qgpl/custList?custName=John


	By     Date       PTF     Description
	------ ---------- ------- ---------------------------------------------------
	NLI    25.07.2018         New program
	----------------------------------------------------------------------------- */
 /include qasphdr,jsonparser
 /include qasphdr,iceutility
 
// --------------------------------------------------------------------
// Main line:
// --------------------------------------------------------------------
dcl-proc main;

	dcl-s pPayload       pointer;

	pPayload = unpackParms();
	processAction(pPayload);
	cleanup(pPayload);

end-proc;
// --------------------------------------------------------------------  
dcl-proc processAction;	

	dcl-pi *n;
		pAction pointer value;
	end-pi;
	
	dcl-s pResponse		pointer;		
	dcl-s msg 			varchar(512);		

	pResponse = runService (pAction);
	if (pResponse = *NULL);
		pResponse =  FormatError (
			'Null object returned from service'
		);
	endif;
	
	if json_getStr(pResponse : 'description') <> 'HTML';
		responseWriteJson(pResponse);
		if json_getstr(pResponse : 'success') = 'false';
			msg = json_getstr(pResponse: 'message');
			if msg = '';
				msg = json_getstr(pResponse: 'msg');
			endif;
			setStatus ('500 ' + msg);
			consoleLogjson(pResponse);
		endif;
	endif;
	json_delete(pResponse);

end-proc;
/* -------------------------------------------------------------------- *\  
   get data form request
\* -------------------------------------------------------------------- */
dcl-proc unpackParms;

	dcl-pi *n pointer;
	end-pi;

	dcl-s pPayload 		pointer;
	dcl-s msg     		varchar(4096);
	dcl-s callback     	varchar(512);


	SetContentType('application/json; charset=utf-8');
	SetEncodingType('*JSON');
	json_setDelimiters('/\@[] ');
	json_sqlSetOptions('{'             + // use dfault connection
		'upperCaseColname: false,   '  + // set option for uppcase of columns names
		'autoParseContent: true,    '  + // auto parse columns predicted to have JSON or XML contents
		'sqlNaming       : false    '  + // use the SQL naming for database.table  or database/table
	'}');

	callback = reqStr('callback');
	if (callback>'');
		responseWrite (callback + '(');
	endif;

	if reqStr('payload') > '';
		pPayload = json_ParseString(reqStr('payload'));
	elseif getServerVar('REQUEST_METHOD') = 'POST';
		pPayload = json_ParseRequest();
	else;
		pPayload = *NULL;
	endif;

	/*
	if json_error(pPayload);
		msg = json_message(pPayload);
		%>{ "text": "Microservices transactions is ready. Please POST payload in JSON", "desc": "<%= msg %>"}<%
		return *NULL;
	endif;
	*/
	return pPayload;


end-proc;
// -------------------------------------------------------------------------------------
dcl-proc cleanup;
	
	dcl-pi *n;
		pPayload pointer value;
	end-pi;
	dcl-s callback     	varchar(512);

	json_close(pPayload);

	callback = reqStr('callback');
	if (callback > '');
		responseWrite (')');
	endif;

end-proc;
/* -------------------------------------------------------------------- *\ 
   	run a a microservice call
\* -------------------------------------------------------------------- */
dcl-proc runService export;	

	dcl-pi *n pointer;
		pActionIn pointer value options (*string);
	end-pi;
	
	dcl-s Action  		varchar(128);
	dcl-s schemaName    varchar(10);
	dcl-s procName 		varchar(128);
	dcl-s pAction       pointer;
	dcl-s pResponse		pointer;		
	dcl-s name  		varchar(64);
	dcl-s value  		varchar(32760);
	dcl-s parmList  	varchar(32760);
	dcl-s sqlStmt   	varchar(32760);
	
	dcl-s len 			int(10);
	dcl-ds iterParms  	likeds(json_iterator);


	// will return the same pointer id action is already a parse object
	pAction = json_parseString(pActionIn);

	action   = json_GetStr(pAction:'action');
	if (action <= '');
		action = strUpper(getServerVar('REQUEST_FULL_PATH'));
		schemaName  = word (action:2:'/');
		procName = word (action:3:'/');
	else;

		//if  action <> prevAction;
		//	prevAction = action;
		action = strUpper(action);
		schemaName  = word (action:1:'.');
		procName = word (action:2:'.');
	endif;

	if schemaName <= '';
		return FormatError (
			'Need schema and procedure'
		);
	endif;

	if procname = '';
		return listProcForSchema ( schemaName);
	endif;


	// Build parameter from posted payload:
	iterParms = json_SetIterator(pAction);
	dow json_ForEach(iterParms);
		if json_getName(iterParms.this) <> 'action';
			strAppend (parmlist : ',' : json_getName(iterParms.this) + '=>' + strQuot(json_getValue(iterParms.this)));
		endif;
  	enddo;

	// Or if parametres are given atr the URL
	getQryStrList ( name : value : '*FIRST');
	dow name > '';
		strAppend (parmlist : ',' : name + '=>' + strQuot(value));
		getQryStrList ( name : value : '*NEXT');
	enddo;    

	sqlStmt = 'call ' + schemaName + '.' + procName + ' (' + parmlist + ')';

	
	pResponse = json_sqlResultSet(
        sqlStmt: // The sql statement,
        1:  // from row,
        -1: // -1=*ALL number of rows
        JSON_META
	);
    

	if json_Error(pResponse);
		consolelog(sqlStmt);
		pResponse= FormatError (
			'Invalid action or parameter: ' + action 
		);
	endif;

	// if my input was a jsonstring, i did the parse and i have to cleanup
	if pAction <> pActionIn;
		json_delete (pAction);
	endif;

	return pResponse; 

end-proc;

/* -------------------------------------------------------------------- *\ 
   JSON error monitor 
\* -------------------------------------------------------------------- */
dcl-proc FormatError;

	dcl-pi *n pointer;
		description  varchar(256) const options(*VARSIZE);
	end-pi;                     

	dcl-s msg 					varchar(4096);
	dcl-s pMsg 					pointer;

	msg = json_message(*NULL);
	pMsg = json_parseString (' -
		{ -
			"success": false, - 
			"description":"' + description + '", -
			"message": "' + msg + '"-
		} -
	');

	consoleLog(msg);
	return pMsg;


end-proc;
/* -------------------------------------------------------------------- *\ 
   JSON error monitor 
\* -------------------------------------------------------------------- */
dcl-proc successTrue;

	dcl-pi *n pointer;
	end-pi;                     

	return json_parseString ('{"success": true}');

end-proc;
/* -------------------------------------------------------------------- *\ 
   produce HTML catalog
\* -------------------------------------------------------------------- */
dcl-proc listProcForSchema;

	dcl-pi *n pointer;
		schemaName varchar(32) value;
	end-pi;

	dcl-s pResult pointer; 
	dcl-ds iterList  	likeds(json_iterator);
	dcl-s  prevSchema   	varchar(32);
	dcl-s  prevRoutine 		varchar(32);
 

	pResult = json_sqlResultSet (`
		Select a.routine_schema , a.routine_name, a.long_comment as desc, b.*
		from sysprocs a
		left join  sysparms b 
		on a.specific_schema = b.specific_schema and a.specific_name = b.specific_name 
		where a.routine_schema in ( ${strQuot(schemaName)}) 
		and   a.result_sets = 1 
		and   a.out_parms = 0 ;
	`);

	head();

	// Build parameter from posted payload:
	iterList = json_SetIterator(pResult);
	dow json_ForEach(iterList);

		if  json_getValue(iterList.this:'routine_schema') <> prevSchema
		or  json_getValue(iterList.this:'routine_name')   <> prevRoutine;
			%><tr><td colspan="7"/></tr><tr>
			<td class="col01"><%= json_getValue(iterList.this:'routine_schema')%></td>    
			<td class="col02" colspan="5"><%= json_getValue(iterList.this:'routine_name')%></td>    
			<td class="col07"><%= json_getValue(iterList.this:'desc')%></td>    
			</tr><%
		endif;
		%><tr>
		<td class="col01"></td>    
		<td class="col02"></td>    
		<td class="col03"><%= json_getStr(iterList.this:'parameter_name')%></td>    
		<td class="col04"><%= json_getStr(iterList.this:'data_type')%></td>    
		<td class="col05"><%= json_getStr(iterList.this:'character_maximum_length')%></td>    
		<%if json_getStr(iterList.this:'IS_NULLABLE') = 'YES'; %>    
			<td class="col06">NO</td>
		<%else;%>
			<td class="col06">YES</td>
		<%endif;%>
		<td class="col07"><%= json_getValue(iterList.this:'long_comment')%></td>    
		</tr><%
		prevSchema  = json_getStr(iterList.this:'routine_schema');
		prevRoutine = json_getStr(iterList.this:'routine_name');
  	enddo;

	tail();

	return formatError ('HTML');

end-proc;
// --------------------------------------------------------------------------------
// Setup the HTML header and stylesheet / (evt. the script links)
// --------------------------------------------------------------------------------
dcl-proc head;
	setContentType('text/html');
%><html>
 <Head>
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
	<link rel="stylesheet" type="text/css" href="/System/Styles/portfolio.css"/>
 </head> 
 <body>
 <h1>Auto services for stored procedures</h1>
 <style>
	.col01{width:80} 
	.col02{width:300} 
	.col03{width:300} 
	.col04{width:200} 
	.col05{width:80;text-align: right } 
	.col06{width:80} 
	.col07{width:800}  
xxxtr:nth-child(even){
	background-color: #fafafa;
}
</style>

<table id="tab1" >
	<thead>
		<tr>
			<th class="col01">Schema</th>
			<th class="col02">Procedure</th>
			<th class="col03">Parameter</th>
			<th class="col04">Type</th>
			<th class="col05">Length</th>
			<th class="col06">Required</th>
			<th class="col07">Description</th>
		</tr>
	</thead>
<%
end-proc;
// --------------------------------------------------------------------------------
// Finish up the final html
// --------------------------------------------------------------------------------
dcl-proc tail;
%></body>
</html>
<%
end-Proc;
