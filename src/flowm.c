/******************************************************************************
  This file contains low level routines used by yflow.c and yflowparse.y
******************************************************************************/
#include "postgres.h"
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



