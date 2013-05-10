
#include "postgres.h"
#include "float.h"

#include <float.h>
#include <math.h> 
#include "wolf.h"

#include "lib/stringinfo.h"


TresChemin *flowc_maximum(Tflow *flow);
char * flowc_vecIntStr(short dim,int64 *vecInt);

static TypeFlow _calType(Tflow *flow);
static double _calOmega(TresChemin *chem, bool lnIgnoreOmega);
static void _calOwns(TresChemin *chem);
static void _calGains(TresChemin *chem,double Omega);
static short _flowMaximum(Tflow *flow,double *piom,double *fluxExact);
static Tstatusflow _rounding(short iExhausted, TresChemin *chem,bool _lnIgOmega);
static void _flow_maximum_barter(bool defined,TresChemin *chem);
static bool _flow_maximum_quote(TresChemin *chem);

/******************************************************************************
 * int64 r = floor(d) and error if rounding < 0
 *****************************************************************************/
#define _FLOOR_INT64(d,r) \
do { \
	double __d = floor(d); \
	r = (int64) __d; \
	\
	if(r < 0) r = 0; \
	if(((double)(r)) != __d) { \
		ereport(ERROR, \
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED), \
			 errmsg("in _FLOOR_INT64, %f cannot be rounded",(d))));\
	} \
} while(0)

/******************************************************************************
 * gives the maximum flow of flow
 * return chem->flowNodes[.] and chem->status
 * flowNodes is copied to wolf->x[.].flowr
 *****************************************************************************/
TresChemin *flowc_maximum(Tflow *flow) {
	short _dim = flow->dim;
	short _i;
	bool _defined;
	
	TresChemin *chem = (TresChemin *) palloc(sizeof(TresChemin));
	chem->status = empty;
	chem->type = CYCLE_BEST;
	chem->flow = flow;	
	
	if(_dim == 0) {
		return chem;
	}

	
	#ifdef GL_VERIFY
	if(_dim > FLOW_MAX_DIM) 
		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			 errmsg("max dimension %i reached for the flow",FLOW_MAX_DIM)));
			
	obMRange(_i,_dim) 
	    // all qtt >=0 and proba >=0
		if(flow->x[_i].qtt < 0 ||  flow->x[_i].proba < 0.0) 
			ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("flow with qtt <0 or proba <0.0")));

	obMRange(_i,_dim) {
		short _m;		
		Tfl *o = &flow->x[_i];
				 
		// verify that each b.oid is unique in the flow
		obMRange(_m,_i) {
			if(o->oid == flow->x[_m].oid) {
				ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("createChemin: Tfl[%i].oid=%i found twice",_i,o->oid)));
			}
		}
	}
	#endif
			 
	if(_dim == 1) {
		chem->status = noloop;
		return chem;
	}
	chem->status = undefined;
	
	chem->type = _calType(flow); 
	/* chem->type set to CYCLE_LIMIT if at least one order is LIMIT. 
	Otherise set to CYCLE_BEST	*/
	
	_calOwns(chem);
	/* sets nbOwn,occOwn[.] and ownIndex[.] */
	
    /******************************************************************************
     * quote,prequote,noQttLimit,lnIgnoreOmega,orderLimit
     * 	*,      true,   true,   true,   false   prequote(qlt_requ,qlt_prov)
     *  true,   false,  true,   false,  *       quote2(qlt_requ,qtt_requ,qlt_prov,qtt_prov) 
     *  true,   false,  false,  false,  *       quote3(qlt_requ,qtt_requ,qlt_prov,qtt_prov) 
     *  false,  false,  false,  false,  *       barter(qlt_requ,qtt_requ,qlt_prov,qtt_prov)
     *****************************************************************************/
	
	if(FLOW_IS_IGNOREOMEGA(flow) || FLOW_IS_NOQTTLIMIT(flow)) {
			/* when FLOW_IS_NOQTTLIMIT qtt is not set
			qtt_prov,qtt_requ are set when FLOW_IS_IGNOREOMEGA
			*/
			//elog(WARNING,"before quote: chem %s",flowc_cheminToStr(chem));
			_defined = _flow_maximum_quote(chem);
			
	} else _defined = true;
	
	_flow_maximum_barter(_defined,chem);
	return chem;
}
/******************************************************************************
 * gives the maximum flow
 * returns chem->flowNodes[.] and chem->status
 * flowNodes[.] is copied to flow->x[.].flowr
 *****************************************************************************/
