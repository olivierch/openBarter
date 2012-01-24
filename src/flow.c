/******************************************************************************
  This file contains routines that can be bound to a Postgres backend and
  called by the backend in the process of processing queries.  The calling
  format for these routines is dictated by Postgres architecture.
******************************************************************************/

#include "postgres.h"

#include <float.h>
#include <math.h>

#include "access/gist.h"
#include "access/skey.h"
#include "lib/stringinfo.h"
#include "libpq/pqformat.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h"
#include "catalog/pg_type.h"
#include "funcapi.h"
#include "uuid.h"

#include "flowdata.h"

PG_MODULE_MAGIC;

/*
 * Taken from the intarray contrib header
 */
#define ARRPTR(x)  ( (double *) ARR_DATA_PTR(x) )
#define ARRNELEMS(x)  ArrayGetNItems( ARR_NDIM(x), ARR_DIMS(x))

extern int  flow_yyparse();
extern void flow_yyerror(const char *message);
extern void flow_scanner_init(const char *str);
extern void flow_scanner_finish(void);

ob_tGlobales globales;

/*
** Input/Output routines
*/
PG_FUNCTION_INFO_V1(flow_in);
PG_FUNCTION_INFO_V1(flow_out);
PG_FUNCTION_INFO_V1(flow_recv);
PG_FUNCTION_INFO_V1(flow_send);

PG_FUNCTION_INFO_V1(flow_proj);
PG_FUNCTION_INFO_V1(flow_refused);
PG_FUNCTION_INFO_V1(flow_dim);
PG_FUNCTION_INFO_V1(flow_to_matrix);
PG_FUNCTION_INFO_V1(flow_cat);
PG_FUNCTION_INFO_V1(flow_init);
PG_FUNCTION_INFO_V1(flow_omegay);
PG_FUNCTION_INFO_V1(flow_to_commits);
PG_FUNCTION_INFO_V1(flow_uuid);

Datum flow_in(PG_FUNCTION_ARGS);
Datum flow_out(PG_FUNCTION_ARGS);
Datum flow_recv(PG_FUNCTION_ARGS);
Datum flow_send(PG_FUNCTION_ARGS);

Datum flow_proj(PG_FUNCTION_ARGS);
Datum flow_refused(PG_FUNCTION_ARGS);
Datum flow_dim(PG_FUNCTION_ARGS);
Datum flow_to_matrix(PG_FUNCTION_ARGS);
Datum flow_cat(PG_FUNCTION_ARGS);
Datum flow_init(PG_FUNCTION_ARGS);
Datum flow_omegay(PG_FUNCTION_ARGS);
Datum flow_to_commits(PG_FUNCTION_ARGS);
Datum flow_uuid(PG_FUNCTION_ARGS);

static FTCOMMIT *_flowFtCommit(NDFLOW * flow);

// for internal use

char *flow_statusBoxToStr (NDFLOW *box);
// memory allocation of NDFLOW
static NDFLOW * Ndbox_init(int dim);
static NDFLOW *Ndbox_adjust(NDFLOW *box);

// init
void		_PG_init(void);
void		_PG_fini(void);


void		_PG_init(void) {
	globales.verify = true;	
	return;
}
void		_PG_fini(void) {
	return;
}


/*****************************************************************
 * Input/Output functions
 *****************************************************************/

