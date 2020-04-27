# procREST - Stored procedures as REST services.

Automatic SQL Stored procedures as RESTfull services 

procREST is a simple way to expose Db2 stored procedures as RESTservice on the IBM i. 
In this examples everything is full open, however you might contain the services 
you expose either by access security or by user defined access rules added to this code - Whatever serves you best.

This application is using IceBreak - however you can easy follow the steps below and use the ILEastic and noxDB 
open source project. You will see in the code that it is actually noxDB is doing all the magic.  

Db2 stored procedures on the IBM i can be used if they have:
* Only input parameters
* Return one dynamic result set:
Look in the example belowe.


## 1) Creat environment

On your IBM i: 

```
GO ICEBREAK
ADDICESVR SVRID(PROCREST) TEXT('Stored Procedures as REST services') SVRPORT(7007)                               
STRICESVR SVRID(PROCREST)
```
This will create a directory `/www/procrest`

Now `ssh` or  `call qp2term` into `/www/procrest` and clone this repo into the IFS:

```
git -c http.sslVerify=false clone https://github.com/NielsLiisberg/procREST.git /www/procrest

``` 

Compile the stored procedure router:

```
CRTICEPGM STMF('/www/ProcRest/procRest.rpgle') SVRID(procrest)
````

### Enable procREST in your web config:

Add the procREST in the routing section in you webconfig.xml file in your server root:

```
<routing strict="false">
	<map pattern="^procREST/" pgm="procrest" lib="*LIBL" />
</routing>
```


## 2) Using stored procedures: 

Procedures can be used if they have:

*	Only inputparameters
*	Return one dynamic result set:

Example:

Build a test stored procedure - paste this into ACS:

```
-- Procedure returns a resultset
--------------------------------
CREATE or REPLACE PROCEDURE  procrest.custlist  (
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

comment on procedure procrest.custlist is 'Customer list';
comment on parameter procrest.custlist (custname is 'Search customers by name');

-- Test the procedure works in ACS:

call procrest.custList (custName => 'j');
call procrest.custList ();
``` 



## 3) Into action:

From your browser type: 
```
http://myibmi:7007/procREST
```

It will ask for a schema, so we suply out library procrest:
```
http://myibmi:7007/procREST/procrest
```
This will format the list of current exposed stord procedures in the schema (library) for now 
this is simple HTML however a swagger/openAPI interface is on its way


Here we have the `custlist` service and it takes a paramter `custname` - Nothing is btw case sensitive. So simply run it like lets run it:
```
http://myibmi:8003/procRest/qgpl/custList?custName=John
```
