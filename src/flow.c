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
PG_FUNCTION_INFO_V1(flow_catt);
PG_FUNCTION_INFO_V1(flow_init);
PG_FUNCTION_INFO_V1(flow_omegay);
PG_FUNCTION_INFO_V1(flow_replace);
PG_FUNCTION_INFO_V1(flow_iscycle);
PG_FUNCTION_INFO_V1(flow_omegaz);
PG_FUNCTION_INFO_V1(flow_to_commits);
PG_FUNCTION_INFO_V1(flow_uuid);
PG_FUNCTION_INFO_V1(flow_tarr);
PG_FUNCTION_INFO_V1(flow_isloop);
PG_FUNCTION_INFO_V1(flow_maxdimrefused);
PG_FUNCTION_INFO_V1(flow_orderaccepted);

Datum flow_in(PG_FUNCTION_ARGS);
Datum flow_out(PG_FUNCTION_ARGS);
Datum flow_recv(PG_FUNCTION_ARGS);
Datum flow_send(PG_FUNCTION_ARGS);

Datum flow_proj(PG_FUNCTION_ARGS);
Datum flow_refused(PG_FUNCTION_ARGS);
Datum flow_dim(PG_FUNCTION_ARGS);
Datum flow_to_matrix(PG_FUNCTION_ARGS);
Datum flow_catt(PG_FUNCTION_ARGS);
Datum flow_init(PG_FUNCTION_ARGS);
Datum flow_omegay(PG_FUNCTION_ARGS);
Datum flow_replace(PG_FUNCTION_ARGS);
Datum flow_iscycle(PG_FUNCTION_ARGS);
Datum flow_omegaz(PG_FUNCTION_ARGS);
Datum flow_to_commits(PG_FUNCTION_ARGS);
Datum flow_uuid(PG_FUNCTION_ARGS);
Datum flow_tarr(PG_FUNCTION_ARGS);
Datum flow_isloop(PG_FUNCTION_ARGS);
Datum flow_maxdimrefused(PG_FUNCTION_ARGS);
Datum flow_orderaccepted(PG_FUNCTION_ARGS);
static FTCOMMIT *_flowFtCommit(NDFLOW * flow);

// for internal use

char *flow_statusBoxToStr (NDFLOW *box);
// memory allocation of NDFLOW
static NDFLOW * Ndbox_init(int dim);
static NDFLOW *Ndbox_adjust(NDFLOW *box);
static bool  _checkInArrayInt8(ArrayType *a, int64 val);

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
	if(dim >0) {
		appendStringInfo(&buf, "%c,",(flow->isloop)?'f':'t');
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

Datum flow_catt(PG_FUNCTION_ARGS)
{
	NDFLOW	*X;
	NDFLOW	*result;
	BID	*bid;
	int 	dim;
	ArrayType	*Yrefused;
	
	X = PG_GETARG_NDFLOW(0);	

	result = Ndbox_init(FLOW_MAX_DIM);

	dim = X->dim;
	memcpy(result,X,SIZE_NDFLOW(dim));			
	dim += 1;	
	if(dim > FLOW_MAX_DIM)
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("attempt to extend a flow out of range")));	

	result->dim = dim;
	bid = &result->x[dim-1];

	bid->id 	= PG_GETARG_INT64(1);
	bid->nr 	= PG_GETARG_INT64(2);
	bid->qtt_prov 	= PG_GETARG_INT64(3);
	bid->qtt_requ 	= PG_GETARG_INT64(4);
	bid->own 	= PG_GETARG_INT64(5);
	bid->qtt 	= PG_GETARG_INT64(6);
	bid->np 	= PG_GETARG_INT64(7);
	Yrefused 	= PG_GETARG_ARRAYTYPE_P_COPY(8);
	
	result->lastRelRefused = _checkInArrayInt8(Yrefused,result->x[0].id);	
	
	(void) flowc_maximum(result,globales.verify);
	
	PG_FREE_IF_COPY(X, 0);
	PG_FREE_IF_COPY(Yrefused, 8);

	result = Ndbox_adjust(result);
	PG_RETURN_NDFLOW(result);
}
Datum flow_replace(PG_FUNCTION_ARGS) {
	NDFLOW	*X;
	int64	id;
	
	X = PG_GETARG_NDFLOW(0);
	id = PG_GETARG_INT64(1);
	PG_RETURN_BOOL(!flowc_idInBox(X,id));

}

