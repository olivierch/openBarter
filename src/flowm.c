/******************************************************************************
  This file contains low level routines used by yflow.c and yflowparse.y
******************************************************************************/
#include "postgres.h"
#include "wolf.h"

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
	f->status = notcomputed;
	SET_VARSIZE(f, sb);
	return f;
}
/* extends the flow using the same memory space
does not test if o.id belongs to the flow
*/


Tflow *flowm_extends(Tfl *o,Tflow *f, bool before) {

	short dim = f->dim;
	size_t sg,sf = offsetof(Tflow,x) + dim * sizeof(Tfl);
	Tflow *g;

	sg = sf+sizeof(Tfl);
	g = repalloc(f,sg);
		
	if(before) {
		memcpy(&g->x[1],&f->x[0],dim*sizeof(Tfl));
		memcpy(&g->x[0],o,sizeof(Tfl));
	} else {	
		memcpy(&g->x[dim],o,sizeof(Tfl));
	}
	g->dim = dim+1;
	SET_VARSIZE(g, sg);

	return g;	
}
/* same as flowm_extends, but provides a new copy */
Tflow *flowm_cextends(Tfl *o,Tflow *f, bool before) {

	short dim = f->dim;
	size_t sg,sf = offsetof(Tflow,x) + dim * sizeof(Tfl);
	Tflow *g;

	sg = sf+sizeof(Tfl);
	g = palloc(sg);
	
	if(before) {
		memcpy(g,f,offsetof(Tflow,x));
		memcpy(&g->x[0],o,sizeof(Tfl));
		memcpy(&g->x[1],&f->x[0],dim*sizeof(Tfl));
	} else {
		memcpy(g,f,sf);	
		memcpy(&g->x[dim],o,sizeof(Tfl));
	}
	
	g->dim = dim+1;
	SET_VARSIZE(g, sg);
	
	return g;	
}



