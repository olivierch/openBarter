/*
 * 
 *
 ******************************************************************************

******************************************************************************/
#include "postgres.h"
#include "float.h"

#include <float.h>
#include <math.h> 
#include "flowdata.h"

#include "lib/stringinfo.h"

typedef struct Tchemin {
	// bool	lastignore;
	short	nbOwn; 
	short 	occOwn[FLOW_MAX_DIM]; 
	double	gain,prodOmega;
	Tflow 	*box;
	double 	omegaCorrige[FLOW_MAX_DIM],fluxExact[FLOW_MAX_DIM],piom[FLOW_MAX_DIM]; 
	int64	flowNodes[FLOW_MAX_DIM]; 
	int64	floor[FLOW_MAX_DIM];
	Tno	no[FLOW_MAX_DIM];
	
} Tchemin;

char *flowc_cheminToStr(Tchemin *pchemin);
char *flowc_flowToStr(Tflow *flow);

static void _calGains(Tchemin *pchemin,double omegaCorrige[]);
static short _fluxMaximum(const Tchemin *pchemin,double	*omegaCorrige, double *fluxExact) ;
static bool _rounding(double *fluxExact, Tchemin *pchemin);
static void _calOwns(Tchemin *pchemin);
static double _calOmega(Tchemin *pchemin);
char * flowc_vecIntStr(short dim,int64 *vecInt);
char * flowc_vecDoubleStr(short dim,double *vecDouble);
static char *_flowc_maximum(Tflow *box,bool ret_str);


/******************************************************************************
 * gives the maximum flow of box
 * return box->x[.].flowr and box->status
 *****************************************************************************/
Tstatusflow flowc_maximum(Tflow *box) {
	(void) _flowc_maximum(box,false);
	return box->status;
}
char *flowc_toStr(Tflow *box) {
	return _flowc_maximum(box,true);
}
static char *_flowc_maximum(Tflow *box,bool ret_str) {
	short _dim = box->dim;
	short _i,_ldim;
	Tchemin chemin;
	short _iExhausted;

	
	box->status = empty;
	box->lastignore = false;
	
	chemin.box = box;
	if(_dim == 0) 
		goto _end;	

	if(_dim > FLOW_MAX_DIM) 
		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			 errmsg("max dimension reached for the flow")));


	
	
	box->lastignore = box->x[_dim-1].id == 0;

	_ldim = (box->lastignore)?_dim-1:_dim; 	
	obMRange(_i,_ldim) 
		if(box->x[_i].qtt == 0) 
			goto _dropflow; // box->status = empty
		else if(box->x[_i].qtt < 0) 
			ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("flow with qtt <0")));
				 
	// elog(WARNING,"flowc_maximum: dim=%i",_dim);
	if(_dim == 1) {
		box->status = noloop;
		goto _dropflow;
	}
		
	if(box->x[_dim-1].np != box->x[0].nr) {
		box->status = noloop; 
		goto _dropflow;
	}
	// end->begin

				 
	//elog(WARNING,"flowc_maximum: ->status!=noloop");
	// error for 3-agreement: on omega ~= 1.1e-16
	
	if( _calOmega(&chemin) < 1.0) {
		box->status = refused;
		goto _dropflow;
	}
		
	_calOwns(&chemin);
	
	// omegas are bartered so that the product(omegaCorrige[i] for i in [0,_dim-1])== 1 
	_calGains(&chemin,chemin.omegaCorrige);

	/* maximum flow, as a floating point vector 
	in order than at least one stock is exhausted by the flow
	and than the ratio between successive elements of flowr is omegaCorrige */
	_iExhausted = _fluxMaximum(&chemin,chemin.omegaCorrige,chemin.fluxExact); 
	
	/* the floating point vector is rounded 
	to the nearest vector of positive integers */
	if (_rounding(chemin.fluxExact, &chemin) ) 
		box->status = draft;
	else {
		box->status = undefined;
_dropflow: 	
		{
			short _k;
		
			// the flow is undefined
			obMRange (_k,_dim)
				box->x[_k].flowr = 0;		
		}
		
	}
_end:
	if(ret_str)
		return flowc_cheminToStr(&chemin);
	else 
		return NULL;
}
/******************************************************************************
 * 
 *****************************************************************************/
