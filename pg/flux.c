/* $Id: flux.c 22 2010-01-15 16:00:22Z olivier.chaussavoine $ */
/*
 openbarter - The maximum wealth for the minimum collective effort
 Copyright (C) 2008 olivier Chaussavoine

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.

 olivier.chaussavoine@openbarter.org
 */
#include <flux.h>
#include <math.h> /* pow(x,y), sqrt(x),floor(x)s */
#include <tests.h>
//#include <point.h>


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
static double _idistance(const unsigned char lon, 
				const double *vecExact,
				const ob_tQtt *vecArrondi) {
	double _s, _na, _va;
	unsigned char _i;

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

 It must be called with:
	pchemin->nbOwn !=0 and pchemin->no[.]ownOcc !=0
 It returns ob_flux_CerCgain in this case, and 0 otherwise.
 *******************************************************************************/

static int _calGains(ob_tChemin *pchemin,double omegaCorrige[]) {
	unsigned char _i, _occ;
	double no_gain[obCMAXCYCLE];

	if (!pchemin->nbOwn)
		return ob_flux_CerCheminNoOwn;
	// the gain is shared between owners
	pchemin->gain = pow(pchemin->prodOmega, -1.0 /((double) pchemin->nbOwn));

	// next, it is shared between nodes
	obMRange(_i,pchemin->nbNoeud) {
		_occ = pchemin->no[pchemin->no[_i].ownIndex].ownOcc;
		if (!_occ)
			return ob_flux_CerCgain;
		else if (_occ == 1)
			no_gain[_i] = pchemin->gain;
		else
			no_gain[_i] = pow(pchemin->gain, 1.0 / ((double) _occ));
	}
	
	obMRange(_i,pchemin->nbNoeud)
		omegaCorrige[_i] = pchemin->no[_i].noeud.omega * no_gain[_i];
	return 0;
}

/*******************************************************************************
Computes the maximum flow fluxExact of pchemin.
 
This flow fluxExact[.] is such than:
 	fluxExact[i] = omegaCorrige[i] * fluxExact[i-1]
and such as quantities of stock can provide this flow
 
Each stock can be used by several nodes.
 
Input-output
************	
 In	pchemin, for i in [0,nbNoeud[ and j in [0,nbStock[
		->cflags
		->no[i].omegaCorrige
		->no[i].stockIndex = j
		->no[j].stockOcc
		->no[j].stock.qtt

 Out	fluxExact[.] the maximum flow, of pchemin->lon elts

returns the index i of the exhausted stock.
	when ob_flux_CLastIgnore, 
		i in [0,->->nbStock -1[
	else
		i in [0,->->nbStock[
Details
*******
If flags & obCLastIgnore: The flow is not limited by the last node
This node has always it's own stock.

_poim[i] is the product of omegas between the start of the path and a given node i.
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
static int _fluxMaximum(const ob_tChemin *pchemin,double omegaCorrige[], double *fluxExact) {
	unsigned char _is, _jn, _lon, _jm;
	double _piom[obCMAXCYCLE]; //  _fPiomega(i)
	double _spiom[obCMAXCYCLE]; // (SUM(_fPiomega(i)) for i in Sj)
	double _min, _cour;
	int	_iStockExhausted;

	_lon = pchemin->nbNoeud;
	
	memset(_spiom, 0, sizeof(_spiom));

	// piom are obtained on each node, 
	/********************************/
	obMRange(_jn,_lon) {// loop on nodes
		unsigned char _k;

		_is = pchemin->no[_jn].stockIndex;
		/* computation of _piom */
		_piom[_jn] = 1.0;
		if(_jn > 0 ) obMRange(_k,_jn) {
			_piom[_jn] *= omegaCorrige[_k + 1];
		}
		/* end */
		_spiom[_is] += _piom[_jn]; // sum of _piom for each stock
	}

	// minimum flow for the first node f[0]
	/*********************************/
	_lon = pchemin->nbStock;
	_jm = (pchemin->cflags & ob_flux_CLastIgnore) ? (_lon - 1) : _lon;

	obMRange(_is,_jm) { // loop on stocks
		_cour = ((double) (pchemin->no[_is].stock.qtt)) / _spiom[_is] ;
		if ((_is == 0) || (_cour < _min)) {
			_min = _cour;
			_iStockExhausted = (int) _is;
		}
	}
	//printf("_min =%f\n",_min);

	// distributed between nodes
	/****************************/
	_lon = pchemin->nbNoeud;
	obMRange(_jn,_lon)
		fluxExact[_jn] = _min * _piom[_jn];
	// ob_flux_printtableaudoubles(stdout,"flux",fluxExact,_lon);	
	return _iStockExhausted;
}

