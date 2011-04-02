/*
 * getaccords.c
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
Datum ob_getdraft_get(PG_FUNCTION_ARGS);

/***************************************************************************************
usage:
	SELECT ob_getdraft_get(1,1.,2,3);
returns the list of drafts.

PG_FUNCTION_ARGS = (stockId,omega,nF,nR)
sql declaration:
	create or replace function ob_getdraft_get(int8,double precision,int8,int8) returns setof ob_tldraft
	as '$libdir/openbarter' language C strict;
***************************************************************************************/

static int ob_getdraft_getcommit_next(ob_getdraft_ctx *ctx,HeapTuple *ptuple);
static ob_getdraft_ctx* ob_getdraft_getcommit_init(TupleDesc tuple_desc,PG_FUNCTION_ARGS);
static int ob_getdraft_get_commit(ob_getdraft_ctx *ctx);

void ob_getdraft_init(void) {
	ob_getdraft_ctx *ctx = &openbarter_g.ctx;

	openbarter_g.pathEnv[0] = 0;
	memset(ctx,0,sizeof(ob_getdraft_ctx));
}

/*

drop table ob_tldraft2 cascade;
create table ob_tldraft2 (
	-- draft
    id int8, 		--[0] get_draft supposes that it is  >0 : 1,2,3 ... changes for each draft
    cix int2, -- between 0..nbnoeud-1	--[1]
    nbsource int2,			--[2]
    nbnoeud int2,			--[3]
    cflags int4, -- draft flags	--[4]
    bid int8, -- loop.rid.Xoid		--[5]
    sid int8, -- loop.rid.Yoid		--[6]
    wid int8, -- loop.rid.version	--[7]
    fluxarrondi bigint,  		--[8]
    flags int4, -- commit flags	--[9]
    ret_algo int4			--[10]
);
create or replace function ob_getdraft_get2(int8,double precision,int8,int8)
returns SETOF ob_tldraft2
	as '$libdir/openbarter','ob_getdraft_get' language C strict;
 */

PG_FUNCTION_INFO_V1(ob_getdraft_get);
Datum ob_getdraft_get(PG_FUNCTION_ARGS) { // FunctionCallInfo fcinfo
	HeapTuple tuple;
	FuncCallContext *funcctx;
	int ret;
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
		
		funcctx->user_fctx = ob_getdraft_getcommit_init(BlessTupleDesc(tupdesc),fcinfo);
		
		MemoryContextSwitchTo(oldcontext);
		
		if(funcctx->user_fctx == NULL)  { // error in ob_getdraft_getcommit_init
			SPI_finish();
			elog(ERROR,"ob_getdraft_get() erreur");
			SRF_RETURN_DONE(funcctx);
		}
	}
	
	funcctx = SRF_PERCALL_SETUP();
	
	ret = ob_getdraft_getcommit_next(funcctx->user_fctx,&tuple);
	if (ret == 0) {
		result = HeapTupleGetDatum(tuple);
		SRF_RETURN_NEXT(funcctx, result);
	} else {
		SPI_finish();
		SRF_RETURN_DONE(funcctx);

	}
}

/***************************************************************************************
iterator ob_getdraft_getcommit

	ob_getdraft_ctx* ctx = NULL;
	HeapTuple	*tuple;
	ctx = ob_getdraft_getcommit_init(tuple,PG_FUNCTION_ARGS)
	while ((ret = int ob_getdraft_getcommit_next(ctx,&tuple) ) == 0) {
		use of tuple;
	}
***************************************************************************************/

