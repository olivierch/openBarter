/******************************************************************************
  This file contains routines that can be bound to a Postgres backend and
  called by the backend in the process of processing queries.  The calling
  format for these routines is dictated by Postgres architecture.
******************************************************************************/

#include "postgres.h"

#include <math.h>

#include "lib/stringinfo.h"
#include "libpq/pqformat.h"

#include "utils/builtins.h"
#include "utils/lsyscache.h" 
#include "catalog/pg_type.h" 
#include "funcapi.h" 

#include "wolf.h"


PG_MODULE_MAGIC;

extern int  yflow_yyparse(void *resultat);
extern void yflow_yyerror(const char *message);
extern void yflow_scanner_init(const char *str);
extern void yflow_scanner_finish(void);

// ob_tGlobales globales;

PG_FUNCTION_INFO_V1(yflow_in);
PG_FUNCTION_INFO_V1(yflow_out);
PG_FUNCTION_INFO_V1(yflow_dim);
PG_FUNCTION_INFO_V1(yflow_get_maxdim);
PG_FUNCTION_INFO_V1(yflow_init);
PG_FUNCTION_INFO_V1(yflow_grow);
PG_FUNCTION_INFO_V1(yflow_finish);
PG_FUNCTION_INFO_V1(yflow_contains_oid);
PG_FUNCTION_INFO_V1(yflow_match);
PG_FUNCTION_INFO_V1(yflow_maxg);
PG_FUNCTION_INFO_V1(yflow_reduce);
PG_FUNCTION_INFO_V1(yflow_reducequote);
PG_FUNCTION_INFO_V1(yflow_is_draft);
PG_FUNCTION_INFO_V1(yflow_to_matrix);
PG_FUNCTION_INFO_V1(yflow_qtts);

PG_FUNCTION_INFO_V1(yflow_show);
PG_FUNCTION_INFO_V1(yflow_to_json);

Datum yflow_in(PG_FUNCTION_ARGS);
Datum yflow_out(PG_FUNCTION_ARGS);
Datum yflow_dim(PG_FUNCTION_ARGS);
Datum yflow_get_maxdim(PG_FUNCTION_ARGS);

Datum yflow_init(PG_FUNCTION_ARGS);
Datum yflow_grow(PG_FUNCTION_ARGS);
Datum yflow_finish(PG_FUNCTION_ARGS);
Datum yflow_contains_oid(PG_FUNCTION_ARGS);
Datum yflow_match(PG_FUNCTION_ARGS);
Datum yflow_maxg(PG_FUNCTION_ARGS);
Datum yflow_reduce(PG_FUNCTION_ARGS);
Datum yflow_reducequote(PG_FUNCTION_ARGS);
Datum yflow_is_draft(PG_FUNCTION_ARGS);
Datum yflow_to_matrix(PG_FUNCTION_ARGS);
Datum yflow_qtts(PG_FUNCTION_ARGS);

Datum yflow_show(PG_FUNCTION_ARGS);
Datum yflow_to_json(PG_FUNCTION_ARGS);

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
where yfl = (id,oid,own,qtt_requ,qtt_prov,qtt,proba) */
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
	
	{
		TresChemin *c;
		c = flowc_maximum(result);
		pfree(c);
	}	

	//(void) flowc_maximum(result);

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
		appendStringInfo(&buf, "YFLOW ");
	}
	appendStringInfoChar(&buf, '[');
	if(dim >0) {
		for (i = 0; i < dim; i++)
		{	
			Tfl *s = &yflow->x[i];
		
			if(i != 0) appendStringInfoChar(&buf, ',');

			// type,id,oid,own,qtt_requ,qtt_prov,qtt,proba
			appendStringInfo(&buf, "(%i, ", s->type);
			appendStringInfo(&buf, "%i, ", s->id);
			appendStringInfo(&buf, "%i, ", s->oid);
			appendStringInfo(&buf, "%i, ", s->own);
			appendStringInfo(&buf, INT64_FORMAT ", ", s->qtt_requ);
			appendStringInfo(&buf, INT64_FORMAT ", ", s->qtt_prov);
			appendStringInfo(&buf, INT64_FORMAT ", ", s->qtt);
		
			if(internal)
				appendStringInfo(&buf,"%f :" INT64_FORMAT ")",s->proba, s->flowr);
			else 
				appendStringInfo(&buf, "%f)", s->proba);
		}
	}
	appendStringInfoChar(&buf, ']');
	if(internal)
		appendStringInfoChar(&buf, '\n');
	
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
	
	if(dim > FLOW_MAX_DIM)
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("flow->dim not <=%i",FLOW_MAX_DIM)));
	PG_RETURN_INT32(dim);
}
/******************************************************************************
******************************************************************************/
Datum yflow_get_maxdim(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT32(FLOW_MAX_DIM);
}