Datum flow_maxdimrefused(PG_FUNCTION_ARGS) {
	ArrayType	*a = PG_GETARG_ARRAYTYPE_P_COPY(0); 
	int32	maxrefused = PG_GETARG_INT32(1);
	bool res;

	if (ARR_NDIM(a) > 1)
		ereport(ERROR,
				(errcode(ERRCODE_ARRAY_SUBSCRIPT_ERROR),
				 errmsg("wrong number of array subscripts"),
				 errdetail("Refused array must be one dimensional.")));
	if(ARR_NDIM(a) == 1)		 
		res = (maxrefused >= (int32) (ARR_DIMS(a)[0]));
	else res = true;
				 	
	PG_FREE_IF_COPY(a, 0);
	PG_RETURN_BOOL(res);	
}

static bool  _checkInArrayInt8(ArrayType *a, int64 val) {
	bool found = false;
	/*
	 * Params checks
	 */
	if(ARR_NDIM(a) == 0)
		return false;
		
	if (ARR_NDIM(a) != 1)
		ereport(ERROR,
				(errcode(ERRCODE_ARRAY_SUBSCRIPT_ERROR),
				 errmsg("wrong number of array subscripts"),
				 errdetail("Refused array must be one dimensional.")));
	
	if (ARR_LBOUND(a)[0] != 1)
		ereport(ERROR,
				(errcode(ERRCODE_ARRAY_SUBSCRIPT_ERROR),
				 errmsg("wrong range of array subscripts"),
				 errdetail("Lower bound of refused array must be one.")));

	if (array_contains_nulls(a))
		ereport(ERROR,
				(errcode(ERRCODE_NULL_VALUE_NOT_ALLOWED),
				 errmsg("refused values cannot be null.")));
	
	if (INT8OID != ARR_ELEMTYPE(a))
		ereport(ERROR,
				(errcode(ERRCODE_DATATYPE_MISMATCH),
				 errmsg("refused values must be int8.")));

	{
		Datum		*datums;
		bool		*nulls;
		int		count,_i;
		int16		typlen;
		bool	typbyval;
		char	typalign;

		get_typlenbyvalalign(INT8OID, &typlen, &typbyval, &typalign);
		deconstruct_array(a,
						  INT8OID,typlen,typbyval,typalign,
						  &datums, &nulls, &count);

		obMRange(_i,count) {

			if (nulls[_i])
				ereport(ERROR,
						(errcode(ERRCODE_NULL_VALUE_NOT_ALLOWED),
						 errmsg("null value not allowed for refused")));
			if(val == DatumGetInt64(datums[_i])) {
				found = true;
				break;
			}
		}
		pfree(datums);pfree(nulls);	
	}
	return found;
}


