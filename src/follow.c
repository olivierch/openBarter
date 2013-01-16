#include "postgres.h" 
#include "wolf.h"

/******************************************************************************
 * returns true when orders prev and next match
 *****************************************************************************/
bool follow_orders(Torder *prev,Torder *next) {
	bool _res = false;
	Datum _qprov = prev->qua_prov;
	Datum _qrequ = next->qua_requ;

	#ifdef ACTIVATE_DISTANCE
	if( prev->dist > earth_distance_internal(&prev->pos_prov,&prev->pos_requ)) 
		return false;
	#endif
	#ifdef ACTIVATE_FULLTEXT	
	return tsquery_match_vq(_qprov,_qrequ);
	#else
	IDEMTXT(_qprov,_qrequ,_res);
	// elog(WARNING,"_qprov: %s,_qrequ: %s,_res: %c",follow_DatumTxtToStr(_qprov),follow_DatumTxtToStr(_qrequ),_res?'t':'f');
	return _res;
	#endif
}

/******************************************************************************
 * returns a double that is omega when qualities are matching
 * but less when qualities are less matching
 *****************************************************************************/
double follow_rank(bool end,Torder *prev,Torder *next) {
	double _omega;
	
	if(next->qtt_requ == 0) {
		// sanity check
		if(!end)
			ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("yflow_rank(): wolf->x[_dim-1].qtt_requ == 0")));
		_omega = 1.0;
	} else 
		_omega = ((double) next->qtt_prov)/((double) next->qtt_requ);
		
	// TODO intéger le matching entre prev et next
	// see backend/utils/adt/tsrank.c
	return _omega;
}
/******************************************************************************
 * string representation of a text inside a datum 
 *****************************************************************************/
char *follow_DatumTxtToStr(Datum d) {
	char *_res;
	Datum _d = d;
	//elog(WARNING,"varsize:%i",VARSIZE(d));
	DATUM_TO_STR(_d,_res);
	return _res;
} 
/******************************************************************************
 * string representation of a qua_requ inside a datum 
 *****************************************************************************/
char *follow_qua_requToStr(Datum d) {
	char *_res;
	Datum _d = d;
	
	#ifdef ACTIVATE_FULLTEXT
	_d = tsqueryout(_d);
	#endif
	DATUM_TO_STR(_d,_res);
	
	return _res;
} 
/******************************************************************************
 * string representation of a qua_prov inside a datum 
 *****************************************************************************/
char *follow_qua_provToStr(Datum d) {
	char *_res;
	Datum _d = d;
	
	#ifdef ACTIVATE_FULLTEXT
	_d = tsvectorout(_d);
	#endif
	DATUM_TO_STR(_d,_res);
	return _res;
} 



