/* $Id: chemin.h 22 2010-01-15 16:00:22Z olivier.chaussavoine $ */
#ifndef defined__chemin_h
#define defined__chemin_h
#include "openbarter.h"
#include <point.h>
#include "getdraft.h"
int ob_chemin_faire_accords( DB_ENV *env, DB_TXN *txn,char *pathDbTemp, ob_tId *versionSg,
	ob_tNoeud *pivot, int *nbAccord, ob_tAccord **paccords);
int ob_chemin_parcours_arriere(DB_ENV *envt,DB_TXN *txn,int *nblayer);

int ob_chemin_get_draft_init(ob_getdraft_ctx *ctx);
int ob_chemin_get_draft_next(ob_getdraft_ctx *ctx);
#endif // defined__chemin_h

