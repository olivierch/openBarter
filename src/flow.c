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

#include "flowdata.h"

PG_MODULE_MAGIC;

/*
 * Taken from the intarray contrib header
 */
#define ARRPTR(x)  ( (double *) ARR_DATA_PTR(x) )
#define ARRNELEMS(x)  ArrayGetNItems( ARR_NDIM(x), ARR_DIMS(x))

extern int	flow_yyparse();
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
PG_FUNCTION_INFO_V1(flow_status);
PG_FUNCTION_INFO_V1(flow_omega);
PG_FUNCTION_INFO_V1(flow_omegax);
PG_FUNCTION_INFO_V1(flow_provides);
PG_FUNCTION_INFO_V1(flow_dim);
PG_FUNCTION_INFO_V1(flow_get_fim1_fi);
PG_FUNCTION_INFO_V1(flow_to_matrix);
PG_FUNCTION_INFO_V1(flow_cat);


Datum flow_in(PG_FUNCTION_ARGS);
Datum flow_out(PG_FUNCTION_ARGS);
Datum flow_recv(PG_FUNCTION_ARGS);
Datum flow_send(PG_FUNCTION_ARGS);

Datum flow_proj(PG_FUNCTION_ARGS);
Datum flow_status(PG_FUNCTION_ARGS);
Datum flow_omega(PG_FUNCTION_ARGS);
Datum flow_omegax(PG_FUNCTION_ARGS);
Datum flow_provides(PG_FUNCTION_ARGS);
Datum flow_dim(PG_FUNCTION_ARGS);
Datum flow_get_fim1_fi(PG_FUNCTION_ARGS);
Datum flow_to_matrix(PG_FUNCTION_ARGS);
Datum flow_cat(PG_FUNCTION_ARGS);

// for internal use

char *flow_statusBoxToStr (NDFLOW *box);
// memory allocation of NDFLOW
static NDFLOW * Ndbox_init(int dim);
NDFLOW *Ndbox_adjust(NDFLOW *box);

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

	flowc_maximum(result,globales.verify);

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

		// id,nr,qtt_prov,qtt_requ,sid,own,qtt,np and flowr;
		appendStringInfo(&buf, "(%lli, ", s->id);
		appendStringInfo(&buf, "%lli, ", s->nr);
		appendStringInfo(&buf, "%lli, ", s->qtt_prov);
		appendStringInfo(&buf, "%lli, ", s->qtt_requ);
		appendStringInfo(&buf, "%lli, ", s->sid);
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
		flow->x[_i].sid = pq_getmsgint64(buf);
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
		pq_sendint64(&buf,flow->x[_i].sid);
		pq_sendint64(&buf,flow->x[_i].own);
		pq_sendint64(&buf,flow->x[_i].qtt);
		pq_sendint64(&buf,flow->x[_i].np);
		pq_sendint64(&buf,flow->x[_i].flowr);
	}

	PG_RETURN_BYTEA_P(pq_endtypsend(&buf));
}

/*
FUNCTION flow_cat(flow,int64,int64,int64,int64,int64,int64,int64,int64)
RETURNS flow
args:
	(flow,id,nr,qtt_prov,qtt_requ,sid,own,qtt,np)
Adds a bid at the end of the flow.
	The flow must be not NULL
	the bid added does not belong to the flow
	the dimension of the flow after the bid is added is less or equal to FLOW_MAX_DIM
*/
Datum flow_cat(PG_FUNCTION_ARGS)
{
	NDFLOW	*c;
	NDFLOW	*result;
	BID	*bid;
	int 	dim;
	int64	id;
	
	if(PG_ARGISNULL(0) || PG_ARGISNULL(1)|| PG_ARGISNULL(2)|| PG_ARGISNULL(3)|| PG_ARGISNULL(4)|| PG_ARGISNULL(5)|| PG_ARGISNULL(6)|| PG_ARGISNULL(7)|| PG_ARGISNULL(8) )
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				errmsg("flow_cat: with at least one argument NULL")));
	c = PG_GETARG_NDFLOW(0);
	//elog(WARNING,"flow_cat: input %s",flow_ndboxToStr(c,true));

	id = PG_GETARG_INT64(1);		

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
		bid->sid 	= PG_GETARG_INT64(5);
		bid->own 	= PG_GETARG_INT64(6);
		bid->qtt 	= PG_GETARG_INT64(7);
		bid->np 	= PG_GETARG_INT64(8);	
	}
	result = Ndbox_adjust(result);
	//elog(WARNING,"flow_cat: output %s",flow_ndboxToStr(result,true));
	// elog(WARNING,"flow_cat: bid(id=%lli,nr=%lli,np=%lli,sid=%lli) added to flow",bid->id,bid->nr,bid->np,bid->sid);
	flowc_maximum(result,globales.verify);
	PG_FREE_IF_COPY(c, 0);
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
			case 5: _r = box->x[_i].sid;break;
			case 6: _r = box->x[_i].own;break;
			case 7: _r = box->x[_i].qtt;break;
			case 8: _r = box->x[_i].np;break;
			case 9: _r = box->x[_i].flowr;break;
			default: 
				pfree(_datum_out);		
				ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("flow_proj: with arg1 not in [1,9]")));
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

	PG_RETURN_ARRAYTYPE_P(result);
}