/*******************************************************************************
 flow rounding

 When it can be found, gives the vector pchemin->fluxArrondi of ingeters
 the nearest of fluxExact not greater than stocks.

 pchemin->nbNoeud must be <= obCMAXCYCLE < 32 (2^31 loops !!)

 returns
 	 0 if a solution is found
  	 <0 on error
 The solution is returned in pchemin->no[.].fluxArrondi

 when pchemin->cflags & obCLastIgnore,
 the last node should use a stock that is not used by others
 In this case this stock does not limit the flow

 *******************************************************************************/
static int _arrondir(const double *fluxExact, ob_tChemin *pchemin,int _iStockExhausted) {
	unsigned char _i, _j, _k, _lonNode, _lonStock, _lonStockl,_lonNodel;
	int _matcour, _matmax;
	int _ret = 0;
	bool _notFound;
	ob_tQtt _flowNodes[obCMAXCYCLE], _flowStocks[obCMAXCYCLE], _r;
	ob_tQtt _floor[obCMAXCYCLE],_f;
	double _newdist, _maxdist;

	_notFound = true;
	_lonNode = _lonNodel = pchemin->nbNoeud;
	_lonStock = _lonStockl = pchemin->nbStock;

	if (pchemin->cflags & ob_flux_CLastIgnore) {
		_lonNodel -= 1; 
		_lonStockl -= 1;
		/* the stock of the pivot should not be used by any other node when ob_flux_CLastIgnore
		=> index of stocks used by nodes other than the pivot should be in [0,_lonStockl[ */
		_k = 0;
		obMRange(_i,_lonNodel) {
			if( _k < pchemin->no[_i].stockIndex)
				_k = pchemin->no[_i].stockIndex;
		}
		_k +=1;

		if(_k != _lonStockl) {
			_ret = ob_flux_CerStockPivotUsed;
			goto fin;
		}
	}

	obMRange(_i,_lonNode) {
		_f = floor(fluxExact[_i]);
		if(_f < 0) _f = 0; // security
		_floor[_i] = _f;
	}

	// the stock exhausted should be in [0,_lonstockl[
	if(_iStockExhausted >= _lonStockl) {
		_ret = ob_flux_CerStockPb; goto fin;
	}

	_matmax = 1 << ((int) _lonNode); // one bit for each node

	// for each vertex of the hypercude
	/**********************************/
	for (_matcour = 0; _matcour < _matmax; _matcour++) {
		bool _admissible = true;
		
		// obtain the vertex _flowNodes
		/******************************/
		obMRange (_j,_lonNode) {
			_r = _floor[_j];
			if (_matcour & (1 << ((int) _j)))
				_r += 1;
			_flowNodes[_j] = _r;
		}


		// obtain _flowStocks
		/********************/
		obMRange (_k,_lonStock)
			_flowStocks[_k] = 0;

		obMRange (_j,_lonNode) {
			_k = pchemin->no[_j].stockIndex;
			_flowStocks[_k] += _flowNodes[_j];
		}

		// several checking
		/*****************************************/
		obMRange (_k,_lonStockl) {

			// All _flowStocks[.] > 0
			if(_flowStocks[_k] == 0) {
				_admissible = false; break;
			}

			if(_k == (unsigned char) _iStockExhausted) {
				// verify the flow exhausts the stock
				if(_flowStocks[_k] != pchemin->no[_k].stock.qtt ) {
					_admissible = false; break;
				}
			} else {
				// verify the flow is not greater than the stock
				if ( _flowStocks[_k] > pchemin->no[_k].stock.qtt ) {
					_admissible = false; break;
				}
			}
		}
		if (!_admissible) continue; // the vertex is rejected
		
		/* At this point, each stock can provide flowStock{],
		all flowStock[.] > 0
			=> every stock provide something
			=> every one provide something
		the cycle exhausts the flow  */


		// choose the best
		/*****************/
		_newdist = _idistance(_lonNode, fluxExact, _flowNodes);


		// this vertex is better than other found (if any)
		/************************************************/
		if( _notFound || _maxdist < _newdist) {
			_notFound = false;
			_maxdist = _newdist;
			obMRange (_k,_lonNode)
				pchemin->no[_k].fluxArrondi = _flowNodes[_k];
		}
	}
	if(_notFound) _ret = ob_flux_CerFlowNotFound;
	else _ret = 0;
fin:
	return (_ret); /*
		0 if a solution is found
		< 0 on error */
}
/*******************************************************************************
 pchemin is initialized with 0 nodes.
 cflags is an oring of:
 obCLastIgnore
 obCFast
 *******************************************************************************/