static void _flow_maximum_barter(bool defined,TresChemin *chem) {
	Tflow *flow = chem->flow;
	short _dim = flow->dim;
	short _iExhausted;
	double _Omega;
	bool _lnIgnoreOmega = FLOW_IS_IGNOREOMEGA(flow);
	bool _lnIgnoreQtt = FLOW_IS_NOQTTLIMIT(flow);
	
	if(!defined) goto _dropflow;
	
	// all nodes are used to compute chem->omega[.]				
	_Omega  = _calOmega(chem,false); // _lnIgnoreOmega == false
	
	if( (chem->type == CYCLE_LIMIT) && (_Omega < 1.0 )) {
	    // some orders of the cycle are LIMIT and the product of omega<1.0
		chem->status = refused;
		#ifdef WHY_REJECTED 
			elog(WARNING,"_flow_maximum_barter: refused: 1.0 - Omega =%.10e",1.0-_Omega);
		#endif
		goto _dropflow;
	}


	// omegas are bartered so that the product(omegaCorrige[i]) for i in [0,_dim-1]) == 1 
	_calGains(chem,_Omega); // computes omegaCorrige[.] and piom[.]

	/* maximum flow, as a floating point vector chem->fluxExact[.]
	in order than at least one stock is exhausted by the flow
	and than the ratio between successive elements of flowr is omegaCorrige */
	_iExhausted = _flowMaximum(flow,chem->piom,chem->fluxExact); 

	/* the floating point vector is rounded 
	to the nearest vector x[.].flowr of positive integers */
	chem->status = _rounding(_iExhausted, chem,false);
	/* that is: 
			* each node can provide then flow: x[.].flowr<=x[.].qtt
			* all x[.].flowr > 0
				=> every order provide something
				=> every owner provide something
			* the flow exhausts the cycle: x[i].flowr<=x[i].qtt for some i
			* Omega ~= 1.0 and the error is minimized
			* the limit defined by LIMIT orders are observed (when _lnIgOmega except for the last node)
    */
	if(chem->status == draft) {
		return;
	}
	
_dropflow:
	{
		short _k;

		// the flow is undefined
		obMRange (_k,_dim)
			flow->x[_k].flowr = QTTFLOW_UNDEFINED;
	}
	return;
}

/******************************************************************************
 * lnIgnoreOmega
 * 	true		quote1(qlt_requ,qlt_prov)
 *  false		quote2(qlt_requ,qtt_requ,qlt_prov,qtt_prov) 
 *****************************************************************************/
static bool _flow_maximum_quote(TresChemin *chem) { 
	Tflow *flow = chem->flow;
	short _dim = flow->dim;
	short _i;
	short _iExhausted;  
	double _Omega;
	bool _lnIgnoreOmega = FLOW_IS_IGNOREOMEGA(flow); 
	int64	_qtt_prov,_qtt_requ;
 
	obMRange(_i,_dim - 1) 
		if(flow->x[_i].qtt == 0) {
			// resflow unchanged
			return false;
		}
	flow->x[_dim-1].qtt = QTTFLOW_UNDEFINED;
	
	// all nodes are used to compute chem->omega[.]	except the last node
	_Omega = _calOmega(chem,_lnIgnoreOmega); 
	// _Omega ==1.0,
	
	// omegas are bartered so that the product(omegaCorrige[i]) for i in [0,_dim-1]) == 1 
	_calGains(chem,_Omega); // computes omegaCorrige[.] and piom[.] 

	/* maximum flow, as a floating point vector chem->fluxExact[.]
	in order than at least one stock is exhausted by the flow
	and than the ratio between successive elements of flowr is omegaCorrige */
	_iExhausted = _flowMaximum(flow,chem->piom,chem->fluxExact);
	//elog(WARNING,"after _flowMaximum: chem %s",flowc_cheminToStr(chem));
	/* _iExhausted is not _dim-1 since the quantity of the last node is undefined */
	
	
	
	_FLOOR_INT64(chem->fluxExact[ _dim-2 ],_qtt_requ);
	_FLOOR_INT64(chem->fluxExact[ _dim-1 ],_qtt_prov);
	// elog(WARNING,"after _flowMaximum: qtt_requ:%f -> %li,qtt_prov:%f->%li",chem->fluxExact[ _dim-2 ],_qtt_requ,chem->fluxExact[ _dim-1 ],_qtt_prov);
	if((_qtt_requ == 0 || _qtt_prov == 0)) 
		return false;
	
	if(_lnIgnoreOmega) {
		/* the ratio _qtt_prov/_qtt_requ is increased 
		in order to be shure that prodOmega remains >=1 
		even with previous rounding */
		flow->x[ _dim-1 ].qtt_requ = _qtt_requ;
		flow->x[ _dim-1 ].qtt_prov = _qtt_prov+1;
		
		/* The flag ORDER_IGNOREOMEGA cannot be reset here since several instances 
		of this node are store in _temp. The flag is reset in yflow_reduce() 
		called by the Sql UPDATE instruction 
		*/
		
	}
	flow->x[ _dim-1 ].qtt = _qtt_prov;
	
	return true;
}

