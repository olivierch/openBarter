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
#include "access/relscan.h" // HeapTupleHeaderGetTypeId

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
	BOX *p;

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

	//orderp->qua_requ = (HStore *) PG_DETOAST_DATUM(heap_getattr(&tmptup,6,tupDesc,&isnull)); 	
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

	//orderp->qua_prov = (HStore *) PG_DETOAST_DATUM(heap_getattr(&tmptup,8,tupDesc,&isnull)); 	
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

 	// pos_requ box,
    p = DatumGetBoxP(heap_getattr(&tmptup,10,tupDesc,&isnull)); 	
    if(isnull) 
		ereport(ERROR,
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			   errmsg("the field pos_requ is null in yorder_get_order")));
	
	GL_CHECK_BOX_S0(p);		   
    orderp->pos_requ.x = p->low.x;orderp->pos_requ.y = p->low.y; 
				   
    // pos_prov box,
    p = DatumGetBoxP(heap_getattr(&tmptup,11,tupDesc,&isnull)); 
    if(isnull) 
		ereport(ERROR,
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			   errmsg("the field pos_prov is null in yorder_get_order")));
			   
    GL_CHECK_BOX_S0(p);
    orderp->pos_prov.x = p->low.x;orderp->pos_prov.y = p->low.y; 
    
	// dist flat
	orderp->dist = DatumGetFloat8(heap_getattr(&tmptup,12,tupDesc,&isnull)); 
	if(isnull) 
		ereport(ERROR,
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			   errmsg("the field dist is null in yorder_get_order")));
			   	
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

#define GETPREFIX2(rk,p,rlen) \
do { \
	rk = 0; \
	while('*' == *p) { \
        rk = 1; \
        p += 1; rlen -= 1; \
	} ; \
} while(0)

bool yorder_checktxt(Datum text) {
	char *_p = VARDATA(text);
	int32 _l = VARSIZE(text)-VARHDRSZ;
	int32 _k;
	int32 _res = 0;
	
	if (_l >= 1) _res |= TEXT_NOT_EMPTY;
	
	GETPREFIX2(_k,_p,_l);
	
	if (_k >= 1) _res |= TEXT_PREFIX_NOT_EMPTY;
	if (_l >= 1) _res |= TEXT_SUFFIX_NOT_EMPTY;
	return _res;
}

/******************************************************************************
 * yorder_match(prov yorder,requ yorder)
 *****************************************************************************/

bool yorder_match(Torder *prev,Torder *next) {
	//HStore *_qprov = prev->qua_prov; 
	//HStore *_qrequ = next->qua_requ;
	Datum _qprov = prev->qua_prov; 
	Datum _qrequ = next->qua_requ;
	/*
	if( (prev->dist!= 0.0) && (prev->dist < earth_points_distance( &prev->pos_prov, &next->pos_requ))) {
		// elog(WARNING,"prev->dist %f < %f",prev->dist,earth_distance_internal(&prev->pos_prov,&next->pos_requ));
		return false;
	} */
	if(earth_match_position(prev->dist,&prev->pos_prov,&next->pos_requ))
	    return yorder_match_quality(_qprov,_qrequ);
	else return false;
}

/******************************************************************************
 * bool yorder_match_quality(HStore *qprov, HStore *tmpl): qprov.keys contains tmpl.keys ?
 *****************************************************************************/
/*bool yorder_match_quality(HStore *qprov, HStore *tmpl)
{
	bool		res = true;
	HEntry	   *te = HSARRPTR(tmpl);
	char	   *tstr = HSSTRPTR(tmpl);
	int			tcount = HS_COUNT(tmpl);
	int			lastidx = 0;
	int			i;



	for (i = 0; res && i < tcount; ++i)
	{
		int			idx = hstoreFindKey(qprov, &lastidx,
									  HS_KEY(te, tstr, i), HS_KEYLEN(te, i));

		if (idx < 0) {
			res = false;
			break;
		}
	}

	return(res);
}*/

bool yorder_match_quality(Datum qprov,Datum qrequ) {
	bool _res = true;
	//Datum _qprov = prev->qua_prov;
	//Datum _qrequ = next->qua_requ;
	char *_pv = VARDATA(qprov);
	char *_pu = VARDATA(qrequ);
	int32 _lv = VARSIZE(qprov)-VARHDRSZ;
	int32 _lu = VARSIZE(qrequ)-VARHDRSZ;
	int32 _l,_k;
	
	_l = (_lu < _lv)?_lu:_lv;
    if(_l <1) {
		ereport(ERROR,
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			   errmsg("a quality is empty")));
    }  
    
    // if the qlt required starts with '*'
    GETPREFIX2(_k,_pu,_lu);
    if(_k != 0)
        // limit the comparison length of quality provided
        if(_lv > _lu)
            _lv = _lu;
    /*    
    if(_pu[0] == '*') {
        _pu +=1;
        _lu -=1;
        // limit the comparison length of quality provided
        if(_lv > _lu)
            _lv = _lu;
    } */

    IDEMTXT(_pu,_lu,_pv,_lv,_res);
    return _res;
}

/******************************************************************************
******************************************************************************/
double yorder_match_proba(Torder *prev,Torder *next) {
	
	if(yorder_match(prev,next)) return 1.0;
	return 0.0;
}