static ob_getdraft_ctx* ob_getdraft_getcommit_init(TupleDesc tuple_desc,PG_FUNCTION_ARGS)
{
	ob_getdraft_ctx *ctx;
	ob_tNoeud	*pivot;
	ob_tStock 	stock;
	ob_tPrivateTemp *privt;
	//int _nblayer,i_graph,ret=0,ret_t,_nbSource,_lo;
	int ret;
	
	ctx = &openbarter_g.ctx;
	/*
	ctx = palloc(sizeof(ob_getdraft_ctx));
	if(ctx== NULL) {
		elog(ERROR,"out of memory");
		return NULL;
	}*/
	if(ctx->envt != 0) {
		ob_dbe_closeEnvTemp(ctx->envt);
		ctx->envt = NULL; // Done
	}
	memset(ctx,0,sizeof(ob_getdraft_ctx));
	ctx->i_graph = -1;
	ctx->tuple_desc = tuple_desc;
	ctx->end = false;
	if(ob_dbe_openEnvTemp1(&ctx->envt)) {
		// pfree(ctx);
		elog(INFO,"could not open EnvTemp1");
		return NULL;
	}
	privt = ctx->envt->app_private;
	
	pivot = &ctx->pivot;

	privt->pivot 	= pivot;
	pivot->stockId 	= PG_GETARG_INT64(0);
	pivot->omega	= PG_GETARG_FLOAT8(1);
	pivot->nF 		= PG_GETARG_INT64(2);
	pivot->nR 		= PG_GETARG_INT64(3);
	if(pivot->nF == pivot->nR) {
		elog(INFO,"nF should be different from nR");
		goto err;
	}

	privt->cflags = 0;
	if(pivot->stockId == 0) { 
		privt->cflags |= ob_flux_CLastIgnore;
		privt->deposOffre = false;
	} else  {

		privt->cflags &= ~ob_flux_CLastIgnore;
		privt->deposOffre = true;

		stock.sid = pivot->stockId;
		ret = ob_iternoeud_getStock(&stock);
		if(ret) {
			if(ret == DB_NOTFOUND) {
				elog(INFO,"stockId not found");
			} else
				elog(INFO,"error %i in ob_iternoeud_getStock",ret);
			goto err;
		}
		pivot->own = stock.own;
	}

	//elog(INFO,"pivotx stockId %016llx nF %llx nR %llx omega %f own %llx oid %llx",pivot->stockId,pivot->nF,pivot->nR,pivot->omega,pivot->own,pivot->oid);

	ret = ob_chemin_parcours_arriere(ctx->envt,NULL,&ctx->nblayer,&stock);
	if (ret) {
		elog(INFO,"Error %i in _parcours_arriere",ret);
		goto err;
	}
	//elog(INFO,"parcours_arriere %i layer",ctx->nblayer);
	if (ctx->nblayer < 1) goto err; 
	ctx->i_graph = -1;
	return ctx;
err:
	ob_dbe_closeEnvTemp(ctx->envt);
	ctx->envt = NULL; // Done
	// pfree(ctx);
	return NULL;
}
/***************************************************************************************/
static int ob_getdraft_getcommit_next(ctx,ptuple) 
	ob_getdraft_ctx *ctx;
	HeapTuple	*ptuple;
{
	int ret = 0;
	
	if(ctx == NULL) return -1;
	
	// the graph is empty,normal termination
	if (ctx->nblayer == 0) {
		ret = 1;
		goto endloop; 
	}
	
	if(ctx->end) return 1;

	ret = ob_getdraft_get_commit(ctx);
	//elog(INFO,"ob_getdraft_get_commit _graph=%i i_commit=%i",ctx->i_graph,ctx->i_commit);
	if (ret == 0 ) {
		ob_tNo *node  = &ctx->accord.chemin.no[ctx->i_commit];
		Datum values[12];
		bool nulls[] = {false,false,false,false,false,false,false,false,false,false,false,false};
		
		values[0] = Int64GetDatum((int64) ctx->i_graph);
		//id int8, 		-- get_draft supposes that it is  >0 : 1,2,3 ... changes for each draft
		values[1] = Int16GetDatum((int16) ctx->i_commit);
			/* cix int2, -- between 0..nbnoeud-1  */
		values[2] = Int16GetDatum((int16) ctx->accord.nbSource);
			/* nbsource int2,  */
		values[3] = Int16GetDatum((int16) ctx->accord.chemin.nbNoeud);
			/* nbnoeud int2,  */
		values[4] = Int32GetDatum((int32) ctx->accord.chemin.cflags);
			/* flags int4, -- draft flags	  */
		if(node->noeud.oid ==0)
			nulls[5] = true;
		else
			values[5] = Int64GetDatum(node->noeud.oid);
			/*  bid int8, -- loop.rid.Xoid	  */
		if(node->noeud.stockId ==0)
			nulls[6] = true;
		else
			values[6] = Int64GetDatum(node->noeud.stockId);
			/*  sid int8, -- loop.rid.Yoid	  */
		if(node->noeud.own ==0)
			nulls[7] = true;
		else
			values[7] = Int64GetDatum(node->noeud.own);
			/*  wid int8, -- loop.rid.version  */
		values[8] = Int64GetDatum(node->fluxArrondi);
		//elog(INFO,"flux %lli",node->fluxArrondi);
			/* fluxarrondi bigint,    */
		values[9] = Int32GetDatum((int32) node->flags);
			/*  cflags int4 -- commit flags	  */
		values[10] = Int32GetDatum((int32) ret);
			/* ret_algo int4			 */
		values[11] = Int64GetDatum(ctx->accord.versionSg);

		//elog(NOTICE,"version %lli",ctx->accord.versionSg);
		*ptuple = heap_form_tuple(ctx->tuple_desc, values, nulls);
		return 0;
	//
	} else if(ret == ob_chemin_CerLoopOnOffer) { // a loop has been found
		Datum values[12];
		bool nulls[] = {false,true,true,true,true,false,false,false,true,true,false,true};
		//elog(INFO,"Xoid=%lli Yoid=%lli",ctx->loop.rid.Xoid,ctx->loop.rid.Yoid);
		ctx->end = true; // will return 1 the next call.
		values[0] = Int64GetDatum(ctx->i_graph);
		values[5] = Int64GetDatum(ctx->loop.rid.Xoid);
		values[6] = Int64GetDatum(ctx->loop.rid.Yoid);
		values[7] = Int64GetDatum(ctx->loop.version);
		values[10] = Int32GetDatum(ret);
		*ptuple = heap_form_tuple(ctx->tuple_desc, values, nulls);
		ret = 0;

	} else if (ret == ob_chemin_CerNoDraft) { // normal termination, no more agreement
		ret = 1;

	} else  { // an error occured
		elog(INFO,"An error %i in ob_chemin_get_draft_next",ret);
		ret = -1;

	}
endloop:
	ob_dbe_closeEnvTemp(ctx->envt);
	ctx->envt = NULL; // Done
	//pfree(ctx);
	return ret;
}
static int ob_getdraft_get_commit(ob_getdraft_ctx *ctx) {
	int ret;

	ctx->i_commit += 1;
	if(ctx->i_graph == -1 || ctx->i_commit >= ctx->accord.chemin.nbNoeud) {
			ctx->i_graph += 1;
			ctx->i_commit = 0;
			ret = ob_chemin_get_draft_next(ctx);
			// elog(INFO,"ob_chemin_get_draft_next returned %i",ret);
	} else {
		ret = 0;
	}
	return ret;
}


