#include <postgres.h>
#include "catalog/pg_type.h"
#include "fmgr.h"
#include "funcapi.h"
#include "executor/spi.h"
#include "lib/stringinfo.h"
#include "miscadmin.h"
#include "utils/builtins.h"
#include "utils/guc.h"
#include "utils/lsyscache.h"
#include "openbarter.h"
#include "iternoeud.h"

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

#define _logZone(mem) logZone(&mem,sizeof(mem))

ob_tGlob openbarter_g;
/* a compiler avec utils pour _SPI_init et iternoeud 
initialiser avec testiternoeud.sql */
Datum ob_iternoeud_getstock_test(PG_FUNCTION_ARGS);

Datum ob_iternoeud_next_test(PG_FUNCTION_ARGS);
Datum ob_iternoeud_next_test1(PG_FUNCTION_ARGS);
void		_PG_init(void);
void		_PG_fini(void);

static void logZone(void *mem,size_t len);


static void logZone(void *mem,size_t len) {
	size_t i = 0,off;
	int j = 0,l = len>>2;
	int *ptr = mem;
	char buf[1000],*buf1;
	size_t k = 1000;

	buf1 = buf;*buf1 = 0;
	snprintf(buf1,k,"%08X,%i :",(int)ptr,((int)ptr) & (sizeof(int)-1));
	off = strlen(buf1);
	elog(INFO,"%s",buf);
	buf1 = buf;
	k = 1000;
	j = 0;
	while(i<l) {
		snprintf(buf1,k,"%08X ",ptr[i]);
		off = strlen(buf1);
		buf1 += off;
		k -= off;
		if (j == 7) {
			elog(INFO,"%s",buf);
			buf1 = buf;
			k = 1000;
			j = 0;
		} else j +=1;
		i +=1;
	}
	if(j) elog(INFO,"%s",buf);
	return;
}

/* usage: 
SELECT ob_iternoeud_getStock_test(1)  affiche le stock 1
SELECT ob_iternoeud_getStock_test(2)  affiche le stock 2
SELECT ob_iternoeud_getStock_test(100)  affiche qu'il n'y a pas de stock
*/
PG_FUNCTION_INFO_V1(ob_iternoeud_getstock_test);
Datum ob_iternoeud_getstock_test(PG_FUNCTION_ARGS) {
	int64 p1 = PG_GETARG_INT64(0);
	ob_tStock stock;
	int ret;
	SPI_connect();
	
	stock.sid = p1;
	ret = ob_iternoeud_getStock(&stock);
	
	if(ret == DB_NOTFOUND) {
		elog(INFO, "stock %i not found",(int)p1);
		goto fin;
	} else if(ret == 0) { // found
		elog(INFO, "stock %i found",(int)p1);
		_logZone(stock);
	} else {
		elog(INFO, "error %i",ret);
		goto fin;
	}
fin:
	SPI_finish();
	PG_RETURN_INT32(ret);

}
/* usage: 
SELECT ob_iternoeud_next_test(1,1)  affiche la liste
*/
PG_FUNCTION_INFO_V1(ob_iternoeud_next_test);
Datum ob_iternoeud_next_test(PG_FUNCTION_ARGS) {
	int64 p1 = PG_GETARG_INT64(0);
	int64 p2 = PG_GETARG_INT64(1);
	Portal portal_noeuds;
	ob_tNoeud noeud;
	ob_tId nid;
	int ret;
	int cnt = 0;
	
	SPI_connect();

	portal_noeuds = ob_iternoeud_GetPortal(p1,p2); 
	do {
		ret = ob_iternoeud_Next(portal_noeuds,&nid,&noeud);
		if(ret) continue;
		_logZone(nid);
		_logZone(noeud);
		cnt +=1;
	} while (ret == 0);
	if (ret == DB_NOTFOUND) ret = 0;
	if(ret) elog(ERROR, "%i error",ret);
	else elog(INFO, "%i nodes found",cnt);
	SPI_finish();
	PG_RETURN_INT32(ret);
}
