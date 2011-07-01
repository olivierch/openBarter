/*
 * itenoeud.h
 *
 //~ *  Created on: 16 déc. 2010
 *      Author: olivier
 */
#ifndef defined__iternoeud_h
#define defined__iternoeud_h
/*
#include <postgres.h>
#include "openbarter.h" */

void		_PG_init(void);
void		_PG_fini(void);
int ob_iternoeud_getStock(ob_tStock *stock);
Portal ob_iternoeud_GetPortalA(DB_ENV *envt,ob_tId yoid,ob_tId nr,int limit);
int ob_iternoeud_NextA(ob_tPortal portal,ob_tId *Xoid,ob_tNoeud *offreX,ob_tStock *stock);
int ob_iternoeud_put_stocktemp3(DB_ENV *envt,ob_tStock *pstock);

int ob_iternoeud_getTupleDesc(const char *table,TupleDesc *ptupdesc);
Oid ob_iternoeud_SPI_gettypeid(const TupleDesc rowdesc, const char * colname);

/* this macro ob_iternoeud_getBinValue supposes the following variables exist: row,tupdesc,bool isnull
and the label err exists.
 */
#define ob_iternoeud_getBinValue(dst,indice,type) \
	datum = SPI_getbinval(row, tupdesc, indice, &isnull); \
	if(SPI_result == SPI_ERROR_NOATTRIBUTE || isnull) { \
		elog( ERROR,"pgGetBinValue: failed" ); \
		goto err; \
	} \
	if(isnull) { \
		elog( ERROR,"pgGetBinValue: returned null value" ); \
		goto err; \
	} \
	if(sizeof(type) > sizeof(Datum)) dst = *((type*)datum); \
	else if(sizeof(type) <= sizeof(Datum)) dst = (type) datum; \
	else { \
		elog( ERROR,"pgGetBinValue: failed for %i",indice ); \
		goto err; \
	}

#endif