void ob_flux_cheminVider(ob_tChemin *pchemin, const char cflags) {
	memset(pchemin, 0, sizeof(ob_tChemin));
	pchemin->cflags = cflags & (~ob_flux_CFlowDefined);
	// printf("cflags = %x, %x\n",pchemin->cflags,~obCFlowDefined);
	return;
}
int ob_flux_cheminLoop(const ob_tChemin *pchemin,const ob_tId oid) {
	unsigned char _i;

	obMRange(_i,pchemin->nbNoeud)
		if (pchemin->no[_i].noeud.oid == oid) {
			if(_i == pchemin->nbNoeud-1)
				return ob_flux_CerCheminPom3;
			else
				return ob_flux_CerLoopOnOffer;
		}
	return 0;
}
/*******************************************************************************
 adds a node (pnoeud,pstock) to pchemin
 pnoeud and pstock can be already initialized in pchemin
 return 0 when no error, or an error defined in flux.h

Verifies:
	all nodes are distinct
	
	updates the chemin:

	->prodOmega = product of omega[i] for  i in [0,nbNoeud[
	->nbNoeud = number of nodes <= obCMAXCYCLE
	->nbStock = number of stocks <= nbNoeud
	->nbOwn = number of owners <= nbStock

	and 3 tables:

	no[i].noeud,no[i].ownIndex,no[i].stockIndex			with i in [0,nbNoeud[
	no[j].own,no[j].ownOcc					with j in [0,nbOwn[
	no[k].stock,no[k].stockOcc					with k in [0,nbStock[
	
	ownIndex and stockIndex are used to refer to owner and stock from a given node
 *******************************************************************************/
int ob_flux_cheminAjouterNoeud(ob_tChemin *pchemin, const ob_tStock *pstock,
		const ob_tNoeud *pnoeud,ob_tLoop *loop) {

	unsigned char _i;
	unsigned char _noeudIndex = 0, _ownIndex = 0, _stockIndex = 0;
	//double _fluxExact[obCMAXCYCLE];
	int _ret;

#ifndef NDEBUG // mise au point
	//elog(INFO,"NDEBUG not defined, complete checks are performed");
	if (pnoeud->omega < 0.) { // should be > 0. ?????
		_ret = ob_flux_CerOmegaNeg;
		return _ret;
	}
	if (pstock->sid != pnoeud->stockId) {
		_ret = ob_flux_CerNoeudNotStock;
		return _ret;
	}
	/* pchemin->nbNoeud<=obCMAXCYCLE after increment,
	 * hence <obCMAXCYCLE before.
	 */
	if (pchemin->nbNoeud >= obCMAXCYCLE) { 
		_ret = ob_flux_CerCheminTropLong;
		return _ret;
	}
#endif
	// verify that the node is not already in the chemin
	_ret = ob_flux_cheminLoop(pchemin,pnoeud->oid);
	if(_ret) return _ret;

	_noeudIndex = pchemin->nbNoeud;
	pchemin->nbNoeud += 1;

	//printf("noeudIndex %i\n",_noeudIndex);
	// elog(INFO,"noeud %lli noeudIndex %i",pnoeud->oid,_noeudIndex);
	// node insert
	if (&pchemin->no[_noeudIndex].noeud != pnoeud)
		// not already copied
		memcpy(&(pchemin->no[_noeudIndex].noeud), pnoeud, sizeof(ob_tNoeud));

	// if the chemin was empty
	if (!_noeudIndex)
		pchemin->prodOmega = 1.;
	pchemin->prodOmega *= pnoeud->omega;
	// elog(INFO,"prodOmega[%i]=%f",_noeudIndex,pchemin->prodOmega);

	//printf("owner:");ob_flux_voirDBT(stdout,&pstock->own,1);
	// search for the owner
	_ownIndex = pchemin->nbOwn;
	obMRange(_i,pchemin->nbOwn) {
		if (pstock->own == pchemin->no[_i].own) {
			_ownIndex = _i;
			break;// found
		}
	}
	if (_ownIndex == pchemin->nbOwn) { // not found
		pchemin->no[_ownIndex].own = pstock->own;
		pchemin->no[_ownIndex].ownOcc = 0;
		pchemin->nbOwn += 1;
	}
	//printf("ownIndex %i\n",_ownIndex);
	pchemin->no[_ownIndex].ownOcc += 1;
	pchemin->no[_noeudIndex].ownIndex = _ownIndex;

	//printf("sid:");ob_flux_voirDBT(stdout,&pnoeud->stockId,1);
	// search for the stock
	_stockIndex = pchemin->nbStock;
	obMRange(_i,pchemin->nbStock) {
		if (pchemin->no[_i].stock.sid == pnoeud->stockId) {
			_stockIndex = _i;
			break;// found
		}
	}
	if (_stockIndex == pchemin->nbStock) {
		// not found, it must be inserted
		_stockIndex = pchemin->nbStock;
		// not already copied
		if (&pchemin->no[_stockIndex].stock != pstock)
			memcpy(&(pchemin->no[_stockIndex].stock), pstock, sizeof(ob_tStock));
		pchemin->no[_stockIndex].stockOcc = 0;
		pchemin->nbStock += 1;
	}
	//printf("stockIndex %i\n",_stockIndex);
	pchemin->no[_stockIndex].stockOcc += 1;
	pchemin->no[_noeudIndex].stockIndex = _stockIndex;
	pchemin->no[_noeudIndex].flags = 0;

	//printf("fin\n");
	return (0);
}
/******************************************************************************
 * gives the maximum flow of pchemin
 * return 
	0 if a flow was found
	<0 on error
 *****************************************************************************/
