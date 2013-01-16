
#include "postgres.h"

#include <math.h>

#include "lib/stringinfo.h"
#include "libpq/pqformat.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h" 
#include "utils/typcache.h"
#include "catalog/pg_type.h" 
#include "funcapi.h" 

#include "wolf.h"


#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

PG_FUNCTION_INFO_V1(ywolf_to_lines);
PG_FUNCTION_INFO_V1(ywolf_iterid);
PG_FUNCTION_INFO_V1(ywolf_status);
PG_FUNCTION_INFO_V1(ywolf_follow);
PG_FUNCTION_INFO_V1(ywolf_maxg);
PG_FUNCTION_INFO_V1(ywolf_reduce);
PG_FUNCTION_INFO_V1(ywolf_cat);
PG_FUNCTION_INFO_V1(ywolf_qtts);
PG_FUNCTION_INFO_V1(ywolf_is_draft);

Datum ywolf_to_lines(PG_FUNCTION_ARGS);
Datum ywolf_iterid(PG_FUNCTION_ARGS);
Datum ywolf_status(PG_FUNCTION_ARGS);
Datum ywolf_follow(PG_FUNCTION_ARGS);
Datum ywolf_maxg(PG_FUNCTION_ARGS);
Datum ywolf_reduce(PG_FUNCTION_ARGS);
Datum ywolf_cat(PG_FUNCTION_ARGS);
Datum ywolf_qtts(PG_FUNCTION_ARGS);
Datum ywolf_is_draft(PG_FUNCTION_ARGS);

static void ywolf_get_order(Datum eorder,Torder *orderp);
static Datum ywolf_get_datum(TupleDesc tupdesc,Torder *orderp);
static void ywolf_get_w(ArrayType *awolf,Twolf **wolfp);
static void ywolf_free_w(Twolf *wolf);
static Twolf *ywolf_add(Torder *order,Twolf *wolf);

