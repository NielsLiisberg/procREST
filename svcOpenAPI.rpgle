
<%@ free="true" language="RPGLE" runasowner="*YES" owner="QPGMR"%><%
ctl-opt copyright('System & Method (C), 2023');
ctl-opt decEdit('0,') datEdit(*YMD.) main(main); 
ctl-opt bndDir('NOXDB':'ICEUTILITY':'QC2LE');

/* -----------------------------------------------------------------------------
   Service . . . : microservice router
   Author  . . . : Niels Liisberg 
   Company . . . : System & Method A/S
  
   CRTICEPGM STMF('/www/IceBreak-Samples/restrouter.rpgle') SVRID(samples)
   
   By     Date       PTF     Description
   ------ ---------- ------- ---------------------------------------------------
   NLI    14.02.2023         New program
   ----------------------------------------------------------------------------- */
 /include qasphdr,jsonparser
 /include qasphdr,iceutility
 /include AINCLUDE/QRPGHDR,REGEX_H

 dcl-c RT_GET    1; 
 dcl-c RT_POST   2; 
 dcl-c RT_PUT    4;
 dcl-c RT_DELETE 8;
 dcl-c RT_PATCH  16;
 dcl-c RT_ANY    127;

// Bit mask  0000-0000-0000-1111 
 dcl-c RT_PATH    1;
 dcl-c RT_QRYSTR  2;
 dcl-c RT_FORM    3;
 dcl-c RT_PAYLOAD 4;

 dcl-c RT_RETURN  -1;

 dcl-c RT_REQUIRED *NULL;
 dcl-c RT_DEFAULT  '';
  
// Bit mask  0000-0000-0010-0000 
 dcl-c RT_JSON 32; 
 

 dcl-s RT_PREFIX varchar(256) inz('/api');
  
// TODO !! 
dcl-ds pmatch   likeds(regmatch_t) dim(100);

 
// --------------------------------------------------------------------
// Main line:
// --------------------------------------------------------------------
dcl-proc main;

	dcl-s pRoutes        pointer static inz(*NULL);

	if pRoutes = *NULL;
		pRoutes = setupRoutes();
	endif;

	router_execute( pRoutes );


end-proc;

// --------------------------------------------------------------------  
dcl-proc setupRoutes;	

	dcl-pi *n pointer;
	end-pi;

	dcl-s pRoutes pointer;

	router_add ( pRoutes : 
		router_url  ( RT_GET  : '/product/{id}' ): 
		router_info ( 'Find product by ID') : 
		router_service_program_to_call ( '*LIBL' : 'msProduct' : 'productFindById'):
		router_parms (
			router_input(RT_PATH  : RT_JSON  :
				1: 'id'     : 'int(10)'     : 'Product id number' : RT_REQUIRED)
		)
	);

	router_add ( pRoutes : 
		router_url  ( RT_GET : '/product/search' ): 
		router_info ( 'List and serarch in the products') : 
		router_service_program_to_call ( '*LIBL' : 'msProduct' : 'productSearch'):
		router_parms (
			router_input(RT_QRYSTR : RT_JSON :
				1: 'search' : 'varchar(32)' : 'Search in database' : RT_DEFAULT):
			router_input(RT_QRYSTR : RT_JSON :
				1: 'start'  : 'int(10)'     : 'Starting from row number': %char(1)):
			router_input(RT_QRYSTR : RT_JSON :
				1: 'limit'  : 'int(5)'      : 'Number of rows to return' : %char(JSON_ALLROWS)):
			router_input(RT_QRYSTR : RT_JSON :
				1: 'sort' : 'varchar(32)' : 'sort resultset by column' : RT_DEFAULT)
		)
	);


	router_add ( pRoutes : 
		router_url  ( RT_PATCH  : '/product/{id}' ): 
		router_info ( 'Update product by ID') : 
		router_service_program_to_call ( '*LIBL' : 'msProduct' : 'productUpdate'):
		router_parms (
			router_input(RT_PATH   : RT_JSON  :
				1: 'id'     : 'int(10)'     : 'Product id number' : RT_REQUIRED):
			router_input(RT_PAYLOAD  : RT_JSON  :
				1: 'row'     : 'pointer'    : 'Product row' : RT_REQUIRED)
		)
	);



	json_writeJsonStmf ( pRoutes : '/tmp/routes.json' : 1208 : *off);

	return pRoutes;