/******************************************************************************
******************************************************************************/
Datum yflow_show(PG_FUNCTION_ARGS) {
	Tflow	*X;
	char *str;
	
	X = PG_GETARG_TFLOW(0);
	// elog(WARNING,"yflow_show: %s",yflow_ndboxToStr(X,true));
	//str = flowc_cheminToStr(c);
	str = yflow_ndboxToStr(X,true);
	PG_RETURN_CSTRING(str);
/*
	c = flowc_maximum(X);
	str = flowc_cheminToStr(c);
	pfree(c);
	PG_RETURN_CSTRING(str);
*/
}
/******************************************************************************
******************************************************************************/
Datum yflow_to_json(PG_FUNCTION_ARGS) {
	Tflow *yflow = PG_GETARG_TFLOW(0);
	StringInfoData 	buf;
	int	dim = yflow->dim;
	int	i;

	initStringInfo(&buf);

	appendStringInfoChar(&buf, '[');
	if(dim >0) {
		for (i = 0; i < dim; i++)
		{	
			Tfl *s = &yflow->x[i];
		
			if(i != 0) appendStringInfo(&buf, ",\n");

			// type,id,oid,own,qtt_requ,qtt_prov,qtt,proba
			appendStringInfo(&buf, "{\"type\":%i, ", s->type);
			appendStringInfo(&buf, "\"id\":%i, ", s->id);
			appendStringInfo(&buf, "\"oid\":%i, ", s->oid);
			appendStringInfo(&buf, "\"own\":%i, ", s->own);
			appendStringInfo(&buf, "\"qtt_requ\":" INT64_FORMAT ", ", s->qtt_requ);
			appendStringInfo(&buf, "\"qtt_prov\":" INT64_FORMAT ", ", s->qtt_prov);
			appendStringInfo(&buf, "\"qtt\":" INT64_FORMAT ", ", s->qtt);
		
			appendStringInfo(&buf,"\"proba\":%.10e,\"flowr\":" INT64_FORMAT "}",s->proba, s->flowr);
		}
	}
	appendStringInfoChar(&buf, ']');
	
	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

/******************************************************************************
******************************************************************************/
char * yflow_statusToStr (Tstatusflow s){
	switch(s) {
	case noloop: return "noloop";
	case draft: return "draft";
	case refused: return "refused";
	case undefined: return "undefined";
	case empty: return "empty";
	default: return "unknown status!";
	}
}
/******************************************************************************
******************************************************************************/
char * yflow_typeToStr (int32 t){
	switch(ORDER_TYPE(t)) {
	case ORDER_LIMIT: return "ORDER_LIMIT";
	case ORDER_BEST: return "ORDER_BEST";
	default: return "unknown type!";
	}
}
/******************************************************************************
yflow_get()
******************************************************************************/
static Tflow* _yflow_get(Tfl *o,Tflow *f, bool before) {
	Tflow	*result;
	short 	dim = f->dim,i;
	bool	found = false;
	
	if(dim > (FLOW_MAX_DIM-1))
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("attempt to extend a yflow out of range")));
			
	obMRange(i,dim) {

		if(f->x[i].oid == o->oid) {
			found = true;
			break;
		} else if(f->x[i].id == o->id) //  && f->x[i].oid != o->oid
			ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				errmsg("same order with different oid")));
	}
		
	if (found)
		result = flowm_copy(f);
	else
		result = flowm_cextends(o,f,before);

	#ifdef GL_WARNING_GET
		elog(WARNING,"_yflow_get %s",yflow_pathToStr(result));
	#endif
	return result;	
	
}

