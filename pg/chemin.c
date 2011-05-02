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

	walks through the graph backward from the pivot.
	for path ending at pivot,
	fills envit->points with nodes mo and envit->traits with arcs.
	for a node mo, mo.ar.layer is numbered from 1 for the pivot to nblayer,
	clients of the pivot are called sources and have mo.av.layer=1,mo.av.igraph=0
		mo.av.layer=0 for others.

	env	environment
	txn unused
	nblayer (out)
		 0 no sources
		 else, nblayer layers inserted between [1,layer]

	return 0 or an error

*****************************************************************************/
int ob_chemin_parcours_arriere(envt,txn,nblayer,stockPivot)
	DB_ENV *envt;
	DB_TXN *txn;
	int *nblayer;
	ob_tStock *stockPivot;
{

	ob_tPrivateTemp *privt = envt->app_private;
	ob_tNoeud *pivot = privt->pivot;

	int layer; // layerY layer, layerX layer+1
	int ret,ret_t;

	bool sources;
	ob_tId Yoid,Xoid;
	ob_tMarqueOffre moY,moX; // some points on layer X and layer Y
	ob_tNoeud offreX;
	ob_tStock stock;

	DBT ku_Yoid,du_moY,ku_Xoid,du_moX,du_offreX,ks_nR,ks_Xoid;
	DBC *cmar_pointY = NULL;
	DBC *c_point = NULL;
	ob_tPortal cvy_offreX = NULL;

	obMtDbtU(ku_Yoid,Yoid);
	obMtDbtU(du_moY,moY);

	obMtDbtU(ku_Xoid,Xoid);
	obMtDbtU(du_moX,moX);

	obMtDbtU(du_offreX,offreX);
	obMtDbtS(ks_nR,moY.offre.nR);
	obMtDbtS(ks_Xoid,Xoid);
	// elog(INFO,"pivot stockId %lli nF %lli nR %lli omega %f own %lli oid %lli",pivot->stockId,pivot->nF,pivot->nR,pivot->omega,pivot->own,pivot->oid);

	/* cursor for iteration on points for a given moY.ar
	 * ob_tMar contains (layer,igraph) */
	ret = privt->mar_points->cursor(privt->mar_points,NULL,&cmar_pointY,0);
	if(ret) {obMTRACE(ret); goto fin;}

	/* cursor for insertion and read of points */
	ret = privt->points->cursor(privt->points,NULL,&c_point,0);
	if(ret) {obMTRACE(ret); goto fin;}

	privt->versionSg = 0;

	// the pivot is inserted on the first layer (moY.ar.layer==1) *********
	memset(&moY,0,sizeof(moY));
	// it is not source, hence mo.av.layer = 0

	memcpy(&moY.offre,pivot,sizeof(moY.offre));//ob_tNoeud
	moY.ar.layer = 1 ;
	// moY.ar.igraph = 0
	Yoid = pivot->oid; // the oid of the pivot
	ret = privt->points->put(privt->points,0,&ku_Yoid,&du_moY,DB_NOOVERWRITE);
	if(ret) {obMTRACE(ret);goto fin;}

	// the stock of the pivot is inserted
	if(privt->deposOffre) {
		//stock.sid = pivot->stockId;
		memcpy(&stock,stockPivot,sizeof(ob_tStock));
	} else {
		// the stock of the pivot is created temporarily with sid=0
		memset(&stock,0,sizeof(ob_tStock));
		stock.nF = pivot->nF;
		// stock.own = stock.qtt = stock.sid = stock.version = 0
	}

	// stocktemps[stock.sid] <- stock
	// and privt->versionsg = max(privt->versionsg,pstock->version) if pstock->sid != 0
	ret = ob_iternoeud_put_stocktemp3(envt,&stock);
	if(ret){obMTRACE(ret);goto fin;}

	/* Begin **************************************************************/
	layer = 1;
	sources = false;

	/*********************************************************************/
	// while [A] layer<obCMAXCYCLE and layer non empty
	while(true) { // [A]
		bool layerX_empty = true;// reset when some points are on layer+1

		ob_tMar marqueYar;
		DBT ks_marqueYar;

		obMtDbtS(ks_marqueYar,marqueYar);

		marqueYar.layer = layer;
		marqueYar.igraph = 0;
		//elog(INFO,"Start new layer %i",layer);
		/**********************************************************************************/
		// loop [B] ALL (moY,Yoid) on layer
		// cmar_pointY
		// for all pointY of layer (pointY.mo.ar.layer,pointY.mo.ar.igraph) == (layer,0)
		ret = cmar_pointY->pget(cmar_pointY,&ks_marqueYar,&ku_Yoid,&du_moY,DB_SET);
		if(!ret) do { // [B]
			//elog(INFO,"Layer %i, Yoid=%lli found",layer,Yoid);
			// moY.offre.nR is now set
			
			/*******************************************************************************/
			/* [C] ALL (offreX,Xoid,stock)  nF =------>>--------=nR   moY
			 * selects from database bids having noeud.nf==moY.offre.nR and S.qtt != 0
			"SELECT NOX.*,S.* FROM ob_tnoeud NOX INNER JOIN ob_stock S ON (NOX.sid =S.id)
				WHERE NOX.nf=Y_nR AND S.qtt!=0  */
			cvy_offreX = ob_iternoeud_GetPortal2(envt,Yoid,moY.offre.nR);
			if( cvy_offreX == NULL)  {
				ret = ob_chemin_CerIterNoeudErr;
				obMTRACE(ret);
				goto fin;
			}
			//elog(INFO,"ob_iternoeud_GetPortal2(Yoid=%lli,nR=%lli)",Yoid,moY.offre.nR);

			while(true) { // /* next element of the select [1]
				bool XoidNotFound = false;

				ret = ob_iternoeud_Next2(cvy_offreX,&Xoid,&offreX,&stock);
				if(ret == DB_NOTFOUND) break;
				else if (ret !=0) { obMTRACE(ret); goto fin;}
				//elog(INFO,"ob_iternoeud_Next2(Yoid=%lli,nR=%lli) found offreX.oid=%lli with offreX.nF=nR and offreX.nR=%lli",Yoid,moY.offre.nR,Xoid,offreX.nR);

				if( true) { // Xoid != pivot->oid) { // traits from pivot to source are not inserted
					ret = ob_point_new_trait(envt,&Xoid,&Yoid);
					if(ret) { obMTRACE(ret);goto fin; }
				}
				//elog(INFO,"trait %lli->%lli inserted",offreX.oid,moY.offre.oid);

				ret = c_point->get(c_point,&ks_Xoid,&du_moX,DB_SET);
				if(ret == DB_NOTFOUND ) XoidNotFound = true;
				else if( ret != 0 ) { obMTRACE(ret); goto fin;}

				/* if points[Xoid] is found, it is unchanged
				=> it will not belong to layer+1, and the path to it will be stopped even if traits[X,Y] was written */

				if( XoidNotFound) {

					layerX_empty = false;

					// stocktemps[stock.sid] <- stock
					// and privt->versionsg = max(privt->versionsg,pstock->version) if pstock->sid != 0
					ret = ob_iternoeud_put_stocktemp3(envt,&stock);
					if(ret) {obMTRACE(ret);goto fin;}

					memset(&moX,0,sizeof(ob_tMarqueOffre));
					// moX.ar.layer =0, moY.ar.igraph = 0, moY.av.layer = 0, moY.av.igraph = 0
					memcpy(&moX.offre,&offreX,sizeof(ob_tNoeud));
					moX.ar.layer = layer+1;

					if(pivot->nF == moX.offre.nR) {
						// moX is client of the pivot
						moX.av.layer = 1; sources = true;
						// moX.av.igraph = 0
					}
					// points[Xoid] <- moX on layer+1

					ret = c_point->put(c_point,&ks_Xoid,&du_moX,DB_KEYFIRST);
					if(ret) { obMTRACE(ret);goto fin; }
					//elog(DEBUG,"Xoid=%lli inserted into points layer=%i",Xoid,layer);
				}
				/* all traits[X,Y] have a point[X] that belongs to layer+1 or not */
			}
			SPI_cursor_close(cvy_offreX);cvy_offreX = NULL;
			// end while [C].next
			/*******************************************************************************/

			// next Yoid,moY from privt->points[Yoid] having moY.ar.layer==layer
			ret = cmar_pointY->pget(cmar_pointY,&ks_marqueYar,&ku_Yoid,&du_moY,DB_NEXT_DUP);
		} while(!ret);
		if (ret == DB_NOTFOUND) ret = 0;
		else { obMTRACE(ret);  goto fin;}
		// end loop [B] cmar_pointY on the layer
		/*************************************************************/

		// break condition for [A]

		if (layerX_empty)  {
			/* layer is the last inserted, and the number of layers inserted
			 * the last traits[X,Y] has a point[X] not on layer+1
			 */
			//elog(INFO,"Layer %i empty - BREAK",layer+1);
			break; 
		}

		if(layer == (obCMAXCYCLE -1)) {
			layer +=1;
			/* layer is now the last inserted, and the number of layers inserted is obCMAXCYCLE
			 */
			//elog(INFO,"Layer %i == %i reached - BREAK",layer,obCMAXCYCLE);
			break;
		}
		layer +=1;
	} // end [A]
	/*********************************************************************/

	// mo.ar.layer in [1,layer] since layer is the last inserted
	if(sources) {
		*nblayer = layer;
		//elog(INFO,"%i layers found",layer);
	} else {
		*nblayer = 0; // there is no clients of pivot
		//elog(INFO,"no sources found with layer %i",layer);
	}
fin:
	obMCloseCursor(cmar_pointY);
	obMCloseCursor(c_point);
	if(cvy_offreX != NULL) SPI_cursor_close(cvy_offreX);
	return (ret);
}
/*******************************************************************************
parcours_avant()

	build a graph(i_graph+1) from graph(i_graph).
	This graph excludes arcs going from the pivot to sources, and allows
	bellman ford on paths going from sources to the pivot.
	walks the graph from the sources to the pivot
	i_graph is the old graph and new_igraph=i_graph+1 is the new one.
	at the first call i_graph==0, and source have (av.igraph,av.layer) = 0,1

	all sources are passed to the new graph new_igraph.
	foreach pointX (layer,new_igraph) , starting from sources av.layer=1
		foreach pointY connected with a trait to this pointX:
			point.mo.av.igraph = new_igraph
			point.mo.av.layer = layer+1
			trait.igraph = new_igraph

		layer +=1

	a cycle is detected when layer > nblayer

	at the end nbSource = 0 means the graph is empty

	returns 0 if no error
	ob_chemin_CerLoopOnOffer when a loop is found
		then loop is set

*******************************************************************************/
static int _parcours_avant(envt,nblayer,i_graph,nbSource,loop)
	DB_ENV *envt;
	int 		nblayer;
	int 		i_graph;
	int 		*nbSource;
	ob_tLoop	*loop;
{
	ob_tPrivateTemp *privt = envt->app_private;
	ob_tNoeud *pivot = privt->pivot;
	int layer,ret,ret_t,new_igraph;
	ob_tMar marqueXav;
	bool layerY_empty,_graphe_vide;
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


	ret = privt->mav_points->cursor(privt->mav_points,NULL,&cmav_point,0);
	if(ret) {obMTRACE(ret); goto fin;}

	ret = privt->px_traits->cursor(privt->px_traits,NULL,&cx_trait,0);
	if(ret) {obMTRACE(ret); goto fin;}

	ret = privt->points->cursor(privt->points,NULL,&c_point,0);
	if(ret) {obMTRACE(ret); goto fin;}

	_graphe_vide = true;

	//*********************************************************************
	// sources are moved from the old graph (i_graph) to the new (i_graph+1)

	marqueXav.igraph = i_graph; // source in the old graph
	marqueXav.layer = 1;
	new_igraph = i_graph+1;

	*nbSource = 0;
	ret = cmav_point->pget(cmav_point,&ks_marqueXav,&ku_Xoid,&du_pointX,DB_SET);
	while(!ret) {
		pointX.mo.av.igraph = new_igraph;
		pointX.mo.av.layer = 1;
		ret = ob_point_initPoint(privt,&pointX);
		if (ret == 0)
			*nbSource +=1;
		else if (ret!=ob_point_CerStockEpuise) {obMTRACE(ret); goto fin;}

		ret = cmav_point->pget(cmav_point,&ks_marqueXav,&ku_Xoid,&du_pointX,DB_NEXT_DUP);
	}
	if (ret == DB_NOTFOUND) ret = 0;
	else {obMTRACE(ret);  goto fin;}

	if(!*nbSource) goto fin;

	//*********************************************************************
	// loop [D] while(!layerY_empty)
	layer = 1;
	do { // [D]
		layerY_empty = true;

		//*************************************************************
		// loop [E] cmav_point
		// select (pointX,Xoid) from points having layer,igraph == layer,new_igraph

		marqueXav.igraph = new_igraph;
		marqueXav.layer = layer;

		ks_marqueXav.data = &marqueXav;
		ret = cmav_point->pget(cmav_point,&ks_marqueXav,&ku_Xoid,&du_pointX,DB_SET);
		if(!ret) do { // [E]

			//*****************************************************
			// loop [F] cx_trait
			// select (trait,fleche) from traits having fleche.Xoid == Xoid

			ks_Xoid.data = &Xoid;
			ret = cx_trait->pget(cx_trait,&ks_Xoid,&ku_fleche,&du_trait,DB_SET);
			if(!ret) do { //[F]
				//elog(INFO,"%lli->%lli layer %i X.ar %i X.av %i",fleche.Xoid,fleche.Yoid,layer,pointX.mo.ar.layer,pointX.mo.av.layer);
				// get points[fleche.Yoid]
				ret = c_point->get(c_point,&ks_fleche_Yoid,&du_pointY,DB_SET);
				if (ret) {obMTRACE(ret); goto fin;}
				// it must be found

				//*******************************************
				// points[Y] and traits[X,Y] written into i_graph+1
				// only if stock is not empty

				pointY.mo.av.igraph = new_igraph;
				pointY.mo.av.layer = layer+1;
				ret = ob_point_initPoint(privt,&pointY);
				if(ret == 0 ) { // stock of pointY is not empty

					layerY_empty = false;

					trait.igraph = new_igraph;
					ret = privt->traits->put(privt->traits,0,&ks_fleche,&du_trait,0);
					if (ret) { obMTRACE(ret); goto fin; }

					// The graph is not empty if the pivot is found
					if(pointY.mo.offre.oid == pivot->oid)
						_graphe_vide = false;

				} else if ( ret != ob_point_CerStockEpuise)
				{obMTRACE(ret); goto fin;}

				// next (trait,fleche)
				ret = cx_trait->pget(cx_trait,&ks_Xoid,&ku_fleche,&du_trait,DB_NEXT_DUP);
			} while(!ret);
			if (ret == DB_NOTFOUND) ret = 0;
			else {obMTRACE(ret); goto fin;}
			// end [F] cx_trait
			//*****************************************************

			// next (pointX,Xoid) on layer,igraph == layer,new_igraph
			ret = cmav_point->pget(cmav_point,&ks_marqueXav,&ku_Xoid,&du_pointX,DB_NEXT_DUP);
		}  while(!ret);
		if (ret == DB_NOTFOUND) ret = 0;
		else {obMTRACE(ret); goto fin;}
		// end [E] cmav_point
		/*****************************************************/

		/*
		 *
		 */
		layer +=1;
		if(layer > nblayer && !layerY_empty) {
			ret = ob_chemin_CerLoopOnOffer;
			//elog(INFO,"ob_chemin_CerLoopOnOffer layer=%i nblayer=%i",layer,nblayer);
			memcpy(&loop->rid,&fleche,sizeof(ob_tFleche));
			elog(INFO,"loop found on Xoid=%lli Yoid=%lli",loop->rid.Xoid,loop->rid.Yoid);
			goto fin;
		}
	} while(!layerY_empty);
	// end [D] loop while(!layerY_empty)
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

point.chemin is a path from the pivot to point, or is empty.
on the trait pointX->pointY, if pointX.chemin is empty, nothing is done.
If it is not, we consider the path follows the path pointX.chemin and goes to pointY.
It is compared with pointY.chemin using their prodOmega .
If this path is better than pointY.chemin, it is written into pointY.chemin.
*******************************************************************************/
static int _bellman_ford_in(privt,trait,loop)
	ob_tPrivateTemp *privt;
	ob_tTrait *trait;
	ob_tLoop	*loop;
{
	int ret;
	bool flowEmpty;
	ob_tId oid;
	ob_tPoint point,pointY;
	double oldOmega,newOmega;
	ob_tStock *pstockY;
	DBT ks_oid,ds_point;

	obMtDbtS(ks_oid,oid);
	obMtDbtS(ds_point,point);

	ret = ob_point_getPoint(privt,&trait->rid.Xoid,&point);
	if(ret) goto fin;

	// if pointX (here point) is empty,
	// we do not modify pointY, (it must also be empty)
	if(!ob_flux_cheminGetNbNode(&point.chemin)) goto fin;

	ret = ob_point_getPoint(privt,&trait->rid.Yoid,&pointY);
	if(ret) goto fin;

	oldOmega = ob_flux_cheminGetOmega(&pointY.chemin);
	// 0. if the path is empty

	pstockY = ob_flux_cheminGetAdrStockLastNode(&pointY.chemin);

	ret =ob_flux_cheminAjouterNoeud(&point.chemin,pstockY,&pointY.mo.offre,loop);
	if (ret) {obMTRACE(ret); goto fin;}

	if(trait->rid.Yoid == privt->pivot->oid) {
		// trait->rid.Yoid == pivotId
		flowEmpty = ob_flux_fluxMaximum(&point.chemin);
		if(flowEmpty) goto fin;
	}
	newOmega = ob_flux_cheminGetOmega(&point.chemin);
	if (newOmega <= oldOmega)  goto fin; // omega is weaker

	// writes point.chemin into points[trait->rid.Yoid]
	memcpy(&point.mo,&pointY.mo,sizeof(ob_tMarqueOffre));
	oid = trait->rid.Yoid;

	ds_point.size = sizeof(ob_tPoint);//ob_point_getsizePoint(&point);
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

	memcpy(chemin,&(pointPivot.chemin),ob_flux_cheminGetSize(&pointPivot.chemin));

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

			// all traits that touch this point are deleted
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


	if( ctx->nblayer == 0 ) {
		ret = ob_chemin_CerNoDraft; // normal termination
		goto fin;
	}

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
