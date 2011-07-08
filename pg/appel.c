/*
* testlibpq.c
*
* Test the C version of libpq, the PostgreSQL frontend library.
*/
#include <postgres.h>
#include "openbarter.h"

#include "catalog/pg_type.h"
#include "fmgr.h"
#include "funcapi.h"
#include "executor/spi.h"
#include "getdraft.h"
#include "balance.h"

/* already declared in getdraft.c
#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif
*/
/* test with
 * SELECT * from ob_appel_from_master(3,2.1,3,2);
 */
ob_tGlob openbarter_g;
static int ob_appel_from_master_next(ob_appel_ctx *ctx,HeapTuple *ptuple);
static ob_appel_ctx* ob_appel_from_master_init(TupleDesc tuple_desc,PG_FUNCTION_ARGS);

Datum ob_appel_from_master(PG_FUNCTION_ARGS);
PG_FUNCTION_INFO_V1(ob_appel_from_master);
Datum ob_appel_from_master(PG_FUNCTION_ARGS) { // (FunctionCallInfo fcinfo)

	HeapTuple tuple;
	FuncCallContext *funcctx;
	int ret;
	Datum result;
	
	if (SRF_IS_FIRSTCALL()) {

		MemoryContext oldcontext;
		TupleDesc tupdesc;

		if(SPI_OK_CONNECT != SPI_connect())
			elog(ERROR,"SPI_connect() error");
		// we are in the context of SPI
		funcctx = SRF_FIRSTCALL_INIT();
		oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);
		
		if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
			ereport(ERROR,(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
						errmsg("function returning record called in context "
								"that cannot accept type record")));
		
		funcctx->user_fctx = ob_appel_from_master_init(BlessTupleDesc(tupdesc),fcinfo);

		MemoryContextSwitchTo(oldcontext);
		
		//ob_balance_testtabconnect();

		if(funcctx->user_fctx == NULL)  { // error in ob_getdraft_getcommit_init
			SPI_finish();
			elog(ERROR,"ob_appel_from_master_init() error");
			SRF_RETURN_DONE(funcctx);
		}
	}

	funcctx = SRF_PERCALL_SETUP();
	
	ret = ob_appel_from_master_next(funcctx->user_fctx,&tuple);
	if (ret == 0) {
		result = HeapTupleGetDatum(tuple);
		SRF_RETURN_NEXT(funcctx, result);
	} else {
		if(ret== -1) elog(ERROR,"ob_appel_from_master_next() error");
		SPI_finish();
		SRF_RETURN_DONE(funcctx);

	}
}/***************************************************************************************
iterator ob_appel_from_master_init

	ob_appel_ctx* ctx = NULL;
	HeapTuple	*tuple;
	ctx = ob_appel_from_master_init(tuple,PG_FUNCTION_ARGS)
	while ((ret = int ob_appel_from_master_next(ctx,&tuple) ) == 0) {
		use of tuple;
	}
***************************************************************************************/
static ob_appel_ctx* ob_appel_from_master_init(TupleDesc tuple_desc,PG_FUNCTION_ARGS)
{
	ob_appel_ctx *ctx = &openbarter_g.actx;
	const char *conninfo,*conninfo_default= "dbname=mp user=olivier";

	PGresult *res;	
	char sql[obCMAXBUF];
	
	ctx->tuple_desc = tuple_desc;
	//ctx->end = false;

	conninfo = conninfo_default;

	/* choose among connections of ob_tconnectdesc the best */
	ctx->connDesc = ob_balance_getBestConnect();
	if(ctx->connDesc) {
		//elog(INFO,"ob_balance_getBestConnect returned result");
		conninfo = ctx->connDesc->conninfo;
		ctx->start = GetCurrentTimestamp();
	}
	//elog(INFO,"ici,connDesc=%p",(void*)ctx->connDesc);
	//elog(INFO,"la,connDesc=%p,%s",(void*)ctx->connDesc,ctx->connDesc->conninfo);
	/* Make a connection to the database */
	ctx->conn = PQconnectdb(conninfo);
	if (PQstatus(ctx->conn) != CONNECTION_OK)
	{
		elog(INFO, "Connection to database failed: %s",PQerrorMessage(ctx->conn));
		goto abort;
	}

	res = PQexec(ctx->conn, "BEGIN");
	if (PQresultStatus(res) != PGRES_COMMAND_OK)
	{
		elog(ERROR, "BEGIN command failed: %s", PQerrorMessage(ctx->conn));
		PQclear(res);
		goto abort;
	}
	PQclear(res);
	snprintf(sql,obCMAXBUF,"DECLARE myportal CURSOR FOR SELECT * FROM ob.getdraft_get(%lli,%f,%lli,%lli)",
			PG_GETARG_INT64(0),PG_GETARG_FLOAT8(1),PG_GETARG_INT64(2),PG_GETARG_INT64(3));
			//pivot->stockId,pivot->omega,pivot->nF,pivot->nR);
	res = PQexec(ctx->conn, sql);
	if (PQresultStatus(res) != PGRES_COMMAND_OK)
	{
		elog(INFO, "SQL:[%s] failed: %s,%i",sql, PQerrorMessage(ctx->conn),PQresultStatus(res));
		PQclear(res);
		goto abort;
	}
	PQclear(res);
	//elog(INFO,"la,connDesc=%p,%p,%s",(void*)ctx->connDesc,ctx->connDesc->conninfo,ctx->connDesc->conninfo);
	return ctx;

abort:
	PQfinish(ctx->conn);
	return NULL;
}