static void ywolf_get_order(Datum eorder,Torder *orderp) {

	bool isnull;
	HeapTupleHeader t = ((HeapTupleHeader) PG_DETOAST_DATUM(eorder));
	
	orderp->id = DatumGetInt32(GetAttributeByName(t, "id", &isnull)); if(isnull) goto _end;
	orderp->own = (Datum) PG_DETOAST_DATUM(GetAttributeByName(t, "own", &isnull)); if(isnull) goto _end;
	//elog(WARNING,"ywolf_get_order: order->own='%s'",follow_DatumTxtToStr(orderp->own));
	orderp->oid = DatumGetInt32(GetAttributeByName(t, "oid", &isnull)); if(isnull) goto _end;
	orderp->qtt_requ = DatumGetInt64(GetAttributeByName(t, "qtt_requ", &isnull)); if(isnull) goto _end;
	orderp->qua_requ = (Datum) PG_DETOAST_DATUM(GetAttributeByName(t, "qua_requ", &isnull)); if(isnull) goto _end;
	//elog(WARNING,"ywolf_get_order: order->qua_requ='%s'",follow_DatumTxtToStr(orderp->qua_requ));
	orderp->qtt_prov = DatumGetInt64(GetAttributeByName(t, "qtt_prov", &isnull)); if(isnull) goto _end;
	orderp->qua_prov = (Datum) PG_DETOAST_DATUM(GetAttributeByName(t, "qua_prov", &isnull)); if(isnull) goto _end;
	//elog(WARNING,"ywolf_get_order: order->qua_prov='%s'",follow_DatumTxtToStr(orderp->qua_prov));
	orderp->qtt = DatumGetInt64(GetAttributeByName(t, "qtt", &isnull)); if(isnull) goto _end;
	orderp->flowr = DatumGetInt64(GetAttributeByName(t, "flowr", &isnull)); if(isnull) goto _end;

	return;
_end:
	ereport(ERROR,
					(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			   errmsg("a field is null")));	
	return;
}
static Datum ywolf_get_datum(TupleDesc tupdesc,Torder *orderp) {
        Datum       *values;
        HeapTuple    tuple;
        Datum        result;
        bool		 isNull;
         
        values = palloc(9 * sizeof(Datum));
        
        values[0] = Int32GetDatum(orderp->id);
        values[1] = orderp->own;
        values[2] = Int32GetDatum(orderp->oid);
        values[3] = Int64GetDatum(orderp->qtt_requ);
        values[4] = orderp->qua_requ;
        values[5] = Int64GetDatum(orderp->qtt_prov);
        values[6] = orderp->qua_prov;
        values[7] = Int64GetDatum(orderp->qtt);
        values[8] = Int64GetDatum(orderp->flowr);

        tuple = heap_formtuple( tupdesc, values, &isNull );

        // make the tuple into a datum 
        result = HeapTupleGetDatum(tuple);

        // clean up (this is not really necessary) 
        pfree(values);
        
        return result;
}
/* get the array of composite type yorder[]; allocates wolf and put data in wolf
call ywolf_free_w(wolf) to deallocate
*/
static void ywolf_get_w(ArrayType *awolf,Twolf **wolfp) {

	int			ndimswolf = ARR_NDIM(awolf);
	Oid			elmtype = ARR_ELEMTYPE(awolf);
	Datum		*elmsp;
	int16		elmlen;
	char		elmalign;
	bool 		elmbyval;
	int			_dim,_i;
	Twolf		*_wolf;
	
	if (ndimswolf >1) // can be 0
			ereport(ERROR,
					(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			   errmsg("the array must be monodimensional")));
	
	get_typlenbyvalalign(elmtype, &elmlen, &elmbyval, &elmalign);
	deconstruct_array(awolf, elmtype, elmlen, elmbyval, elmalign, &elmsp, NULL, &_dim);
	
	_wolf = palloc(sizeof(Twolf)+ _dim*sizeof(Torder));
	*wolfp = _wolf;
	_wolf->dim = _dim;
	_wolf->alld = elmsp;
	
	obMRange(_i,_dim) {
		ywolf_get_order(elmsp[_i],&_wolf->x[_i]);
	}
	return;
	
}
static void ywolf_free_w(Twolf *wolf) {
	pfree(wolf->alld);
	pfree(wolf);
}
/*
static Twolf *ywolf_add(Torder *order,Twolf *wolf) {
	Twolf *_wolf;
	int	_sw,_dim = (wolf->dim);

	_sw = sizeof(Twolf)+ (_dim)*sizeof(Torder);
	_wolf = palloc(_sw+ sizeof(Torder));
	memcpy(_wolf,wolf,_sw);
	_wolf->dim = _dim+1;
	memcpy(&_wolf->x[_dim],order,sizeof(Torder));
	return _wolf;	
}
*/
static Twolf *ywolf_add(Torder *order,Twolf *wolf) {
	Twolf *_wolf;
	int	_sw,_dim = (wolf->dim);

	_sw = sizeof(Twolf)+ (_dim)*sizeof(Torder);
	_wolf = palloc(_sw+ sizeof(Torder));

	_wolf->dim = _dim+1;
	_wolf->alld = wolf->alld;
	memcpy(&_wolf->x[0],order,sizeof(Torder));
	memcpy(&_wolf->x[1],&wolf->x[0],(_dim)*sizeof(Torder));
	return _wolf;	
}

/******************************************************************************
returns a set of ywolf
******************************************************************************/
typedef struct ywolf_to_lines_fctx {
		Twolf			*wolf;
		//TresChemin 		*chem;
	} ywolf_to_lines_fctx;