int ob_flux_fluxMaximum(ob_tChemin *pchemin) {
	int _ret;
	double _omegaCorrige[obCMAXCYCLE];
	double _fluxExact[obCMAXCYCLE];
	int _iStockExhausted;
	//unsigned char _i;

	if(pchemin->cflags & ob_flux_CLastIgnore) {
		/* omega of the last node is set in order than the product prodOmega becomes 1.0 :
			omega[_nbNoeud-1] = 1./product(omega[i]) for i in [0,_nbNoeud-2] 
		*/
		pchemin->no[pchemin->nbNoeud-1].noeud.omega = pchemin->no[pchemin->nbNoeud-1].noeud.omega/pchemin->prodOmega;
		pchemin->prodOmega = 1.0;
	}
	// omegas are corrected
	_ret = _calGains(pchemin,_omegaCorrige);

	if (_ret) goto fin;

	// maximum flow
	/*elog(INFO,"lastIgnode %i",(pchemin->cflags & ob_flux_CLastIgnore) ?1:0);
	obMRange(_i,pchemin->nbStock) elog(INFO,"\t_stock[.].qtt %lli",pchemin->no[_i].stock.qtt);
	*/
	_iStockExhausted = _fluxMaximum(pchemin,_omegaCorrige,_fluxExact);

	/*obMRange(_i,pchemin->nbNoeud) {
		elog(INFO,"\t_fluxExact[.]=%f, omega[.]=%f",_fluxExact[_i],pchemin->no[_i].noeud.omega);
	}*/
	_ret = _arrondir(_fluxExact, pchemin,_iStockExhausted);

	//elog(INFO,"_flux %i",_fluxNul?1:0);
	if (_ret == 0 ) {
		pchemin->cflags |= ob_flux_CFlowDefined;
	}
fin:
	return _ret;
}
/******************************************************************************
 * verify pchemin consistancy
 *****************************************************************************/