/******************************************************************************
 flow_init(order) ->path = [ord] distance[0]=0 
******************************************************************************/

Datum yflow_init(PG_FUNCTION_ARGS) {
	
	Datum	dnew = (Datum) PG_GETARG_POINTER(0);
	Torder	new;
	Tflow	*f,*result;
	Tfl		fnew;
	
	yorder_get_order(dnew,&new);
	yorder_to_fl(&new,&fnew);
	
	f = flowm_init();
	result = _yflow_get(&fnew,f,true);
	result->x[0].proba = -1.0;
	result->x[0].flowr = 0;

	PG_RETURN_TFLOW(result);

}
/******************************************************************************
 flow_grow(new,debut,path) -> path = new || path avec la distance(new,debut) 
******************************************************************************/

Datum yflow_grow(PG_FUNCTION_ARGS) {
	
	Datum	dnew = (Datum) PG_GETARG_POINTER(0);
	Datum	ddebut = (Datum) PG_GETARG_POINTER(1);
	Tflow	*f = PG_GETARG_TFLOW(2);
	Torder	new,debut;
	Tfl		fnew;
	Tflow	*result;
	short	dim = f->dim;
	
	if(dim == 0 )
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("attempt to extend a yflow that is empty")));
	
	yorder_get_order(ddebut,&debut);
	if(f->x[0].id != debut.id )
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("attempt to grow a yflow with an order %i that is not the begin of the flow %s",debut.id,yflow_ndboxToStr(f,false))));
	
	yorder_get_order(dnew,&new);		
	if(!yorder_match(&new,&debut))
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("attempt to grow a yflow with an order that is not matching the begin of the flow")));

			
	yorder_to_fl(&new,&fnew);
	result = _yflow_get(&fnew,f,true);
	result->x[0].proba = yorder_match_proba(&new,&debut);
	result->x[0].flowr = 0;
	
	PG_FREE_IF_COPY(f, 2);
	PG_RETURN_TFLOW(result);

}
/******************************************************************************
 flow_finish(debut,path,fin) -> -> path idem, distance[0] la distance(fin,debut) 
******************************************************************************/

