#include "postgres.h"

#include <math.h>

#include "lib/stringinfo.h"
#include "libpq/pqformat.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h" 
#include "catalog/pg_type.h" 
#include "funcapi.h"
#include "utils/typcache.h" // lookup_rowtype_tupdesc() 

#include "wolf.h"

/******************************************************************************
******************************************************************************/
void yorder_get_order(Datum eorder,Torder *orderp) {

	bool isnull;
	HeapTupleHeader tuple = ((HeapTupleHeader) PG_DETOAST_DATUM(eorder));
	Oid			tupType;
	int32		tupTypmod;
	TupleDesc	tupDesc;
	HeapTupleData tmptup;

	tupType = HeapTupleHeaderGetTypeId(tuple);
	tupTypmod = HeapTupleHeaderGetTypMod(tuple);
	tupDesc = lookup_rowtype_tupdesc(tupType, tupTypmod);

	tmptup.t_len = HeapTupleHeaderGetDatumLength(tuple);
	ItemPointerSetInvalid(&(tmptup.t_self));
	tmptup.t_tableOid = InvalidOid;
	tmptup.t_data = tuple;

	orderp->type = DatumGetInt32(heap_getattr(&tmptup,1,tupDesc,&isnull)); 	
	if(isnull) 
		ereport(ERROR,
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			   errmsg("the field type is null in yorder_get_order")));

	if(!ORDER_TYPE_IS_VALID(orderp->type)) 
		ereport(ERROR,
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			   errmsg("order type incorrect in yorder_get_order")));
			    
	orderp->id = DatumGetInt32(heap_getattr(&tmptup,2,tupDesc,&isnull)); 
	if(isnull) 
		ereport(ERROR,
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			   errmsg("the field id is null in yorder_get_order")));

	orderp->own = DatumGetInt32(heap_getattr(&tmptup,3,tupDesc,&isnull)); 
		if(isnull) 
		ereport(ERROR,
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			   errmsg("the field own is null in yorder_get_order")));

	orderp->oid = DatumGetInt32(heap_getattr(&tmptup,4,tupDesc,&isnull)); 	
	if(isnull) 
		ereport(ERROR,
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			   errmsg("the field oid is null in yorder_get_order")));

	orderp->qtt_requ = DatumGetInt64(heap_getattr(&tmptup,5,tupDesc,&isnull)); 	
	if(isnull) 
		ereport(ERROR,
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			   errmsg("the field qtt_requ is null in yorder_get_order")));

	orderp->qua_requ = (Datum) PG_DETOAST_DATUM(heap_getattr(&tmptup,6,tupDesc,&isnull)); 	
	if(isnull) 
		ereport(ERROR,
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			   errmsg("the field qua_requ is null in yorder_get_order")));

	orderp->qtt_prov = DatumGetInt64(heap_getattr(&tmptup,7,tupDesc,&isnull)); 	
	if(isnull) 
		ereport(ERROR,
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			   errmsg("the field qtt_prov is null in yorder_get_order")));

	orderp->qua_prov = (Datum) PG_DETOAST_DATUM(heap_getattr(&tmptup,8,tupDesc,&isnull)); 	
	if(isnull) 
		ereport(ERROR,
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			   errmsg("the field qua_prov is null in yorder_get_order")));

	orderp->qtt = DatumGetInt64(heap_getattr(&tmptup,9,tupDesc,&isnull)); 	
	if(isnull) 
		ereport(ERROR,
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			   errmsg("the field qtt is null in yorder_get_order")));
	
	ReleaseTupleDesc(tupDesc);
	
	return;
}

/******************************************************************************
 * converts Torder to Tfl
 *****************************************************************************/
void yorder_to_fl(Torder *o,Tfl *fl) {
	fl->type = o->type;
	fl->id = o->id;
	fl->oid = o->oid;
	fl->own = o->own;
	fl->qtt_requ = o->qtt_requ;
	fl->qtt_prov = o->qtt_prov;
	fl->qtt = o->qtt;
	fl->proba = 0.0;
}

/******************************************************************************
 * returns true when orders prev and next match
 testé avec yorder.c
 quality are prefixed with integers.
 when the integer of qua_requ is defined, then comparison with qua_prov is limited to this length 
 *****************************************************************************/
#define IDEMTXT(a,lena,b,lenb,res) \
do { \
	if(lena != lenb) res = false; \
	else { \
		if(memcmp(a,b,lena) == 0) res = true; \
		else res = false; \
	} \
} while(0)

#define GETPREFIX(rk,ra,rlen) \
do { \
	rk = 0; \
	if(rlen != 0) do { \
	    if ('0' <= *ra && *ra <= '9' ) { \
            rk *=10; \
            rk += (int32)(*ra -'0'); \
            ra +=1; rlen -=1; \
	    } else break; \
	} while(rlen > 0); \
} while(0)

bool yorder_checktxt(Datum qua) {
	char *_p = VARDATA(qua);
	int32 _l = VARSIZE(qua)-VARHDRSZ;
	int32 _k;
	int32 _res;
	if (_l >= 1) _res |= 1; // not empty
	
	GETPREFIX(_k,_p,_l);
	if (_k >= 1) _res |= 2; // prefix not empty
	if (_l >= 1) _res |= 4; // suffix not empty
	return _res;
}

bool yorder_match(Torder *prev,Torder *next) {

	bool _res = true;
	Datum _qprov = prev->qua_prov;
	Datum _qrequ = next->qua_requ;
	char *_pv = VARDATA(_qprov);
	char *_pu = VARDATA(_qrequ);
	int32 _lv = VARSIZE(_qprov)-VARHDRSZ;
	int32 _lu = VARSIZE(_qrequ)-VARHDRSZ;
	int32 _rku,_rkv,_l;
	
	_l = (_lu < _lv)?_lu:_lv;
    if(_l <1) {
		ereport(ERROR,
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			   errmsg("a quality is empty")));
    }  
    
    // required
    GETPREFIX(_rku,_pu,_lu);
    if(_lu == 0) // required cath all
        return true;
        
    if(_rku == 0 || _rku > _lu) // _rku undefined
        _rku = _lu; 
       
    // provided
    GETPREFIX(_rkv,_pv,_lv);
    if(_lv == 0) // provide nothing 
        return false;
    
    if(_rku < _lv) // limit comparison length
        _lv = _rku;
    IDEMTXT(_pu,_rku,_pv,_lv,_res);
    return _res;
}

/******************************************************************************
******************************************************************************/
double yorder_match_proba(Torder *prev,Torder *next) {
	
	if(yorder_match(prev,next)) return 1.0;
	return 0.0;
}