int ob_flux_cheminError(ob_tChemin *pchemin) {
	int ret = 0;
	unsigned char _occ, _is, _in, _iw, _ins;
	double _pom;
	int _err;

	if (!pchemin || (pchemin->nbNoeud > obCMAXCYCLE)) {
		ret = ob_flux_CerCheminTropLong;
		goto fin;
	}
	// nbStock <nbNoeud
	if (pchemin->nbStock > pchemin->nbNoeud) {
		// printf("Stocks %i Noeuds %i\n",pchemin->nbStock,pchemin->nbNoeud);
		ret = ob_flux_CerCheminTropStock;
		goto fin;
	}
	// sum(no[.].stockOcc)==nbNoeud
	_occ = 0;
	obMRange(_is,pchemin->nbStock)
		_occ += pchemin->no[_is].stockOcc;
	if (_occ != pchemin->nbNoeud) {
		ret = ob_flux_CerCheminPbOccStock;
		goto fin;
	}
	// sum(no[.].ownOcc)==nbNoeud
	_occ = 0;
	obMRange(_iw,pchemin->nbOwn)
		_occ += pchemin->no[_iw].ownOcc;
	if (_occ != pchemin->nbNoeud) {
		ret = ob_flux_CerCheminPbOccOwn;
		goto fin;
	}
	// no[.].stockIndex < nbStock
	obMRange(_in,pchemin->nbNoeud) {
		if (pchemin->no[_in].stockIndex >= pchemin->nbStock) {
			ret = ob_flux_CerCheminPbIndexStock;
			goto fin;
		}
	}
	// no[no[.].ownIndex].own == no[no[.].stockIndex].stock.own
	obMRange(_in,pchemin->nbNoeud) {
		_is = pchemin->no[_in].stockIndex;
		_iw = pchemin->no[_in].ownIndex;
		if (pchemin->no[_iw].own != pchemin->no[_is].stock.own) {
			ret = ob_flux_CerCheminPbOwn;
			goto fin;
		}
	}
	// no[.].ownIndex < nbOwn
	obMRange(_in,pchemin->nbNoeud) {
		if (pchemin->no[_in].ownIndex >= pchemin->nbOwn) {
			ret = ob_flux_CerCheminPbIndexOwn;
			goto fin;
		}
	}
	// no[.].noeud.omega > 0.
	// si (nbNoeud) prodOmega==prod(no[.].noeud.omega)
	// sinon ==0
	_err = 0;
	if (pchemin->nbNoeud) {
		_pom = 1.0;
		obMRange (_in,pchemin->nbNoeud) {
			_pom *= pchemin->no[_in].noeud.omega;
			if (pchemin->no[_in].noeud.omega <= 0.) {
				elog(INFO,"pchemin->no[%i].noeud.omega=%f <=0.",_in,pchemin->no[_in].noeud.omega);
				_err = 1;
				break;
			}
		}
	} else _pom = 0.;
	if(_err == 1) {
		ret = ob_flux_CerCheminPom;
		goto fin;
		obMTRACE(ret);
		return ret;
	}
	if(pchemin->prodOmega != _pom) {
		elog(INFO,"pchemin->prodOmega %016llx!= _pom %16llx",
				*((long long int*)(&pchemin->prodOmega)),
				*((long long int*)(&_pom )) );
		ret = ob_flux_CerCheminPom2;
		goto fin;
		obMTRACE(ret);
		return ret;
	}

	_err = 0;
	obMRange(_in,pchemin->nbNoeud) {
		_is = pchemin->no[_in].stockIndex;
		_iw = pchemin->no[_in].ownIndex;
		_ins = (_in+1) % pchemin->nbNoeud;
		//printf("_in=%i,_ins=%i,nbNoeud=%i\n",_in,_ins,pchemin->nbNoeud);
		if(pchemin->no[_is].stock.nF != pchemin->no[_in].noeud.nF) {
			_err += 1;
			//printf("sid incoherente:\n");
			//ob_point_voirStock(&pchemin->no[_is].stock);
			//ob_point_voirNoeud(&pchemin->no[_is].noeud);
		}
		if(pchemin->no[_iw].own != pchemin->no[_is].stock.own) {
			_err += 10;
			//printf("owns incoherent:\n");
			//ob_flux_voirDBT(stdout,&pchemin->no[_iw].own,1);
			//ob_point_voirStock(&pchemin->no[_is].stock);
		}
		if(_in>=_ins) continue;
		if(pchemin->no[_in].noeud.nF != pchemin->no[_ins].noeud.nR) {
			//printf("noeud[%i].nF!=noeud[%i].nR noeud[%i],noeud[%i]: \n",_in,_ins,_in,_ins);
			//ob_point_voirNoeud(&pchemin->no[_in].noeud);
			//ob_point_voirNoeud(&pchemin->no[_ins].noeud);
			_err += 100;
		}
	}
	if (_err) {
		elog(INFO,"_err=%i",_err);
		ret = ob_flux_CerCheminCuillere;
		goto fin;
	}
	ret = 0;
fin:
	if(ret) obMTRACE(ret);
	return ret;
}
				/* usage, for the owner[k], with k in [0,pchem->nbOwn[:
				 * pown = ob_flux_cheminGetOwn(pchem,k);*/
ob_tOwnId *ob_flux_cheminGetOwn(ob_tChemin *pchemin, int iw) {
	ob_tOwnId *_pown;
	unsigned char _iw;

	if (!pchemin->nbOwn)
		_pown = NULL; // pchemin is empty
	else {
		_iw = (unsigned char) iw;
		_iw = _iw % pchemin->nbOwn;
		if (_iw < 0)
			_iw += pchemin->nbOwn;
		_pown = &(pchemin->no[_iw].own);
	}
	return _pown;
}

