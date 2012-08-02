/******************************************************************************
  This file contains routines that can be bound to a Postgres backend and
  called by the backend in the process of processing queries.  The calling
  format for these routines is dictated by Postgres architecture.
******************************************************************************/

#include "postgres.h"

#include <math.h>

#include "lib/stringinfo.h"
#include "libpq/pqformat.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h" 
#include "catalog/pg_type.h" 
#include "funcapi.h" 

#include "flowdata.h"

PG_MODULE_MAGIC;

extern int  yflow_yyparse(void *resultat);
extern void yflow_yyerror(const char *message);
extern void yflow_scanner_init(const char *str);
extern void yflow_scanner_finish(void);

// ob_tGlobales globales;

PG_FUNCTION_INFO_V1(yflow_in);
PG_FUNCTION_INFO_V1(yflow_out);
PG_FUNCTION_INFO_V1(yflow_dim);
PG_FUNCTION_INFO_V1(yflow_get_yorder);
PG_FUNCTION_INFO_V1(yflow_get_yorder_yflow);
PG_FUNCTION_INFO_V1(yflow_get_yflow_yorder);
PG_FUNCTION_INFO_V1(yflow_follow_yorder_yflow);
PG_FUNCTION_INFO_V1(yflow_follow_yflow_yorder);
PG_FUNCTION_INFO_V1(yflow_show);
PG_FUNCTION_INFO_V1(yflow_eq);
PG_FUNCTION_INFO_V1(yflow_left);
PG_FUNCTION_INFO_V1(yflow_reduce);
PG_FUNCTION_INFO_V1(yflow_last_iomega);
PG_FUNCTION_INFO_V1(yflow_maxg);
PG_FUNCTION_INFO_V1(yflow_ming);
PG_FUNCTION_INFO_V1(yflow_status);
PG_FUNCTION_INFO_V1(yflow_flr_omega);
PG_FUNCTION_INFO_V1(yflow_to_matrix);
PG_FUNCTION_INFO_V1(yflow_qtts);
PG_FUNCTION_INFO_V1(yflow_get_last_order);

Datum yflow_in(PG_FUNCTION_ARGS);
Datum yflow_out(PG_FUNCTION_ARGS);
Datum yflow_dim(PG_FUNCTION_ARGS);
Datum yflow_get_yorder(PG_FUNCTION_ARGS);
Datum yflow_get_yorder_yflow(PG_FUNCTION_ARGS);
Datum yflow_get_yflow_yorder(PG_FUNCTION_ARGS);
Datum yflow_follow_yorder_yflow(PG_FUNCTION_ARGS);
Datum yflow_follow_yflow_yorder(PG_FUNCTION_ARGS);
Datum yflow_show(PG_FUNCTION_ARGS);
Datum yflow_eq(PG_FUNCTION_ARGS);
Datum yflow_left(PG_FUNCTION_ARGS);
Datum yflow_reduce(PG_FUNCTION_ARGS);
Datum yflow_last_iomega(PG_FUNCTION_ARGS);
Datum yflow_maxg(PG_FUNCTION_ARGS);
Datum yflow_ming(PG_FUNCTION_ARGS);
Datum yflow_status(PG_FUNCTION_ARGS);
Datum yflow_flr_omega(PG_FUNCTION_ARGS);
Datum yflow_to_matrix(PG_FUNCTION_ARGS);
Datum yflow_qtts(PG_FUNCTION_ARGS);
Datum yflow_get_last_order(PG_FUNCTION_ARGS);


char *yflow_statusBoxToStr (Tflow *box);
char *yflow_pathToStr(Tflow *yflow);

void		_PG_init(void);
void		_PG_fini(void);

/******************************************************************************
begin and end functions called when flow.so is loaded
******************************************************************************/
void		_PG_init(void) {
	return;
}
void		_PG_fini(void) {
	return;
}