/* flow = [bid1,bid2,....] 
where bid = int8[9] = (id,nr,qtt_prov,qtt_requ,sid,own,qtt,np) */
Datum
flow_in(PG_FUNCTION_ARGS)
{
	char	   *str = PG_GETARG_CSTRING(0);

	NDFLOW 	*result;
	
	result = Ndbox_init(FLOW_MAX_DIM);

	flow_scanner_init(str);

	if (flow_yyparse(result) != 0)
		flow_yyerror("bogus input for a flow");

	flow_scanner_finish();
	result = Ndbox_adjust(result);

	(void) flowc_maximum(result,globales.verify);

	PG_RETURN_NDFLOW(result);
}
/* provides a string representation of the flow 
When internal is set, it gives complete representation of the flow,
adding status and flowr */
char *flow_ndboxToStr(NDFLOW *flow,bool internal) {
	StringInfoData 	buf;
	int	dim = flow->dim;
	int	i;

	initStringInfo(&buf);

	if(internal) {
		appendStringInfo(&buf, "FLOW %s ",flow_statusBoxToStr(flow));
	}
	appendStringInfoChar(&buf, '[');
	for (i = 0; i < dim; i++)
	{	
		BID *s = &flow->x[i];
		
		if(i != 0) appendStringInfoChar(&buf, ',');

		// id,nr,qtt_prov,qtt_requ,own,qtt,np and flowr;
		appendStringInfo(&buf, "(%lli, ", s->id);
		appendStringInfo(&buf, "%lli, ", s->nr);
		appendStringInfo(&buf, "%lli, ", s->qtt_prov);
		appendStringInfo(&buf, "%lli, ", s->qtt_requ);
		//appendStringInfo(&buf, "%lli, ", s->sid);
		appendStringInfo(&buf, "%lli, ", s->own);
		appendStringInfo(&buf, "%lli, ", s->qtt);
		
		if(internal)
			appendStringInfo(&buf, "%lli:%lli)",s->np, s->flowr);
		else 
			appendStringInfo(&buf, "%lli)", s->np);
	}
	appendStringInfoChar(&buf, ']');
	if(internal)
		appendStringInfoChar(&buf, '\n');
	
	return buf.data;
}

Datum flow_out(PG_FUNCTION_ARGS)
{
	NDFLOW	*_flow;
	char 	*_res;
	
	if(PG_ARGISNULL(0) )
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				errmsg("flow_out: with flow=NULL")));
	_flow = PG_GETARG_NDFLOW(0);					
	_res = flow_ndboxToStr(_flow,false);

	PG_FREE_IF_COPY(_flow, 0);
	PG_RETURN_CSTRING(_res);
}

Datum flow_recv(PG_FUNCTION_ARGS)
{
	StringInfo	buf = (StringInfo) PG_GETARG_POINTER(0);
	NDFLOW	  	 *flow;
	int 		_i;

	flow = Ndbox_init(FLOW_MAX_DIM);
	flow->dim = (int) pq_getmsgint(buf,4);
	
	obMRange(_i,flow->dim) {
		flow->x[_i].id = pq_getmsgint64(buf);
		flow->x[_i].nr = pq_getmsgint64(buf);
		flow->x[_i].qtt_prov = pq_getmsgint64(buf);
		flow->x[_i].qtt_requ = pq_getmsgint64(buf);
		//flow->x[_i].sid = pq_getmsgint64(buf);
		flow->x[_i].own = pq_getmsgint64(buf);
		flow->x[_i].qtt = pq_getmsgint64(buf);
		flow->x[_i].np = pq_getmsgint64(buf);
		flow->x[_i].flowr = pq_getmsgint64(buf);
	}
	
	PG_RETURN_POINTER(flow);
}

Datum
flow_send(PG_FUNCTION_ARGS)
{
	NDFLOW *flow = PG_GETARG_NDFLOW(0);
	StringInfoData buf;
	int _i;

	pq_begintypsend(&buf);
	
	pq_sendint(&buf,flow->dim,4);

	obMRange(_i,flow->dim) {
		pq_sendint64(&buf,flow->x[_i].id);
		pq_sendint64(&buf,flow->x[_i].nr);
		pq_sendint64(&buf,flow->x[_i].qtt_prov);
		pq_sendint64(&buf,flow->x[_i].qtt_requ);
		//pq_sendint64(&buf,flow->x[_i].sid);
		pq_sendint64(&buf,flow->x[_i].own);
		pq_sendint64(&buf,flow->x[_i].qtt);
		pq_sendint64(&buf,flow->x[_i].np);
		pq_sendint64(&buf,flow->x[_i].flowr);
	}
	PG_FREE_IF_COPY(flow, 0);
	PG_RETURN_BYTEA_P(pq_endtypsend(&buf));
}

