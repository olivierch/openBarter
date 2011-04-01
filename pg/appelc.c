/*
* testlibpq.c
*
* Test the C version of libpq, the PostgreSQL frontend library.
*/
#include <postgres.h>

/*
 * appelc.c
 *
 *  Created on: 20 déc. 2010
 *      Author: olivier
 */
#include "openbarter.h"
#include "catalog/pg_type.h"
#include "fmgr.h"
#include "funcapi.h"
#include "executor/spi.h"
#include "iternoeud.h"
#include "getdraft.h"
#include "dbe.h"
#include "flux.h"
#include "chemin.h"
#include "iternoeud.h"



#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

ob_tGlob openbarter_g;

void ob_getdraft_init(void);
Datum ob_appel_from_master(PG_FUNCTION_ARGS);

/*
* testlibpq.c
*
* Test the C version of libpq, the PostgreSQL frontend library.
*/

static int ob_exit_nicely(PGconn *conn)
{
	PQfinish(conn);
	elog(ERROR, "Exit Nicely");
	return 1;
}
int test_connection() {
	const char *conninfo;
	PGconn *conn;
	PGresult *res;
	int nFields;
	int i,j;
	
	/*
	* If the user supplies a parameter on the command line, use it as the
	* conninfo string; otherwise default to setting dbname=postgres and using
	* environment variables or defaults for all other connection parameters.
	*/
	conninfo = "dbname = postgres user=olivier";
	/* Make a connection to the database */
	conn = PQconnectdb(conninfo);
	/* Check to see that the backend connection was successfully made */
	if (PQstatus(conn) != CONNECTION_OK)
	{
		elog(ERROR, "Connection to database failed: %s",
		PQerrorMessage(conn));
		return ob_exit_nicely(conn);
	}
	/*
	* Our test case here involves using a cursor, for which we must be inside
	* a transaction block. We could do the whole thing with a single
	* PQexec() of "select * from pg_database", but that’s too trivial to make
	* a good example.
	*/
	/* Start a transaction block */
	res = PQexec(conn, "BEGIN");
	if (PQresultStatus(res) != PGRES_COMMAND_OK)
	{
		elog(ERROR, "BEGIN command failed: %s", PQerrorMessage(conn));
		PQclear(res);
		return ob_exit_nicely(conn);
	}
	/*
	* Should PQclear PGresult whenever it is no longer needed to avoid memory
	* leaks
	*/
	PQclear(res);
	/*
	* Fetch rows from pg_database, the system catalog of databases
	*/
	res = PQexec(conn, "DECLARE myportal CURSOR FOR select * from pg_database");
	if (PQresultStatus(res) != PGRES_COMMAND_OK)
	{
		elog(ERROR, "DECLARE CURSOR failed: %s", PQerrorMessage(conn));
		PQclear(res);
		return ob_exit_nicely(conn);
	}
	PQclear(res);
	res = PQexec(conn, "FETCH ALL in myportal");
	if (PQresultStatus(res) != PGRES_TUPLES_OK)
	{
		elog(ERROR, "FETCH ALL failed: %s", PQerrorMessage(conn));
		PQclear(res);
		return ob_exit_nicely(conn);
	}
	/* first, print out the attribute names */
	nFields = PQnfields(res);
	for (i = 0; i < nFields; i++)
		elog(INFO, "%-15s", PQfname(res, i));
		elog(INFO,"\n\n");
	/* next, print out the rows */
	for (i = 0; i < PQntuples(res); i++)
	{
		for (j = 0; j < nFields; j++)
			elog(INFO,"%-15s", PQgetvalue(res, i, j));
	}
	PQclear(res);
	/* close the portal ... we don’t bother to check for errors ... */
	res = PQexec(conn, "CLOSE myportal");
	PQclear(res);
	/* end the transaction */
	res = PQexec(conn, "END");
	PQclear(res);
	/* close the connection to the database and cleanup */
	PQfinish(conn);
	return 0;
}

static int ob_appel_from_master_next(ob_getdraft_ctx *ctx,HeapTuple *ptuple);
static ob_getdraft_ctx* ob_appel_from_master_init(TupleDesc tuple_desc,PG_FUNCTION_ARGS);