/******************************************************************************
Input/Output functions
******************************************************************************/
/* yflow = [yorder1,yorder2,....] 
where yorder = (id,own,nr,qtt_requ,np,qtt_prov,qtt) */
Datum
yflow_in(PG_FUNCTION_ARGS)
{
	char	   *str = PG_GETARG_CSTRING(0);
	
	Tflow 	*result;
	
	result = flowm_init();

	yflow_scanner_init(str);

	if (yflow_yyparse(&result) != 0)
		yflow_yyerror("bogus input for a yflow");

	yflow_scanner_finish();

	(void) flowc_maximum(result);

	PG_RETURN_TFLOW(result);
}
/******************************************************************************
provides a string representation of yflow 
When internal is set, it gives complete representation of the yflow,
adding status and flowr[.]
******************************************************************************/
char *yflow_ndboxToStr(Tflow *yflow,bool internal) {
	StringInfoData 	buf;
	int	dim = yflow->dim;
	int	i;

	initStringInfo(&buf);

	if(internal) {
		appendStringInfo(&buf, "YFLOW %s ",yflow_statusBoxToStr(yflow));
	}
	appendStringInfoChar(&buf, '[');
	if(dim >0) {
		for (i = 0; i < dim; i++)
		{	
			Torder *s = &yflow->x[i];
		
			if(i != 0) appendStringInfoChar(&buf, ',');

			// id,nr,qtt_prov,qtt_requ,own,qtt,np and yflowr;
			appendStringInfo(&buf, "(%i, ", s->id);
			appendStringInfo(&buf, "%i, ", s->own);
			appendStringInfo(&buf, "%i, ", s->nr);
			appendStringInfo(&buf, "%lli, ", s->qtt_requ);
			appendStringInfo(&buf, "%i, ", s->np);
			appendStringInfo(&buf, "%lli, ", s->qtt_prov);
		
			if(internal)
				appendStringInfo(&buf, "%lli:%lli)",s->qtt, s->flowr);
			else 
				appendStringInfo(&buf, "%lli)", s->qtt);
		}
	}
	appendStringInfoChar(&buf, ']');
	if(internal)
		appendStringInfoChar(&buf, '\n');
	
	return buf.data;
}

/*****************************************************************************/
char *yflow_pathToStr(Tflow *yflow) {
	StringInfoData 	buf;
	int	dim = yflow->dim;
	int	i;

	initStringInfo(&buf);


	appendStringInfo(&buf, "@[");
	if(dim >0) {
		for (i = 0; i < dim; i++)
		{	
			Torder *s = &yflow->x[i];
		
			if(i != 0) appendStringInfoChar(&buf, ',');

			// id,own,nr,qtt_requ,np,qtt_prov,qtt,flow
			appendStringInfo(&buf, "[%i, ", s->id);
			appendStringInfo(&buf, "%i, ", s->own);
			appendStringInfo(&buf, "%i, ", s->nr);
			appendStringInfo(&buf, "%lli, ", s->qtt_requ);
			appendStringInfo(&buf, "%i, ", s->np);
			appendStringInfo(&buf, "%lli, ", s->qtt_prov);
			appendStringInfo(&buf, "%lli,%lli]",s->qtt, s->flowr);
		}
	}
	appendStringInfoChar(&buf, ']');
	
	return buf.data;
}
/******************************************************************************
******************************************************************************/
Datum yflow_out(PG_FUNCTION_ARGS)
{
	Tflow	*_yflow;
	char 	*_res;
	
	_yflow = PG_GETARG_TFLOW(0);					
	_res = yflow_ndboxToStr(_yflow,false);

	PG_RETURN_CSTRING(_res);
}
/******************************************************************************
******************************************************************************/
Datum yflow_dim(PG_FUNCTION_ARGS)
{
	Tflow	*f;
	int32	dim;
	
	f = PG_GETARG_TFLOW(0);
	dim = f->dim;
	
	if((dim < 2) ||(dim > FLOW_MAX_DIM))
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("flow->dim not in [2,%i]",FLOW_MAX_DIM)));
	PG_RETURN_INT32(dim);
}
/******************************************************************************
yflow_get(yorder)
******************************************************************************/
Datum yflow_get_yorder(PG_FUNCTION_ARGS)
{
	Tflow	*result;
	Torder	*o = PG_GETARG_TORDER(0);
	/*
	result = Ndbox_init(1);
	
	result->dim = 1;
	memcpy(&result->x[0],ordi,sizeof(Torder));
	*/
	result = flowm_init();
	result = flowm_extends(o,result,false);
	(void) flowc_maximum(result);
	PG_RETURN_TFLOW(result);
}
/******************************************************************************
yflow_get()
******************************************************************************/
static Tflow* _yflow_get(Torder *o,Tflow *f, bool before) {
	Tflow	*result;
	short 	dim = f->dim,i;
	bool	inflow;
	
	if(dim > (FLOW_MAX_DIM-1))
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("attempt to extend a yflow out of range")));
			
	inflow = false;
	obMRange(i,dim)
		if(f->x[i].id == o->id) {
			inflow = true;
			break;
		}
		
	//result = Ndbox_init(FLOW_MAX_DIM);
	result = flowm_init();
	if(inflow) { // the order already belongs to the flow: flow is unchanged
		//memcpy(result,f,sizeof(Tflow));
		result = flowm_copy(f);
	} else {
		result = flowm_cextends(o,f,before);
		(void) flowc_maximum(result);
	}

	#ifdef GL_WARNING_GET
		elog(WARNING,"_yflow_get %s",yflow_pathToStr(result));
	#endif
	return result;	
	
}
/******************************************************************************
yflow_get(yorder,yflow)
******************************************************************************/
Datum yflow_get_yorder_yflow(PG_FUNCTION_ARGS)
{
	Torder	*o;
	Tflow	*f;
	Tflow	*result;
	
	
	o = PG_GETARG_TORDER(0);
	f = PG_GETARG_TFLOW(1);	
	
	result = _yflow_get(o,f,true);

	PG_RETURN_TFLOW(result);
}
/******************************************************************************
yflow_get(yflow,yorder)
******************************************************************************/
Datum yflow_get_yflow_yorder(PG_FUNCTION_ARGS)
{
	Torder	*o;
	Tflow	*f;
	Tflow	*result;
	
	f = PG_GETARG_TFLOW(0);	
	o = PG_GETARG_TORDER(1);
	
	result = _yflow_get(o,f,false);

	PG_RETURN_TFLOW(result);
}