double ob_flux_cheminGetOmega(ob_tChemin *pchemin) {
	return pchemin->prodOmega; // 0. if empty
}
int ob_flux_cheminGetNbNode(ob_tChemin *pchemin) {
	int i;
	i = (int) pchemin->nbNoeud;
	return ((i < obCMAXCYCLE) ? i : obCMAXCYCLE);
}
int ob_flux_cheminGetNbStock(ob_tChemin *pchemin) {
	int i;
	i = (int) pchemin->nbStock;
	return ((i < obCMAXCYCLE) ? i : obCMAXCYCLE);
}
int ob_flux_cheminGetNbOwn(ob_tChemin *pchemin) {
	int i;
	i = (int) pchemin->nbOwn;
	return ((i < obCMAXCYCLE) ? i : obCMAXCYCLE);
}
// adress of the node[io]
// io can be negative
ob_tNoeud *ob_flux_cheminGetAdrNoeud(ob_tChemin *pchemin, int io) {
	ob_tNoeud *_pnode;
	unsigned char _io;

	if (!pchemin->nbNoeud)
		_pnode = NULL; // pchemin is empty
	else {
		_io = (unsigned char) io;
		_io = _io % pchemin->nbNoeud;
		if (_io < 0)
			_io += pchemin->nbNoeud;
		_pnode = &(pchemin->no[_io].noeud);
	}
	return _pnode;
}
// address of the stock of the node[io]
// io can be negative
ob_tStock *ob_flux_cheminGetAdrStockNode(ob_tChemin *pchemin, int io) {
	ob_tStock *pstock;
	unsigned char _io;

	if (!pchemin->nbNoeud)
		pstock = NULL; // pchemin is empty
	else {
		_io = (char) io;
		_io = _io % pchemin->nbNoeud;
		if (_io < 0)
			_io += pchemin->nbNoeud;
		pstock = &(pchemin->no[pchemin->no[_io].stockIndex].stock);
	}
	return pstock;
}
/* gives the address of the stock of the last node,
 * if chemin->nbNoeud==0, gives the address of the first stock
 * this stock should have been initialized by initPoint */
ob_tStock *ob_flux_cheminGetAdrStockLastNode(ob_tChemin *pchemin) {
	ob_tStock *pstock;
	unsigned char _io;

	if (!pchemin->nbNoeud) // pchemin is empty
		return &(pchemin->no[0].stock);
	else {
		_io = pchemin->nbNoeud - 1;
		pstock = &(pchemin->no[pchemin->no[_io].stockIndex].stock);
	}
	return pstock;
}

//index of the stock of the node[io]
int ob_flux_cheminGetSindex(ob_tChemin *pchemin, int io) {
	return (int) pchemin->no[io].stockIndex;
}
ob_tQtt ob_flux_cheminGetQtt(ob_tChemin *pchemin, int io) {
	return pchemin->no[io].fluxArrondi;
}
/* returns the number of nodes, tabStocks and the number of stocks nbStock
 tabStocks contains information of the stocks, except qtt
 which is not the qtt of the stock, but the sum of the flow from this stock
 */
int ob_flux_GetTabStocks(ob_tChemin *pchemin, ob_tStock *tabStocks,int *nbStock) {
	unsigned char _io, _is;
	// ob_tQtt qtt;

	if (!pchemin->nbNoeud || !(pchemin->cflags & ob_flux_CFlowDefined)) {
		*nbStock = 0;
		return 0;
	}
	obMRange(_is,pchemin->nbStock) {
		memcpy(&tabStocks[_is], &(pchemin->no[_is].stock), sizeof(ob_tStock));
		tabStocks[_is].qtt = 0;
	}
	obMRange(_io,pchemin->nbNoeud) {
		_is = pchemin->no[_io].stockIndex;
		tabStocks[_is].qtt += pchemin->no[_io].fluxArrondi;
	}
	*nbStock = pchemin->nbStock;
	return pchemin->nbNoeud;
}

// gives the new owner
ob_tOwnId *ob_flux_cheminGetNewOwn(ob_tChemin *pchemin, int io) {
	unsigned char _io;

	_io = (unsigned char) (io + 1);
	_io = _io % pchemin->nbNoeud;
	if (_io < 0)
		_io += pchemin->nbNoeud;
	return (&(pchemin->no[pchemin->no[_io].ownIndex].own));
}

size_t ob_flux_cheminGetSize(ob_tChemin *pchemin) {
	unsigned char lon;

	lon = pchemin->nbNoeud;
	if (!lon)
		lon = 1; // TODO why?
	return (sizeof(ob_tChemin) + (lon * sizeof(ob_tNo)));
}