static double _calOmega(Tchemin *pchemin) {
	Tflow *box = pchemin->box;
	short _n,_dim = box->dim;
		
	pchemin->prodOmega = 1.0;
	
	obMRange(_n,_dim) {		
		if((_n == _dim-1) && box->lastignore) {
			continue;
		} else {
			Torder *b = &pchemin->box->x[_n];
			Tno *n = &pchemin->no[_n];
				
			// compute omega and prodOmega
			if(b->qtt_prov == 0 || b->qtt_requ == 0) {
				ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("_calOmega: qtt_prov or qtt_requ is zero for Torder[%i]",_n)));
			}		 
			n->omega = ((double)(b->qtt_prov)) / ((double)(b->qtt_requ));
			pchemin->prodOmega *= n->omega;
		}
	}
	if (box->lastignore) {
		/* omega of the last node is not defined.
		It is set in order than the product of omegas becomes 1.0 :
		omega[_dim-1] 	= 1./product(omega[i] for i in [0,_dim-2] )
		*/
		pchemin->no[_dim-1].omega = 1.0/pchemin->prodOmega;
		pchemin->prodOmega = 1.0;
	}
	return pchemin->prodOmega;
}
/******************************************************************************
 * 
 *****************************************************************************/
static void _calOwns(Tchemin *pchemin) {
	
	short *occOwn = pchemin->occOwn; 
	short _ownIndex,_n;
	Tflow *box = pchemin->box;
	short _dim;
	
	_dim = box->dim;		
	
	// defines ownIndex and updates nbOwn
	/****************************************************/
	pchemin->nbOwn = 0;
	obMRange(_n,_dim) {
		short _m;
		
		Torder *b = &box->x[_n];
		Tno *n = &pchemin->no[_n];
			
		_ownIndex = pchemin->nbOwn;
		obMRange(_m,pchemin->nbOwn) {
			if (b->own == box->x[_m].own) {
				_ownIndex = _m;
				break;// found
			}
		}
		if (_ownIndex == pchemin->nbOwn) { // not found
			occOwn[_ownIndex] = 0;
			pchemin->nbOwn += 1;
		}
		occOwn[_ownIndex] += 1;
		n->ownIndex = _ownIndex;	
	} 
	
	if(pchemin->nbOwn == 0) { 
		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			 errmsg("createChemin: nbOwn equals zero")));		
	}
	 
	#ifdef GL_VERIFY
	obMRange(_n,_dim) {
		short _m;
		
		Torder *o = &box->x[_n];
				 
		// b.id are unique in box
		obMRange(_m,_n) {
			if(o->id == box->x[_m].id) {
				ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("createChemin: Torder[%i].id=%i found twice",_n,o->id)));
			}
		}
	
		// successive orders match
		if(_n != 0 ) {
			if(box->x[_n-1].np != o->nr) {
				ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("createChemin: Torder[%i].np=%i != Torder[%i].nr=%i",_n-1,box->x[_n-1].np,_n,o->nr)));		
			}
		}
	}
	#endif
	
	return;	
}

/*******************************************************************************
 (1/prodOmega) is shared between owners, and then shared between nodes of each owner.
 for each owner, it is:
 	 pow(gain_owner,nb_owners) = 1/prodOmega
 if the owner j owns _occ[j] nodes, it's gain_node for each node is:
 	pow(gain_node[j],_occ[j]) = gain_owner
 	
 input-output
 In:
 	prodOmega,
 	nbOwn,
 	nbNoeud,
 	ownOcc[j] for j in [O,nbOwn[
 Out:
 	omegaCorrige[i] for i in [0,nbNoeud[

	
the result omegaCorrige is such as the product(omegaCorrige[.])== 1 
 *******************************************************************************/

static void _calGains(Tchemin *pchemin,double omegaCorrige[]) {
	short _i, _occ;
	short *occOwn = pchemin->occOwn;
	short _dim = pchemin->box->dim;

	// the gain is shared between owners
	pchemin->gain = pow(pchemin->prodOmega, 1.0 /((double) pchemin->nbOwn));

	// it is shared between nodes
	obMRange(_i,_dim) {
		_occ = occOwn[pchemin->no[_i].ownIndex];
		omegaCorrige[_i] = pchemin->no[_i].omega;
		if (_occ == 1)
			omegaCorrige[_i] /= pchemin->gain;
		else /* _occ is never zero */
			omegaCorrige[_i] /= pow(pchemin->gain, 1.0 / ((double) _occ));
		
	}

	return;
}