/* returns true if 0 in int8[]*/
Datum flow_tarr(PG_FUNCTION_ARGS) {
	ArrayType	*a = PG_GETARG_ARRAYTYPE_P_COPY(0); 
	bool res;
	
	res =  _checkInArrayInt8(a,0);
	
	PG_FREE_IF_COPY(a, 0);
	
	PG_RETURN_BOOL(res);
}	
/*
in the UPDATE of bellman-ford, returns true when the flow should be replaced

the UPDATE performs Y.flow <- X.flow + Y.order, and this function returns True
when it should be done
*/
Datum flow_omegaz(PG_FUNCTION_ARGS)
{
	NDFLOW	*X,*Y,*Z;
	BID	order;
	int 	Xdim;
	
	bool	update = false;
	ArrayType	*Xrefused,*Yrefused;
		
	X 	= PG_GETARG_NDFLOW(0);
	Xdim = X->dim;
	
	if(Xdim == 0) { // X.flow cannot be extended
		PG_FREE_IF_COPY(X, 0);
		PG_RETURN_BOOL(false);
	}
	// X->dim !=0
	Y 		= PG_GETARG_NDFLOW(1);
	order.id 	= PG_GETARG_INT64(2);	
	order.nr 	= PG_GETARG_INT64(3);
	
	if(X->x[Xdim-1].np != order.nr) { // no relation X.flow->Y.order
		PG_FREE_IF_COPY(X, 0);
		PG_FREE_IF_COPY(Y, 1);
		PG_RETURN_BOOL(false);
	}
	
	order.qtt_prov	= PG_GETARG_INT64(4);
	order.qtt_requ	= PG_GETARG_INT64(5);
	order.own 	= PG_GETARG_INT64(6);
	order.qtt 	= PG_GETARG_INT64(7);
	order.np 	= PG_GETARG_INT64(8);
	Xrefused 	= PG_GETARG_ARRAYTYPE_P_COPY(9); 
	Yrefused 	= PG_GETARG_ARRAYTYPE_P_COPY(10);  

	if(_checkInArrayInt8(Xrefused,order.id)) {
		// the relation XEND->Y is refused
		//update = false
		goto fin;
	}

	// at this point, the relation is not refused between X.flow and Y.order
	if(flowc_idInBox(X,order.id)) {
		// order.id is already in X 
		// it is an unexpected cycle
		ereport(WARNING,
				(errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION), // 38000
				 errmsg("flow_omegaz(X,id) while id=%lli in X, it is an unexpected cycle:\n%s",
				 order.id,flow_ndboxToStr(X,true))));
		
		goto fin;
	}
			
	if(Y->dim == 0) {
		update = true;
		goto fin;
	}

	// X->dim !=0 and Y->dim != 0
	
	if((Xdim+1) > FLOW_MAX_DIM)
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("flow_omegaz: attempt to extend a flow out of range")));			
	//elog(WARNING,"flow_cat: input %s",flow_ndboxToStr(c,true));	
	
	// Z = X.flow+Y.order			
	Z = Ndbox_init(FLOW_MAX_DIM);			
	memcpy(Z,X,SIZE_NDFLOW(Xdim));
	Z->dim = Xdim+1;
	memcpy(&Z->x[Xdim],&order,sizeof(BID));	
	
	Z->lastRelRefused = _checkInArrayInt8(Yrefused,Z->x[0].id);
	(void) flowc_maximum(Z,globales.verify);
	
	// if a flow isloop, then it's status can be undefined,refused or draft
	//if(Y->status == noloop) {
	//	if(Z->status != noloop) 
	if(!Y->isloop) {
		if(Z->isloop)
	    		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				errmsg("flow_omegaz: Y is !isloop while Z IS isloop")));
				
		if (flowc_getProdOmega(Z) > flowc_getProdOmega(Y)) 
			// for Z the product qtt_prov/qtt_requ is better than for Y
			update = true;
			
	} else if (Y->status == draft) {
		if ((Z->status == draft) && (flowc_getpOmega(Z) > flowc_getpOmega(Y)))
				update = true;
			
	} else {// Y is refused or undefined
		if (Z->status == draft) 
			update = true;
		
	}
	pfree(Z);
	
fin:	
	PG_FREE_IF_COPY(X, 0);
	PG_FREE_IF_COPY(Y, 1);
	PG_FREE_IF_COPY(Xrefused, 9);
	PG_FREE_IF_COPY(Yrefused, 10);
	
	PG_RETURN_BOOL(update);
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
/*	
	if(PG_ARGISNULL(0) || PG_ARGISNULL(1)|| PG_ARGISNULL(2)|| PG_ARGISNULL(3)|| PG_ARGISNULL(4)|| PG_ARGISNULL(5)|| PG_ARGISNULL(6))
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				errmsg("flow_init: with at least one argument NULL")));	
*/
	result = Ndbox_init(1);
	
	result->dim = 1;
	result->isloop = false;

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
called when Y.flow and X.flow are not NULL
when it returns true: Y.flow <- X.flow+Y.order