/*
CREATE FUNCTION flow_status(flow)
RETURNS text
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;
*/
Datum flow_status(PG_FUNCTION_ARGS)
{
	NDFLOW	*c;
	char 	*_strStatus;
	
	if(PG_ARGISNULL(0))
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				errmsg("flow_status: with flow=NULL")));	
	c = PG_GETARG_NDFLOW(0);
	_strStatus = flow_statusBoxToStr(c);
	PG_RETURN_CSTRING(_strStatus);
}

/*
FUNCTION flow_omega(flow flow) RETURNS float8
returns the product of qtt_prov[i]/qtt_requ[i]
*/
Datum flow_omega(PG_FUNCTION_ARGS)
{
	NDFLOW	*c;
	double 	_omega;

	if(PG_ARGISNULL(0))
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				errmsg("flow_omega: with flow=NULL")));	
	c = PG_GETARG_NDFLOW(0);
	_omega = flowc_getProdOmega(c);
	PG_RETURN_FLOAT8(_omega);
}
/* FUNCTION flow_omega(flow flow,qtt_prov int8,qtt_recu int8) RETURNS float8
return flow_omega(flow) * qtt_prov/qtt_recu
*/
Datum flow_omegax(PG_FUNCTION_ARGS)
{
	NDFLOW	*c;
	int64	qtt_prov;
	int64	qtt_requ;
	double 	_omega;

	if(PG_ARGISNULL(0) || PG_ARGISNULL(1) || PG_ARGISNULL(2))
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				errmsg("flow_omegax: called with at least one argument NULL")));		
	c = PG_GETARG_NDFLOW(0);
	qtt_prov = PG_GETARG_INT64(1);
	qtt_requ = PG_GETARG_INT64(2);
		
	_omega = flowc_getProdOmega(c);
	_omega *= ((double)qtt_prov) / ((double)qtt_requ);
	PG_RETURN_FLOAT8(_omega);
}

Datum flow_provides(PG_FUNCTION_ARGS)
{
	NDFLOW	*c;
	int64 	_np;

	if(PG_ARGISNULL(0))
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				errmsg("flow_provides: called with argument NULL")));		
	c = PG_GETARG_NDFLOW(0);	
	if(c->dim == 0)
		_np = 0;
	else
		_np = c->x[c->dim-1].np;
	PG_RETURN_INT64(_np);
}


Datum flow_dim(PG_FUNCTION_ARGS)
{
	NDFLOW	*c;
	int32 	_dim;
	
	if(PG_ARGISNULL(0))
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				errmsg("flow_dim: called with at least one argument NULL")));		
	c = PG_GETARG_NDFLOW(0);
	
	_dim = ((int32)(c->dim));
	PG_RETURN_INT32(_dim);
}
/* returns ARRAY(x[i-1].flowr,x[i].flowr) */
Datum flow_get_fim1_fi(PG_FUNCTION_ARGS)
{
	NDFLOW	   *box;
	ArrayType	*result;

	int16       typlen;
	bool        typbyval;
	char        typalign;
	int         ndims = 1;
	int         dims[1] = {2};
	int         lbs[2] = {1};

	int 		_dim,_i,_j;
	Datum		_datum_out[2];
	bool		_null_out[2] = {false,false};
	
	if(PG_ARGISNULL(0) || PG_ARGISNULL(1))
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				errmsg("flow_get_fim1_fi: with at least one argument NULL")));		
	box = PG_GETARG_NDFLOW(0);
	_i = PG_GETARG_INT32(1);
	_dim = box->dim;
	
	if(_dim < 2 || _i<0 || _i>=_dim)
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				errmsg("flow_get_fim1_fi: with dim <2 or i out of range")));;

	_j = _i-1;
	if(_j<0) _j = _dim-1;
	_datum_out[0] = Int64GetDatum(box->x[_j].flowr);
	_datum_out[1] = Int64GetDatum(box->x[_i].flowr);

	/* get required info about the INT8 */
	get_typlenbyvalalign(INT8OID, &typlen, &typbyval, &typalign);

	/* now build the array */
	result = construct_md_array(_datum_out, _null_out, ndims, dims, lbs,
		                INT8OID, typlen, typbyval, typalign);

	PG_RETURN_ARRAYTYPE_P(result);
}

Datum flow_to_matrix(PG_FUNCTION_ARGS)
{
#define DIMELTRESULT 9

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
		_null_out[_j+4] = false; _datum_out[_j+4] = Int64GetDatum(box->x[_i].sid);
		_null_out[_j+5] = false; _datum_out[_j+5] = Int64GetDatum(box->x[_i].own);
		_null_out[_j+6] = false; _datum_out[_j+6] = Int64GetDatum(box->x[_i].qtt);
		_null_out[_j+7] = false; _datum_out[_j+7] = Int64GetDatum(box->x[_i].np);
		_null_out[_j+8] = false; _datum_out[_j+8] = Int64GetDatum(box->x[_i].flowr);
	}

	dims[0] = _dim;

	/* get required info about the INT8 */
	get_typlenbyvalalign(INT8OID, &typlen, &typbyval, &typalign);

	/* now build the array */
	result = construct_md_array(_datum_out, _null_out, ndims, dims, lbs,
		                INT8OID, typlen, typbyval, typalign);

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

NDFLOW *Ndbox_adjust(NDFLOW *box) {
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





