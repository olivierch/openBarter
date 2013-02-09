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

	orderp->type = DatumGetInt32(heap_getattr(&tmptup,1,tupDesc,&isnull)); if(isnull) goto _end;
	if(!ORDER_TYPE_IS_VALID(orderp->type)) 
		ereport(ERROR,
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			   errmsg("order type incorrect in yorder_get_order"))); 
	orderp->id = DatumGetInt32(heap_getattr(&tmptup,2,tupDesc,&isnull)); if(isnull) goto _end;
	orderp->own = DatumGetInt32(heap_getattr(&tmptup,3,tupDesc,&isnull)); if(isnull) goto _end;
	orderp->oid = DatumGetInt32(heap_getattr(&tmptup,4,tupDesc,&isnull)); if(isnull) goto _end;
	orderp->qtt_requ = DatumGetInt64(heap_getattr(&tmptup,5,tupDesc,&isnull)); if(isnull) goto _end;
	orderp->qua_requ = (Datum) PG_DETOAST_DATUM(heap_getattr(&tmptup,6,tupDesc,&isnull)); if(isnull) goto _end;
	orderp->qtt_prov = DatumGetInt64(heap_getattr(&tmptup,7,tupDesc,&isnull)); if(isnull) goto _end;
	orderp->qua_prov = (Datum) PG_DETOAST_DATUM(heap_getattr(&tmptup,8,tupDesc,&isnull)); if(isnull) goto _end;
	orderp->qtt = DatumGetInt64(heap_getattr(&tmptup,9,tupDesc,&isnull)); if(isnull) goto _end;
	
	ReleaseTupleDesc(tupDesc);
	
	return;
_end:
	ereport(ERROR,
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			   errmsg("a field is null in yorder_get_order")));	
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
 *****************************************************************************/
bool yorder_match(Torder *prev,Torder *next) {
	bool _res = false;
	Datum _qprov = prev->qua_prov;
	Datum _qrequ = next->qua_requ;

	IDEMTXT(_qprov,_qrequ,_res);
	// elog(WARNING,"_qprov: %s,_qrequ: %s,_res: %c",follow_DatumTxtToStr(_qprov),follow_DatumTxtToStr(_qrequ),_res?'t':'f');
	return _res;
}

/******************************************************************************
******************************************************************************/
double yorder_match_proba(Torder *prev,Torder *next) {
	
	if(yorder_match(prev,next)) return 1.0;
	return 0.0;
}