/******************************************************************************
 * A chemin is CYCLE_BEST if all orders are ORDER_BEST
 *****************************************************************************/
static TypeFlow _calType(Tflow *flow) {
	short _i,_dim = flow->dim;
	TypeFlow _type = CYCLE_BEST;
	
	obMRange(_i,_dim) 

		if((ORDER_TYPE(flow->x[_i].type)) == ORDER_LIMIT ) {
			_type = CYCLE_LIMIT;
			break;	
	}

	return _type;
}
/******************************************************************************
 * computes chem->omega[.] as product of flow->x[.].qtt_prov/flow->[.].qtt_requ
 * when lnIgnoreOmega is set (ignore omega of the last node), 
 * the last node is ignored
 *****************************************************************************/
static double _calOmega(TresChemin *chem, bool lnIgnoreOmega) {
	Tflow *flow = chem->flow;
	short _n,_ldim,_dim = flow->dim;
	double *omega = chem->omega;
	double _prodOmega;
		
	_prodOmega = 1.0;
	
	_ldim = (lnIgnoreOmega)?(_dim - 1):_dim;
	obMRange(_n,_ldim) {		
			Tfl *b = &flow->x[_n];

			// compute omega and prodOmega
			if(b->qtt_prov == 0 || b->qtt_requ == 0 || b->proba == 0.0) {
				ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("_calOmega: qtt_prov=%li or qtt_requ=%li or proba=%f is zero for Tfl[%i]",
					 	b->qtt_prov,b->qtt_requ,b->proba,_n)));
			}		 
			omega[_n] = GET_OMEGA_P(b);
			_prodOmega *= omega[_n];
	}
	
	if (lnIgnoreOmega) {
		// omega of the last node is ignored.
		//It is set so that the product of omegas becomes 1.0 :
		// omega[_dim-1] 	= 1./product(omega[i] for i in [0,_dim-2] )
		
		omega[_dim-1] = 1.0/_prodOmega;
		_prodOmega = 1.0;
	}
	return _prodOmega;
}

/******************************************************************************
 * sets nbOwn,	the number of partners
 	occOwn[.],	the number of orders of the partner
 	ownIndex[.], the index of the partner
 *****************************************************************************/
static void _calOwns(TresChemin *chem) {
	
	short *occOwn = chem->occOwn; 
	short _n;
	Tflow *flow = chem->flow;
	short _dim = flow->dim;
	// bool _res;		
	
	// defines ownIndex and updates nbOwn
	/****************************************************/
	chem->nbOwn = 0;
	obMRange(_n,_dim) {
		short _m;
		short _ownIndex = chem->nbOwn;		
		Tfl *b = &flow->x[_n];
		short *ownIndex = chem->ownIndex;
			
		obMRange(_m,_ownIndex) {
			if (b->own == flow->x[_m].own) {
				_ownIndex = _m;
				break;// found
			}
		}
		if (_ownIndex == chem->nbOwn) { // not found
			occOwn[_ownIndex] = 0;
			chem->nbOwn += 1;
		}
		occOwn[_ownIndex] += 1;
		ownIndex[_n] = _ownIndex;	
	} 
	

	// sanity checks
	/****************************************************/	
	if(chem->nbOwn == 0) { 
		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			 errmsg("createChemin: nbOwn equals zero")));		
	}

	
	return;	
}