if(Y.status == noloop or flowc_refused(Y)==-1)
if(Y.flow is draft or noloop)
	return flow_omega(Y.flow) < flow_omega(X.flow) * qtt_prov/qtt_requ
else (no solution found or is refused)
	return true

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
				errmsg("flow_omegay: called with one argument NULL")));
				
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
/* flow_refused returns c->iworst
*/
Datum flow_refused(PG_FUNCTION_ARGS) {
	NDFLOW	*c;
	int	_i;
	
	if(PG_ARGISNULL(0))
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				errmsg("flow_refused: called with argument NULL")));		
	c = PG_GETARG_NDFLOW(0);
	
	_i = c->iworst; // defined by flowc_refused() when the flow is built
	if(!((c->status == refused) || (c->status == draft) || (c->status == undefined))) 
		ereport(WARNING,
				(errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION), // 38000
				 errmsg("flow_refused(box) called while box->status not in (undefined,draft,refused)\n%s",
				 flow_ndboxToStr(c,true))));	
	PG_FREE_IF_COPY(c,0);
	PG_RETURN_INT32(_i);
}

Datum flow_isloop(PG_FUNCTION_ARGS) {
	NDFLOW	*c;
	bool 	res;
			
	c = PG_GETARG_NDFLOW(0);
	
	res = c->isloop; 
		
	PG_FREE_IF_COPY(c,0);
	PG_RETURN_BOOL(res);
}

Datum flow_orderaccepted(PG_FUNCTION_ARGS) {
	HeapTupleHeader t = PG_GETARG_HEAPTUPLEHEADER(0);
	int32 max_refused = PG_GETARG_INT32(1);
	Datum	d_refused,d_qtt;
	ArrayType	*refused;
	int64	qtt;
	bool	isnull;
	bool 	res;

	d_qtt = GetAttributeByName(t, "qtt", &isnull);	
	if (isnull)
		ereport(ERROR,
				(errcode(ERRCODE_ARRAY_SUBSCRIPT_ERROR),
				 errmsg("qtt should not be null"),
				 errdetail("qtt should not be null.")));
	qtt = DatumGetInt64(d_qtt);
	elog(WARNING,"flow_orderaccepted: qtt=%lli",qtt);
	if(qtt <= 0)
		PG_RETURN_BOOL(false);
	
	d_refused = GetAttributeByName(t, "refused", &isnull);	
	if (isnull)
		ereport(ERROR,
				(errcode(ERRCODE_ARRAY_SUBSCRIPT_ERROR),
				 errmsg("qtt should not be null"),
				 errdetail("qtt should not be null.")));
				 
	refused = DatumGetArrayTypeP(d_refused);

	if (ARR_NDIM(refused) > 1)
		ereport(ERROR,
				(errcode(ERRCODE_ARRAY_SUBSCRIPT_ERROR),
				 errmsg("wrong number of array subscripts"),
				 errdetail("Refused array must be one dimensional.")));

	if(ARR_NDIM(refused) == 1) {	
		elog(WARNING,"flow_orderaccepted: dim=%i",ARR_DIMS(refused)[0]);	 
		res = (max_refused >= (int32) (ARR_DIMS(refused)[0]));
	} else res = true;			

	PG_RETURN_BOOL(res);
} 
/*
Datum flow_lastid(PG_FUNCTION_ARGS)
{
	NDFLOW	*c;
	int32 	_dim;
	int64	_id;
		
	if(PG_ARGISNULL(0))
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				errmsg("flow_dim: called with argument NULL")));		
	c = PG_GETARG_NDFLOW(0);
	
	_dim = ((int32)(c->dim));
	if(_dim) {
		_id = c->x[_dim-1].id;
	} else _id = -1;
	
	PG_FREE_IF_COPY(c,0);
	PG_RETURN_INT64(_id);
}
*/

Datum flow_dim(PG_FUNCTION_ARGS)
{
	NDFLOW	*c;
	int32 	_dim;
		
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
	case draft: return "draft";
	case refused: return "refused";
	case undefined: return "undefined";
	
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








