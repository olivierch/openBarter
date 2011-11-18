
#include "postgres.h"

#include <float.h>
#include <math.h>
/*
#include "access/gist.h"
#include "access/skey.h"
#include "lib/stringinfo.h"
#include "utils/array.h"
#include "utils/builtins.h"
*/

#include "flowdata.h"
#include "storage/shmem.h"
#include "lib/stringinfo.h"


static void _calGains(ob_tChemin *pchemin,double omegaCorrige[]);
static int _fluxMaximum(const ob_tChemin *pchemin, double *fluxExact) ;
static bool _rounding(double *fluxExact, ob_tChemin *pchemin,int _iStockExhausted);
static ob_tChemin * _createChemin(NDBOX *box, int cflags );
static bool _isCycle(NDBOX *box);

/******************************************************************************
 * gives the maximum flow of box
 * return box->x[.].flowr and box->status
 
 if box->x[box->dim-1].id == 0 (cflags & ob_flux_CLastIgnore)
	the flow is not limited by the last stock
	
 if (cflags & ob_flux_CVerify  )
	the flow is verified even if there is no loop
	
 *****************************************************************************/

void flowc_maximum(NDBOX *box,bool verify) {
	int _dim = box->dim;
	ob_tChemin *pchemin;
	int _iStockExhausted;
	int cflags;
	
	if(_dim == 0) {
		box->status = empty;
		return;
	}

	if(_dim > FLOW_MAX_DIM) 
		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			 errmsg("max dimension reached for the flow")));

	
	// computes cflags
	cflags = 0;
	if(box->x[(box->dim)-1].sid == 0) cflags |= ob_flux_CLastIgnore;
	else cflags &= ~(ob_flux_CLastIgnore);
	
	if(verify) cflags |= ob_flux_CVerify;
	else cflags &= ~(ob_flux_CVerify);	
	
	if (!_isCycle(box)) {
		int _k;
		
		box->status = noloop;
		// the flow is undefined
		obMRange (_k,_dim)
			box->x[_k].flowr = 0;	
		if (cflags & ob_flux_CVerify ) {
			pchemin = _createChemin(box,cflags);
			pfree(pchemin);
		}
		return;
	}

	pchemin = _createChemin(box,cflags);
	
	if (pchemin->cflags & ob_flux_CLastIgnore) {
		/* omega of the last node is not defined.
		It is set in order than the product of omegas becomes 1.0 :
		omega[_dim-1] 	= 1./product(omega[i] for i in [0,_dim-2] )
				= omega[_dim-1]/product(omega[i] for i in [0,_dim-1] )
		*/
		pchemin->no[_dim-1].omega = pchemin->no[_dim-1].omega/pchemin->prodOmega;
		pchemin->prodOmega = 1.0;
	}
	
	// omegas are bartered so that the product(omegaCorrige[i] for i in [0,_dim-1])== 1 
	_calGains(pchemin,pchemin->omegaCorrige);

	/* maximum flow, as a floating point vector 
	in order than at least one stock is exhausted by the flow
	and than the ratio between successive elements of flowr is omegaCorrige */
	_iStockExhausted = _fluxMaximum(pchemin,pchemin->fluxExact); 
	
	/* the floating point vector is rounded 
	to the nearest vector of positive integers */
	if (_rounding(pchemin->fluxExact, pchemin,_iStockExhausted) ) 
		box->status = draft; 
	else {
		box->status = undefined;

	}	
	pfree(pchemin);
	return;
}

bool flowc_idInBox(NDBOX *box,int64 id) {
	int _dim = box->dim;
	int _n;
	
	obMRange(_n,_dim) {
		if(id == box->x[_n].id) 
			return true;
	}
	return false;
	
}

