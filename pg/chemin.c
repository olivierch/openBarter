/* $Id: chemin.c 22 2010-01-15 16:00:22Z olivier.chaussavoine $ */
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
/* Y Provided X Received */
// #include <flux.h>
#include <postgres.h>
#include <chemin.h>
#include <point.h> // include flux.h
#include <iternoeud.h>
#include <dbe.h>


/*******************************************************************************
parcours_arriere

	walks through the graph backward from the pivot, and
	fills the table envit->points with ob_tMarqueOffre mo elements,
	nodes of paths going to the pivot where:
		mo.ar.layer is the length of the path  from the pivot,
			numbered from 1 for the pivot to nblayer,
	clients of the pivot are called sources and have mo.av.layer=1,
		mo.av.layer=0 for others.
	env
		environment
	nblayer
		(out) the number of layers

	return 0 or an error

*****************************************************************************/
int ob_chemin_parcours_arriere(envt,txn,nblayer,stockPivot)
	DB_ENV *envt;
	DB_TXN *txn;
	int *nblayer;
	ob_tStock *stockPivot;
{
	// ob_tPrivate *priv = env->app_private;
	// ob_tPrivateTemp *privt = priv->envt->app_private;
	ob_tPrivateTemp *privt = envt->app_private;
	ob_tNoeud *pivot = privt->pivot;

	int layer; // layerY layer, layerX layer+1
	int ret,ret_t;
	bool layerX_vide;// reset when some points are on layerX
	bool sources;
	ob_tId Yoid,Xoid;
	ob_tMarqueOffre moY,moX; // some points on layer X and layer Y
	ob_tNoeud offreX;
	ob_tStock stock;
	ob_tMar marqueYar;
	DBT ku_Yoid,du_moY,ku_Xoid,du_moX,ks_marqueYar,du_offreX,ks_nR,ks_Xoid;
	DBC *cmar_pointY = NULL;
	DBC *c_point = NULL;
	ob_tPortal cvy_offreX = NULL;

	obMtDbtU(ku_Yoid,Yoid);
	obMtDbtU(du_moY,moY);

	obMtDbtU(ku_Xoid,Xoid);
	obMtDbtU(du_moX,moX);

	obMtDbtS(ks_marqueYar,marqueYar);
	obMtDbtU(du_offreX,offreX);
	obMtDbtS(ks_nR,moY.offre.nR);
	obMtDbtS(ks_Xoid,Xoid);
	// elog(INFO,"pivot stockId %lli nF %lli nR %lli omega %f own %lli oid %lli",pivot->stockId,pivot->nF,pivot->nR,pivot->omega,pivot->own,pivot->oid);

	/* cursor for iteration on points for a given moY.ar.layer */
	ret = privt->mar_points->cursor(privt->mar_points,NULL,&cmar_pointY,0);
	if(ret) {obMTRACE(ret); goto fin;}

	/* cursor for iteration on offres for a given moY.offre.nR */

	/*DBC *cvy_offreX;
	ret = priv->vy_offres->cursor(priv->vy_offres,txn,&cvy_offreX,0);
	if(ret) {obMTRACE(ret); goto fin;} */

	//DBC *c_point;
	/* cursor for insertion of points */
	ret = privt->points->cursor(privt->points,NULL,&c_point,0);
	if(ret) {obMTRACE(ret); goto fin;}

	privt->versionSg = 0;

	// the pivot is inserted on the first layer (moY.ar.layer==1) *********
	// it is not source, hence mo.av.layer = 0

	memset(&moY,0,sizeof(moY));
	memcpy(&moY.offre,pivot,sizeof(moY.offre));//ob_tNoeud
	moY.ar.layer = 1 ; // moY.ar.igraph = 0
	Yoid = pivot->oid; // the oid of the pivot
	ret = privt->points->put(privt->points,0,&ku_Yoid,&du_moY,DB_NOOVERWRITE);
	if(ret) {obMTRACE(ret);goto fin;}

	// the stock of the pivot is inserted
	if(privt->deposOffre) {
		//stock.sid = pivot->stockId;
		memcpy(&stock,stockPivot,sizeof(ob_tStock));
	} else {
		// the stock of the pivot is created temporarily
		memset(&stock,0,sizeof(ob_tStock));
		stock.sid = 0;
		stock.nF = pivot->nF;
		// stock.own = stock.qtt = stock.sid = stock.version = 0
	}

	ret = ob_iternoeud_put_stocktemp3(envt,&stock);
	// if(sid!=0) the stocks[sid] has been red.
	if(ret){obMTRACE(ret);goto fin;}

	/* Begin **************************************************************/
	layer = 1;
	sources = false;
	memset(&marqueYar,0,sizeof(ob_tMar));
	// marqueYar.igraph is unused

	/*********************************************************************/
	// while layer<obCMAXCYCLE and layer non empty
	while(true) {
		layerX_vide = true;
		marqueYar.layer = layer;
		//elog(INFO,"Start new layer %i",layer);
		/*************************************************************/
		// loop cmar_pointY
		// for all pointY of layer (pointY.mo.ar.layer == layer)
		ks_marqueYar.data = &marqueYar;
		ret = cmar_pointY->pget(cmar_pointY,&ks_marqueYar,&ku_Yoid,&du_moY,DB_SET);
		if(!ret) do {
			//elog(INFO,"Layer %i, Yoid=%lli found",layer,Yoid);
			// moY.offre.nR is now set
			
			/* [1] selects from database bids having noeud.nf==moY.offre.nR and S.qtt != 0
			"SELECT NOX.*,S.* FROM ob_tnoeud NOX INNER JOIN ob_stock S ON (NOX.sid =S.id) WHERE NOX.nf=Y_nR ",Yoid,moY.offre.nR AND S.qtt!=0*/
			cvy_offreX = ob_iternoeud_GetPortal2(envt,Yoid,moY.offre.nR);
			if( cvy_offreX == NULL)  {
				ret = ob_chemin_CerIterNoeudErr;
				goto fin;
			}
			//elog(INFO,"ob_iternoeud_GetPortal2(Yoid=%lli,nR=%lli)",Yoid,moY.offre.nR);

			do {
				/* next element of the select [1], result: Xoid<-NOX.id ,offreX<-NOX.* stock<-S.*	*/
				ret = ob_iternoeud_Next2(cvy_offreX,&Xoid,&offreX,&stock);
				if(ret == DB_NOTFOUND) continue;
				else if (ret !=0) {
					obMTRACE(ret); goto fin;
				}
				//elog(INFO,"ob_iternoeud_Next2(Yoid=%lli,nR=%lli) found offreX.oid=%lli with offreX.nF=nR and offreX.nR=%lli",Yoid,moY.offre.nR,Xoid,offreX.nR);
				ret = c_point->get(c_point,&ks_Xoid,&du_moX,DB_SET);
				
				if( ret == 0 ) { // points[Xoid] is found, 
					ret = ob_point_new_trait(envt,&offreX,&moY.offre);
					if(ret) { obMTRACE(ret);goto fin; }

				} else if( ret == DB_NOTFOUND) { // points[Xoid] was not found
					ret = ob_point_new_trait(envt,&offreX,&moY.offre);
					if(ret) { obMTRACE(ret);goto fin; }
					// elog(INFO,"offreX.id = %lli was not found",Xoid);
					layerX_vide = false;
					// the stock is inserted into privt->stocktemps[sid]

					ret = ob_iternoeud_put_stocktemp3(envt,&stock);
					if(ret) {obMTRACE(ret);goto fin;}

					// point X (moX) is written
					// at this stage, the pivot is not yet inserted into envi.offres.

					memset(&moX,0,sizeof(ob_tMarqueOffre));
					memcpy(&moX.offre,&offreX,sizeof(ob_tNoeud));
					moX.ar.layer = layer+1; // moY.ar.igraph = 0, moY.av.layer = 0, moY.av.igraph = 0

					if(pivot->nF == moX.offre.nR) {
					// moX is client of the pivot, it is a source
						moX.av.layer = 1; sources = true;
					}

					ret = c_point->put(c_point,&ks_Xoid,&du_moX,DB_KEYFIRST);
					if(ret) { obMTRACE(ret);goto fin; }

					//elog(DEBUG,"Xoid=%lli inserted into points layer=%i",Xoid,layer);
				} else  { // ret != DB_NOTFOUND or !=0
					obMTRACE(ret); goto fin;
				}
				
				//elog(INFO,"trait %lli->%lli inserted",offreX.oid,moY.offre.oid);
			} while(!ret); // ob_iternoeud_Next
			SPI_cursor_close(cvy_offreX);cvy_offreX = NULL;
			if (ret == DB_NOTFOUND) ret = 0;
			else {obMTRACE(ret); goto fin;}
			// end loop cvy_offreX
			/*****************************************************/

			// next privt->points[Yoid]=moY 
			// having moY.ar.layer==layer
			ret = cmar_pointY->pget(cmar_pointY,&ks_marqueYar,
					&ku_Yoid,&du_moY,DB_NEXT_DUP);
		} while(!ret);
		if (ret == DB_NOTFOUND) ret = 0;
		else { obMTRACE(ret);  goto fin;}
		// end loop cmar_pointY
		/*************************************************************/

		// break condition of the while(true):
		// if layerX_vide, layer is the last inserted
		if (layerX_vide)  {
			//elog(INFO,"Layer %i empty - BREAK",layer);
			break; 
		} else  layer +=1;
		if(layer == obCMAXCYCLE-1) {
			//elog(INFO,"Layer %i == %i reached - BREAK",layer,obCMAXCYCLE-1);
			break;
		}

	} // while(true):  layer<obCMAXCYCLE and layer non empty
	/*********************************************************************/

	// mo.ar.layer in [1,layer] since layer is the last inserted
	// and the pivot is into points
	if(sources) {
		*nblayer = layer;
		//elog(INFO,"%i layers found",layer);
	} else {
		*nblayer = 1; // there is no clients of pivot
		//elog(INFO,"no sources found with layer %i",layer);
	}
fin:
	// obMCloseCursor(cvy_offreX);
	obMCloseCursor(cmar_pointY);
	obMCloseCursor(c_point);
	if(cvy_offreX != NULL) SPI_cursor_close(cvy_offreX);
	// elog(INFO,"%i nblayers found",*nblayer);
	return (ret);
}
/*******************************************************************************
parcours_avant()
	walks the graph from the sources to the pivot
	i_graph is the old graph and i_graph+1 is the new one.
	at the first call i_graph==0
	all sources are passed to the new graph.
	from layer = 1 (sources) the pointX (layer,i_graph+1) are scanned.
	foreach pointY connected with a trait to pointX:
		point.mo.av.igraph = i_graph+1
		point.mo.av.layer = layer+1
		trait.igraph = i_graph+1
		layer +=1

	a cycle is detected when the layer becomes > nblayer

	at the end nbSource = 0 means the graph is empty

	returns 0 if no error
	ob_chemin_CerLoopOnOffer when a loop is found
		accordLoop is written

*******************************************************************************/
static int _parcours_avant(envt,nblayer,i_graph,nbSource,loop)
	DB_ENV *envt;
	int 		nblayer;
	int 		i_graph;
	int 		*nbSource;
	ob_tLoop	*loop;
{
	//ob_tPrivate *priv = env->app_private;
	ob_tPrivateTemp *privt = envt->app_private;
	ob_tNoeud *pivot = privt->pivot;
	int layer,ret,ret_t,new_igraph;
	ob_tMar marqueXav;
	bool layerY_vide,_graphe_vide;
	ob_tFleche fleche;
	ob_tId Xoid;
	ob_tTrait trait;
	ob_tPoint pointX,pointY;
	DBT ks_marqueXav,ku_Xoid,ks_Xoid,du_pointX,du_pointY,ks_fleche_Yoid,ku_fleche,du_trait,ks_fleche;
	DBC *cmav_point = NULL;
	DBC *cx_trait = NULL;
	DBC *c_point = NULL;

	obMtDbtS(ks_marqueXav,marqueXav);
	obMtDbtU(ku_Xoid,Xoid);
	obMtDbtS(ks_Xoid,Xoid);

	obMtDbtU(du_pointX,pointX);
	obMtDbtU(du_pointY,pointY);

	obMtDbtS(ks_fleche_Yoid,fleche.Yoid);
	obMtDbtU(ku_fleche,fleche);
	obMtDbtU(du_trait,trait);

	obMtDbtS(ks_fleche,fleche);

	_graphe_vide = true;

	ret = privt->mav_points->cursor(privt->mav_points,NULL,&cmav_point,0);
	if(ret) {obMTRACE(ret); goto fin;}

	ret = privt->px_traits->cursor(privt->px_traits,NULL,&cx_trait,0);
	if(ret) {obMTRACE(ret); goto fin;}

	ret = privt->points->cursor(privt->points,NULL,&c_point,0);
	if(ret) {obMTRACE(ret); goto fin;}


	//*********************************************************************
	// sources are moved from the old graph (i_graph) to the new (i_graph+1)

	marqueXav.igraph = i_graph; // source in the old graph
	marqueXav.layer = 1;
	new_igraph = i_graph+1;

	*nbSource = 0;
	ret = cmav_point->pget(cmav_point,&ks_marqueXav,
			&ku_Xoid,&du_pointX,DB_SET);
	if(!ret) do {
		pointX.mo.av.igraph = new_igraph;
		pointX.mo.av.layer = 1;
		ret = ob_point_initPoint(privt,&pointX);
		if (ret) {obMTRACE(ret); goto fin;}
		*nbSource +=1;

		ret = cmav_point->pget(cmav_point,&ks_marqueXav,
				&ku_Xoid,&du_pointX,DB_NEXT_DUP);
	} while(!ret);
	if (ret == DB_NOTFOUND) ret = 0;
	else {obMTRACE(ret);  goto fin;}
	if(!*nbSource) goto fin;

	//*********************************************************************
	// loop while(!layerY_vide)

	layer = 1;layerY_vide = false;
	while(!layerY_vide) {
		layerY_vide = true;

		//*************************************************************
		// loop cmav_point

		// for (pointX,Xoid) on the layer
		marqueXav.igraph = new_igraph;
		marqueXav.layer = layer;

		ks_marqueXav.data = &marqueXav;
		ret = cmav_point->pget(cmav_point,&ks_marqueXav,&ku_Xoid,&du_pointX,DB_SET);
		if(!ret) do {

			//*****************************************************
			//loop cx_trait
			//  (fleche,trait) having fleche.Xoid == Xoid
			ks_Xoid.data = &Xoid;
			ret = cx_trait->pget(cx_trait,&ks_Xoid,&ku_fleche,&du_trait,DB_SET);
			if(!ret) do {
				//elog(INFO,"%lli->%lli layer %i X.ar %i X.av %i",fleche.Xoid,fleche.Yoid,layer,pointX.mo.ar.layer,pointX.mo.av.layer);
				// get points[fleche.Yoid]
				ret = c_point->get(c_point,&ks_fleche_Yoid,&du_pointY,DB_SET);
				if (ret) {obMTRACE(ret); goto fin;}
				// it must be found

				//*******************************************
				// pointY written into i_graph+1
				// if it is not empty

				pointY.mo.av.igraph = new_igraph;
				pointY.mo.av.layer = layer+1;
				ret = ob_point_initPoint(privt,&pointY);

				if(ret != ob_point_CerStockEpuise) {
					if (ret) {obMTRACE(ret); goto fin;}

					trait.igraph = new_igraph;
					ret = privt->traits->put(privt->traits,0,&ks_fleche,&du_trait,0);
					if (ret) { obMTRACE(ret); goto fin; }

					layerY_vide = false;

					// The graph is not empty
					// if the pivot is there
					if(pointY.mo.offre.oid == pivot->oid)
						_graphe_vide = false;
				}

				// next (fleche,trait)
				ret = cx_trait->pget(cx_trait,&ks_Xoid,
					&ku_fleche,&du_trait,DB_NEXT_DUP);
			} while(!ret);
			if (ret == DB_NOTFOUND) ret = 0;// fin cx_trait
			else {obMTRACE(ret); goto fin;}
			// end loop cx_trait
			//*****************************************************

			// next (Xoid,pointX)
			ret = cmav_point->pget(cmav_point,&ks_marqueXav,
					&ku_Xoid,&du_pointX,DB_NEXT_DUP);
		}  while(!ret);
		if (ret == DB_NOTFOUND) ret = 0; // fin cmav_point
		else {obMTRACE(ret); goto fin;}
		// end loop cmav_point

		// elog(INFO,"parcours_avant layer=%i nblayer=%i seuil %i",layer,nblayer,obCMAXCYCLE-1);
		// a loop was found if layer > nblayer

		if(layer > nblayer) {
			ret = ob_chemin_CerLoopOnOffer;
			//elog(INFO,"ob_chemin_CerLoopOnOffer layer=%i nblayer=%i",layer,nblayer);
			memcpy(&loop->rid,&fleche,sizeof(ob_tFleche));
			elog(INFO,"for Xoid=%lli Yoid=%lli",loop->rid.Xoid,loop->rid.Yoid);
			goto fin;
		}
		layer +=1;
	}
	// end loop while(!layerY_vide)
	//*********************************************************************
fin:
	if(_graphe_vide) *nbSource = 0;
	obMCloseCursor(cx_trait);
	obMCloseCursor(cmav_point);
	obMCloseCursor(c_point);
	return(ret);
}
/*******************************************************************************
bellman_ford_in

on the trait pointX->pointY, the pointY contains a path pointY.chemin.
it is compared using prodOmega with an other composed of the path pointX.chemin
terminated by pointY.oid . If this path is better than pointY.chemin,
it is written into pointY.chemin.
*******************************************************************************/
static int _bellman_ford_in(privt,trait,loop)
	ob_tPrivateTemp *privt;
	ob_tTrait *trait;
	ob_tLoop	*loop;
{
	int ret;
	bool fluxVide;
	ob_tId oid;
	ob_tPoint point,pointY;
	double oldOmega,newOmega;
	ob_tStock *pstockY;
	DBT ks_oid,ds_point;

	obMtDbtS(ks_oid,oid);
	obMtDbtS(ds_point,point);

	ret = ob_point_getPoint(privt->points,&trait->rid.Xoid,&point);
	if(ret) goto fin;

	// if pointX (here point) is empty,
	// we do not modify pointY, (it must also be empty)
	if(!ob_flux_cheminGetNbNode(&point.chemin)) goto fin;

	ret = ob_point_getPoint(privt->points,&trait->rid.Yoid,&pointY);
	if(ret) goto fin;

	oldOmega = ob_flux_cheminGetOmega(&pointY.chemin);
	// 0. if the path is empty

	pstockY = ob_flux_cheminGetAdrStockLastNode(&pointY.chemin);

	ret =ob_flux_cheminAjouterNoeud(&point.chemin,pstockY,&pointY.mo.offre,loop);
	if (ret) {obMTRACE(ret); goto fin;}

	if(trait->rid.Yoid == privt->pivot->oid) {
		// trait->rid.Yoid == pivotId
		fluxVide = ob_flux_fluxMaximum(&point.chemin);
		if(fluxVide) goto fin;
	}
	newOmega = ob_flux_cheminGetOmega(&point.chemin);
	if (newOmega <= oldOmega)  goto fin; // omega is weaker

	// writes point.chemin into points[trait->rid.Yoid]
	memcpy(&point.mo,&pointY.mo,sizeof(ob_tMarqueOffre));
	oid = trait->rid.Yoid;

	ds_point.size = ob_point_getsizePoint(&point);
	ret = privt->points->put(privt->points,0,&ks_oid,&ds_point,0);
	if (ret) {obMTRACE(ret); goto fin;}

fin:
	return(ret);
}