Datum
ywolf_to_lines(PG_FUNCTION_ARGS)
{
    FuncCallContext     *funcctx;
    int                  call_cntr;
    int                  max_calls;
    TupleDesc            tupdesc;
	Twolf				*wolf;
    ywolf_to_lines_fctx *ufctx;
        
    // stuff done only on the first call of the function 
    if (SRF_IS_FIRSTCALL())
    {
        MemoryContext   oldcontext;
        ArrayType		*awolf = PG_GETARG_ARRAYTYPE_P(0);

        // create a function context for cross-call persistence 
        funcctx = SRF_FIRSTCALL_INIT();

        // switch to memory context appropriate for multiple function calls 
        oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

		ufctx = (ywolf_to_lines_fctx *) palloc(sizeof(ywolf_to_lines_fctx));
        ywolf_get_w(awolf,&wolf);
        ufctx->wolf = wolf;

        // total number of tuples to be returned 
        funcctx->max_calls = wolf->dim;
		funcctx->user_fctx = ufctx;
		
        // Build a tuple descriptor for our result type 
        if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
            ereport(ERROR,
                    (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                     errmsg("function returning record called in context "
                            "that cannot accept type record")));

        BlessTupleDesc( tupdesc );
        funcctx->tuple_desc = tupdesc;

        MemoryContextSwitchTo(oldcontext);
    }

    // stuff done on every call of the function 
    funcctx = SRF_PERCALL_SETUP();

    call_cntr = funcctx->call_cntr;
    max_calls = funcctx->max_calls;
    tupdesc   = funcctx->tuple_desc;
    ufctx	  = funcctx->user_fctx;
    wolf	  = ufctx->wolf;

    if (call_cntr < max_calls)    // do when there is more left to send 
    {
      	Datum result;
       	result = ywolf_get_datum(tupdesc,&wolf->x[call_cntr]);
        SRF_RETURN_NEXT(funcctx, result);
    }
    else    // do when there is no more left 
    {
    	pfree(wolf);
    	pfree(ufctx);
        SRF_RETURN_DONE(funcctx);
    }
}

/******************************************************************************
returns an empty set if the flow has some qtt == 0, and otherwise set of order[.].id
******************************************************************************/
typedef struct ywolf_iterid_fctx {
		short		k;
		Twolf		*wolf;
		int32		oids[];
	} ywolf_iterid_fctx;

Datum
ywolf_iterid(PG_FUNCTION_ARGS)
{
    FuncCallContext     *funcctx;
	ywolf_iterid_fctx 	*fctx;
	Twolf				*wolf;

    // stuff done only on the first call of the function 
    if (SRF_IS_FIRSTCALL())
    {
        MemoryContext   oldcontext;
        ArrayType		*awolf = PG_GETARG_ARRAYTYPE_P(0);
        int32			_k,_dim;

        // create a function context for cross-call persistence 
        funcctx = SRF_FIRSTCALL_INIT();

        // switch to memory context appropriate for multiple function calls 
        oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

        ywolf_get_w(awolf,&wolf);
        _dim = wolf->dim;
        fctx =  (ywolf_iterid_fctx *) palloc(sizeof(ywolf_iterid_fctx) + _dim * sizeof(int32));
        funcctx->user_fctx = fctx;
		fctx->wolf = wolf;
		fctx->k = 0;

		obMRange (_k,_dim) {
			if(wolf->x[_k].qtt == 0) {
				wolf->dim = 0;
				break;
			}
			fctx->oids[_k] = wolf->x[_k].oid;		
		}
        
        MemoryContextSwitchTo(oldcontext);
    }

    // stuff done on every call of the function 
    funcctx = SRF_PERCALL_SETUP();

	fctx = funcctx->user_fctx;
	wolf = fctx->wolf;

	if (fctx->k < wolf->dim) {
		int32 _id = fctx->oids[fctx->k];
		fctx->k += 1;
		SRF_RETURN_NEXT(funcctx, Int32GetDatum(_id));
		
	} else {   // do when there is no more left 
    	ywolf_free_w(wolf);
        SRF_RETURN_DONE(funcctx);
        
    }
}
/******************************************************************************
******************************************************************************/
Datum ywolf_status(PG_FUNCTION_ARGS)
{
	ArrayType		*awolf = PG_GETARG_ARRAYTYPE_P(0);
	Twolf			*wolf;
	TresChemin 		*chem;
	Tstatusflow		status;
	
	ywolf_get_w(awolf,&wolf);
	chem = wolfc_maximum(wolf);
	status = chem->status;
	pfree(wolf);
	pfree(chem);
	
	switch(status) {
		case noloop: PG_RETURN_INT32(0);	
		case undefined: PG_RETURN_INT32(1);
		case refused: PG_RETURN_INT32(2);
		case draft: PG_RETURN_INT32(3);
		case empty: PG_RETURN_INT32(4);
		default: PG_RETURN_INT32(-1);
	}
}
Datum ywolf_is_draft(PG_FUNCTION_ARGS)
{
	ArrayType		*awolf = PG_GETARG_ARRAYTYPE_P(0);
	Twolf			*wolf;
	int 			i;
	
	ywolf_get_w(awolf,&wolf);
	obMRange(i,wolf->dim) {
		if(wolf->x[i].flowr <=0 ) 
			goto _no;
	}
	
	pfree(wolf);
	PG_RETURN_BOOL(true);				
_no:
	pfree(wolf);
	PG_RETURN_BOOL(false);
}
/******************************************************************************
CREATE FUNCTION ywolf_follow(int,yorder,yorder[])
RETURNS bool
AS 'exampleText.so'
LANGUAGE C IMMUTABLE STRICT;
returns true if yorder added to yorder[] form a path with a possible cycle at the end of yorder[]
******************************************************************************/

