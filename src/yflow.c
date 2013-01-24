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
PG_FUNCTION_INFO_V1(yflow_init);
PG_FUNCTION_INFO_V1(yflow_grow);
PG_FUNCTION_INFO_V1(yflow_finish);
PG_FUNCTION_INFO_V1(yflow_contains_id);
PG_FUNCTION_INFO_V1(yflow_match);
PG_FUNCTION_INFO_V1(yflow_maxg);
PG_FUNCTION_INFO_V1(yflow_reduce);
PG_FUNCTION_INFO_V1(yflow_is_draft);
PG_FUNCTION_INFO_V1(yflow_to_matrix);
PG_FUNCTION_INFO_V1(yflow_qtts);
/*
PG_FUNCTION_INFO_V1(yflow_get_yorder);
PG_FUNCTION_INFO_V1(yflow_get_yorder_yflow);
PG_FUNCTION_INFO_V1(yflow_get_yflow_yorder);
PG_FUNCTION_INFO_V1(yflow_follow_yorder_yflow);
PG_FUNCTION_INFO_V1(yflow_follow_yflow_yorder);
*/
PG_FUNCTION_INFO_V1(yflow_show);
/*
PG_FUNCTION_INFO_V1(yflow_eq);
PG_FUNCTION_INFO_V1(yflow_left);
PG_FUNCTION_INFO_V1(yflow_reduce);
PG_FUNCTION_INFO_V1(yflow_last_iomega);
PG_FUNCTION_INFO_V1(yflow_maxg);
PG_FUNCTION_INFO_V1(yflow_status);
PG_FUNCTION_INFO_V1(yflow_flr_omega);
PG_FUNCTION_INFO_V1(yflow_to_matrix);
PG_FUNCTION_INFO_V1(yflow_qtts);
PG_FUNCTION_INFO_V1(yflow_get_last_order);
PG_FUNCTION_INFO_V1(yflow_to_json);
PG_FUNCTION_INFO_V1(yflows_array_to_json);
PG_FUNCTION_INFO_V1(yflow_iterid);
*/

Datum yflow_in(PG_FUNCTION_ARGS);
Datum yflow_out(PG_FUNCTION_ARGS);
Datum yflow_dim(PG_FUNCTION_ARGS);