/*
FUNCTION flow_cat(flow,flow,int64,int64,int64,int64,int64,int64,int64,int64)
RETURNS flow
args:
	(X.flow,id,nr,qtt_prov,qtt_requ,sid,own,qtt,np)
Adds a bid at the end of the flow.
	All arguments must be not NULL execept X.flow
	the bid added does not belong to the flow
	the dimension of the flow after the bid is added is less or equal to FLOW_MAX_DIM
	
if(X.flow is NULL) 
	returns [bid]	
else 
	returns X.flow+bid
	0
	1	0
	2	1
	3	2
	4	3
	5
	6
	7
	8
*/
Datum flow_cat(PG_FUNCTION_ARGS)
{
	NDFLOW	*c;
	NDFLOW	*result;
	BID	*bid;
	int 	dim;
	int64	id;
	
	if( PG_ARGISNULL(0) || PG_ARGISNULL(1)|| PG_ARGISNULL(2)|| PG_ARGISNULL(3)|| PG_ARGISNULL(4)|| PG_ARGISNULL(5)|| PG_ARGISNULL(6)|| PG_ARGISNULL(7))
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				errmsg("flow_cat: with at least one argument NULL")));
	
	id = PG_GETARG_INT64(1);
	
	c = PG_GETARG_NDFLOW(0);
	//elog(WARNING,"flow_cat: input %s",flow_ndboxToStr(c,true));		

	result = Ndbox_init(FLOW_MAX_DIM);
	if(flowc_idInBox(c,id)) {
		// a cycle is found in the graph - the flow returned is empty 
		ereport(WARNING,
				(errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION), // 38000
				 errmsg("flow_cat(box,id) while box contains id=%lli\n%s",
				 id,flow_ndboxToStr(c,true))));
		result->dim = 0;
	} else {
			
		dim = c->dim+1;	
		if(dim > FLOW_MAX_DIM)
	    		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				errmsg("attempt to extend a flow out of range")));	
		memcpy(result,c,SIZE_NDFLOW(dim-1));
	
		result->dim = dim;

		bid = &result->x[dim-1];

		bid->id 	= id;
		bid->nr 	= PG_GETARG_INT64(2);
		bid->qtt_prov 	= PG_GETARG_INT64(3);
		bid->qtt_requ 	= PG_GETARG_INT64(4);
		//bid->sid 	= PG_GETARG_INT64(6);
		bid->own 	= PG_GETARG_INT64(5);
		bid->qtt 	= PG_GETARG_INT64(6);
		bid->np 	= PG_GETARG_INT64(7);	

		//result = Ndbox_adjust(result);
		
		(void) flowc_maximum(result,globales.verify);
		
		/*
		if(!flowc_maximum(result,globales.verify)) {
			// no solution found, Y returned
			Y = PG_GETARG_NDFLOW(0);
			memcpy(result,Y,SIZE_NDFLOW(Y->dim));
			PG_FREE_IF_COPY(Y, 0);
		}*/
	}
	
	PG_FREE_IF_COPY(c, 0);

	result = Ndbox_adjust(result);
	PG_RETURN_NDFLOW(result);
}
/*
FUNCTION flow_init(int64,int64,int64,int64,int64,int64,int64,int64)
RETURNS flow
args:
	(,id,nr,qtt_prov,qtt_requ,sid,own,qtt,np)
creates a flow with a single bid.
*/
Datum flow_init(PG_FUNCTION_ARGS)
{
	NDFLOW	*result;
	BID	*bid;
	
	if(PG_ARGISNULL(0) || PG_ARGISNULL(1)|| PG_ARGISNULL(2)|| PG_ARGISNULL(3)|| PG_ARGISNULL(4)|| PG_ARGISNULL(5)|| PG_ARGISNULL(6))
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				errmsg("flow_init: with at least one argument NULL")));	

	result = Ndbox_init(1);
	
	result->dim = 1;

	bid = &result->x[0];

	bid->id 	= PG_GETARG_INT64(0);
	bid->nr 	= PG_GETARG_INT64(1);
	bid->qtt_prov 	= PG_GETARG_INT64(2);
	bid->qtt_requ 	= PG_GETARG_INT64(3);
	//bid->sid 	= PG_GETARG_INT64(4);
	bid->own 	= PG_GETARG_INT64(4);
	bid->qtt 	= PG_GETARG_INT64(5);
	bid->np 	= PG_GETARG_INT64(6);	

	result = Ndbox_adjust(result);
	
	flowc_maximum(result,globales.verify);
	PG_RETURN_NDFLOW(result);
}


/*
FUNCTION flow_proj(flow,int arg1) RETURNS int8[]
returns an array of box->dim elements int64
1 -> id, 2-> nr, ... 9->flowr
*/