/*******************************************************************************
 USAGES
 ob_flux_fvoirEchange(stdout,pchemin,flags)

 provides 1 line:
 s2w2o5 DfI 24.002 ok:>o003s004q0012->o004s004q0012->o003s004q00012-:
 meaning:
 2 stocks,
 2 owners,
 5 offers,
 24.002 prodOmega,
 D	the flow is defined,
 f	fast,no checkings,
 I	last ignore,
 ok	path ok,
 ....



 *******************************************************************************/
#define obCFMTQTT " f%05lli "
#define obCFMTDBT "%016llX"
int ob_flux_svoirQtt(ob_tMsg *msg, ob_tQtt *pqtt, int flags) {
	int ret;
	ob_flux_makeMessage(msg,obCFMTQTT, *pqtt);
	if (flags & 1)
		ret = ob_flux_makeMessage(msg, "\n");
	else
		ret = ob_flux_makeMessage(msg, " ");
	return ret;
}
void ob_flux_voirQtt(FILE *stream, ob_tQtt *pqtt, int flags) {
	ob_tMsg msg;
	int ret;

	msg.begin = NULL;
	ret = ob_flux_svoirQtt(&msg,pqtt,flags);
	if(ret ==0) {
		fprintf(stream,"%s",msg.begin);
		pfree(msg.begin);
	} else fprintf(stream,"Error in ob_flux_svoirQtt");
	return;
}
/*****************************************************************************/
/* displays the string of bytes
 * flags &1 avec /n
 * flags &2 forme courte
 * */
int ob_flux_svoirDBT(ob_tMsg *msg, int64 *dbt, int flags) {
	int ret;
	ob_flux_makeMessage(msg,obCFMTDBT, *dbt);
	if (flags & 1)
		ret = ob_flux_makeMessage(msg, "\n");
	else
		ret = ob_flux_makeMessage(msg, " ");
	return ret;
}
void ob_flux_voirDBT(FILE *stream, int64 *dbt, int flags) {
	ob_tMsg msg;
	int ret;

	msg.begin = NULL;
	ret = ob_flux_svoirDBT(&msg,dbt,flags);
	if(ret ==0) {
		fprintf(stream,"%s",msg.begin);
		pfree(msg.begin);
	} else fprintf(stream,"Error in ob_flux_svoirDBT");
	return;
}
/*******************************************************************************
 USAGES
 ob_flux_svoirChemin(msg,pchemin,flags)

 provides 1 heading and one line for each commit.

 Heading:
 	 s2w2o5 DFI 24.002 ok:
 meaning:
 2 stocks,
 2 owners,
 5 offers,
 24.002 prodOmega,
 D	the flow is defined, (D,_)
 F	fast,no checkings, (F,_)
 I	last ignore, (I,_)
 OK	path ok, (OK,ERROR)

 line for each commit:
 	 >o003s004q0012->o004s004q0012->o003s004q00012-:



 *******************************************************************************/

int ob_flux_svoirChemin(ob_tMsg *msg, ob_tChemin *pchemin, int flags) {
	int _i, _nb,ret;//, _ecrit;
	bool _diag;
	//char _fin;

	_diag = ob_flux_cheminError(pchemin);

	_nb = (int) pchemin->nbNoeud;
	if(_nb > obCMAXCYCLE) {
		ret = ob_flux_makeMessage(msg, "chemin->nbNoeud > obCMAXCYCLE - ERROR\n");
		return ret;
	}

	ret = ob_flux_makeMessage(msg, "Draft S%c W%c O%c %c%c%c %.3f %s: \n", '0' + pchemin->nbStock,
			'0' + pchemin->nbOwn, '0' + pchemin->nbNoeud, (pchemin->cflags
					& ob_flux_CFlowDefined) ? 'D' : '_', (pchemin->cflags
					& ob_flux_CFast) ? 'F' : '_', (pchemin->cflags
					& ob_flux_CLastIgnore) ? 'I' : '_', pchemin->prodOmega,
			_diag ? "ERROR" : "OK");
	if (!_nb) {
		ret = ob_flux_makeMessage(msg, "chemin empty\n");
		return ret;
	}
	obMRange(_i,_nb) {
		ret = ob_flux_makeMessage(msg, "b>");
		ret = ob_flux_makeMessage(msg, " q%03lli->q%03lli",pchemin->no[_i].noeud.nR,pchemin->no[_i].noeud.nF);
		ret = ob_flux_makeMessage(msg, " s[%c]x",'0'+pchemin->no[_i].stockIndex);
		ret = ob_flux_svoirDBT(msg, &pchemin->no[_i].noeud.stockId, 0);
		ret = ob_flux_makeMessage(msg, " w[%c]x",'0'+pchemin->no[_i].ownIndex);
		ret = ob_flux_svoirDBT(msg, &pchemin->no[_i].noeud.own, 0);
		ret = ob_flux_makeMessage(msg, " om%6.3f ix",pchemin->no[_i].noeud.omega);
		ret = ob_flux_svoirDBT(msg, &pchemin->no[_i].noeud.oid, 0);
		if (pchemin->cflags & ob_flux_CFlowDefined) {
			ret = ob_flux_makeMessage(msg, " f%05lli\n", pchemin->no[_i].fluxArrondi);
		} else {
			ret = ob_flux_makeMessage(msg, " Flow?\n");
		}
		//if (_i==_nb-1) _fin = '\n'; else _fin = '-';
		//ob_flux_makeMessage(msg,"%c",_fin);
	}
	return ret;
}
void ob_flux_voirChemin(FILE *stream, ob_tChemin *pchemin, int flags) {
	ob_tMsg msg;
	int ret;

	msg.begin = NULL;
	ret = ob_flux_svoirChemin(&msg,pchemin,flags);
	if(ret ==0) {
		fprintf(stream,"%s",msg.begin);
		pfree(msg.begin);
	} else fprintf(stream,"Error in ob_flux_svoirChemin");
	return;
}