/*******************************************************************************
bellman_ford
the algorithm is usually repeated for all node, but here only
nblayer times, since paths are at most nblayer long.
_bellman_ford_in is called for each trait of i_graph+1
*******************************************************************************/
static int _bellman_ford(privt,chemin,nblayer,i_graph,loop)
	ob_tPrivateTemp *privt;
	ob_tChemin *chemin;
	int nblayer,i_graph;
	ob_tLoop	*loop;
	// TODO remove nblayer

{
	int _layer,_graph,ret,ret_t;
	ob_tPoint pointPivot;
	ob_tTrait trait;
	ob_tFleche rid;
	DBT ks_marque,ku_rid,du_trait,ks_pivotId,du_pointPivot;
	DBC *cm_trait = NULL;

	obMtDbtS(ks_marque,_graph);
	obMtDbtU(ku_rid,rid);
	obMtDbtU(du_trait,trait);
	obMtDbtpS(ks_pivotId,&privt->pivot->oid);

	obMtDbtU(du_pointPivot,pointPivot);

	ret=privt->m_traits->cursor(privt->m_traits,NULL,&cm_trait,0);
	if (ret) { obMTRACE(ret); goto fin;}

	_graph = i_graph+1;
	_layer = obCMAXCYCLE;

	while(_layer) {
		ks_marque.data = &_graph;
		ret = cm_trait->pget(cm_trait,&ks_marque,&ku_rid,&du_trait,DB_SET);
		if(!ret) do {
			ret = _bellman_ford_in(privt,&trait,loop);
			if(ret) goto fin;
			ret = cm_trait->pget(cm_trait,&ks_marque,&ku_rid,&du_trait,DB_NEXT_DUP);
		} while(!ret);
		if (ret == DB_NOTFOUND) ret = 0;
		else {obMTRACE(ret); goto fin;}
		_layer -=1;
	}

	ret = privt->points->get(privt->points,0,&ks_pivotId,&du_pointPivot,0);
	if (ret) { obMTRACE(ret); goto fin;}
	// pivot shoud be found since it was found by parcours_avant

	memcpy(chemin,&(pointPivot.chemin),
			ob_flux_cheminGetSize(&pointPivot.chemin));

fin:
	obMCloseCursor(cm_trait);
	return(ret);
}