/******************************************************************************
yflow_follow()
******************************************************************************/
static bool _yflow_follow(int32 maxlen,Torder *o,Tflow *f, bool before) {

	short 	dim = f->dim,i;
	// bool	inflow,cycle;
	
	#ifdef GL_WARNING_FOLLOW
		elog(WARNING,"_yflow_follow %s",yflow_pathToStr(f));
	#endif
	
	if((dim >=maxlen) || (dim >= FLOW_MAX_DIM))
		return false;

	if(o->qtt <=0)
		return false;
		
	// o.id in f->x[.].id	
	obMRange(i,dim)
		if(f->x[i].id == o->id) 
			return false;
	
	if(before) { 
		// not o -> begin(f)
		if (o->np != f->x[0].nr)
			return false;
			
		// unexpected cycle
		obMRange(i,dim-1)
			if(f->x[i].np == o->nr) 
				return false;
				
		// not yet a cycle
		if(f->x[dim-1].np != o->nr)
			return true;
			
		/* o->f form a cycle */
	} else {
		// not end(f) -> o
		if(f->x[dim-1].np != o->nr)
			return false;
			
		// unexpected cycle
		obMRange(i,dim-1)
			if(o->np == f->x[i+1].nr) 
				return false;

		// not yet a cycle
		if(o->np != f->x[dim-1].nr)
			return true;
			
		/* f->o from a cycle */
	}
	// it is a cycle
	if(f->lastignore) // then omega of the pivot is undefined
		return true;
	{
		double _om = 1.;
		obMRange(i,dim)
			_om *= ((double)(f->x[i].qtt_prov)) / ((double)(f->x[i].qtt_requ));
		_om *= ((double)(o->qtt_prov)) / ((double)(o->qtt_requ));
		//elog(WARNING,"_om %f, %c",_om,(_om>=1)?'T':'F');
		return (_om >= 1.);
	}
	
}
/******************************************************************************
yflow_follow(int,yorder,yflow)
******************************************************************************/
Datum yflow_follow_yorder_yflow(PG_FUNCTION_ARGS)
{
	Torder	*o;
	Tflow	*f;
	int32 maxlen = PG_GETARG_INT32(0);	
	
	o = PG_GETARG_TORDER(1);
	f = PG_GETARG_TFLOW(2);	

	PG_RETURN_BOOL(_yflow_follow(maxlen,o,f,true));
}
/******************************************************************************
yflow_follow(int,yflow,yorder)
******************************************************************************/
Datum yflow_follow_yflow_yorder(PG_FUNCTION_ARGS)
{
	Torder	*o;
	Tflow	*f;
	int32 maxlen = PG_GETARG_INT32(0);

	f = PG_GETARG_TFLOW(1);	
	o = PG_GETARG_TORDER(2);

	PG_RETURN_BOOL(_yflow_follow(maxlen,o,f,false));
}