/*******************************************************************************
Computes the maximum flow fluxExact of pchemin.
 
This flow fluxExact[.] is such than:
 	fluxExact[i] = omegaCorrige[i] * fluxExact[i-1]
and such as quantities of stock can provide this flow
 
Each stock can be used by several nodes.
 
Input-output
************	
 In	pchemin, for i in [0,dim[ and j in [0,nbStock[
		->cflags
		->omegaCorrige[i]
		->no[i].stockIndex = j
		->occStock[j]
		->box[j].qtt

 Out	fluxExact[.] the maximum flow, of pchemin->lon elts

returns the index i of the exhausted stock.
	when lastIgnore, 
		i in [0, nbStock -1[
	else
		i in [0, nbStock[
Details
*******
If lastIgnore: The flow is not limited by the last node
This node has always it's own stock.

_piom[i] is the product of omegas between the start of the path and a given node i.
	 For i==0 it is 1.
	 For i!=0 it is omegaCorrige[1]*.. omegaCorrige[i]

	 If we know the flow f[0] at the first node, the flow vector is given by:
		f[i] = f[0] * _piom[i]

If q[j] is the quantity of a stock j; Sj the set of nodes using this stock j,
and  f[i] is the flow of a node i,
Then we must have:  
	q[j] >= SUM(f[i]) for i in Sj
since:
	_piom[i] = f[i]/f[0]
we have:
	f[0] = MIN( q[j]/(SUM(_piom[i]) for i in Sj)) for j in stocks
and:
	f[i] = f[0] * _piom[i]
	
 *******************************************************************************/
static short _fluxMaximum(const Tchemin *pchemin, double *omegaCorrige, double *fluxExact) {
	short 	_is, _jn,_jm;
	double	*_piom = (double *) pchemin->piom; //  _fPiomega(i)
	double	_min, _cour;
	short	_iExhausted;	
	//double	*omegaCorrige = (double *) pchemin->omegaCorrige;
	Tflow	*box = pchemin->box;
	short 	_dim = box->dim;
	bool 	_lastignore = box->lastignore;
		
	// piom are obtained on each node, 
	/***********************************************************************/
	obMRange(_jn,_dim) {// loop on nodes
		short _k;
		
		/* computation of _piom */
		_piom[_jn] = 1.0;
		if(_jn > 0 ) 
			obMRange(_k,_jn) 
				_piom[_jn] *= omegaCorrige[_k + 1];
	}
	
	// minimum flow for the first node f[0]
	/***********************************************************************/
	_jm = _dim;
	if(_lastignore)
		_jm -= 1;
	// now _is is an index on nodes
	obMRange(_is,_jm) { // loop on nodes
		_cour = ((double) (box->x[_is].qtt)) /_piom[_is]; 
		if ((_is == 0) || (_cour < _min)) {
			_min = _cour;
			_iExhausted = _is;
		}
	}
	
	// propagation to other nodes
	/***********************************************************************/
	obMRange(_jn,_dim)
		fluxExact[_jn] = _min * _piom[_jn];
		
	return _iExhausted;
}
/*******************************************************************************
floor,flow and mat are vectors of dimension _dim
floor and flow contains integers, and mat bits.
	in: dim,mat,floor
	out:flow
for each i, if the bit i of mat is 0, flow[i] := floor[i]
else flow[i] := floor[i]+1
*******************************************************************************/
#define _obtain_vertex(dim,mat,floor,flow) \
do { \
	short __j; \
	for(__j=0;__j<dim;__j++) { \
		flow[__j] = floor[__j]; \
		if (mat & (1 << __j)) \
			flow[__j] += 1; \
	} \
} while(0) 

/*******************************************************************************
 Computes a distance between two vectors vecExact and vecArrondi. 
 It the angle alpha made by these vectors.
 We have:
 cos(alpha) = (vecExact.vecArrondi)/ (||vecArrondi||*||vecExact||)

 To minimize this distance between vecExact and vecArrondi, we maximize this cos(alpha).
 Since vecExact does not change between comparisons, alpha is minimized when the value:
	cos(alpha)*||vecExact|| is maximized,
 
 or (vecExact.vecArrondi)/ (||vecArrondi||) maximized.
 This value is returned by the function.
*******************************************************************************/
static double _idistance(short lon, 
				const double *vecExact,
				const int64 *vecArrondi) {
	double _s, _na, _va;
	short _i;

	_s = 0.0;
	_na = 0.0;
	obMRange(_i,lon) {
		_va = (double) (vecArrondi[_i]);
		_s += _va * vecExact[_i];
		_na += _va * _va;
	}
	return (_s / sqrt(_na));
}
/*******************************************************************************
 flow rounding
	in: _iExhausted,pchemin
	out: fluxExact,pchemin

 When it can be found, gives the vector pchemin->fluxArrondi of ingeters
 the nearest of fluxExact, not greater than orders.qtt.

 box->dim must be <= 31 (2^dim loops)

 returns
 	 1 if a solution is found
  	 0 if no solution
 The solution is returned in pchemin->no[.].fluxArrondi

 when pchemin->cflags & obCLastIgnore,
 the last node does not limit the flow

 *******************************************************************************/
