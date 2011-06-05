/* $Id: flux.h 22 2010-01-15 16:00:22Z olivier.chaussavoine $ */
#ifndef defined__flux_h
#define defined__flux_h
#include "openbarter.h"

// #include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <syslog.h>
// #include <ut.h>

/* #define obMTRACE(err) ob_flux_log(__FILE__,__LINE__,err)
defined in svn_test_main */

// chemin->cflags
#define ob_flux_CLastIgnore 	1
#define ob_flux_CFast		(ob_flux_CLastIgnore <<1)
#define ob_flux_CFlowDefined	(ob_flux_CLastIgnore <<2)
 
#define ob_flux_McheminGetOmega(pchemin) (pchemin)->prodOmega

#define ob_flux_MMinCYCLE(i) ((((int) i )< obCMAXCYCLE)? ((int) i ) : obCMAXCYCLE )    
#define ob_flux_McheminGetNbNode(pchemin)  ob_flux_MMinCYCLE((pchemin)->nbNoeud)
#define ob_flux_McheminGetNbStock(pchemin) ob_flux_MMinCYCLE((pchemin)->nbStock)
#define ob_flux_McheminGetNbOwn(pchemin)   ob_flux_MMinCYCLE((pchemin)->nbOwn)

// points to the place where the first stock node should be inserted
#define ob_flux_McheminGetAdrFirstStock(pchemin) &((pchemin)->no[0].stock)


//#define ob_flux_MVoirDBT(a) ob_flux_voirDBT(stdout,a,1);

void 		ob_flux_cheminVider(ob_tChemin *pchemin, const char cflags);
int 		ob_flux_cheminAjouterNoeud(ob_tChemin *pchemin,
				const ob_tStock *pstock,const ob_tNoeud *pnoeud,ob_tLoop *loop);
int 		ob_flux_fluxMaximum(ob_tChemin *pchemin);
int 		ob_flux_cheminError(ob_tChemin *pchemin);
double 		ob_flux_cheminGetOmega(ob_tChemin *pchemin);
int 		ob_flux_cheminGetNbNode(ob_tChemin *pchemin);
ob_tQtt		ob_flux_cheminGetQtt(ob_tChemin *pchemin,int io);
int 		ob_flux_GetTabStocks(ob_tChemin *pchemin, ob_tStock *tabStocks,int *nbStock);
int 		ob_flux_cheminGetNbStock(ob_tChemin *pchemin);
int 		ob_flux_cheminGetNbOwn(ob_tChemin *pchemin);
ob_tNoeud 	*ob_flux_cheminGetAdrNoeud(ob_tChemin *pchemin,int io);
ob_tStock 	*ob_flux_cheminGetAdrStockNode(ob_tChemin *pchemin,int io);
ob_tStock 	*ob_flux_cheminGetAdrStockLastNode(ob_tChemin *pchemin);
int 		ob_flux_cheminGetSindex(ob_tChemin *pchemin,int io);
ob_tOwnId 	*ob_flux_cheminGetNewOwn(ob_tChemin *chemin,int io);
ob_tOwnId 	*ob_flux_cheminGetOwn(ob_tChemin *pchemin,int iw);
size_t 		ob_flux_cheminGetSize(ob_tChemin *pchemin);

void ob_flux_voirChemin(FILE *stream,ob_tChemin *pchemin,int flags);
void ob_flux_voirQtt(FILE *stream,ob_tQtt *pqtt,int flags);
void ob_flux_voirDBT(FILE *stream,int64 *dbt,int flags);
int ob_flux_makeMessage(ob_tMsg *msg,const char *fmt, ...);
void ob_flux_writeFile(ob_tMsg *msg);
int ob_flux_svoirChemin(ob_tMsg *msg,ob_tChemin *pchemin,int flags);
int ob_flux_svoirQtt(ob_tMsg *msg,ob_tQtt *pqtt,int flags);
int ob_flux_svoirDBT(ob_tMsg *msg,int64 *dbt,int flags);

#define ob_flux_MVoirDBT(a) ob_flux_voirDBT(stdout,a,1);

#endif // defined__flux_h