Datum
flow_proj(PG_FUNCTION_ARGS)
{
	NDFLOW	*box;
	int32	arg1;

	int 		_dim,_i;
	Datum		*_datum_out;
	
	ArrayType  *result;
	bool        isnull[1];
	int16       typlen;
	bool        typbyval;
	char        typalign;
	int         ndims;
	int         dims[1];
	int         lbs[1];
	
	
	if(PG_ARGISNULL(0) || PG_ARGISNULL(1))
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				errmsg("flow_proj: with flow=NULL or arg1=NULL")));
	box = PG_GETARG_NDFLOW(0);
	arg1 = PG_GETARG_INT32(1);
	_dim = box->dim;
	
	if(_dim == 0) {
		result = construct_empty_array(INT8OID);
		PG_RETURN_ARRAYTYPE_P(result);
	}
	
	_datum_out = palloc(sizeof(Datum) * _dim);
	//id,nr,qtt_prov,qtt_requ,sid,own,qtt,np
	obMRange(_i,_dim) {
		int64 _r =0;
		
		switch(arg1) {		
			case 1: _r = box->x[_i].id;break;
			case 2: _r = box->x[_i].nr;break;
			case 3: _r = box->x[_i].qtt_prov;break;
			case 4: _r = box->x[_i].qtt_requ;break;
			//case 5: _r = box->x[_i].sid;break;
			case 5: _r = box->x[_i].own;break;
			case 6: _r = box->x[_i].qtt;break;
			case 7: _r = box->x[_i].np;break;
			case 8: _r = box->x[_i].flowr;break;
			default: 
				pfree(_datum_out);		
				ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("flow_proj: with arg1 not in [1,8]")));
		}

		_datum_out[_i] = Int64GetDatum(_r);
		isnull[_i] = false;
	}

	ndims = 1;
	dims[0] = _dim;
	lbs[0] = 1;

	/* get required info about the INT8 */
	get_typlenbyvalalign(INT8OID, &typlen, &typbyval, &typalign);

	/* now build the array */
	result = construct_md_array(_datum_out, isnull, ndims, dims, lbs,
		                INT8OID, typlen, typbyval, typalign);
	PG_FREE_IF_COPY(box,0);
	PG_RETURN_ARRAYTYPE_P(result);
}

/* FUNCTION flow_omegay(Y.flow flow,X.flow flow,qtt_prov int8,qtt_requ int8) RETURNS bool
return flow_omega(Y.flow) < flow_omega(X.flow) * qtt_prov/qtt_requ
	if Y.flow is NULL returns true
	if X.flow is NULL returns false
*/
Datum flow_omegay(PG_FUNCTION_ARGS)
{
	NDFLOW	*X,*Y;
	int64	qtt_prov;
	int64	qtt_requ;
	double 	_omegaX,_omegaY;

	if( PG_ARGISNULL(0) ||PG_ARGISNULL(1) ||PG_ARGISNULL(2) || PG_ARGISNULL(3))
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				errmsg("flow_omegax: called with one argument NULL")));
				
	Y = PG_GETARG_NDFLOW(0);
	X = PG_GETARG_NDFLOW(1);	
	qtt_prov = PG_GETARG_INT64(2);
	qtt_requ = PG_GETARG_INT64(3);
		
	_omegaX = flowc_getProdOmega(X) * ((double)qtt_prov) / ((double)qtt_requ);
	_omegaY = flowc_getProdOmega(Y);

	PG_FREE_IF_COPY(Y, 0);
	PG_FREE_IF_COPY(X, 1);
	//elog(WARNING,"flow_omegay:  returns ????");
	PG_RETURN_BOOL(_omegaY < _omegaX);
}
/*
Datum flow_testb(PG_FUNCTION_ARGS)
{
	bool	b;
	
	if(PG_ARGISNULL(0)) {
		elog(WARNING,"flow_testb");
		PG_RETURN_BOOL(true);
	}	
	b = PG_GETARG_BOOL(0);
	
	PG_RETURN_BOOL(b);
}
*/
Datum flow_refused(PG_FUNCTION_ARGS) {
	NDFLOW	*c;
	int	_i;
	
	if(PG_ARGISNULL(0))
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				errmsg("flow_refused: called with argument NULL")));		
	c = PG_GETARG_NDFLOW(0);
	
	_i = flowc_refused(c);
	PG_FREE_IF_COPY(c,0);
	PG_RETURN_INT32(_i);
}