PG_FUNCTION_INFO_V1(ob_appel_from_master);
Datum ob_appel_from_master(PG_FUNCTION_ARGS) { // FunctionCallInfo fcinfo
	HeapTuple tuple;
	FuncCallContext *funcctx;
	int ret,ret1;
	Datum result;
	
	if (SRF_IS_FIRSTCALL()) {

		MemoryContext oldcontext;
		TupleDesc tupdesc;

		if(SPI_OK_CONNECT != SPI_connect())
			elog(ERROR,"SPI_connect() error");

		funcctx = SRF_FIRSTCALL_INIT();
		oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);
		
		if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
			ereport(ERROR,(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
						errmsg("function returning record called in context "
								"that cannot accept type record")));
		
		funcctx->user_fctx = ob_appel_from_master_init(BlessTupleDesc(tupdesc),fcinfo);

		MemoryContextSwitchTo(oldcontext);
		
		if(funcctx->user_fctx == NULL)  { // error in ob_appel_from_master_init
			SPI_finish();
			SRF_RETURN_DONE(funcctx);
		}
	}
	funcctx = SRF_PERCALL_SETUP();
	
	ret = ob_appel_from_master_next(funcctx->user_fctx,&tuple);
	if (ret == 0) {
		result = HeapTupleGetDatum(tuple);
		SRF_RETURN_NEXT(funcctx, result);
	} else {
		SPI_finish();
		SRF_RETURN_DONE(funcctx);

	}
}/***************************************************************************************
iterator ob_appel_from_master_init

	ob_getdraft_ctx* ctx = NULL;
	HeapTuple	*tuple;
	ctx = ob_appel_from_master_init(tuple,PG_FUNCTION_ARGS)
	while ((ret = int ob_appel_from_master_next(ctx,&tuple) ) == 0) {
		use of tuple;
	}
***************************************************************************************/
static ob_getdraft_ctx* _ob_exit_nicely(PGconn *conn)
{
	PQfinish(conn);
	elog(ERROR, "Exit Nicely");
	return NULL;
}
static ob_getdraft_ctx* ob_getdraft_getcommit_init(TupleDesc tuple_desc,PG_FUNCTION_ARGS)
{
	ob_getdraft_ctx *ctx = &openbarter_g.ctx;
	const char *conninfo= "dbname = postgres user=olivier";
	PGconn *conn;
	PGresult *res;	
	ob_tNoeud	*pivot;
	int ret;
	char sql[obCMAXBUF];
	
	ctx->tuple_desc = tuple_desc;
	ctx->end = false;
	pivot = &ctx->pivot;

	pivot->stockId 	= PG_GETARG_INT64(0);
	pivot->omega	= PG_GETARG_FLOAT8(1);
	pivot->nF 		= PG_GETARG_INT64(2);
	pivot->nR 		= PG_GETARG_INT64(3);
	
	/* Make a connection to the database */
	ctx->conn = PQconnectdb(conninfo);
	/* Check to see that the backend connection was successfully made */
	if (PQstatus(ctx->conn) != CONNECTION_OK)
	{
		elog(ERROR, "Connection to database failed: %s",PQerrorMessage(ctx->conn));
		return _ob_exit_nicely(ctx->conn);
	}

	/* Start a transaction block */
	res = PQexec(ctx->conn, "BEGIN");
	if (PQresultStatus(res) != PGRES_COMMAND_OK)
	{
		elog(ERROR, "BEGIN command failed: %s", PQerrorMessage(ctx->conn));
		PQclear(res);
		return _ob_exit_nicely(ctx->conn);
	}
	PQclear(res);
	snprinft(sql,obCMAXBUF,"SELECT ob_fgetdraft_get(%lli,%f,%lli,%lli)",pivot->stocId,pivot->omega,pivot->nF,pivot->nR);
	res = PQexec(ctx->conn, sql);
	if (PQresultStatus(res) != PGRES_COMMAND_OK)
	{
		elog(ERROR, "%s failed: %s",sql, PQerrorMessage(ctx->conn));
		PQclear(res);
		return _ob_exit_nicely(ctx->conn);
	}
	PQclear(res);	
	return ctx;
}