/******************************************************************************
******************************************************************************/
Datum yflow_show(PG_FUNCTION_ARGS) {
	Tflow	*X;
	
	X = PG_GETARG_TFLOW(0);
	// elog(WARNING,"yflow_show: %s",yflow_ndboxToStr(X,true));
	// yflow_ndboxToStr(X,true)
	PG_RETURN_CSTRING(flowc_toStr(X));

}
/******************************************************************************
******************************************************************************/
Datum yflow_eq(PG_FUNCTION_ARGS)
{
	Tflow	*f1 = PG_GETARG_TFLOW(0);
	Tflow	*f2 = PG_GETARG_TFLOW(1);
	short 	i;
	
	if(f1->dim != f2->dim) PG_RETURN_BOOL(false);

	obMRange(i,f1->dim)
		if(f1->x[i].id != f2->x[i].id) {
			PG_RETURN_BOOL(false);
		}
	PG_RETURN_BOOL(true);

}
/******************************************************************************
******************************************************************************/
Datum yflow_left(PG_FUNCTION_ARGS)
{
	Tflow	*f1 = PG_GETARG_TFLOW(0);
	Tflow	*f2 = PG_GETARG_TFLOW(1);
	Tflow	*result;
	
	if(f1->dim !=0) 
		result = f1;
	else
		result = f2;
	PG_RETURN_TFLOW(result);

}
/******************************************************************************
yflow = yflow_reduce(f yflow,fr yflow)
if (f and fr are drafts) 
	when f->x[i].id == fr->x[j].id 
		if f->x[i].qtt >= fr->flowr[j]
			f->x[i].qtt -= fr->flowr[j]
		else 
			error
if (f or fr is not in (empty,draft))
	error
******************************************************************************/
#define FLOWISDOEU(f) (((f)->status == draft) || ((f)->status == empty) || ((f)->status == undefined))
#define FLOWAREDOEU(f1,f2) (FLOWISDOEU(f1) && FLOWISDOEU(f2))


Datum yflow_reduce(PG_FUNCTION_ARGS)
{
	Tflow	*f = PG_GETARG_TFLOW(0);
	Tflow	*fr = PG_GETARG_TFLOW(1);
	Tflow	*r;
	short 	i,j;
			 
	//r = Ndbox_init(FLOW_MAX_DIM);
	//memcpy(r,f,sizeof(Tflow));
	r = flowm_copy(f);
	
	if (false && !FLOWAREDOEU(r,fr)) 
		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			 errmsg("yflow_reduce: flows should be draft,undefined or empty;%s and %s instead",yflow_statusBoxToStr(r),yflow_statusBoxToStr(fr))));
	
	if(r->status == draft && fr->status == draft) {
		//short _dim;
		
		//_dim = (r->lastignore) ? (r->dim-1) : r->dim; // lastignore?
		obMRange(i,fr->dim) {
			obMRange(j,r->dim)
				if(r->x[j].id == fr->x[i].id) {
					if(r->x[j].qtt >= fr->x[i].flowr)
						r->x[j].qtt -= fr->x[i].flowr;
					else 
				    		ereport(ERROR,
							(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
							errmsg("yflow_reduce: the flow is greater than available")));
				}
		}
		(void) flowc_maximum(r);
	
	}

	PG_RETURN_TFLOW(r);

}
#define FLOW_LAST_OMEGA(f)  ((double)((f)->x[(f)->dim-1].flowr))/((double)((f)->x[(f)->dim-2].flowr))
#define FLOW_LAST_IOMEGA(f) ((double)((f)->x[(f)->dim-2].flowr))/((double)((f)->x[(f)->dim-1].flowr))
Datum yflow_last_iomega(PG_FUNCTION_ARGS)
{
	Tflow	*f = PG_GETARG_TFLOW(0);
	
	if(f->status != draft) 
		PG_RETURN_FLOAT8(0.);
		
	PG_RETURN_FLOAT8(FLOW_LAST_IOMEGA(f));
}
/******************************************************************************
aggregate function yflow_max(yflow) and min (useless)
******************************************************************************/