Datum yflow_init(PG_FUNCTION_ARGS);
Datum yflow_grow(PG_FUNCTION_ARGS);
Datum yflow_finish(PG_FUNCTION_ARGS);
Datum yflow_contains_id(PG_FUNCTION_ARGS);
Datum yflow_match(PG_FUNCTION_ARGS);
Datum yflow_maxg(PG_FUNCTION_ARGS);
Datum yflow_reduce(PG_FUNCTION_ARGS);
Datum yflow_is_draft(PG_FUNCTION_ARGS);
Datum yflow_to_matrix(PG_FUNCTION_ARGS);
Datum yflow_qtts(PG_FUNCTION_ARGS);
/*
Datum yflow_get_yorder(PG_FUNCTION_ARGS);
Datum yflow_get_yorder_yflow(PG_FUNCTION_ARGS);
Datum yflow_get_yflow_yorder(PG_FUNCTION_ARGS);
Datum yflow_follow_yorder_yflow(PG_FUNCTION_ARGS);
Datum yflow_follow_yflow_yorder(PG_FUNCTION_ARGS);
*/
Datum yflow_show(PG_FUNCTION_ARGS);
/*
Datum yflow_eq(PG_FUNCTION_ARGS);
Datum yflow_left(PG_FUNCTION_ARGS);
Datum yflow_reduce(PG_FUNCTION_ARGS);
Datum yflow_last_iomega(PG_FUNCTION_ARGS);
Datum yflow_maxg(PG_FUNCTION_ARGS);
Datum yflow_status(PG_FUNCTION_ARGS);
Datum yflow_flr_omega(PG_FUNCTION_ARGS);
Datum yflow_to_matrix(PG_FUNCTION_ARGS);
Datum yflow_qtts(PG_FUNCTION_ARGS);
Datum yflow_get_last_order(PG_FUNCTION_ARGS);
Datum yflow_to_json(PG_FUNCTION_ARGS);
Datum yflows_array_to_json(PG_FUNCTION_ARGS);
Datum yflow_iterid(PG_FUNCTION_ARGS);
*/

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
		appendStringInfo(&buf, "YFLOW %s ",yflow_statusToStr(yflow->status));
	}
	appendStringInfoChar(&buf, '[');
	if(dim >0) {
		for (i = 0; i < dim; i++)
		{	
			Tfl *s = &yflow->x[i];
		
			if(i != 0) appendStringInfoChar(&buf, ',');

			// id,oid,own,qtt_requ,qtt_prov,qtt,proba
			appendStringInfo(&buf, "(%i, ", s->id);
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
Datum yflow_show(PG_FUNCTION_ARGS) {
	Tflow	*X;
	char *str;
	TresChemin *c;
	
	X = PG_GETARG_TFLOW(0);
	// elog(WARNING,"yflow_show: %s",yflow_ndboxToStr(X,true));
	c = flowc_maximum(X);
	pfree(c);
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
char * yflow_statusToStr (Tstatusflow s){
	switch(s) {
	case notcomputed: return "notcomputed";
	case noloop: return "noloop";
	case draft: return "draft";
	case refused: return "refused";
	case undefined: return "undefined";
	case empty: return "empty";
	default: return "unknown status!";
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
			
	obMRange(i,dim)
		if(f->x[i].id == o->id) {
			found = true;
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

	PG_RETURN_TFLOW(result);
}
/******************************************************************************
 flow_finish(id,path) -> true when some order of the flow have the same id 
******************************************************************************/
Datum yflow_contains_id(PG_FUNCTION_ARGS) {
	int32	id = PG_GETARG_INT32(0);
	Tflow	*f = PG_GETARG_TFLOW(1);
	short 	i;
	bool	result = false;;

	obMRange(i,f->dim)
		if(f->x[i].id == id) {
			result = true;
			break;
		}

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
		
	if(f0->status == notcomputed) {
		TresChemin *c;
		c = flowc_maximum(f0);
		pfree(c);
	}
		
	_rank0 = 1.0;
	obMRange(i,dim0) {
		Tfl *b = &f0->x[i];
		if(b->flowr <=0 ) 
			goto _end;	// wolf0 is not a draft
		_rank0 *=  GET_OMEGA(b);				
	}	

	dim1 = f1->dim;
	// wolf1 is empty
	if(dim1 == 0)
		goto _end;
		
	if(f1->status == notcomputed) {
		TresChemin *c;
		c = flowc_maximum(f1);
		pfree(c);
	}		
	_rank1 = 1.0;
	obMRange(i,dim1) {
		Tfl *b = &f1->x[i];
		if(b->flowr <=0) 
			goto _end;	// f1 is not a draft
		_rank1 *= GET_OMEGA(b);			
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
#define FLOWISDOEU(f) ((f)->status != notcomputed)
#define FLOWAREDOEU(f1,f2) (FLOWISDOEU(f1) && FLOWISDOEU(f2))

Datum yflow_reduce(PG_FUNCTION_ARGS)
{
	Tflow	*f = PG_GETARG_TFLOW(0);
	Tflow	*fr = PG_GETARG_TFLOW(1);
	Tflow	*r;
	short 	i,j;
	TresChemin *c;
			 
	//r = Ndbox_init(FLOW_MAX_DIM);
	//memcpy(r,f,sizeof(Tflow));
	r = flowm_copy(f);
	
	if(r->status == notcomputed) {
		c = flowc_maximum(r);
		pfree(c);
	}
	if(fr->status == notcomputed) {
		c = flowc_maximum(fr);
		pfree(c);
	}
	
	if (!FLOWAREDOEU(r,fr)) 
		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			 errmsg("yflow_reduce: flows should be computed;%s and %s instead",yflow_statusToStr(r->status),yflow_statusToStr(fr->status))));
	
	if(r->status == draft && fr->status == draft) {
		//short _dim;
		
		//_dim = (r->lastignore) ? (r->dim-1) : r->dim; // lastignore?
		obMRange(i,fr->dim) {
			obMRange(j,r->dim)
				if(r->x[j].oid == fr->x[i].oid) {
					if(r->x[j].qtt >= fr->x[i].flowr)
						r->x[j].qtt -= fr->x[i].flowr;
					else 
				    		ereport(ERROR,
							(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
							errmsg("yflow_reduce: the flow is greater than available")));
				}
		}
		
		c = flowc_maximum(r);
		pfree(c);
	}

	PG_RETURN_TFLOW(r);

}
/******************************************************************************
******************************************************************************/
Datum yflow_is_draft(PG_FUNCTION_ARGS)
{
	Tflow	*f = PG_GETARG_TFLOW(0);
	bool	isdraft = true;
	short 	i;

	if(f->status == notcomputed) {
		TresChemin *c;
		c = flowc_maximum(f);
		pfree(c);
	}
		
	obMRange(i,f->dim) {
		if (f->x[i].flowr <=0) {
			isdraft = false;
			break;
		}
	}
	
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
	if(flow->status == notcomputed) {
		TresChemin *c;
		c = flowc_maximum(flow);
		pfree(c);
	}

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

	if(f->status == notcomputed) {
		TresChemin *c;
		c = flowc_maximum(f);
		pfree(c);
	}
	if(f->status != draft)
			ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("yflow_qtts: the flow should be draft")));
	
	_datum_out = palloc(sizeof(Datum) * 2);
	_isnull = palloc(sizeof(bool) * 2);
	_datum_out[0] = Int64GetDatum(f->x[f->dim-2].flowr); // qtt_in
	_isnull[0] = false;
	_datum_out[1] = Int64GetDatum(f->x[f->dim-1].flowr); // qtt_out
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
/******************************************************************************
******************************************************************************/
/* unused
static bool _yflow_hs_contains_keys(HStore	*h2,HStore *h1) {
	
	int			cnth1 = HS_COUNT(h1);
	HEntry	   *enth1 = HSARRPTR(h1);
	char	   *bash1 = HSSTRPTR(h1);
	bool		contains = true;	
	int 		i;
	int 		lowbound = 0;
	
	//elog(WARNING,"cnth1=%i",cnth1);
	obMRange(i,cnth1) {
		int 	l1 = HS_KEYLEN(enth1, i);
		char 	*key1 = HS_KEY(enth1, bash1, i);
		
		int		idx = hstoreFindKey(h2, &lowbound,key1,l1);
		
		// elog(WARNING,"i=%i,cnth1=%i, key h2[%s],len=%i found in idx=%i",i,cnth1,key1,l1,idx);
		
		if(idx <0) {
			contains = false;
			break;
		}
	}
	//elog(WARNING,"cnth1=%i",cnth1);
	return contains;	
} */
/******************************************************************************
float weight = yflow_weigth(hstore w,hstore p,hstore r,bool all)
weight = sum (if(p[i] == r[i] then w[i] else 0)/sum(w[i]) for i in w.keys
weigth >= 0
errors:
	if w[i] is not float returns -3
	if w[i] <0 returns -4
******************************************************************************/
PG_FUNCTION_INFO_V1(yflow_weight);
Datum yflow_weight(PG_FUNCTION_ARGS);
Datum yflow_weight(PG_FUNCTION_ARGS) {
	HStore	   *w = PG_GETARG_HS(0);
	HStore	   *p = PG_GETARG_HS(1);
	HStore	   *r = PG_GETARG_HS(2);
	
	PG_RETURN_FLOAT8((float8)  yflow_weight_internal(w,p,r));
}

double yflow_weight_internal(HStore *w,HStore *p,HStore *r) {
	double 		f = 0.0,s = 0.0,wp;
	
	int			cntw = HS_COUNT(w);
	HEntry	   *entw = HSARRPTR(w);
	char	   *basw = HSSTRPTR(w);
	
	//int			cntp = HS_COUNT(p);
	HEntry	   *entp = HSARRPTR(p);
	char	   *basp = HSSTRPTR(p);
	int 	lowboundp = 0;
		
	//int			cntr = HS_COUNT(r);
	HEntry	   *entr = HSARRPTR(r);
	char	   *basr = HSSTRPTR(r);
	int 	lowboundr = 0;
	int			i;
	
	
	// elog(WARNING,"cntw=%i,cntp=%i,cntr=%i,%c,%c",cntw,cntp,cntr,_yflow_hs_contains_keys(p,r)?'t':'f',_yflow_hs_contains_keys(w,r)?'t':'f');
	// elog(WARNING,"cntw=%i,cntp=%i,cntr=%i,%c,%c",cntw,cntp,cntr,_yflow_hs_contains_keys(p,r)?'t':'f',_yflow_hs_contains_keys(w,r)?'t':'f');
	/*
	if(!(_yflow_hs_contains_keys(p,r))) {
		f = -1.0;
		goto _end;
	}
	if(all && (cntp!=cntr ) {
		f = -5.0;
		goto _end;
	}		
	if(!(_yflow_hs_contains_keys(r,w))) {
		f = -2.0;
		goto _end;
	}
	*/
	
	obMRange(i,cntw) {
		char *cweight = HS_VAL(entw, basw, i);
		// int lw = HS_VALLEN(entw, i);
		char *end;
		int 	lw = HS_KEYLEN(entw, i);
		char 	*cw = HS_KEY(entw, basw, i);
		
		wp = strtod(cweight,&end);
		if(cweight == end) {
			f = -3.0; // this is not a float
			goto _end;
		}
		if(wp < 0.0) {
			f = -4.0; // the weigth < 0
			goto _end;
		}
		
		s += wp;
		//elog(WARNING,"w[%i]=%f,%s,%i",i,wp,cw,klw);
		{
			int 	ir,ip;
			
			char	*cr,*cp;
			int		lr,lp;
			
			ir = hstoreFindKey(r, &lowboundr,cw,lw);
			lr = HS_VALLEN(entr, ir);
			cr = HS_VAL(entr, basr, ir);
			//elog(WARNING,"r[%i]=%s,%i",ir,cr,lr);
			if(ir >=0) {
				ip = hstoreFindKey(p, &lowboundp,cw,lw);
				if(ip >=0) {
					lp = HS_VALLEN(entp, ip);
					cp = HS_VAL(entp, basp, ip);
					//elog(WARNING,"p[%i]=%s,%i",ip,cp,lp);
					
					if((lr==lp) && (0 == memcmp(cp,cr,lr)))			
						f += wp;
				}
			}
		}

	}		
	if(s != 0.0)	 
		f = f/s;
	else f = 0.0;
_end:
	return f;
}