static ob_tChemin * _createChemin(NDBOX *box, int cflags ) {
	
	ob_tChemin *pchemin;
	int *occOwn,*occStock;
	int _stockIndex,_ownIndex,_n;
	int _dim = box->dim;
	int size_che,size_occ,size_dou,size_tot;
	bool _verify = cflags & ob_flux_CVerify; 	

	
	/* memory allocation of chemin, occStock, occOwn and omegaCorrige
	in the same block of memory */	

	size_che = offsetof(ob_tChemin, no[0]);
	size_che = MAXALIGN(size_che);
	size_che = add_size(size_che,mul_size(_dim,sizeof(ob_tNo)));
	size_occ = mul_size(_dim,MAXALIGN(sizeof(int)));
	size_dou = mul_size(_dim,MAXALIGN(sizeof(double)));
	
	size_tot = size_che + (2 * size_occ) + (4 * size_dou);
	
	pchemin = (ob_tChemin *) (palloc0(size_tot));
	pchemin->occStock = (int *) (pchemin + ((size_t)size_che));
	pchemin->occOwn = (int *) (pchemin->occStock + ((size_t)size_occ));
	pchemin->omegaCorrige = (double *) (pchemin->occOwn + ((size_t)size_occ));
	pchemin->fluxExact = (double *) (pchemin->omegaCorrige + ((size_t)size_dou));
	
	pchemin->piom = (double *) (pchemin->fluxExact + ((size_t)size_dou));
	pchemin->spiom = (double *) (pchemin->piom + ((size_t)size_dou));
	
	pchemin->box = box;	
	
	pchemin->prodOmega = 1.;
	pchemin->nbOwn = 0;
	pchemin->nbStock = 0;
	pchemin->cflags = cflags;
	
	occStock = pchemin->occStock;
	occOwn = pchemin->occOwn;
	
	obMRange(_n,_dim) {
		int _m;
		
		BID *b = &box->x[_n];
		ob_tNo *n = &pchemin->no[_n];
		
		// compute omega and prodOmega
		if(b->qtt_prov == 0 || b->qtt_requ == 0) {
			pfree(pchemin);
			ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("createChemin: qtt_prov or qtt_requ is zero for bid[%i]",_n)));
		}		 
		n->omega = ((double)(b->qtt_prov)) / ((double)(b->qtt_requ));
		pchemin->prodOmega *= n->omega;
		
		// b.id and b.np are unique in box
		if (_verify ) obMRange(_m,_n) {
			if(b->id == box->x[_m].id) {
				pfree(pchemin);
				ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("createChemin: bid[%i].id=%lli found twice",_n,b->id)));
			}
			// but not b.np
			/*
			if(b->np == box->x[_m].np) {
				pfree(pchemin);
				ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("createChemin: bid[%i].np=%lli found twice",_n,b->np)));
			} */
		}
		
		if((_n != 0) &&  _verify ) 
			if(box->x[_n-1].np != b->nr) {
				pfree(pchemin);
				ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("createChemin: bid[%i].np=%lli != bid[%i].nr=%lli",_n-1,box->x[_n-1].np,_n,b->nr)));		
			}
			
		// defines ownIndex and updates nbOwn
		/****************************************************/
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
		
		// defines stockIndex and updates nbStock
		/****************************************************/
		_stockIndex = pchemin->nbStock;
		obMRange(_m,pchemin->nbStock) {
			if (b->sid == box->x[_m].sid) {
				_stockIndex = _m;
				break;// found
			}
		}
		if (_stockIndex == pchemin->nbStock) { // not found
			occStock[_stockIndex] = 0;
			pchemin->nbStock += 1;
		} else if (_verify ) { // found
			if(b->own != box->x[_stockIndex].own) {
				pfree(pchemin);
				ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("createChemin: the stock[%lli] has several owners!",b->sid)));
			}
			if(b->np != box->x[_stockIndex].np) {
				pfree(pchemin);
				ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("createChemin: the stock[%lli] has several np!",b->sid)));
			}
			if(b->qtt != box->x[_stockIndex].qtt) {
				pfree(pchemin);
				ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("createChemin: the stock[%lli] has several qtt!",b->sid)));
			}
		}
		occStock[_stockIndex] += 1;
		n->stockIndex = _stockIndex;
	} 
	
	if(pchemin->nbOwn == 0 || pchemin->nbStock == 0) {
		pfree(pchemin);
		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			 errmsg("createChemin: nbOwn or nbStock equals zero")));		
	}

	if (pchemin->cflags & ob_flux_CLastIgnore) {
		/* the stock of the pivot should not be used by any other node when ob_flux_CLastIgnore
		=> index of stocks used by nodes other than the pivot should be in [0,_lonStockl[ */
		int _m = pchemin->no[_dim-1].stockIndex;
		
		if( occStock[_m]!= 1) {
				pfree(pchemin);
				ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("createChemin: when ob_flux_CLastIgnore, the last stock is not only used by the last bid")));
			}
		if(box->x[_m].sid != 0) {
				pfree(pchemin);
				ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("createChemin: when ob_flux_CLastIgnore, the last stock is with sid != 0")));
			}
	}
	return pchemin;	
}


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
static double _idistance(int lon, 
				const double *vecExact,
				const int64 *vecArrondi) {
	double _s, _na, _va;
	int _i;

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

static void _calGains(ob_tChemin *pchemin,double omegaCorrige[]) {
	int _i, _occ;
	int *occOwn = pchemin->occOwn;
	int _dim = pchemin->box->dim;

	// the gain is shared between owners
	pchemin->gain = pow(pchemin->prodOmega, -1.0 /((double) pchemin->nbOwn));

	// next, it is shared between nodes
	obMRange(_i,_dim) {
		_occ = occOwn[pchemin->no[_i].ownIndex];
		omegaCorrige[_i] = pchemin->no[_i].omega;
		if (_occ == 1)
			omegaCorrige[_i] *= pchemin->gain;
		else /* _occ is never zero */
			omegaCorrige[_i] *= pow(pchemin->gain, 1.0 / ((double) _occ));
		
	}
	/* it would be clearer like this:
	pchemin->gain = pow(pchemin->prodOmega, 1.0 /((double) pchemin->nbOwn));
	.....
			omegaCorrige[_i] /= pchemin->gain;
		else 
			omegaCorrige[_i] /= pow(pchemin->gain, 1.0 / ((double) _occ));
	*/
	return;
}

static bool _isCycle(NDBOX *box) {
	int _dim = box->dim;	
	return box->x[0].nr == box->x[_dim-1].np;
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
static int _fluxMaximum(const ob_tChemin *pchemin, double *fluxExact) {
	int _is, _jn,_jm;
	double *_piom = pchemin->piom; //  _fPiomega(i)
	double *_spiom = pchemin->spiom; // (SUM(_fPiomega(i)) for i in Sj)
	double _min, _cour;
	int	_iStockExhausted;	
	double *omegaCorrige = pchemin->omegaCorrige;
	NDBOX *box = pchemin->box;
	int _dim = box->dim;
		
	// piom are obtained on each node, 
	/**********************************************************/
	obMRange(_jn,_dim)
		_spiom[_jn] = 0.;
	obMRange(_jn,_dim) {// loop on nodes
		int _k;
		
		/* computation of _piom */
		_piom[_jn] = 1.0;
		if(_jn > 0 ) 
			obMRange(_k,_jn) 
				_piom[_jn] *= omegaCorrige[_k + 1];
		
		_is = pchemin->no[_jn].stockIndex;
		_spiom[_is] += _piom[_jn]; // sum of _piom for each stock
	}
	
	// minimum flow for the first node f[0]
	/**********************************************************/
	_jm = pchemin->nbStock;
	if(pchemin->cflags & ob_flux_CLastIgnore)
		_jm -= 1;

	obMRange(_is,_jm) { // loop on stocks
		_cour = ((double) (box->x[_is].qtt)) / _spiom[_is] ;
		if ((_is == 0) || (_cour < _min)) {
			_min = _cour;
			_iStockExhausted = _is;
		}
	}
	
	// propagation to other nodes
	/**********************************************************/
	obMRange(_jn,_dim)
		fluxExact[_jn] = _min * _piom[_jn];
		
	return _iStockExhausted;
}

/*******************************************************************************
floor,flow and mat are vectors of dimension _dim
floor and flow contains integers, and mat bits.
	in: dim,mat,floor
	out:flow
for each i, if the bit i of mat is 0, flow[i] := floor[i]
else flow[i] := floor[i]+1
*******************************************************************************/
static void _obtain_vertex(int dim,int mat,int64 *floor,int64 *flow) {
	int _j;
	
	obMRange (_j,dim) {
		flow[_j] = floor[_j];
		if (mat & (1 << _j))
			flow[_j] += 1;
	}
	return;
}

/*******************************************************************************
 flow rounding
	in: iStockExhausted,pchemin
	out: fluxExact,pchemin

 When it can be found, gives the vector pchemin->fluxArrondi of ingeters
 the nearest of fluxExact, not greater than stocks.

 box->dim must be <= 31 (2^31 loops !!)

 returns
 	 1 if a solution is found
  	 0 if no solution
 The solution is returned in pchemin->no[.].fluxArrondi

 when pchemin->cflags & obCLastIgnore,
 the last node should use a stock that is not used by others
 In this case this stock does not limit the flow

 *******************************************************************************/

static bool _rounding(double *fluxExact, ob_tChemin *pchemin,int iStockExhausted) {
	int _i, _j, _k, _lonStock;
	int _matcour, _matmax, _matbest;
	bool _found;
	int64 * _flowNodes,* _flowStocks, *_floor;
	double _newdist, _maxdist;
	NDBOX *box = pchemin->box;
	int _dim = box->dim;
	size_t _s;
	
	_s = mul_size(_dim,MAXALIGN(sizeof(int64)));
	_flowNodes = (int64 *) (palloc0(3*_s));
	_flowStocks = (int64 *) (((char *)_flowNodes)+_s);
	_floor = (int64 *) (((char *)_flowStocks)+_s);
	
	_lonStock = pchemin->nbStock;


	// computes floor[] from fluxExact[]
	obMRange(_i,_dim) {
		double _d = floor(fluxExact[_i]);
		int64 _f = (int64) _d;
		if(_f < 0) _f = 0; 
		if(((double)(_f)) != _d) {
			pfree(_flowNodes);pfree(pchemin);
			ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("in _rounding, fluxExact[%i] = %f cannot be rounded",_i,fluxExact[_i])));
		}
		_floor[_i] = _f;
	}

	_matmax = 1 << _dim; // one bit for each node 
	if(_matmax < 1) {
		pfree(_flowNodes);pfree(pchemin);
		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			 errmsg("in _rounding, matmax=%i,flow too long",_matmax)));
	}
	
	// for each vertex of the hypercude
	/**********************************/
	_found = false;
	for (_matcour = 0; _matcour < _matmax; _matcour++) {
		bool _admissible = true;
		
		// obtain the vertex _flowNodes
		/******************************/
		_obtain_vertex(_dim,_matcour,_floor,_flowNodes);

		// obtain _flowStocks
		/********************/
		obMRange (_k,_lonStock)
			_flowStocks[_k] = 0;

		obMRange (_j,_dim) {
			_k = pchemin->no[_j].stockIndex;
			_flowStocks[_k] += _flowNodes[_j];
		}

		// several checkings
		/*******************/
		obMRange (_k,_lonStock) {

			// All _flowStocks[.] > 0
			if(_flowStocks[_k] == 0) {
				_admissible = false; break;
			}
		}
		
		if(!(pchemin->cflags & ob_flux_CLastIgnore)) obMRange (_k,_lonStock) {
			
			if(_k == iStockExhausted) {
				// verify the flow exhausts the stock
				if(_flowStocks[_k] != box->x[_k].qtt ) {
					_admissible = false; break;
				}
			} else {
				// verify the flow is not greater than the stock
				if ( _flowStocks[_k] > box->x[_k].qtt ) {
					_admissible = false; break;
				}
			}
		}
		if (!_admissible) continue; // the vertex is rejected
		
		/* At this point, each stock can provide flowStock[],
		all flowStock[.] > 0
			=> every stock provide something
			=> every one provide something
		the cycle exhausts the box  */


		// choose the best
		/*****************/
		_newdist = _idistance(_dim, fluxExact, _flowNodes);


		// this vertex is better than other found (if any)
		/************************************************/
		if( (!_found) || _maxdist < _newdist) {
			_found = true;
			_maxdist = _newdist;
			_matbest = _matcour;

		}
	}
	if(_found) {
		_obtain_vertex(_dim,_matbest,_floor,_flowNodes);
		obMRange (_k,_dim)
			box->x[_k].flowr = _flowNodes[_k];	
	} else obMRange (_k,_dim)
			box->x[_k].flowr = 0;	

	pfree(_flowNodes);
	return _found; 
}