Datum flow_dim(PG_FUNCTION_ARGS)
{
	NDFLOW	*c;
	int32 	_dim;
	
	if(PG_ARGISNULL(0))
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				errmsg("flow_dim: called with argument NULL")));		
	c = PG_GETARG_NDFLOW(0);
	
	_dim = ((int32)(c->dim));
	PG_FREE_IF_COPY(c,0);
	PG_RETURN_INT32(_dim);
}

Datum flow_to_matrix(PG_FUNCTION_ARGS)
{
#define DIMELTRESULT 8

	NDFLOW	   *box;
	ArrayType	*result;

	int16       typlen;
	bool        typbyval;
	char        typalign;
	int         ndims = 2;
	int         dims[2] = {0,DIMELTRESULT};
	int         lbs[2] = {1,1};

	int 		_dim,_i;
	Datum		*_datum_out;
	bool		*_null_out;
	
	if(PG_ARGISNULL(0))
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				errmsg("flow_to_matrix: with at least one argument NULL")));		
	box = PG_GETARG_NDFLOW(0);	

	_dim = box->dim;

	/* get the provided element, being careful in case it's NULL */
	/*
	isnull = PG_ARGISNULL(0);
	if (isnull)
		element = (Datum) 0;
	else
		element = PG_GETARG_DATUM(0);
	*/
	if(_dim == 0) {
		result = construct_empty_array(INT8OID);
		PG_RETURN_ARRAYTYPE_P(result);
	}
	
	_datum_out = palloc(sizeof(Datum) * _dim * DIMELTRESULT);
	_null_out =  palloc(sizeof(bool)  * _dim * DIMELTRESULT);
	
	//id,nr,qtt_prov,qtt_requ,sid,own,qtt,np
	obMRange(_i,_dim) {
		int _j = _i * DIMELTRESULT;
		_null_out[_j+0] = false; _datum_out[_j+0] = Int64GetDatum(box->x[_i].id);
		_null_out[_j+1] = false; _datum_out[_j+1] = Int64GetDatum(box->x[_i].nr);
		_null_out[_j+2] = false; _datum_out[_j+2] = Int64GetDatum(box->x[_i].qtt_prov);
		_null_out[_j+3] = false; _datum_out[_j+3] = Int64GetDatum(box->x[_i].qtt_requ);
		//_null_out[_j+4] = false; _datum_out[_j+4] = Int64GetDatum(box->x[_i].sid);
		_null_out[_j+4] = false; _datum_out[_j+4] = Int64GetDatum(box->x[_i].own);
		_null_out[_j+5] = false; _datum_out[_j+5] = Int64GetDatum(box->x[_i].qtt);
		_null_out[_j+6] = false; _datum_out[_j+6] = Int64GetDatum(box->x[_i].np);
		_null_out[_j+7] = false; _datum_out[_j+7] = Int64GetDatum(box->x[_i].flowr);
	}

	dims[0] = _dim;

	/* get required info about the INT8 */
	get_typlenbyvalalign(INT8OID, &typlen, &typbyval, &typalign);

	/* now build the array */
	result = construct_md_array(_datum_out, _null_out, ndims, dims, lbs,
		                INT8OID, typlen, typbyval, typalign);
	PG_FREE_IF_COPY(box,0);
	PG_RETURN_ARRAYTYPE_P(result);
}


/*****************************************************************/
// memory allocation of NDFLOW
/*****************************************************************/
static NDFLOW * Ndbox_init(int dim) {
	NDFLOW 	*box;
	int 	size;

	size = SIZE_NDFLOW(dim);
	box = palloc(size);
	box->dim = 0;
	SET_VARSIZE(box,size);
	return box;
}

static NDFLOW *Ndbox_adjust(NDFLOW *box) {
	int 	size;
	NDFLOW	*newbox;

	size = SIZE_NDFLOW(box->dim);
	newbox = repalloc(box,size);
	SET_VARSIZE(newbox,size);
	return newbox;
}

/*****************************************************************/
char * flow_statusBoxToStr (NDFLOW *box){
	switch(box->status) {
	case empty: return "empty";
	case noloop: return "noloop";
	case loop: return "loop";
	case draft: return "draft";
	case undefined: return "undefined";
	case tobedefined: return "tobedefined";
	
	default: return "unknown status!";
	}
}

