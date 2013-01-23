#include "postgres.h"

#include <math.h>

#include "lib/stringinfo.h"
#include "libpq/pqformat.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h" 
#include "catalog/pg_type.h" 
#include "funcapi.h" 

#include "wolf.h"

/******************************************************************************
******************************************************************************/
void yorder_get_order(Datum eorder,Torder *orderp) {

	bool isnull;
	HeapTupleHeader t = ((HeapTupleHeader) PG_DETOAST_DATUM(eorder));
	
	orderp->id = DatumGetInt32(GetAttributeByName(t, "id", &isnull)); if(isnull) goto _end;
	orderp->own = DatumGetInt32(GetAttributeByName(t, "own", &isnull)); if(isnull) goto _end;
	orderp->oid = DatumGetInt32(GetAttributeByName(t, "oid", &isnull)); if(isnull) goto _end;
	orderp->qtt_requ = DatumGetInt64(GetAttributeByName(t, "qtt_requ", &isnull)); if(isnull) goto _end;
	orderp->qua_requ = (Datum) PG_DETOAST_DATUM(GetAttributeByName(t, "qua_requ", &isnull)); if(isnull) goto _end;
	orderp->qtt_prov = DatumGetInt64(GetAttributeByName(t, "qtt_prov", &isnull)); if(isnull) goto _end;
	orderp->qua_prov = (Datum) PG_DETOAST_DATUM(GetAttributeByName(t, "qua_prov", &isnull)); if(isnull) goto _end;
	//elog(WARNING,"ywolf_get_order: order->qua_prov='%s'",follow_DatumTxtToStr(orderp->qua_prov));
	orderp->qtt = DatumGetInt64(GetAttributeByName(t, "qtt", &isnull)); if(isnull) goto _end;

	return;
_end:
	ereport(ERROR,
					(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			   errmsg("a field is null")));	
	return;
}

/******************************************************************************
 * converts Torder to Tfl
 *****************************************************************************/
void yorder_to_fl(Torder *o,Tfl *fl) {
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
/*
	#ifdef ACTIVATE_DISTANCE
	if( prev->dist > earth_distance_internal(&prev->pos_prov,&prev->pos_requ)) 
		return false;
	#endif
	#ifdef ACTIVATE_FULLTEXT	
	return tsquery_match_vq(_qprov,_qrequ);
	#else
*/
	IDEMTXT(_qprov,_qrequ,_res);
	// elog(WARNING,"_qprov: %s,_qrequ: %s,_res: %c",follow_DatumTxtToStr(_qprov),follow_DatumTxtToStr(_qrequ),_res?'t':'f');
	return _res;
//	#endif
}

/******************************************************************************
******************************************************************************/
double yorder_match_proba(Torder *prev,Torder *next) {
	
	if(yorder_match(prev,next)) return 1.0;
	return 0.0;
}