Datum yflow_maxg(PG_FUNCTION_ARGS)
{
	Tflow	*f1 = PG_GETARG_TFLOW(0);
	Tflow	*f2 = PG_GETARG_TFLOW(1);

	if(false && !FLOWAREDOEU(f1,f2)) 
			ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("yflow_maxg: flows should be draft,undefined or empty;%s and %s instead",yflow_statusBoxToStr(f1),yflow_statusBoxToStr(f2))));

					 
	if ((f1->status == draft) && (f2->status == draft)) {
	
		if(	// for the last partner, qtt_out(f1)/qtt_in(f1) > qtt_out(f2)/qtt_in(f2)
			FLOW_LAST_OMEGA(f1) > FLOW_LAST_OMEGA(f2)
		) PG_RETURN_TFLOW(f2);
		else PG_RETURN_TFLOW(f1);
		
	} else if(f1->status == draft)
		PG_RETURN_TFLOW(f1);
	else 
		PG_RETURN_TFLOW(f2);	
}
Datum yflow_ming(PG_FUNCTION_ARGS)
{
	Tflow	*f1 = PG_GETARG_TFLOW(0);
	Tflow	*f2 = PG_GETARG_TFLOW(1);

	if(false && !FLOWAREDOEU(f1,f2)) 
			ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("yflow_ming: the flow should be draft,undefined or empty")));
				 
					 
	if ((f1->status == draft) && (f2->status == draft)) {
	
		if(	// for the last partner, qtt_out(f1)/qtt_in(f1) < qtt_out(f2)/qtt_in(f2)
			FLOW_LAST_OMEGA(f1) < FLOW_LAST_OMEGA(f2)
		) PG_RETURN_TFLOW(f2);
		else PG_RETURN_TFLOW(f1);
		
	} else if(f1->status == draft)
		PG_RETURN_TFLOW(f1);
	else 
		PG_RETURN_TFLOW(f2);	
}
/******************************************************************************
aggregate function [qtt_in,qtt_out,dim] = yflow_qtts(yflow)
with: qtt_out=flow[dim-1] and qtt_in=flow[dim-2]
******************************************************************************/
Datum yflow_qtts(PG_FUNCTION_ARGS)
{
	Tflow	*f = PG_GETARG_TFLOW(0);
	Datum	*_datum_out;
	bool	*_isnull;
	
	ArrayType  *result;
	int16       _typlen;
	bool        _typbyval;
	char        _typalign;
	int         _dims[1];
	int         _lbs[1];

	if(f->status != draft)
			ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("yflow_qtts: the flow should be draft")));
	
	_datum_out = palloc(sizeof(Datum) * 3);
	_isnull = palloc(sizeof(bool) * 3);
	_datum_out[0] = Int64GetDatum(f->x[f->dim-2].flowr); // qtt_in
	_isnull[0] = false;
	_datum_out[1] = Int64GetDatum(f->x[f->dim-1].flowr); // qtt_out
	_isnull[1] = false;
	_datum_out[2] = Int64GetDatum((int64)f->dim); // dim
	_isnull[2] = false;

	_dims[0] = 3;
	_lbs[0] = 1;
				 
	/* get required info about the INT8 */
	get_typlenbyvalalign(INT8OID, &_typlen, &_typbyval, &_typalign);

	/* now build the array */
	result = construct_md_array(_datum_out, _isnull, 1, _dims, _lbs,
		                INT8OID, _typlen, _typbyval, _typalign);
	PG_FREE_IF_COPY(f,0);
	PG_RETURN_ARRAYTYPE_P(result);
	
}
/******************************************************************************
******************************************************************************/
Datum yflow_status(PG_FUNCTION_ARGS)
{
	Tflow	*f = PG_GETARG_TFLOW(0);

	switch(f->status) {
		case noloop: PG_RETURN_INT32(0);	
		case refused: PG_RETURN_INT32(1);
		case undefined: PG_RETURN_INT32(2);
		case draft: PG_RETURN_INT32(3);
		case empty: PG_RETURN_INT32(4);
		default: PG_RETURN_INT32(-1);
	}
}
/******************************************************************************
// always returns 1. NORMAL!!!!
******************************************************************************/
Datum yflow_flr_omega(PG_FUNCTION_ARGS)
{
	Tflow	*f = PG_GETARG_TFLOW(0);
	double _Omega = 1.; //float8
	int64	_fprec;
	int32	_dim = f->dim;
	int32 	_k;
	
	
	if(f->status != draft) 
		PG_RETURN_FLOAT8(0.);
		
	_fprec = f->x[_dim-1].flowr;
		
	obMRange (_k,_dim) {
		//elog(WARNING,"yflow_flr_omega: %lli,%lli",f->flowr[_k],_fprec);
		_Omega *= ((double)f->x[_k].flowr)/((double)_fprec);
		_fprec = f->x[_k].flowr;		
	}
	//elog(WARNING,"yflow_flr_omega: %f",_Omega);
	PG_RETURN_FLOAT8(_Omega);
}
/******************************************************************************
******************************************************************************/
Datum yflow_to_matrix(PG_FUNCTION_ARGS)
{
#define DIMELTRESULT 8

	Tflow	   *box;
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
		
	box = PG_GETARG_TFLOW(0);	

	_dim = box->dim;


	if(_dim == 0) {
		result = construct_empty_array(INT8OID);
		PG_RETURN_ARRAYTYPE_P(result);
	}
	
	_datum_out = palloc(sizeof(Datum) * _dim * DIMELTRESULT);
	_null_out =  palloc(sizeof(bool)  * _dim * DIMELTRESULT);
	
	//id,nr,qtt_prov,qtt_requ,sid,own,qtt,np
	obMRange(_i,_dim) {
		int _j = _i * DIMELTRESULT;
		_null_out[_j+0] = false; _datum_out[_j+0] = Int64GetDatum((int64) box->x[_i].id);
		_null_out[_j+1] = false; _datum_out[_j+1] = Int64GetDatum((int64) box->x[_i].own);
		_null_out[_j+2] = false; _datum_out[_j+2] = Int64GetDatum((int64) box->x[_i].nr);
		_null_out[_j+3] = false; _datum_out[_j+3] = Int64GetDatum(box->x[_i].qtt_requ);
		_null_out[_j+4] = false; _datum_out[_j+4] = Int64GetDatum((int64) box->x[_i].np);
		_null_out[_j+5] = false; _datum_out[_j+5] = Int64GetDatum(box->x[_i].qtt_prov);
		_null_out[_j+6] = false; _datum_out[_j+6] = Int64GetDatum(box->x[_i].qtt);
		_null_out[_j+7] = false; _datum_out[_j+7] = Int64GetDatum(box->x[_i].flowr);
	}

	dims[0] = _dim;

	// get required info about the INT8 
	get_typlenbyvalalign(INT8OID, &typlen, &typbyval, &typalign);

	// now build the array 
	result = construct_md_array(_datum_out, _null_out, ndims, dims, lbs,
		                INT8OID, typlen, typbyval, typalign);
	PG_FREE_IF_COPY(box,0);
	PG_RETURN_ARRAYTYPE_P(result);
}
/******************************************************************************
******************************************************************************/
char * yflow_statusBoxToStr (Tflow *box){
	switch(box->status) {
	case noloop: return "noloop";
	case draft: return "draft";
	case refused: return "refused";
	case undefined: return "undefined";
	case empty: return "empty";
	default: return "unknown status!";
	}
}
/*****************************************************************************
// get the last order of the flow
 *****************************************************************************/
Datum
yflow_get_last_order(PG_FUNCTION_ARGS)
{
	Tflow	*f = PG_GETARG_TFLOW(0);
	Torder	*result = palloc(sizeof(Torder));
	short 	dim = f->dim;

	if(dim == 0) 
		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				errmsg("yorder_get_last_order: the flow is empty")));
	memcpy(result,&f->x[dim-1],sizeof(Torder));
	PG_FREE_IF_COPY(f,0);
	PG_RETURN_TORDER(result);
}









