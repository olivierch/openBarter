/******************************************************************************
  This file contains routines that can be bound to a Postgres backend and
  called by the backend in the process of processing queries.  The calling
  format for these routines is dictated by Postgres architecture.
******************************************************************************/
#include "postgres.h"
/*
#include <math.h>

#include "lib/stringinfo.h"
#include "libpq/pqformat.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h" 
#include "catalog/pg_type.h" 
#include "funcapi.h" 
*/

#include "flowdata.h"

Tflow *flowm_copy(Tflow *f) {
	Tflow *g;
	int32 sb = f->vl_len_;
	
	g = palloc(sb);
	memcpy(g,f,sb);
	return g;
}

Tflow *flowm_init(void) {
	Tflow *f;
	int32 sb = offsetof(Tflow,x);
	
	f = palloc0(sb);
	f->dim = 0;
	SET_VARSIZE(f, sb);
	return f;
}
/* extends the flow using the same memory space
does not test if o.id belongs to the flow
*/

Tflow *flowm_extends(Torder *o,Tflow *f, bool before) {

	short dim = f->dim;
	size_t sg,sf = offsetof(Tflow,x) + dim * sizeof(Torder);
	Tflow *g;

	sg = sf+sizeof(Torder);
	g = repalloc(f,sg);
		
	if(before) {
		memcpy(&g->x[1],&f->x[0],dim*sizeof(Torder));
		memcpy(&g->x[0],o,sizeof(Torder));
	} else {	
		memcpy(&g->x[dim],o,sizeof(Torder));
	}
	g->dim = dim+1;
	SET_VARSIZE(g, sg);

	return g;	
}
/* same as flowm_extends, but provides a new copy */
Tflow *flowm_cextends(Torder *o,Tflow *f, bool before) {

	short dim = f->dim;
	size_t sg,sf = offsetof(Tflow,x) + dim * sizeof(Torder);
	Tflow *g;

	sg = sf+sizeof(Torder);
	g = palloc(sg);
	
	if(before) {
		memcpy(g,f,offsetof(Tflow,x));
		memcpy(&g->x[0],o,sizeof(Torder));
		memcpy(&g->x[1],&f->x[0],dim*sizeof(Torder));
	} else {
		memcpy(g,f,sf);	
		memcpy(&g->x[dim],o,sizeof(Torder));
	}
	
	g->dim = dim+1;
	SET_VARSIZE(g, sg);
	
	return g;	
}

/***************************************************************************************************

IDEES
*****

Pour ne pas encombrer la base avec des ordres souvent refusés:

1- A chaque mouvement inscrit, on incrémente un compteur Q pour le couple (np,nr)
2- Au moment ou un ordre est déposé, on mémorise avec lui la position P du compteur Q,
3- On invalide les ordres dont P+MAXTRY < Q, avec MAXTRY = 100 défini dans tconst
4- l'opération 3) est exécutée 1 fois chaque fois que PERIOD_INVALIDATE =10 ordres ont été déposés.

Ainsi, on permet à chaque offre d'être mis en concurrence MAXTRY fois sans pénaliser les couple (np,nr) plus rares. Celà suppose que tous les cas sont parcourus, ce qui n'est pas le cas.

***************************************************************************************************/