/* used by flow_to_commits
*/
static FTCOMMIT *_flowFtCommit(NDFLOW * flow) {
	int i,j,dim = flow->dim;
	FTCOMMIT *ret = palloc(sizeof(FTCOMMIT));

	obMRange (i,dim) {
		if(i==0) j = dim-1;
		else j = i-1;
		ret->c[i].qtt_r = flow->x[j].qtt;
		ret->c[i].nr = flow->x[j].np;
		ret->c[i].qtt_p = flow->x[i].qtt;
		ret->c[i].np = flow->x[i].np;
	}	
	
	return ret;
}
/* flow_to_commits(flow) returns set of (qtt_r int8,nr int8,qtt_p int8,np int8)
for an indice i
	[i].qtt_r	<- commit[i-1].qtt
	[i].nr		<- commit[i-1].np
	[i].qtt_p	<- commit[i].qtt
	[i].np		<- commit[i].np
*/

Datum flow_to_commits(PG_FUNCTION_ARGS) {
	FuncCallContext	*funcctx;
	int	call_cntr;
	int	max_calls;	
	TupleDesc	tupdesc;
	AttInMetadata *attinmeta;
	/* stuff done only on the first call of the function */
	FTCOMMIT *ftc;
	
	if (SRF_IS_FIRSTCALL())
	{
		MemoryContext oldcontext;
		NDFLOW *box;
		/* create a function context for cross-call persistence */
		funcctx = SRF_FIRSTCALL_INIT();
		/* switch to memory context appropriate for multiple function calls */
		oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);
		
		if(PG_ARGISNULL(0))
			ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				errmsg("flow_to_commits: with flow argument NULL")));	
			
		box = PG_GETARG_NDFLOW(0);		
		funcctx->user_fctx = (void *) _flowFtCommit(box);
		
		/* total number of tuples to be returned */
		funcctx->max_calls = (int32) box->dim;
		
		PG_FREE_IF_COPY(box,0);
		
		/* Build a tuple descriptor for our result type */
		if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
			ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				errmsg("flow_to_commits: function returning record called in context "
				"that cannot accept type record")));
		/*
		* generate attribute metadata needed later to produce tuples from raw
		* C strings
		*/
		attinmeta = TupleDescGetAttInMetadata(tupdesc);
		funcctx->attinmeta = attinmeta;
		MemoryContextSwitchTo(oldcontext);
	}
	/* stuff done on every call of the function */
	funcctx = SRF_PERCALL_SETUP();
	call_cntr = funcctx->call_cntr;
	max_calls = funcctx->max_calls;
	attinmeta = funcctx->attinmeta;
	ftc = (FTCOMMIT *) funcctx->user_fctx;
	if (call_cntr < max_calls)
	{
		char 	**values;
		HeapTuple tuple;
		Datum 	result;
		int	_k;
		//char	*zero= "0";

		values = (char **) palloc(5 * sizeof(char *));
		obMRange (_k,5) {
			values[_k] = (char *) palloc(32 * sizeof(char));
		}
		//values[0] = zero;
		snprintf(values[0],32,"%lli",0LL);
		snprintf(values[1],32,"%lli",ftc->c[call_cntr].qtt_r);
		snprintf(values[2],32,"%lli",ftc->c[call_cntr].nr);
		snprintf(values[3],32,"%lli",ftc->c[call_cntr].qtt_p);
		snprintf(values[4],32,"%lli",ftc->c[call_cntr].np);
		

		tuple = BuildTupleFromCStrings(attinmeta, values);
		/* make the tuple into a datum */
		result = HeapTupleGetDatum(tuple);
		/* clean up (this is not really necessary) */
		obMRange (_k,5) pfree(values[_k]);
		pfree(values);
		
		SRF_RETURN_NEXT(funcctx, result);
	} else {
		/* do when there is no more left */
		pfree(ftc);
		SRF_RETURN_DONE(funcctx);
	}
}

Datum flow_uuid(PG_FUNCTION_ARGS)
{
// TODO gcc `uuid-config --cflags` -lm `uuid-config --libs` uuid.c
	
	uuid_t *uuid;
	char *str;
	
	uuid_create(&uuid);
	uuid_make(uuid, UUID_MAKE_V1);
	str = NULL;
	uuid_export(uuid, UUID_FMT_STR, &str, NULL);
	uuid_destroy(uuid);
	PG_RETURN_CSTRING(str);
	
	// PG_RETURN_CSTRING("TO BE DEFINED");
}








