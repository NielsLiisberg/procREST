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

	if 	%scan ('openapi-meta' : strLower(getUrl())) > 0;
		listProcForSchema ('QGPL');
		return;
	endif;


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

	serverSwagerJson (pResult);
	json_delete (pResult);

	return formatError ('HTML');

end-proc;


// --------------------------------------------------------------------  
dcl-proc serverSwagerJson;

	dcl-pi *n ;
		pRoutes pointer value;
	end-pi;

	dcl-ds iterList likeds(json_iterator);  
	dcl-s pOpenApi  pointer;
	dcl-s pRoute 	pointer;
	dcl-s pPaths  	pointer;
	dcl-s pParms  	pointer;
	dcl-s pParm   	pointer;
	dcl-s pMethod 	pointer;
	dcl-s pComponents pointer;
	dcl-s pSchemas   pointer;
	dcl-s pProperty pointer;
	dcl-s method 	int(10);
	dcl-s null  	int(10);
	dcl-s path 		varchar(256);
	dcl-s text 		varchar(256);
	dcl-s ref   	varchar(10) inz('$ref');
	
	dcl-s i 		int(5);

	dcl-s  Schema   	varchar(32);
	dcl-s  Routine 		varchar(32);



	SetContentType ('application/json');

	pOpenApi = json_parseString(`{
		"openapi": "3.0.1",
		"info": {
			"title": "${ getServerVar('SERVER_DESCRIPTION') }",
			"version": "${ getServerVar('SERVER_SOFTWARE')}"
		},
		"servers": [
			{
				"url": "${ getServerVar('SERVER_URI') }",
				"description": "${ getServerVar('SERVER_SYSTEM_NAME') }"
			}
		]
	}`);


	// pOpenApi = json_parsefile ('static/openapi-template.json');
	pPaths = json_locate( pOpenApi : 'paths');
	if pPaths = *null;
		pPaths = json_moveobjectinto  ( pOpenApi  :  'paths' : json_newObject() ); 
	endif;

	pComponents = json_moveobjectinto  ( pOpenApi     :  'components' : json_newObject()); 
	pSchemas    = json_moveobjectinto  ( pComponents  :  'schemas' : json_newObject()); 

	// Now produce the menu JSON 
	iterList = json_setIterator(pRoutes);  
	dow json_ForEach(iterList) ;  

		//method = json_getInt   ( list.this : 'method' ); 
		//path   = json_getStr   ( list.this : 'path'   );
		// text   = json_getStr   ( list.this : 'text'   );

		if  json_getValue(iterList.this:'routine_schema') <> Schema
		or  json_getValue(iterList.this:'routine_name')   <> Routine;

			// Finish last round trip
			if Routine > '';
			endif;

			Schema  = json_getStr(iterList.this:'routine_schema');
			Routine = json_getStr(iterList.this:'routine_name');

		
			pRoute = json_newObject();
			json_noderename (pRoute : '/procrest/qgpl/' + Routine);
			pMethod = json_parseString(
			`{
				"tags": [
					"${Routine}"
				],
				"operationId": "tempura",
				"summary": "${Routine}",
				"requestBody": {
					"content": {
						"application/json": {
							"schema": {
								"${ref}": "#/components/schemas/${Routine}"
							}
						}
					},
					"required": true
				},
				"responses": {
					"200": {
						"description": "OK",
						"content": {
							"application/json": {
								"schema": {
									"${ref}": "#/components/schemas/JsonNode"
								}
							}
						}
					},
					"403": {
						"description": "No response from service"
					},
					"406": {
						"description": "Combination of parameters raises a conflict"
					}
				}
			}`);	
			json_moveobjectinto  ( pRoute  :  'post'  : pMethod ); 
			json_nodeInsert ( pPaths  : pRoute : JSON_LAST_CHILD); 

			pParms = json_moveobjectinto  ( pSchemas  :  Routine : json_newObject() ); 
			json_setStr(pParms : 'type' : 'object');
			pProperty  = json_moveobjectinto  ( pParms  :  'properties' : json_newObject() ); 
			
		endif;

		json_nodeInsert ( pProperty  : swaggerParm (iterList.this)  : JSON_LAST_CHILD); 


	enddo;	

	responseWriteJson(pOpenApi);
	json_delete(pOpenApi);


end-proc;

// ------------------------------------------------------------------------------------
// swaggerParm
// ------------------------------------------------------------------------------------
dcl-proc swaggerParm;

	dcl-pi swaggerParm pointer ;
		pMetaParm pointer value;
	end-pi;

	dcl-s pParm pointer; 
	dcl-s parmType int(5); 
	dcl-s unmasked  int(5); 
	dcl-s mask      int(5); 
	dcl-s inType varchar(32);
	
	/* 
	parmType =  json_getInt (pMetaParm : 'parmType') ;

	select; 
		when parmType = RT_PATH;
			intype = 'path';
		when parmType = RT_QRYSTR;
			intype = 'query';
		when parmType = RT_FORM;
			intype = 'formData';
		when parmType = RT_PAYLOAD;
			intype = 'body';
		other;
			intype = 'query';
	endsl; 
	*/ 

	pParm = json_newObject(); 
	json_noderename (pParm : json_getstr (pMetaParm : 'parameter_name'));
	json_copyValue (pParm : 'name'        : pMetaParm : 'parameter_name' );
	json_copyValue (pParm : 'description' : pMetaParm : 'long_comment');
	json_setStr    (pParm : 'type'        : dataTypeJson  (json_getstr (pMetaParm : 'data_type')));
	json_setStr    (pParm : 'format'      : dataFormatJson(json_getstr (pMetaParm : 'data_type')));
	json_setBool   (pParm : 'required'    : json_getstr(pMetaParm : 'IS_NULLABLE') <> 'YES' );
	return pParm;
end-proc;
// ------------------------------------------------------------------------------------
// dataTypeJson
// ------------------------------------------------------------------------------------
dcl-proc dataTypeJson;

	dcl-pi *n varchar(32);
		inputType varchar(32) const;
	end-pi;

	select; 
		when %len(inputType) >= 3 and %subst ( strLower (inputType) : 1 : 3)  = 'int';
			return 'integer';
		other;
			return 'string';
	endsl;

end-proc;

// ------------------------------------------------------------------------------------
// dataFormatJson
// ------------------------------------------------------------------------------------
dcl-proc dataFormatJson;

	dcl-pi *n varchar(32);
		inputType varchar(32) const;
	end-pi;

	select; 
		when %len(inputType) >= 3 and %subst ( strLower (inputType) : 1 : 3)  = 'int';
			return 'int64';
		other;
			return '';

	endsl;

end-proc;


// ------------------------------------------------------------------------------------
// getUrl
// ------------------------------------------------------------------------------------
dcl-proc getUrl;

	dcl-pi getUrl varchar(4096);
	end-pi;

	return '/' + getServerVar('REQUEST_FULL_PATH');

end-proc;