/*******************************************************************************
 1/prodOmega is shared between owners, and then shared between nodes of each owner.
 for each owner, it is:
 	 pow(gain_owner,nb_owners) = 1/prodOmega
 if the owner j owns _occ[j] nodes, it's gain_node for each node is:
 	pow(gain_node[j],_occ[j]) = gain_owner
 	
 input-output
 In:  for i in [0,nbNoeud[ and j in [O,nbOwn[
 	prodOmega,
 	omega[i]
 	nbOwn,
 	nbNoeud,
 	ownOcc[j]
 Out:
 	omegaCorrige[i]
 	piom[i]

	
the result omegaCorrige is such as the product(omegaCorrige[.])== 1 

_piom[i] is the product of omegas between the start of the path and a given node i.
	 For i==0 it is 1.
	 For i!=0 it is omegaCorrige[1]*.. omegaCorrige[i]

	 If we know the flow f[0] at the first node, the flow vector is given by:
		f[i] = f[0] * _piom[i]
		
 *******************************************************************************/

static void _calGains(TresChemin *chem,double prodOmega) {
	short _i;
	short *occOwn = chem->occOwn;
	short *ownIndex = chem->ownIndex;
	double *omega = chem->omega;
	double *omegaCorrige = chem->omegaCorrige;
	short _dim = chem->flow->dim;
	double	*_piom = chem->piom;
	double _gain;

	// the gain is shared between owners
	_gain = pow(prodOmega, 1.0 /((double) chem->nbOwn));

	// it then is shared between nodes
	obMRange(_i,_dim) {
		short _occ = occOwn[ownIndex[_i]];
		
		omegaCorrige[_i] = omega[_i];
		if (_occ == 0) // sanity check
			ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			 errmsg("_calGains: nbOwn <=0 ")));
			 
		else if (_occ == 1)
			omegaCorrige[_i] /= _gain;
		else 
			omegaCorrige[_i] /= pow(_gain, 1.0 / ((double) _occ));
		
	}
	
	// piom are obtained on each node, 
	/***********************************************************************/
	obMRange(_i,_dim) { // loop on nodes
		short _k;
		
		/* computation of _piom */
		_piom[_i] = 1.0;
		if(_i > 0 ) 
			obMRange(_k,_i) 
				_piom[_i] *= omegaCorrige[_k + 1];
	}

	return;
}


/*******************************************************************************
Computes the maximum flow fluxExact of pchemin.
 
This flow fluxExact[.] is such than:
 	fluxExact[i] = omegaCorrige[i] * fluxExact[i-1]
and such as quantities of stock can provide this flow
 
Input-output
************	
 In	pchemin, for i in [0,dim[ 
		->omegaCorrige[i]
		->box[j].qtt

 Out	fluxExact[.] the maximum flow, of pchemin->lon elts

returns the index i of the exhausted node.
		i in [0, dim[
Details
*******

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
static short _flowMaximum(Tflow *flow,double *piom,double *fluxExact) {
	short 	_is, _jn; 
	short	_dim = flow->dim;
	double	_min = -1.0, _cour;
	short	_iExhausted;

	// minimum flow for the first node f[0]
	/***********************************************************************/
	// now _is is an index on nodes
	_iExhausted = 0;
	
	obMRange(_is,_dim) { // loop on nodes
		int64 qtt = flow->x[_is].qtt;
		//elog(WARNING,"qtt[%i]=%li",_is,qtt);
		if( qtt == QTTFLOW_UNDEFINED ) 
			continue; // the flow is not limited by a quantity undefined
			
		_cour = ((double) qtt) /piom[_is]; 
		if ((_min == -1.0) || (_cour < _min)) {
			_min = _cour;
			_iExhausted = _is;
		}
	} 
	
	// propagation to other nodes
	/***********************************************************************/
	obMRange(_jn,_dim)
		fluxExact[_jn] = _min * piom[_jn];
		
	return _iExhausted;
}