static int ob_appel_from_master_next(ctx,ptuple)
	ob_appel_ctx *ctx;
	HeapTuple	*ptuple;
{
	int ret = 0;
	PGresult *res;
	int s,i;
	Datum values[12];
	bool nulls[12];

	if(ctx == NULL) return -1;
	//if(ctx->end) return 1;
	//elog(INFO,"appel,connDesc=%p,%p",(void*)ctx->connDesc,ctx->connDesc->conninfo);
	res = PQexec(ctx->conn, "FETCH NEXT in myportal");
	if (PQresultStatus(res) != PGRES_TUPLES_OK)
	{
		elog(INFO, "FETCH NEXT failed: %s", PQerrorMessage(ctx->conn));
		ret = -1;goto abort;
	}
	if( PQntuples(res) == 0) {
		ret = 1;
		if(ctx->connDesc)
			ob_balance_recordStat(ctx->connDesc,ctx->start);
		goto abort;
	}
	if( (s=PQnfields(res)) != 12) {
		elog(INFO,"12 Columns expected, %i obtained",s);
		ret = -1;goto abort;
	}
	for(i=0;i<12;i++) {
		char *buf;

		if(PQgetisnull(res,0,i)) {
			nulls[i] = true;
			continue;
		}
		nulls[i] = false;

		s = PQfsize(res,i);
		if(s == 8) {
			int64 k;

			buf =  PQgetvalue(res, 0, i);
			sscanf(buf,"%llu",&k);
			values[i] = Int64GetDatum(k);
		} else if(s == 4) {
			int32 k;

			buf =  PQgetvalue(res, 0, i);
			sscanf(buf,"%u",&k);
			values[i] = Int32GetDatum(k);
		} else if(s == 2) {
			int16 k;

			buf =  PQgetvalue(res, 0, i);
			sscanf(buf,"%hu",&k);
			values[i] = Int16GetDatum(k);
		} else {
			elog(INFO,"Size %i of field %i  not allowed",s,i);
			ret = -1;goto abort;
		}
	}
	*ptuple = heap_form_tuple(ctx->tuple_desc, values, nulls);
	//elog(INFO,"la1,connDesc=%p,%s",(void*)ctx->connDesc,ctx->connDesc->conninfo);
	return 0;
abort:
	PQclear(res);
	PQfinish(ctx->conn);
	return ret;
}