// #define WHY_REJECTED
static bool _rounding(double *fluxExact, Tchemin *pchemin) {
	short 	_i,  _k;
	short 	_matcour, _matmax, _matbest;
	bool 	_found;
	int64	*_flowNodes = pchemin->flowNodes;
	int64	*_floor = pchemin->floor;
	double 	_distcour, _distbest;
	Tflow 	*box = pchemin->box;
	short 	_dim = box->dim;
	short _ldim = (box->lastignore)?(_dim-1):_dim;

	// computes floor[] from fluxExact[]
	/***********************************************************************/
	obMRange(_i,_dim) {
		double _d = floor(fluxExact[_i]);
		int64 _f = (int64) _d;
		if(_f < 0) _f = 0; 
		if(((double)(_f)) != _d) {
			ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("in _rounding, fluxExact[%i] = %f cannot be rounded",_i,fluxExact[_i])));
		}
		_floor[_i] = _f;
		//elog(WARNING,"flowc_maximum: _floor[%i]=%lli",_i,_f);
	}

	_matmax = 1 << _dim; // one bit for each node 
	if(_matmax < 1) {
		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			 errmsg("in _rounding, matmax=%i,flow too long",_matmax)));
	}
	
	// for each vertex of the hypercude
	/***********************************************************************/
	_found = false;
	for (_matcour = 0; _matcour < _matmax; _matcour++) {
		 
		// obtain the vertex _flowNodes
		/***************************************************************/
		_obtain_vertex(_dim,_matcour,_floor,_flowNodes);

		// several checkings
		/***************************************************************/
		
		// verify that flow <= box->k[.].qtt
		obMRange (_k,_ldim) {
			// verify that order >= flow
			if(box->x[_k].qtt<_flowNodes[_k]) {
				#ifdef WHY_REJECTED 
					elog(WARNING,"flowc_maximum 1: NOT order >= flow %s",flowc_vecIntStr(_dim,_flowNodes));
				#endif
				goto _continue;
			}
		}
				
		// verify that flow > 0
		obMRange (_k,_dim) {
			// verify that flow >0
			if(_flowNodes[_k] <= 0) {
				#ifdef WHY_REJECTED
					elog(WARNING,"flowc_maximum 2: NOT flow>0 %s",flowc_vecIntStr(_dim,_flowNodes));
				#endif
				goto _continue;
			}
		}
		
		/* when lastignore, pivot.qtt is not defined
		*/
		
		// verify that the flow exhausts some order 
		{
			bool _exhausts = false;
			/*
			for lastignore, some order between [0,dim-2] should be exhausted
			*/
			obMRange (_k,_ldim) {
				if(_flowNodes[_k] == box->x[_k].qtt ) {
					_exhausts = true; 
					break;
				}		
			}
			if(!_exhausts) {
				//elog(WARNING,"flowc_maximum 3: _mat=%x",_matcour);
				#ifdef WHY_REJECTED
					elog(WARNING,"flowc_maximum 3: NOT exhaust %s",flowc_vecIntStr(_dim,_flowNodes));
				#endif
				goto _continue;
			}
		} 
				
		/* At this point, 
			* each node can provide flowNodes[],
			* all flowNodes[.] > 0
				=> every order provide something
				=> every one provide something
			* the cycle exhausts the box
			* Omega ~= 1.0 
		*/
		if(!box->lastignore) {
			short _kp = _dim-1;
			double _precision = 1.E-8;
			
			obMRange(_k,_dim) {
				if(pchemin->no[_k].omega + _precision < ((double) _flowNodes[_k]) / ((double) _flowNodes[_kp])) {
					#ifdef WHY_REJECTED
						elog(WARNING,"flowc_maximum 4: NOT omega %f>=%f %s",pchemin->no[_k].omega,((double) _flowNodes[_k]) / ((double) _flowNodes[_kp]),flowc_vecIntStr(_dim,_flowNodes));
					#endif
					goto _continue;
				}
				_kp = _k;
			}
		}

		// choose the best
		/***************************************************************/

		_distcour = _idistance(_dim, fluxExact, _flowNodes);
		// elog(WARNING,"flowc_maximum: matcour=%x _newdist=%f fluxExact=%s flowNodes=%s",_matcour,_distcour,_vecDoubleStr(_dim,fluxExact),_vecIntStr(_dim,_flowNodes));


		// this vertex is better than other found (if any)
		/***************************************************************/
		if( (!_found) || _distbest < _distcour) {
			// _distbest=max(cos(a)) === min(a) 
			_found = true;
			_distbest = _distcour;
			_matbest = _matcour;

		}
_continue:
		;
	};
	if(_found) {
		_obtain_vertex(_dim,_matbest,_floor,_flowNodes);
		//elog(WARNING,"flowc_maximum: _matbest=%x",_matbest);
		obMRange (_k,_dim) {
			box->x[_k].flowr = _flowNodes[_k];	
		}
	} 

	return _found; 
}
/******************************************************************************
 * 
 *****************************************************************************/
