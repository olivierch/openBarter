#ifndef defined__dbe_h
#define defined__dbe_h
#include "openbarter.h"

int ob_dbe_dircreate(char * path);

void ob_dbe_resetStock(ob_tStock *pstock);
void ob_dbe_resetNoeud(ob_tNoeud *pnoeud);
void ob_dbe_resetFleche(ob_tFleche *pfleche);
void ob_dbe_resetTrait(ob_tTrait *ptrait);
void ob_dbe_resetMarqueOffre(ob_tMarqueOffre *pmo);

int ob_dbe_openEnvTemp(DB_ENV **penvt);
int ob_dbe_resetEnvTemp(DB_ENV **penvt);
int ob_dbe_closeEnvTemp(DB_ENV *envt);

// 1<<16 256K, cache 1<<24 soit 16 Mo
#define ob_dbe_CCACHESIZE (1<<21)	// cache durable
// 32 Mo
#define ob_dbe_CCACHESIZETEMP (1<<25) // cache temporaire

#endif // defined__dbe_h