/*******************************************************************************
 Computes a distance between two vectors vecExact and vecArrondi. 
 It is the angle alpha made by these vectors.
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

/******************************************************************************
reduce the number of iteration of _rounding
the matrix of bits is at most _NMATBITS long 
******************************************************************************/
#define _NMATBITS (1<<3)
#define _bitSetInMatrix(mat,i) (mat &( 1 << (i & (_NMATBITS -1))))
/*******************************************************************************
floor,flow and mat are vectors of dimension _dim
floor and flow contains integers, and mat bits.
	in: dim,mat,floor
	out:flow
for each i, if the bit i of mat is 0 then flow[i] := floor[i]
			else flow[i] := floor[i]+1
*******************************************************************************/ 
#define _obtain_vertex(dim,mat,floor,flow) \
do { \
	short __j; \
	for(__j=0;__j<dim;__j++) { \
		flow[__j] = floor[__j]; \
		if (_bitSetInMatrix(mat,__j)) \
			flow[__j] += 1; \
	} \
} while(0)
/*******************************************************************************
 flow rounding

 When it can be found, gives the vector pchemin->fluxArrondi of integers
 the nearest of fluxExact, not greater than orders.qtt.

 box->dim short => must be <= 31 (2^dim loops)

 returns
 	 draft if solution
  	 undefined or refused if no solution
 The solution is returned in pchemin->no[.].fluxArrondi


 *******************************************************************************/
static Tstatusflow _rounding(short iExhausted, TresChemin *chem, bool _lnIgOmega) {
	short 	_i,  _k;
	short 	_matcour, _matmax, _matbest;
	bool 	_found;
	int64	*_flowNodes = chem->flowNodes;
	int64	*_floor = chem->floor;
	double 	_distcour, _distbest;
	Tflow 	*flow = chem->flow;
	short 	_dim = flow->dim;
	double  *fluxExact = chem->fluxExact;
	double  *omega = chem->omega;
	Tstatusflow _ret;

	// computes floor[.] as the floor rounding of fluxExact[.]
	/***********************************************************************/
	obMRange(_i,_dim) {
		int64 _f;
		
		_FLOOR_INT64(fluxExact[_i],_f);
		
		if(_i == iExhausted) {
		    if(flow->x[_i].qtt == QTTFLOW_UNDEFINED)
				ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("the node exhausted by the flow is not defined")));
					 
			_floor[_i] = flow->x[_i].qtt; // will not change
			
			if(_f > _floor[_i])
				ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("the flow should exhaust the node %i",_i)));
		} else {
			_floor[_i] = _f;
		}
	}

	//_matmax = 1 << min(_dim,NMATBITS); // one bit for each node 
	_matmax = 1 <<  ((_dim < _NMATBITS) ? _dim : _NMATBITS);
	
	// sanity check
	if(_matmax < 1) {
		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			 errmsg("in _rounding, matmax=%i,flow too long",_matmax)));
	}
	
	// for each vertex of the hypercude
	/***********************************************************************/
	_found = false;
	_ret = undefined;
	
	// at most _NMATBITS^2 iterations
	for (_matcour = 0; _matcour < _matmax; _matcour++) {
		
		// a vertex where the value at index iExhausted changes is rejected
		if(_bitSetInMatrix(_matcour,iExhausted)) 
			goto _continue;
		 
		// obtain the vertex _flowNodes
		/***************************************************************/
		_obtain_vertex(_dim,_matcour,_floor,_flowNodes);
		// _flowNodes[.] = _floor[.] + (1 * _matcour[.])

		// several checkings
		/***************************************************************/
		
		obMRange (_k,_dim) {
		    // verify that qttAvailable >= flowNodes
		    
		    if(flow->x[_k].qtt == QTTFLOW_UNDEFINED)
		        continue;
			
			if(flow->x[_k].qtt < _flowNodes[_k]) {
				#ifdef WHY_REJECTED 
					elog(WARNING,"_rounding 1: NOT order >= flow %s",
						flowc_vecIntStr(_dim,_flowNodes));
				#endif
				goto _continue;
			}
		}

		
		if(chem->type == CYCLE_LIMIT) { 
			short _kp = _dim - 1;

			obMRange(_k,_dim) {
				if ((ORDER_TYPE(flow->x[_k].type) == ORDER_LIMIT) && (!(_lnIgOmega && (_k == (_dim-1))))  ) {
					double _omprime  = ((double) _flowNodes[_k]) / ((double) _flowNodes[_kp]);
					
					// a vertex where the limit of some order is not observed is rejected
					if( !( _omprime <= omega[_k] ) ) {
						#ifdef WHY_REJECTED
							elog(WARNING,"_rounding[%X] 4: NOT _omprime <= omega[%i] %.10e<=%.10e %s with ORDER_LIMIT",
								_matcour,_k,_omprime,omega[_k],flowc_vecIntStr(_dim,_flowNodes));
						#endif
						_ret = refused;
						goto _continue;
					}
				}
				_kp = _k;
			}
		}
				
		/* At this point, 
			* each node can provide flowNodes[.],
			* all flowNodes[.] > 0
				=> every order provide something
				=> every owner provide something
			* the flow exhausts the cycle
			* Omega ~= 1.0 
			* the limit defined by LIMIT orders are observed (when _lnIgOmega except for the last node)
		*/
		
		// choose the best
		/***************************************************************/
		_distcour = _idistance(_dim, fluxExact, _flowNodes);
		// elog(WARNING,"flowc_maximum: matcour=%x _newdist=%f fluxExact=%s flowNodes=%s",_matcour,_distcour,_vecDoubleStr(_dim,fluxExact),_vecIntStr(_dim,_flowNodes));


		// this vertex is better than other found (if any)
		/***************************************************************/
		if( (!_found) || _distbest < _distcour) {
			// _distbest=max(cos(alpha)) === min(alpha) 
			_found = true;
			_distbest = _distcour;
			_matbest = _matcour;

		}
_continue:
		; // choose an other vertex
	};
	if(_found) { // _matbest is defined
	
		_obtain_vertex(_dim,_matbest,_floor,_flowNodes);
		// _flowNodes[.] is obtained from _matbest[.] and _floor[.]
		//elog(WARNING,"flowc_maximum: _matbest=%x",_matbest);
		
		obMRange (_k,_dim) {
			flow->x[_k].flowr = _flowNodes[_k];	
		}
		#ifdef WHY_REJECTED
			elog(WARNING,"flowc_maximum: chosen= %s",flowc_vecIntStr(_dim,_flowNodes));
		#endif
		
		_ret = draft; 
	} // else _ret is undefined or refused
	return _ret; 
}

