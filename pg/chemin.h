/* $Id: chemin.h 22 2010-01-15 16:00:22Z olivier.chaussavoine $ */
#ifndef defined__chemin_h
#define defined__chemin_h
#include "openbarter.h"
#include <point.h>
#include "getdraft.h"

int ob_chemin_parcours_arriere(DB_ENV *envt,ob_tNoeud *pivot,
		ob_tStock *stockPivot,bool deposOffre,ob_tId *versionSg);
int _parcours_arriere(DB_ENV *envt,ob_tNoeud *pivot,ob_tStock *stockPivot,
		bool deposOffre,ob_tId *versionSg,int* pnbSrc);
int _parcours_avant(ob_tPrivateTemp *privt,ob_tNoeud *pivot,
		int i_graph,int *nbSource);
void ob_chemin_get_commit_init(ob_getdraft_ctx *ctx);
int ob_chemin_get_commit(ob_getdraft_ctx *ctx);

#endif // defined__chemin_h