Datum ywolf_follow(PG_FUNCTION_ARGS)
{
	int32	maxlen = PG_GETARG_INT32(0);
	Datum	eorder = (Datum) PG_GETARG_POINTER(1);
	ArrayType		*awolf = PG_GETARG_ARRAYTYPE_P(2);
	Torder			order;
	Twolf			*wolf,*_wolfn;
	TresChemin		*_chemn;
	short			dim,i;
	Tstatusflow		status;
		
	ywolf_get_w(awolf,&wolf);
	dim = wolf->dim;
	if(dim == 0)
        ereport(ERROR,
                (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                 errmsg("ywolf_follow: wolf->dim==0 "
                        "cannot accept an empty array as third argument")));
                        	
	if((dim >= maxlen) || (dim >= FLOW_MAX_DIM))
		goto _no;
		
	ywolf_get_order(eorder,&order);
	
	// empty order
	if(order.qtt <= 0) 
		goto _no;

	// order.id not in wolf->x[.].id	
	obMRange(i,dim) {
		if(wolf->x[i].id == order.id) 
			goto _no;
	}		
	
	if(!follow_orders(&order,&wolf->x[0]))
		goto _no;
		
	// unexpected cycle
	obMRange(i,dim-1) {
		if(follow_orders(&wolf->x[i],&order)) 
			goto _no;				
	}

	// is it noloop or draft
	_wolfn = ywolf_add(&order,wolf);
	//elog(WARNING,"ywolf_follow: %s",ywolf_allToStr(_wolfn));
	_chemn = wolfc_maximum(_wolfn);
	status = _chemn->status;
	pfree(_wolfn);
	pfree(_chemn);
		
	switch(status) {
		case noloop: 
		case draft:
			break;	
		case undefined:
		case refused:
		case empty:
		default: 
			goto _no;
			break;
	}
	
	pfree(wolf);
	PG_FREE_IF_COPY(awolf, 2);
	PG_RETURN_BOOL(true); // it can be a cycle or not				
_no:
	pfree(wolf);
	PG_FREE_IF_COPY(awolf, 2);
	PG_RETURN_BOOL(false);
}
/******************************************************************************
CREATE FUNCTION ywolf_maxg(yorder[] w0,yorder[] w1)
RETURNS yorder[]
AS 'exampleText.so'
LANGUAGE C IMMUTABLE STRICT;
returns the w0 if w0>w1 otherwise w1
******************************************************************************/
Datum ywolf_maxg(PG_FUNCTION_ARGS)
{
	ArrayType		*awolf0 = PG_GETARG_ARRAYTYPE_P_COPY(0);
	ArrayType		*awolf1 = PG_GETARG_ARRAYTYPE_P_COPY(1);
	Twolf			*wolf0,*wolf1;
	short			dim,i,iprev;
	double			_rank0,_rank1;
	bool			_sup = false;
	
	ywolf_get_w(awolf0,&wolf0);
	ywolf_get_w(awolf1,&wolf1);
	
	dim = wolf0->dim;
	
	// wolf0 is empty
	if(dim == 0)
		goto _end;
		
	_rank0 = 1.0;
	iprev = dim-1;
	obMRange(i,dim) {
		if(wolf0->x[i].flowr <=0) 
			goto _end;	// wolf0 is not a draft
		_rank0 *= follow_rank(i == (dim-1),&wolf0->x[iprev],&wolf0->x[i]);
		iprev = i;				
	}	

	dim = wolf1->dim;
	
	// wolf1 is empty
	if(dim == 0)
		goto _end;
		
	_rank1 = 1.0;
	iprev = dim-1;
	obMRange(i,dim) {
		if(wolf1->x[i].flowr <=0) 
			goto _end;	// wolf1 is not a draft
		_rank1 *= follow_rank(i == (dim-1),&wolf1->x[iprev],&wolf1->x[i]);
		iprev = i;				
	}	
	
	_sup = _rank0 > _rank1;
	//elog(WARNING,"yflow_maxg: wolf0: %s",ywolf_allToStr(wolf0));
	//elog(WARNING,"yflow_maxg: wolf1: %s",ywolf_allToStr(wolf1));
	//elog(WARNING,"ywolf_maxg: rank0=%f,rank1=%f",_rank0,_rank1);
		
_end:
	pfree(wolf0);
	pfree(wolf1);
	if(_sup) {
		PG_FREE_IF_COPY(awolf1, 1);
		PG_RETURN_ARRAYTYPE_P(awolf0);
	} else {
		PG_FREE_IF_COPY(awolf0, 0);
		PG_RETURN_ARRAYTYPE_P(awolf1);
	}	
}
/******************************************************************************
CREATE FUNCTION ywolf_reduce(yorder[] w0,yorder[] w1)
RETURNS yorder[]

yflow = ywolf_reduce(yorder[] f,yorder[] fr)
	when f->x[i].oid == fr->x[j].oid 
		if f->x[i].qtt >= fr->flowr[j]
			f->x[i].qtt -= fr->flowr[j]
		else 
			error
******************************************************************************/