/******************************************************************************
 * 
 *****************************************************************************/
char * flowc_cheminToStr(TresChemin *chem) {
	StringInfoData buf;
	Tflow *flow = chem->flow;
	short _dim = flow->dim;
	short _n,_o;
	
	initStringInfo(&buf);
	appendStringInfo(&buf, "\n%s\n",yflow_ndboxToStr(flow,true));

	appendStringInfo(&buf, "CHEMIN  status=%s type=%s nbOwn=%i ", 
		yflow_statusToStr(chem->status),
		yflow_typeToStr(chem->type),chem->nbOwn);
			
	if(chem->status == draft || chem->status == undefined) {

		appendStringInfo(&buf, "\noccOwn[.]=[");
		_o = chem->nbOwn;
		obMRange(_n,_o) {
			appendStringInfo(&buf, "%i, ", chem->occOwn[_n]);
		}
	
		appendStringInfo(&buf, "]\nownIndex[.]=[");
		obMRange(_n,_dim) {
			appendStringInfo(&buf, "%i, ", chem->ownIndex[_n]);
		}	
			
		appendStringInfo(&buf, "]\nomega.[.]=[");
		obMRange(_n,_dim) {
			appendStringInfo(&buf, "%f, ", chem->omega[_n]);
		}
	
		appendStringInfo(&buf, "]\npiom[.]=[");
		obMRange(_n,_dim) {
			appendStringInfo(&buf, "%f, ", chem->piom[_n]);
		}		
	
		appendStringInfo(&buf, "]\nfluxExact[.]=[");
		obMRange(_n,_dim) {
			appendStringInfo(&buf, "%f, ", chem->fluxExact[_n]);
		}
	
		appendStringInfo(&buf, "]\nomegaCorrige[.]=[");
		obMRange(_n,_dim) {
			appendStringInfo(&buf, "%f, ", chem->omegaCorrige[_n]);
		}	
	
		appendStringInfo(&buf, "]\nflowNodes[.]=[");
		obMRange(_n,_dim) {
			appendStringInfo(&buf, INT64_FORMAT ", ", chem->flowNodes[_n]);
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
		appendStringInfo(&buf,  INT64_FORMAT ", ", vecInt[_n]);
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