end-proc;


// ============================ Move to Service program  ==============================

// ------------------------------------------------------------------------------------
// router_execute
// ------------------------------------------------------------------------------------
dcl-proc router_execute;

	dcl-pi router_execute ;
		pRoutes  pointer;
	end-pi;

	dcl-s pPayload       pointer;

	if 	%scan ('openapi-meta' : strLower(getUrl())) > 0;
		serverSwagerJson (pRoutes);
		return;
	endif;

	pPayload = unpackParms();
	processAction(pPayload : pRoutes);
	cleanup(pPayload);
	
	// Force reload of reouts in development mode
	if getServerVar('SERVER_JOB_MODE') = '*DEVELOP';
		 json_close(pRoutes);
	endif;

end-proc;
// --------------------------------------------------------------------  
dcl-proc serverSwagerJson;

	dcl-pi *n ;
		pRoutes pointer value;
	end-pi;

	dcl-ds list     likeds(json_iterator);  
	dcl-ds itparms  likeds(json_iterator);  
	dcl-s pOpenApi  pointer;
	dcl-s pRoute 	pointer;
	dcl-s pPaths  	pointer;
	dcl-s pParms  	pointer;
	dcl-s pParm   	pointer;
	dcl-s pMethod 	pointer;
	dcl-s method 	int(10);
	dcl-s null  	int(10);
	dcl-s path 		varchar(256);
	dcl-s text 		varchar(256);
	dcl-s i 		int(5);
	dcl-s mask 		int(10);

	Dcl-ds *N;
		*n varchar(10) inz('get');
		*n varchar(10) inz('post');
		*n varchar(10) inz('put');
		*n varchar(10) inz('delete');
		*n varchar(10) inz('patch');
 		methodText varchar(10) Dim(5) Pos(1);
	End-ds;

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

	// Now produce the menu JSON 
	list = json_setIterator(pRoutes);  
	dow json_ForEach(list) ;  

		method = json_getInt   ( list.this : 'method' ); 
		path   = json_getStr   ( list.this : 'path'   );
		text   = json_getStr   ( list.this : 'text'   );

		if  path > ''; 
		
			pRoute = json_newObject();
			json_noderename (pRoute : path);
			mask = 1; 
			for i = 1 to %elem(methodText); 
				if %bitand( method : mask) <> null; 
					pMethod = json_parseString(
					`{
						"tags": [
							"${text}"
						],
						"operationId": "tempura",
						"summary": "${text}",
						"requestBody": {
							"content": {
								"application/json": {
									"schema": {
										"\\ref": "#/components/schemas/JsonNode"
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
											"\\ref": "#/components/schemas/JsonNode"
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

					if methodText(i) = 'get';
						json_delete ( json_locate (pMethod : 'requestBody'));
					endif;

					pParms = json_moveobjectinto  ( pMethod  :  'parameters' : json_newArray() ); 

					itparms  = json_setIterator(list.this : 'parms');  
					dow json_ForEach(itparms) ;  
						json_arrayPush ( pParms : swaggerParm ( itparms.this ));
					enddo;

					json_moveobjectinto  ( pRoute  :  methodText(i) : pMethod ); 
				endif;
				mask *= 2; 
			endfor;
			json_nodeInsert ( pPaths  : pRoute : JSON_LAST_CHILD); 
		endif;
	enddo;	

	//responseWritejson(pRoutes);
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


	pParm = json_newObject(); 
	json_copyValue (pParm : 'name'        : pMetaParm : 'name');
	json_setStr    (pParm : 'in'          : inType  );
	json_copyValue (pParm : 'description' : pMetaParm : 'text');
	json_setStr    (pParm : 'type'        : dataTypeJson  (json_getstr (pMetaParm : 'datatype')));
	json_setStr    (pParm : 'format'      : dataFormatJson(json_getstr (pMetaParm : 'datatype')));
	json_setBool   (pParm : 'required'    : json_getValuePtr (json_locate(pMetaParm : 'default')) = *NULL );
	return pParm;
end-proc;

// --------------------------------------------------------------------  
dcl-proc router_url; 

	dcl-pi *n pointer;
		method  int(5) value;
		path  	varchar(256) const;
	end-pi;

	dcl-s pReturn pointer;

	pReturn = json_newObject(); 
	json_setInt (pReturn : 'method': method); 
	json_setStr (pReturn : 'path': RT_PREFIX + path); 

	return pReturn;

end-proc;
// --------------------------------------------------------------------  
dcl-proc router_info; 

	dcl-pi *n pointer;
		text  varchar(256) const;
		statuslist  varchar(256) const options(*NOPASS);
	end-pi;

	dcl-s pReturn pointer;

	pReturn = json_newObject(); 
	json_setStr (pReturn : 'text': text); 
	json_setStr (pReturn : 'statuslist': statuslist); 

	return pReturn;

end-proc;
// --------------------------------------------------------------------  
dcl-proc router_service_program_to_call; 

	dcl-pi *n pointer;
		lib  varchar(10) value;
		pgm  varchar(10) value;
		proc varchar(32) value;
	end-pi;

	dcl-s pProc pointer;
	dcl-s pProcPtr pointer(*proc);

	lib = strupper(%trim(lib));
	pgm = strupper(%trim(pgm));
	proc = strupper(%trim(proc));
	pProcPtr = loadServiceProgramProc (lib : pgm : proc);


	pProc = json_newObject();
	json_setStr (pProc : 'lib' : lib);
	json_setStr (pProc : 'pgm' : pgm);
	json_setStr (pProc : 'proc' : proc);
	json_setProcPtr (pProc : 'procptr' : pProcPtr);

	return pProc;

end-proc; 

// --------------------------------------------------------------------  
dcl-proc error404;

	dcl-s pResponse pointer; 

	setStatus ('404');

	pResponse= FormatError (
		'Resource not found ' 
	);

	responseWriteJson ( pResponse); 

	json_delete (pResponse);

end-proc;
// --------------------------------------------------------------------  
dcl-proc router_parms;	

	dcl-pi *n pointer;
		p01  pointer value options(*nopass);
		p02  pointer value options(*nopass);
		p03  pointer value options(*nopass);
		p04  pointer value options(*nopass);
		p05  pointer value options(*nopass);
		p06  pointer value options(*nopass);
		p07  pointer value options(*nopass);
		p08  pointer value options(*nopass);
		p09  pointer value options(*nopass);
		p10  pointer value options(*nopass);
		p11  pointer value options(*nopass);
		p12  pointer value options(*nopass);
		p13  pointer value options(*nopass);
		p14  pointer value options(*nopass);
		p15  pointer value options(*nopass);
		p16  pointer value options(*nopass);
		p17  pointer value options(*nopass);
		p18  pointer value options(*nopass);
		p19  pointer value options(*nopass);
		p20  pointer value options(*nopass);
	end-pi;

	dcl-s pArr pointer;
	dcl-s pReturn pointer;
	
	pArr = json_newArray();
	pReturn = json_newObject(); 

	// This is simply to ugly ... parse an array please !! 
	if json_isNode(p01);
		json_arrayPush ( pArr : p01);
	endif;
	if json_isNode(p02);
		json_arrayPush ( pArr : p02);
	endif;
	if json_isNode(p03);
		json_arrayPush ( pArr : p03);
	endif;
	if json_isNode(p04);
		json_arrayPush ( pArr : p04);
	endif;

	json_moveobjectinto ( pReturn : 'parms' : pArr);
	return pReturn;

end-proc; 

// --------------------------------------------------------------------  
dcl-proc router_input;	

	dcl-pi *n pointer;
		parmType      int(5) value;
		destination   int(5) value;
		parmnumber    int(5) value;
		name          varchar(256) const;
		dataType      varchar(32)  const;
		text          varchar(256) const;
		defaultValue  pointer value options(*string : *nopass);
	end-pi;

	dcl-s parmObj pointer;

	parmObj = json_newObject();
	json_setStr ( parmObj : 'usage'       : 'IN' );
	json_setInt ( parmObj : 'parmType'    : parmType );
	json_setInt ( parmObj : 'destination' : destination );
	json_setInt ( parmObj : 'parmnumber'  : parmnumber );
	json_setStr ( parmObj : 'name'        : name);
	json_setStr ( parmObj : 'dataType'    : dataType);
	json_setStr ( parmObj : 'text'        : text);
	json_setStr ( parmObj : 'default'     : defaultValue);
	
	return parmObj; 

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
// --------------------------------------------------------------------  
dcl-proc router_output;	

	dcl-pi *n pointer;
		parmType    int(5) value;
		parmnumber  int(5) value;
		name        varchar(256) const;
		dataType    varchar(32)  const;
		text        varchar(256) const;
	end-pi;

	dcl-s parmObj pointer;

	parmObj = json_newObject();
	json_setStr ( parmObj : 'usage'     : 'OUT' );
	json_setInt ( parmObj : 'parmType'  : parmType );
	json_setInt ( parmObj : 'parmnumber': parmnumber );
	json_setStr ( parmObj : 'name'      : name);
	json_setStr ( parmObj : 'dataType'  : dataType);
	json_setStr ( parmObj : 'text'      : text);
	
	return parmObj; 

end-proc; 

// --------------------------------------------------------------------  
dcl-proc router_add;	

	dcl-pi *n pointer;
		pRoutes   pointer;
		options01 pointer value options(*nopass);
		options02 pointer value options(*nopass);
		options03 pointer value options(*nopass);
		options04 pointer value options(*nopass);
		options05 pointer value options(*nopass);
	end-pi;

	dcl-s pRoute pointer;

	if pRoutes = *NULL ; 
		pRoutes = json_newArray();
	endif; 


	pRoute = json_newObject();

	if json_isNode(options01);
		json_mergeObjects (pRoute : options01 : MO_MERGE_REPLACE + MO_MERGE_MOVE);
	endif;
	if json_isNode(options02);
		json_mergeObjects (pRoute : options02 : MO_MERGE_REPLACE + MO_MERGE_MOVE);
	endif;
	if json_isNode(options03);
		json_mergeObjects (pRoute : options03 : MO_MERGE_REPLACE + MO_MERGE_MOVE);
	endif;
	if json_isNode(options04);
		json_mergeObjects (pRoute : options04 : MO_MERGE_REPLACE + MO_MERGE_MOVE);
	endif;
	if json_isNode(options05);
		json_mergeObjects (pRoute : options05 : MO_MERGE_REPLACE + MO_MERGE_MOVE);
	endif;

	regex_url (pRoute);

	consoleLogJSon(pRoute);

	json_arrayPush ( pRoutes : pRoute); 
	return pRoute;


end-proc; 
// --------------------------------------------------------------------  
dcl-proc regex_url;	

	dcl-pi *n pointer;
		pRoute pointer;
	end-pi;

	dcl-s st int(5) inz(1);
	dcl-s en int(5);
	dcl-s p  int(5);
	dcl-s rc  int(5);
	dcl-s group  int(5);
	dcl-s done ind;
	dcl-s path      varchar(256);
	dcl-s pathregex	varchar(256);
	dcl-s name      varchar(256);
	dcl-s parmname  varchar(256);
	dcl-s type      varchar(256);
	dcl-s pParms    pointer; 
	dcl-s pNode     pointer; 
	dcl-s pReg      pointer; 
	dcl-s procptr   pointer(*proc); 
 	dcl-ds reg  likeds(regex_t) based(preg);

	// Any path parameters? 
	pParms  = json_locate( pRoute : 'parms');
	path   =  json_getStr( pRoute : 'path'); 
	path = %scanrpl ('/':'\/': path); // TODO - convert the semi regex to a URL 
	pathregex = path; 

	dou done;
		done = *ON;  
		st = %scan ( '{': path : st); 
		if st > 0; 
			en = %scan ( '}': path : st); 
			if en > 0; 
				name = %subst( path : st + 1: en - st - 1); 
				pNode = json_locate (pParms: '[name=' + name +']');
				type = json_getStr(pNode: 'datatype');
				group += 1;
				json_setInt( pNode : 'group' : group);
				select;
					when %len(type) >= 3 and  %subst(type : 1 : 3)  = 'int';
						parmname = '{'+  name+'}'; 
						p = %scan ( parmname : pathregex );
						pathregex = %replace ('([[:digit:]]+)' : pathregex : p : %len(parmname) ); 
					other;
						json_joblog('Missing path parameter for: ' + name);
				endsl; 
				done = *OFF; 
				st = en; 
			endif;	
		endif;
	enddo; 

	pReg = %alloc ( %size (regex_t));
	rc = regcomp(reg : pathregex   : REG_EXTENDED + REG_ICASE );
	if rc <> 0;
		json_joblog('Invaid regex for path: ' + pathregex );
	endif;
	json_setPtr ( pRoute : 'pathregex' : pReg);

	return pRoute;

end-proc;

// --------------------------------------------------------------------  
dcl-proc route_lookup;

	dcl-pi *n pointer;
		url varchar(256) const ;
		pRoutes pointer value;
	end-pi;

	dcl-s  pReturn  pointer; 
	dcl-s  pReg     pointer; 
	dcl-s  rc       int(10) inz(-1);
	dcl-ds reg      likeds(regex_t) based(preg);
	dcl-ds list     likeds(json_iterator);  
	dcl-s  nmatch   int(10); 
	
	nmatch = %elem ( pmatch) ;


	// Loop through routes until a match is found  
	list = json_setIterator(pRoutes);  
	dow json_ForEach(list) and rc <> 0;  
		preg = json_getValuePtr(json_locate(list.this : 'pathregex'));
		rc = regexec ( reg : url : nmatch : pmatch : 0);
		if rc = 0; // FOUND ;) 
			list.break = *ON;
			pReturn = list.this;
		endif; 
	enddo;	

	return pReturn;

end-proc;
// --------------------------------------------------------------------  
dcl-proc processAction;	

	dcl-pi *n;
		pPayload pointer value;
		pRoutes  pointer value;
	end-pi;
	
	dcl-s pResponse		pointer;	
	dcl-s message       varchar(256); 	

	pResponse = runService (pPayload : pRoutes);

	if (pResponse = *NULL) ;
		if getResponseLength() > 0 ;
			// OK - the service produced the output "by hand"
		else; 
			pResponse = json_newObject();
			json_setBool (pResponse : 'success': *OFF);
			setStatus ('403 No response from service');
			responseWriteJson(pResponse);
			json_delete(pResponse);
		endif;
	else;
		if json_getstr(pResponse : 'success') = 'false';
			message = json_getstr(pResponse: 'message');
			if message <= ''; 
				message = json_getstr(pResponse: 'msg');
			endif;
			setStatus ('406 ' + message);
		endif;
		responseWriteJson(pResponse);
		json_delete(pResponse);
	endif;

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
		%>{ "text": "Microservices. Ready for transactions. Please POST payload in JSON", "desc": "<%= msg %>"}<%
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

	json_delete(pPayload);

	callback = reqStr('callback');
	if (callback > '');
		responseWrite (')');
	endif;

end-proc;
/* -------------------------------------------------------------------- *\ 
   	run a microservice call
\* -------------------------------------------------------------------- */
dcl-proc runService;	

	dcl-pi *n pointer;
		pPayload pointer value;
		pRoutes pointer value;
	end-pi;

	dcl-pr ActionProc pointer extproc(pProc);
		pParm1 pointer value;
	end-pr;
	

	dcl-ds itparms  likeds(json_iterator);  
	dcl-s Action  		varchar(128);
	dcl-s pgmName 		char(10);
	dcl-s procName 		varchar(128);
	dcl-s pProc			pointer (*PROC);
	dcl-s pResponse		pointer;	
	dcl-s pRoute        pointer;
	dcl-s errText  		char(128);
	dcl-s errPgm   		char(64);
	dcl-s errList 		char(4096);
    dcl-s len 			int(10);
	dcl-s pParm1			pointer;
	dcl-s parmType		int(5);
	dcl-s name 			varchar(64);
	dcl-s default 	 	varchar(4096);


	pParm1 = pPayload;
	pRoute = route_lookup(getUrl() : pRoutes );

	if pRoute <> *NULL; 
		pProc = json_getValueProcPtr (json_locate ( pRoute : 'procptr'));

		pParm1 = json_newObject();
		itparms  = json_setIterator(pRoute : 'parms');  
		dow json_ForEach(itparms) ;  
			if json_getstr(itparms.this : 'usage') = 'IN';
				parmType =  json_getInt (itparms.this : 'parmType');
				name = json_getstr(itparms.this : 'name');
				default = json_getstr(itparms.this : 'default');

				select; 
					when parmType = RT_PATH;
						json_setStr (pParm1:  name : pathparm ( itparms.this ) );
					when parmType = RT_QRYSTR;
						json_setStr (pParm1:  name : qryStr (name:default) );
					when parmType = RT_FORM;
						json_setStr (pParm1:  name : form (name:default) );
					when parmType = RT_PAYLOAD;
						json_moveobjectinto (pParm1 : name : pPayload );
						//intype = 'body';
					other;
						//intype = 'query';
				endsl; 
			endif;
		enddo;

		// Parms: 

	endif; 

	if pProc =  *NULL; 

		action   = json_GetStr(pPayload:'action');
		if (action <= '');
			action = strUpper(getUrl());
			len = words(action:'/');
			pgmName  = word (action:len-1:'/');
			procName = word (action:len:'/');
		else;

			//if  action <> prevAction;
			//	prevAction = action;
			action = strUpper(action);
			pgmName  = word (action:1:'.');
			procName = word (action:2:'.');
		endif;

		pProc = loadServiceProgramProc ('*LIBL': pgmName : procName);
		pParm1 = pPayload;

	endif; 


	if (pProc = *NULL);
		pResponse= FormatError (
			'Invalid action: ' + action + ' or service not found'
		);
	else;
		monitor;

		pResponse = ActionProc(pParm1);

		on-error;                                     
			soap_Fault(errText:errPgm:errList);    
			pResponse =  FormatError (
				'Error in service ' + action + ', ' + errText
			);
		endmon;                                       	

	endif;

	json_delete (pParm1);

	return pResponse; 

end-proc;

// ------------------------------------------------------------------------------------
// getUrl
// ------------------------------------------------------------------------------------
dcl-proc getUrl;

	dcl-pi getUrl varchar(4096);
	end-pi;

	return '/' + getServerVar('REQUEST_FULL_PATH');

end-proc;
// ------------------------------------------------------------------------------------
// pathParm
// ------------------------------------------------------------------------------------
dcl-proc pathParm;

	dcl-pi pathParm varchar(256);
		pParm pointer value;
	end-pi;

	dcl-s url varchar(4096);
	dcl-s retval varchar(4096);
	dcl-s group int(5);
	dcl-s length  int(5);
	dcl-s start  int(5);
	
	url = getUrl();
	// The first element is the complete match, 
	// next will be the groups - hench the +1 
	group = json_getint(pParm : 'group') + 1; 

	start = pmatch(group).rm_so;
	length =  pmatch(group).rm_eo - start; 
	// Note: C offset is 0 where RPG substring first poiiton is 1; hench start+1
	retval = %subst(url : start + 1: length );

	return retval;

end-proc;
/* -------------------------------------------------------------------- *\ 
   JSON error monitor 
\* -------------------------------------------------------------------- */
dcl-proc FormatError export;

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
dcl-proc successTrue export;

	dcl-pi *n pointer;
	end-pi;                     

	return json_parseString ('{"success": true}');

end-proc;