char * flowc_cheminToStr(Tchemin *pchemin) {
	StringInfoData buf;
	Tflow *flow = pchemin->box;
	short _dim = pchemin->box->dim;
	short _n,_o;
	
	initStringInfo(&buf);
	appendStringInfo(&buf, "\n%s",yflow_ndboxToStr(flow,false));
	if(flow->status == refused) {	
		appendStringInfo(&buf, "CHEMIN refused prodOmega=%f ",pchemin->prodOmega);
		appendStringInfo(&buf, "\nno[.].omega=[");
		obMRange(_n,_dim) {
			appendStringInfo(&buf, "%f, ", pchemin->no[_n].omega);
		}
		appendStringInfo(&buf, "]\n");
		
	} else if(flow->status == draft || flow->status == undefined) {
	
		appendStringInfo(&buf, "CHEMIN  %s lastignore=%c nbOwn=%i gain=%f prodOmega=%f ", 
			yflow_statusBoxToStr(flow),
			(flow->lastignore)?'t':'f',pchemin->nbOwn,pchemin->gain,pchemin->prodOmega);
	
		appendStringInfo(&buf, "\noccOwn[.]=[");
		_o = pchemin->nbOwn;
		obMRange(_n,_o) {
			appendStringInfo(&buf, "%i, ", pchemin->occOwn[_n]);
		}
	
		appendStringInfo(&buf, "]\nno[.].ownIndex[");
		obMRange(_n,_dim) {
			appendStringInfo(&buf, "%i, ", pchemin->no[_n].ownIndex);
		}	
			
		appendStringInfo(&buf, "]\nno[.].omega=[");
		obMRange(_n,_dim) {
			appendStringInfo(&buf, "%f, ", pchemin->no[_n].omega);
		}
	
		appendStringInfo(&buf, "]\npiom[.]=[");
		obMRange(_n,_dim) {
			appendStringInfo(&buf, "%f, ", pchemin->piom[_n]);
		}		
	
		appendStringInfo(&buf, "]\nfluxExact[.]=[");
		obMRange(_n,_dim) {
			appendStringInfo(&buf, "%f, ", pchemin->fluxExact[_n]);
		}
	
		appendStringInfo(&buf, "]\nomegaCorrige[.]=[");
		obMRange(_n,_dim) {
			appendStringInfo(&buf, "%f, ", pchemin->omegaCorrige[_n]);
		}	
	
		appendStringInfo(&buf, "]\nflow->flowr[.]=[");
		obMRange(_n,_dim) {
			appendStringInfo(&buf, "%lli, ", flow->x[_n].flowr);
		}	
		appendStringInfo(&buf, "]\n");
	}

	return buf.data;
}
/******************************************************************************
 * 
 *****************************************************************************/
char * flowc_vecIntStr(short dim,int64 *vecInt) {
	StringInfoData buf;
	short _n;
	
	initStringInfo(&buf);
	appendStringInfo(&buf, "[");
	obMRange(_n,dim) {
		appendStringInfo(&buf, "%lli, ", vecInt[_n]);
	}	
	appendStringInfo(&buf, "]");

	return buf.data;
}
/******************************************************************************
 * 
 *****************************************************************************/
char * flowc_vecDoubleStr(short dim,double *vecDouble) {
	StringInfoData buf;
	short _n;
	
	initStringInfo(&buf);
	appendStringInfo(&buf, "[");
	obMRange(_n,dim) {
		appendStringInfo(&buf, "%f, ", vecDouble[_n]);
	}	
	appendStringInfo(&buf, "]");

	return buf.data;
}