int ob_flux_makeMessage(ob_tMsg *msg,const char *fmt, ...) {
	 char *p = NULL;
	 size_t remains,bloc = 4;
	 int n = 0;
	 va_list ap;

	if(msg->begin == NULL) {
		msg->error = 1;
		msg->current = 0;
		msg->size = bloc;
		if((msg->begin = palloc(bloc)) == NULL) return -1;
		msg->error = 0;
	}
	if(msg->error) return -1;

	while(1) {
		va_start(ap, fmt);
		remains = msg->size - msg->current;
		n = vsnprintf(&msg->begin[msg->current],remains, fmt, ap);
		va_end(ap);

		if(n > -1 && n < remains){
			msg->current += n;
			return 0;
		}

		/* failed: have to try again, alloc more mem. */
		if(n > -1)      /* glibc 2.1 */
		bloc = n + 1;
		else            /* glibc 2.0 */
		bloc *= 2;     /* twice the old size */

		if((p = repalloc (msg->begin, msg->current+bloc)) == NULL) {
		   	if(msg->begin) pfree(msg->begin);
			msg->begin = NULL;
			msg->error = 1;
			return -1;
		} else {
			msg->begin = p;
			msg->size = msg->current+bloc;
		}
	}
}
#define obCFLUX_DUMP_FILE "global/flux.log"
void ob_flux_writeFile(ob_tMsg *msg)
{
	FILE	   *file;

	file = AllocateFile(obCFLUX_DUMP_FILE,"a");
	if (file == NULL)
		goto error;

	(void)fseek(file,0L,SEEK_END);

	if (fwrite(msg->begin,msg->current, 1, file) != 1)
		goto error;

	if (FreeFile(file))
	{
		file = NULL;
		goto error;
	}
	pfree(msg->begin);
	return;

error:
	ereport(LOG,
			(errcode_for_file_access(),
			 errmsg("could not write to file \"%s\": %m",
					 obCFLUX_DUMP_FILE)));
	if (file)
		FreeFile(file);
	unlink(obCFLUX_DUMP_FILE);
	pfree(msg->begin);
}

/*
static bool verify_fluxMaximum(const ob_tChemin *pchemin, double *fluxExact) {
	unsigned char _is, _jn, _lon,_jm;
	double _cumul[obCMAXCYCLE];
	
	memset(_cumul, 0, sizeof(_cumul));
	
	_lon = pchemin->nbNoeud;
	_jm = (pchemin->cflags & ob_flux_CLastIgnore) ? (_lon - 1) : _lon;
	obMRange(_jn,_jm) {// loop on nodes
		_is = pchemin->no[_jn].stockIndex;
		_cumul[_is] += fluxExact[_jn]; 
	}

	_lon = pchemin->nbStock;
	_jm = (pchemin->cflags & ob_flux_CLastIgnore) ? (_lon - 1) : _lon;
	obMRange(_is,_jm) {
		if(_cumul[_is] > (double) (pchemin->no[_is].stock.qtt)) 
			return false;
	}
	return true;
	
}*/