/*******************************************************************************
diminuer
	decreases stocks after a draft has been found
	if privt->deposOffre, the stock of the pivot is considered
	else, it is not
*******************************************************************************/
static int _diminuer(privt,pchemin)
	ob_tPrivateTemp *privt;
	ob_tChemin *pchemin;
{
	int _i,nbNoeud,nbStock,ret = 0,ret_t;
	//ob_tQtt qtt;
	ob_tStock stock,*pflux;
	ob_tId _sid,oid;
	ob_tPoint point;
	ob_tStock tabFlux[obCMAXCYCLE];
	DBT ks_sid,du_stock,ds_stock,ku_oid,du_point;
	DBC *cst_point = NULL;

	obMtDbtS(ks_sid,_sid);
	obMtDbtU(du_stock,stock);
	obMtDbtS(ds_stock,stock);
	obMtDbtU(ku_oid,oid);
	obMtDbtU(du_point,point);

	ret=privt->st_points->cursor(privt->st_points,NULL,&cst_point,0);
	if (ret) { obMTRACE(ret); goto fin;}

	nbNoeud = ob_flux_GetTabStocks(pchemin,tabFlux,&nbStock);

	obMRange(_i,nbStock) {
		pflux = &tabFlux[_i];

		// when the stock is that of the pivot,
		// it is never shared with other nodes. The stock is reduced
		// only if privt->deposOffre, otherwise, it remains empty.
		if(	(pflux->sid == privt->pivot->stockId)
			&&	(!privt->deposOffre)) continue;

		// stock <-stocktemps[pflux->sid], should be found
		ks_sid.data = &pflux->sid;
		du_stock.data = &stock;
		ret = privt->stocktemps->get(privt->stocktemps,0,
				&ks_sid,&du_stock,0);
		if (ret) {obMTRACE(ret); goto fin;}

		if ( stock.qtt < pflux->qtt) {
			// the stocktemps[sid] cannot afford this flow
			ret = ob_point_CerStockNotNeg;obMTRACE(ret);goto fin;

		} else if (stock.qtt > pflux->qtt) {
		// stocktemps[sid]  updated to stock if it is not empty
			stock.qtt -= pflux->qtt;
			ret = privt->stocktemps->put(privt->stocktemps,0,
				&ks_sid,&ds_stock,0);
			if(ret) {obMTRACE(ret);goto fin;}
			continue;
		} /* otherwise, the stock is empty: stock.qtt == pflux->qtt.
		it is useless to update it, since points and traits that use it
		will not belong to the next graph.
		The stock is now empty */

		// all point and traits that use it are deleted
		// ************************************************************
		// loop cst_point

		ks_sid.data = &pflux->sid;
		ku_oid.data = &oid;
		ret = cst_point->pget(cst_point,
				&ks_sid,&ku_oid,&du_point,DB_SET);
		if(!ret) do {

#ifndef NDEBUG // mise au point
			// elog(INFO,"NDEBUG is undefined"); IT IS UNDEFINED
			if(point.mo.offre.oid != *((ob_tId*)ku_oid.data))
			{ret = ob_chemin_CerPointIncoherent;obMTRACE(ret); goto fin;}
			if(point.mo.offre.stockId != pflux->sid)
			{ret = ob_chemin_CerPointIncoherent;obMTRACE(ret); goto fin;}
#endif
			// all points that touch this point are deleted
			ret = privt->points->del(privt->points,0,&ku_oid,0);
			if (ret) {obMTRACE(ret); goto fin;}

			// all traits that touch this trait are deleted
			ret = privt->px_traits->del(privt->px_traits,0,&ku_oid,0);
			if (ret) {
				if(ret==DB_NOTFOUND) ret = 0;
				else {obMTRACE(ret); goto fin;}
			}

			ret = privt->py_traits->del(privt->py_traits,0,&ku_oid,0);
			if (ret) {
				if(ret == DB_NOTFOUND) ret = 0;
				else {obMTRACE(ret); goto fin;}
			}

			ret = cst_point->pget(cst_point,&ks_sid,&ku_oid,&du_point,DB_NEXT_DUP);
		} while (!ret); if(ret == DB_NOTFOUND) ret = 0;
		else {obMTRACE(ret);goto fin;}
		// end loop cst_point
		// ************************************************************
	}
fin:
	obMCloseCursor(cst_point);
	return(ret);
}