double flowc_getProdOmega(NDBOX *box) {
	int _dim = box->dim;
	int _n;
	double p = 1.,_omega;
	
	if(_dim == 0) return 0.;
	
	obMRange(_n,_dim) {
		BID *b = &box->x[_n];

		if(b->qtt_prov == 0 || b->qtt_requ == 0) {
			ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("flowc_getProdOmega: qtt_prov or qtt_requ is zero for bid[%i]",_n)));
		}
				 
		_omega = ((double)(b->qtt_prov)) / ((double)(b->qtt_requ));
		p *= _omega;
	}
	return p;
}

char * flowc_cheminToStr(ob_tChemin *pchemin) {
	StringInfoData buf;
	int _dim = pchemin->box->dim;
	int _n,_o;
	
	
	initStringInfo(&buf);
	
	appendStringInfo(&buf, "CHEMIN cflags=%x nbOwn=%i nbStock=%i gain=%f prodOmega=%f", 
		pchemin->cflags,pchemin->nbOwn,pchemin->nbStock,pchemin->gain,pchemin->prodOmega);
	
	appendStringInfo(&buf, "\noccStock[.]=[");
	_o = pchemin->nbStock;
	obMRange(_n,_o) {
		appendStringInfo(&buf, "%i, ", pchemin->occStock[_n]);
	}
	
	appendStringInfo(&buf, "], occOwn[.]=[");
	_o = pchemin->nbOwn;
	obMRange(_n,_o) {
		appendStringInfo(&buf, "%i, ", pchemin->occOwn[_n]);
	}
	
	appendStringInfo(&buf, "]\nno[.].stockIndex[");
	obMRange(_n,_dim) {
		appendStringInfo(&buf, "%i, ", pchemin->no[_n].stockIndex);
	}
	
	appendStringInfo(&buf, "], no[.].ownIndex[");
	obMRange(_n,_dim) {
		appendStringInfo(&buf, "%i, ", pchemin->no[_n].ownIndex);
	}
	
	appendStringInfo(&buf, "], no[.].flags=[");
	obMRange(_n,_dim) {
		appendStringInfo(&buf, "%x, ", pchemin->no[_n].flags);
	}	
			
	appendStringInfo(&buf, "]\nno[.].omega=[");
	obMRange(_n,_dim) {
		appendStringInfo(&buf, "%f, ", pchemin->no[_n].omega);
	}
	
	appendStringInfo(&buf, "]\npiom[.]=[");
	obMRange(_n,_dim) {
		appendStringInfo(&buf, "%f, ", pchemin->piom[_n]);
	}	
	
	appendStringInfo(&buf, "],spiom[.]=[");
	obMRange(_n,_dim) {
		appendStringInfo(&buf, "%f, ", pchemin->spiom[_n]);
	}	
	
	appendStringInfo(&buf, "]\nfluxExact[.]=[");
	obMRange(_n,_dim) {
		appendStringInfo(&buf, "%f, ", pchemin->fluxExact[_n]);
	}
	
	appendStringInfo(&buf, "]\nomegaCorrige[.]=[");
	obMRange(_n,_dim) {
		appendStringInfo(&buf, "%f, ", pchemin->omegaCorrige[_n]);
	}	
	appendStringInfo(&buf, "]\n");

	return buf.data;
}