Datum ywolf_reduce(PG_FUNCTION_ARGS)
{
	ArrayType		*awolf0 = PG_GETARG_ARRAYTYPE_P_COPY(0);
	ArrayType		*awolf1 = PG_GETARG_ARRAYTYPE_P(1);
	int			_dim0,_dim1;
	Twolf		*_wolf0,*_wolf1;
	
	Oid			elmtype = ARR_ELEMTYPE(awolf0);
	Datum		*elmsp;
	int16		elmlen;
	char		elmalign;
	bool 		elmbyval,touched = false;	
	int 		_i0,_i1;
	
	ywolf_get_w(awolf0,&_wolf0);
	_dim0 = _wolf0->dim;
	// wolf0 is empty
	if(_dim0 == 0) 
		goto _end;
	
	ywolf_get_w(awolf1,&_wolf1);
	_dim1 = _wolf1->dim;
	// wolf1 is empty
	if(_dim1 == 0)
		goto _end;

	if (_wolf1->x[0].flowr <= 0) 
			ereport(ERROR,
					(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			   errmsg("ywolf_reduce: the flow w1 is not computed")));
			   	
	get_typlenbyvalalign(elmtype, &elmlen, &elmbyval, &elmalign);
	deconstruct_array(awolf0, elmtype, elmlen, elmbyval, elmalign, &elmsp, NULL, &_dim0);

	obMRange(_i1,_dim1) {
		obMRange(_i0,_dim0) {
			if((_wolf0->x[_i0].oid) == (_wolf1->x[_i1].oid)) {
				if((_wolf0->x[_i0].qtt) >= (_wolf1->x[_i1].flowr)) {
					_wolf0->x[_i0].qtt -= _wolf1->x[_i1].flowr;
					touched = true;	
				} else {			    		
					ereport(ERROR,
						(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
						errmsg("ywolf_reduce: the wolf is greater than available")));
				}
			}
		}
	}
	
	if(touched) {
		Datum		*_datum_out;
		bool		*_null_out;
		int         ndims = 1;
		int         dims[1] = {0};
		int         lbs[1] = {1};
		//Oid			tupType;
		//int32		tupTypmod;
		TupleDesc	tupDesc;						
		//HeapTupleHeader t = ((HeapTupleHeader) PG_DETOAST_DATUM(elmsp[0]));

		//tupType = HeapTupleHeaderGetTypeId(t);
		//tupTypmod = HeapTupleHeaderGetTypMod(t);
		//tupDesc = lookup_rowtype_tupdesc(tupType, tupTypmod); // to be released
		tupDesc = lookup_rowtype_tupdesc(elmtype, elmbyval);
										
		_datum_out = palloc(sizeof(Datum) * _dim0);
		_null_out =  palloc(sizeof(bool)  * _dim0);
		
		obMRange(_i0,_dim0) {
					_null_out[_i0] = false; 
					_datum_out[_i0] = ywolf_get_datum(tupDesc,&_wolf0->x[_i0]);
		}
		
		ReleaseTupleDesc(tupDesc);
		dims[0] = _dim0;

		// now build the array 
		awolf0 = construct_md_array(_datum_out, _null_out, ndims, dims, lbs,
					        elmtype, elmlen, elmbyval, elmalign);
	}		
_end:
	pfree(_wolf0);
	pfree(_wolf1);
	PG_FREE_IF_COPY(awolf1,1);
	PG_RETURN_ARRAYTYPE_P(awolf0);	
}