/*******************************************************************************
ob_chemin_faire_accords

It is a bid deposit when pivot->stockId!=0,
else it is a omega computation.

	returns 0 or error
	ob_chemin_CerLoopOnOffer
		paccords[nbAccord-1] contains an *ob_tLoop of the loop
		that should be freed later.

for a bid deposit:
	the stock of the pivot is considered in flow calculation,

for an omega calulation:
	a special node is created for loop calculation
	the stock of this node does not limit the flow.

	env
		environment
	versionSg
		the version number of the graph observed
	nbAccord
		the size of the array of accords
	paccord
		(out) the array of agreements returned
		this array must be freed when nbAccord!=0
*******************************************************************************/

/***************************************************************************************
* called by ob_getdraft_get_commit and then by ob_getdraft_getcommit_next
***************************************************************************************/
int ob_chemin_get_draft_next(ob_getdraft_ctx *ctx) {
	int ret,_nbSource;
	ob_tPrivateTemp *privt = ctx->envt->app_private;
	ob_tAccord *paccord = &ctx->accord;

	// ctx->i_graph starts at 0, incremented at each call

	// traversal of graph from sources

	ret = _parcours_avant(ctx->envt,ctx->nblayer,ctx->i_graph,&_nbSource,&ctx->loop);
	if(ret){
		if(ret != ob_chemin_CerLoopOnOffer) obMTRACE(ret);
		goto fin;
	}
	// elog(INFO,"parcours_avant( nblayer %i,i_graph %i)->nbSource %i",ctx->nblayer,ctx->i_graph,_nbSource);

	if(!_nbSource) {
		ret = ob_chemin_CerNoDraft; // normal termination
		goto fin;
	}
	paccord->nbSource = _nbSource;

	// elog(INFO,"_bellman_ford()->chemin.cflags %x",paccord->chemin.cflags);
	// competition on omega
	ret = _bellman_ford(privt,&paccord->chemin,ctx->nblayer,ctx->i_graph,&ctx->loop);
	if(ret)	{ 
		if(ret != ob_chemin_CerLoopOnOffer) obMTRACE(ret);
		goto fin;
	}

	//elog(INFO,"_bellman_ford()->chemin.cflags %x",paccord->chemin.cflags);

	// normal end when the flow is undefined
	if(!(paccord->chemin.cflags & ob_flux_CFlowDefined)) {
		ret = ob_chemin_CerNoDraft;
		goto fin;
	}
	// an agreement was found
	paccord->status = DRAFT;
	paccord->versionSg = privt->versionSg;

	ret = _diminuer(privt,&paccord->chemin);
	if(ret) {
		obMTRACE(ret);goto fin;}
fin:
	// elog(INFO,"ob_chemin_get_draft_next() ret= %i",ret);
	return ret;
}