Datum yflow_finish(PG_FUNCTION_ARGS) {
	
	Datum	ddebut = (Datum) PG_GETARG_POINTER(0);
	Tflow	*f = PG_GETARG_TFLOW(1);
	Datum	dfin = (Datum) PG_GETARG_POINTER(2);
	
	Torder	debut,fin;
	Tflow	*result;
	short	dim = f->dim;

	if(dim < 2 )
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("attempt to finish a yflow that has less than two partners")));
				
	yorder_get_order(dfin,&fin);
	if(f->x[dim-1].id != fin.id )
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("attempt to finish a yflow with an order that is not the one finishing the flow")));
			
	yorder_get_order(ddebut,&debut);
	if(f->x[0].id != debut.id )
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("attempt to finish a yflow with an order %i that is not the one starting %s",debut.id,yflow_ndboxToStr(f,false) )));

	if(!yorder_match(&fin,&debut))
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("attempt to finish a yflow where the end is not matching the begin")));
							
	result = flowm_copy(f);
	result->x[result->dim-1].proba = yorder_match_proba(&fin,&debut);

	{
		TresChemin *c;
		c = flowc_maximum(result);
		pfree(c);
	}	

	PG_FREE_IF_COPY(f, 1);
	PG_RETURN_TFLOW(result);
}
/******************************************************************************
 flow_contains_id(flow) -> true when some order of the flow have the same oid 
******************************************************************************/
Datum yflow_contains_oid(PG_FUNCTION_ARGS) {
	int32	oid = PG_GETARG_INT32(0);
	Tflow	*f = PG_GETARG_TFLOW(1);
	short 	i,dim = f->dim;
	bool	result = false;

	obMRange(i,dim)
		if(f->x[i].oid == oid) {
			result = true;
			break;
		} 

	PG_FREE_IF_COPY(f, 1);
	PG_RETURN_BOOL(result);
}
/******************************************************************************
 flow_match(order,order) -> true when they match 
******************************************************************************/
Datum yflow_match(PG_FUNCTION_ARGS) {
	
	Datum	dprev = (Datum) PG_GETARG_POINTER(0);
	Datum	dnext = (Datum) PG_GETARG_POINTER(1);
	Torder	prev,next;

	yorder_get_order(dprev,&prev);
	yorder_get_order(dnext,&next);

	PG_RETURN_BOOL(yorder_match(&prev,&next));
}
/******************************************************************************
CREATE FUNCTION ywolf_maxg(yorder[] w0,yorder[] w1)
RETURNS yorder[]
AS 'exampleText.so'
LANGUAGE C IMMUTABLE STRICT;
returns the w0 if w0>w1 otherwise w1
******************************************************************************/
Datum yflow_maxg(PG_FUNCTION_ARGS)
{
	Tflow	*f0 = PG_GETARG_TFLOW(0);
	Tflow	*f1 = PG_GETARG_TFLOW(1);
	short			dim0,dim1,i;
	double			_rank0,_rank1;
	bool			_sup = false;
	
	dim0 = f0->dim;
	// f0 is empty
	if(dim0 == 0)
		goto _end;
		
	_rank0 = 1.0;
	obMRange(i,dim0) {
		Tfl *b = &f0->x[i];
		if(b->flowr <=0 ) 
			goto _end;	// wolf0 is not a draft
		_rank0 *=  GET_OMEGA_P(b);				
	}	

	dim1 = f1->dim;
	// wolf1 is empty
	if(dim1 == 0)
		goto _end;
				
	_rank1 = 1.0;
	obMRange(i,dim1) {
		Tfl *b = &f1->x[i];
		if(b->flowr <=0) 
			goto _end;	// f1 is not a draft
		_rank1 *= GET_OMEGA_P(b);			
	}	
	
	// comparing weight
	if(_rank0 == _rank1) {
		/* rank are geometric means of proba. Since 0 <=proba <=1
		if it was a product,large cycles would be penalized.
		*/
		_rank0 = 1.0;
		obMRange(i,dim0) 
			_rank0 *=  (double) f0->x[i].proba;				
		_rank0 = pow(_rank0,1.0/(double) dim0);
		
		_rank1 = 1.0;
		obMRange(i,dim1) 
			_rank1 *=  (double) f1->x[i].proba;
		_rank1 = pow(_rank1,1.0/(double) dim1);					
		
	}
	_sup = _rank0 > _rank1;
	
	//elog(WARNING,"yflow_maxg: wolf0: %s",ywolf_allToStr(wolf0));
	//elog(WARNING,"yflow_maxg: wolf1: %s",ywolf_allToStr(wolf1));
	//elog(WARNING,"ywolf_maxg: rank0=%f,rank1=%f",_rank0,_rank1);
		
_end:
	if(_sup) {
		PG_FREE_IF_COPY(f1, 1);
		PG_RETURN_TFLOW(f0);
	} else {
		PG_FREE_IF_COPY(f0, 0);
		PG_RETURN_TFLOW(f1);
	}	
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
Datum yflow_reduce(PG_FUNCTION_ARGS)
{
	Tflow	*f0 = PG_GETARG_TFLOW(0);
	Tflow	*f1 = PG_GETARG_TFLOW(1);
	Tflow	*r;
	short 	i,j;
	TresChemin *c;
			 
	r = flowm_copy(f0);
	
	obMRange(i,f1->dim) {
		obMRange(j,r->dim)
			if(r->x[j].oid == f1->x[i].oid) {
				if(r->x[j].qtt >= f1->x[i].flowr) {
					r->x[j].qtt -= f1->x[i].flowr;
					// elog(WARNING,"order %i stock %i reduced by %li to %li",r->x[j].id,r->x[j].oid,f1->x[i].flowr,r->x[j].qtt);
				} else 
			    		ereport(ERROR,
						(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
						errmsg("yflow_reduce: the flow is greater than available")));
			}
	}
	
	c = flowc_maximum(r);
	pfree(c);
	
	PG_FREE_IF_COPY(f0, 0);
	PG_FREE_IF_COPY(f1, 1);
	PG_RETURN_TFLOW(r);

}
/******************************************************************************
works as flow_reduce, but

******************************************************************************/
Datum yflow_reducequote(PG_FUNCTION_ARGS)
{
	bool	begin = PG_GETARG_BOOL(0);
	Tflow	*f0 = PG_GETARG_TFLOW(1);
	Tflow	*f1 = PG_GETARG_TFLOW(2);
	Tflow	*r;
	short 	i,j;
	TresChemin *c;
	Tfl 	*lastr,*lastf1;

	r = flowm_copy(f0);
	 
	obMRange(i,f1->dim) {
		obMRange(j,r->dim-1) { // the last node of r is not reduced
			if(r->x[j].oid == f1->x[i].oid) {
				if(r->x[j].qtt >= f1->x[i].flowr) {
					r->x[j].qtt -= f1->x[i].flowr;
					// elog(WARNING,"order %i stock %i reduced by %li to %li",r->x[j].id,r->x[j].oid,f1->x[i].flowr,r->x[j].qtt);
				} else {
			    		ereport(ERROR,
						(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
						errmsg("yflow_reducequote: the flow is greater than available")));
				}
			}
		}
		
	}
	
	lastr  = &r->x[r->dim-1];
	lastf1 = &f1->x[f1->dim-1];
	
	// sanity check
	if(lastr->id != lastf1->id)
			ereport(ERROR,
						(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
						errmsg("yflow_reducequote: the last nodes are not the same")));
						
	if(begin) {
		// sanity check
		if((lastr->type & ORDER_IGNOREOMEGA) == 0)
			ereport(ERROR,
						(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
						errmsg("yflow_reducequote: the flow.type=%i should have IGNOREOMEGA when begin is True",lastr->type)));		
		// omega is set
		lastr->qtt_prov = lastf1->flowr;
		lastr->qtt_requ = f1->x[f1->dim-2].flowr;
	} 
	
	lastr->type = (lastr->type & ORDER_TYPE_MASK) | ORDER_NOQTTLIMIT; 
	// IGNOREOMEGA is reset
	
	c = flowc_maximum(r);
	pfree(c);

	PG_FREE_IF_COPY(f0, 1);
	PG_FREE_IF_COPY(f1, 2);
	PG_RETURN_TFLOW(r);

}

/******************************************************************************
******************************************************************************/
Datum yflow_is_draft(PG_FUNCTION_ARGS)
{
	Tflow	*f = PG_GETARG_TFLOW(0);
	bool	isdraft = true;
	short 	i,_dim = f->dim;
		
	if(_dim < 2) PG_RETURN_BOOL(false);

	obMRange(i,_dim) {
		if (f->x[i].flowr <=0) {
			isdraft = false;
			break;
		}
	}
	PG_FREE_IF_COPY(f, 0);
	PG_RETURN_BOOL(isdraft);
}
/******************************************************************************
returns a matrix int8[i][j] of i lines of nodes, where a node is:
	[id,own,oid,qtt_requ,qtt_prov,qtt,flowr]
******************************************************************************/
Datum yflow_to_matrix(PG_FUNCTION_ARGS)
{
#define DIMELTRESULT 7

	Tflow	   *flow;
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
		
	flow = PG_GETARG_TFLOW(0);	

	_dim = flow->dim;

	if(_dim == 0) {
		result = construct_empty_array(INT8OID);
		PG_RETURN_ARRAYTYPE_P(result);
	}
	
	_datum_out = palloc(sizeof(Datum) * _dim * DIMELTRESULT);
	_null_out =  palloc(sizeof(bool)  * _dim * DIMELTRESULT);
	
	//  id,own,nr,qtt_requ,np,qtt_prov,qtt,flowr
	obMRange(_i,_dim) {
		int _j = _i * DIMELTRESULT;
		_null_out[_j+0] = false; _datum_out[_j+0] = Int64GetDatum((int64) flow->x[_i].id);
		_null_out[_j+1] = false; _datum_out[_j+1] = Int64GetDatum((int64) flow->x[_i].own);
		_null_out[_j+2] = false; _datum_out[_j+2] = Int64GetDatum((int64) flow->x[_i].oid);
		_null_out[_j+3] = false; _datum_out[_j+3] = Int64GetDatum(flow->x[_i].qtt_requ);
		_null_out[_j+4] = false; _datum_out[_j+4] = Int64GetDatum(flow->x[_i].qtt_prov);
		_null_out[_j+5] = false; _datum_out[_j+5] = Int64GetDatum(flow->x[_i].qtt);
		_null_out[_j+6] = false; _datum_out[_j+6] = Int64GetDatum(flow->x[_i].flowr);
	}

	dims[0] = _dim;

	// get required info about the INT8 
	get_typlenbyvalalign(INT8OID, &typlen, &typbyval, &typalign);

	// now build the array 
	result = construct_md_array(_datum_out, _null_out, ndims, dims, lbs,
		                INT8OID, typlen, typbyval, typalign);
	PG_FREE_IF_COPY(flow,0);
	PG_RETURN_ARRAYTYPE_P(result);
}
/******************************************************************************
aggregate function [qtt_in,qtt_out] = yflow_qtts(yflow)
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
	int64		_qtt_in =0,_qtt_out =0;
	short		_i;
	bool		_isDraft = true;
	
	obMRange(_i,f->dim) {
		if(f->x[_i].flowr <=0) {
			_isDraft = false;
		}
	}
	if(_isDraft) {
		//int64	_in,_out;
		//elog(WARNING,"_qtt_in=%li _qtt_out=%li",f->x[f->dim-2].flowr,f->x[f->dim-1].flowr);
		_qtt_in  = Int64GetDatum(f->x[f->dim-2].flowr);
		_qtt_out = Int64GetDatum(f->x[f->dim-1].flowr);
		//_in = DatumGetInt64(_qtt_in);
		//_out = DatumGetInt64(_qtt_out);
		//elog(WARNING,"_in=%li _out=%li",_in,_out);
	} else {
			ereport(WARNING,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("yflow_qtts: the flow should be draft")));
	}
	_datum_out = palloc(sizeof(Datum) * 2);
	_isnull = palloc(sizeof(bool) * 2);
	_datum_out[0] = _qtt_in;
	_isnull[0] = false;
	_datum_out[1] = _qtt_out;
	_isnull[1] = false;

	_dims[0] = 2;
	_lbs[0] = 1;
				 
	/* get required info about the INT8 */
	get_typlenbyvalalign(INT8OID, &_typlen, &_typbyval, &_typalign);

	/* now build the array */
	result = construct_md_array(_datum_out, _isnull, 1, _dims, _lbs,
		                INT8OID, _typlen, _typbyval, _typalign);
	PG_FREE_IF_COPY(f,0);
	PG_RETURN_ARRAYTYPE_P(result);
	
}