/******************************************************************************
concat yorder and yorder[]
******************************************************************************/

Datum ywolf_cat(PG_FUNCTION_ARGS)
{
	Datum			eorder = (Datum) PG_GETARG_POINTER(0);
	ArrayType		*awolf = PG_GETARG_ARRAYTYPE_P(1);
	Torder			order;
	Twolf			*wolf,*_wolfn;
	TresChemin		*_chemn;
	short			_i,_dim;
	
	ArrayType	*awolfn;
	Datum		*_datum_out;
	bool		*_null_out;
	int         ndims = 1;
	int         dims[1] = {0};
	int         lbs[1] = {1};
	TupleDesc	tupDesc;
	Oid			elmtype = ARR_ELEMTYPE(awolf);
	int16		elmlen;
	char		elmalign;
	bool 		elmbyval;
	
	
	ywolf_get_w(awolf,&wolf);
	_dim = wolf->dim;
	if(_dim == 0 || _dim >= FLOW_MAX_DIM)
        ereport(ERROR,
                (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                 errmsg("ywolf_follow: wolf->dim==0 or > MAX"
                        "cannot accept an empty array as second argument")));
		
	ywolf_get_order(eorder,&order);
	_wolfn = ywolf_add(&order,wolf);
	pfree(wolf);
	
	#ifdef GL_VERIFY
	// is it noloop or draft
	_chemn = wolfc_maximum(_wolfn);	
	if(!(_chemn->status == draft || _chemn->status == noloop))
        ereport(ERROR,
                (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                 errmsg("the path result is not noloop or draft")));
    pfree(_chemn);
    #endif
    
	_dim = _wolfn->dim;
		
	get_typlenbyvalalign(elmtype, &elmlen, &elmbyval, &elmalign);						
	tupDesc = lookup_rowtype_tupdesc(elmtype, elmbyval);
									
	_datum_out = palloc(sizeof(Datum) * _dim);
	_null_out =  palloc(sizeof(bool)  * _dim);
	
	obMRange(_i,_dim) {
				_null_out[_i] = false; 
				_datum_out[_i] = ywolf_get_datum(tupDesc,&_wolfn->x[_i]);
	}
	
	ReleaseTupleDesc(tupDesc);
	dims[0] = _dim;

	// now build the array 
	awolfn = construct_md_array(_datum_out, _null_out, ndims, dims, lbs,
				        elmtype, elmlen, elmbyval, elmalign);
	pfree(_wolfn);			        
	PG_FREE_IF_COPY(awolf, 1);		
	PG_RETURN_ARRAYTYPE_P(awolfn);	
}

/******************************************************************************
function [qtt_in,qtt_out,dim] <= ywolf_qtts(yorder[])
with: qtt_out=wolf.x[dim-1]->flowr and qtt_in=wolf.x[dim-2]->flowr
******************************************************************************/
Datum ywolf_qtts(PG_FUNCTION_ARGS)
{	
	ArrayType	*awolf = PG_GETARG_ARRAYTYPE_P(0);
	Twolf		*wolf;
	Datum	*_datum_out;
	bool	*_isnull;
	
	ArrayType  *result;
	int16       _typlen;
	bool        _typbyval;
	char        _typalign;
	int         _dims[1];
	int         _lbs[1];
	int			_dim;
	
	ywolf_get_w(awolf,&wolf);
	_dim = wolf->dim;

	if(_dim < 2)
			ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("ywolf_qtts: the dim <2 ")));
	
	_datum_out = palloc(sizeof(Datum) * 3);
	_isnull = palloc(sizeof(bool) * 3);
	_datum_out[0] = Int64GetDatum(wolf->x[_dim-2].flowr); // qtt_in
	_isnull[0] = false;
	_datum_out[1] = Int64GetDatum(wolf->x[_dim-1].flowr); // qtt_out
	_isnull[1] = false;
	_datum_out[2] = Int64GetDatum((int64)_dim); // dim
	_isnull[2] = false;

	_dims[0] = 3;
	_lbs[0] = 1;
	pfree(wolf); // not ywolf_free_w(wolf) !!
				 
	/* get required info about the INT8 */
	get_typlenbyvalalign(INT8OID, &_typlen, &_typbyval, &_typalign);

	/* now build the array */
	result = construct_md_array(_datum_out, _isnull, 1, _dims, _lbs,
		                INT8OID, _typlen, _typbyval, _typalign);
		                
	PG_FREE_IF_COPY(awolf,0);
	PG_RETURN_ARRAYTYPE_P(result);	
}


/******************************************************************************
string representation of the status
******************************************************************************/
char * ywolf_statusToStr(Tstatusflow s){
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
provides a string representation of yflow 
When internal is set, it gives complete representation of the yflow,
adding status and flowr[.]
******************************************************************************/
char *ywolf_allToStr(Twolf *wolf) {
	StringInfoData 	buf;
	int	dim = wolf->dim;
	int	i;

	initStringInfo(&buf);

	appendStringInfoChar(&buf, '[');
	if(dim >0) {
		for (i = 0; i < dim; i++)
		{	
			Torder *s = &wolf->x[i];
		
			if(i != 0) appendStringInfoChar(&buf, ',');

			appendStringInfo(&buf, "(%i, ", s->id);
			appendStringInfo(&buf, "%s, ", follow_DatumTxtToStr(s->own));
			appendStringInfo(&buf, "%i, ", s->oid);
			
			appendStringInfo(&buf, INT64_FORMAT ", ", s->qtt_requ);
			appendStringInfo(&buf, "%s, ", follow_qua_requToStr(s->qua_requ));
			
			appendStringInfo(&buf, INT64_FORMAT ", ", s->qtt_prov);
			appendStringInfo(&buf, "%s, ", follow_qua_provToStr(s->qua_prov));
			
			appendStringInfo(&buf,INT64_FORMAT ", ",s->qtt);
			appendStringInfo(&buf,INT64_FORMAT ") ",s->flowr);
		}
	}
	appendStringInfoChar(&buf, ']');
	
	return buf.data;
}




