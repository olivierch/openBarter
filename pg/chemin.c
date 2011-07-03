/*
AVEC obCTEST

 */
#ifdef obCTEST
#include <stdbool.h>
#else
#include <chemin.h>
#endif
#include "common.h"
#include "flux.h"
#include "iterators.h"
#ifdef obCTEST
#include "chemin_test.h"
#else
#include "iternoeud.h"
#include "dbe.h"
#endif

static int _diminuer(ob_tPrivateTemp *privt,ob_tChemin *pchemin,
		ob_tId* stockPivotId);

/*******************************************************************************/
/* _put_stocktemp3(envt,pstock)
 * pstock is put into stocktemps[pstock->sid],
 * and versionSg = max(privt->versionsg,pstock->version where pstock->sid !=0)
 */
/*******************************************************************************/
static int _put_stocktemp4(privt,pstock,pversionSg)
	ob_tPrivateTemp *privt;
	ob_tStock *pstock;
	ob_tId *pversionSg;
{
	int ret;

	if(*pversionSg <pstock->version) *pversionSg = pstock->version;
	ret  = iterators_idPut(privt->stocktemps,&pstock->sid,pstock,sizeof(ob_tStock),0);
	if (ret) obMTRACE(ret);

	return ret;
}

/*******************************************************************************
 *  initializes the point from point->mo (ob_tMarqueOffre).
 *  clears the point->chemin,
 *  the stock red from stocktemps[stockId] is stored into point->chemin.no[0].stock
 *  if this stock is empty and deposOffre,
 *  	returns ob_chemin_CerStockEpuise
 *  if the point is a source, puts this offre as first element of point->chemin
 *  stores point into point[oid]
 *  returns
 *******************************************************************************/
static int _initPoint(ob_tPrivateTemp *privt, ob_tPoint *point) {
	int ret;
	ob_tStock *pstock;
	ob_tLoop loop;

	ob_flux_cheminVider(&point->chemin, privt->cflags);
	// place for the first stock
	pstock = ob_flux_McheminGetAdrFirstStock(&point->chemin);

	// get the stocktemps[point->mo.offre.stockId]
	ret  = iterators_idGet(privt->stocktemps,
			&point->mo.offre.stockId,pstock,sizeof(ob_tStock),0);
	if (ret) { obMTRACE(ret); goto fin; }

	// the stock is empty and the node is not the pivot on price read
	if (pstock->qtt == 0 && !(!privt->deposOffre && point->mo.offre.oid == 0)  )
			ret = ob_chemin_CerStockEpuise;
	else {
		if (point->mo.av.layer == 1) { // it is a source
			// put it into the chemin
			// 	chemin = [point->mo.offre,]
			ret = ob_flux_cheminAjouterNoeud(&point->chemin,pstock,&point->mo.offre,&loop);
			if (ret) goto fin;
		}

		ret  = iterators_idPut(privt->points,
				&point->mo.offre.oid,point,sizeof(ob_tPoint),0);
		if (ret) { obMTRACE(ret); goto fin; }
	}
fin:
	return ret;
}


/*******************************************************************************
 new_trait put the trait in the graph  i_graph=0
 *******************************************************************************/
static int _new_trait(ob_tPrivateTemp *privt, ob_tId Xoid, ob_tId Yoid) {
	ob_tTrait trait;
	int ret = 0;
	DBT ds_trait,ks_fleche;

	obMtDbtS(ds_trait, trait);
	obMtDbtS(ks_fleche, trait.rid);

	trait.igraph = 0;
	trait.rid.Xoid = Xoid;
	trait.rid.Yoid = Yoid;


	ret = privt->traits->put(privt->traits, 0, &ks_fleche, &ds_trait, 0);
	if (ret) obMTRACE(ret);
	//printf("trait %lli->%lli\n",Xoid,Yoid);
	return ret;
}

/*******************************************************************************/
static int _init_Pivot(privt,pivot,stockPivot,deposOffre,pversionSg)
	ob_tPrivateTemp *privt;
	ob_tNoeud *pivot;
	ob_tStock *stockPivot;
	bool deposOffre;
	ob_tId *pversionSg;
{
	ob_tMarqueOffre mo;
	int ret;

	/* the pivot is inserted on the first layer (moY.ar.layer==1).
	 * it is not source, hence mo.av.layer = 0 */
	memset(&mo,0,sizeof(mo));
	memcpy(&mo.offre,pivot,sizeof(mo.offre));//ob_tNoeud
	mo.ar.layer = 1 ;// moY.ar.igraph,layer = 0,0
	ret = iterators_idPut(privt->points,
			&pivot->oid,&mo,sizeof(ob_tMarqueOffre),DB_NOOVERWRITE);
	if(ret) {obMTRACE(ret);goto fin;}

	*pversionSg = 0;
	if(deposOffre) {
		ret = _put_stocktemp4(privt,stockPivot,pversionSg);
	} else {
		ob_tStock stock;

		memset(&stock,0,sizeof(ob_tStock)); // sid == 0
		stock.nF = pivot->nF;
		// stock.own = stock.qtt = stock.sid = stock.version = 0
		ret = _put_stocktemp4(privt,&stock,pversionSg);
		// pversionSg == 0
	}
fin:
	return ret;
}
/*******************************************************************************/
static int _getLimit(int layer,int nbTrait,int* nbNoeudLayer) {
	int limit;

	limit = openbarter_g.maxArrow - nbTrait;
	*nbNoeudLayer = 0;
	if(limit <=0) return 0;
	return limit;
}
/*******************************************************************************/
int _parcours_arriere(envt,pivot,stockPivot,deposOffre,versionSg,pnbSrc)
	DB_ENV *envt;
	ob_tNoeud *pivot;
	ob_tStock *stockPivot;
	bool deposOffre;
	ob_tId *versionSg;
	int* pnbSrc;
{
	ob_tPrivateTemp *privt = envt->app_private;
	ob_tNoeud offreX;
	ob_tStock stock;
	int layer,ret,nbTrait=0,nbNoeudLayer,nbSrc = 0;

	ob_tSIterator cmar_pointY;
	ob_tAIterator c_point;
	Portal cvy_offreX = NULL;

	/* cursor for iteration on points
	 * for a given ob_tMar moY.ar containing (layer,igraph) */
	initSIterator(&cmar_pointY,privt->mar_points,
			sizeof(ob_tMar),sizeof(ob_tId),sizeof(ob_tMarqueOffre));

	/* cursor for insertion and read of points */
	initAIterator(&c_point,privt->points,
			sizeof(ob_tId),sizeof(ob_tMarqueOffre));

	ret = _init_Pivot(privt,pivot,stockPivot,deposOffre,versionSg);
	if(ret) {obMTRACE(ret); goto fin;}

	/**************************************************************************
	 *  [A] while layer<openbarter_g.maxCommit and layer non empty                        */
	layer = 0;
	nbSrc = 0;
	nbNoeudLayer = 1;
	while(layer < openbarter_g.maxCommit) { // [A]
		bool layerX_empty = true;// reset when some points are on layer+1
		ob_tMar marqueYar;

		layer +=1;
		// layer in [1,openbarter_g.maxCommit]
		/***********************************************************************
		loop [B] for all (moY,pointY) having
			(pointY.mo.ar.layer,pointY.mo.ar.igraph) == (layer,0)   	       */

		marqueYar.layer = layer;
		marqueYar.igraph = 0;
		//printf("init layer: %i\n",layer);
		ret = openSIterator(&cmar_pointY,&marqueYar);
		if(ret) {obMTRACE(ret); goto fin;}

		while(true) { // [B]
			ob_tId Yoid;
			ob_tMarqueOffre moY;
			int limit,cnt_cvy_OffreX;

			ret = nextSIterator(&cmar_pointY,&Yoid,&moY);
			if(ret) {
				if(ret == DB_NOTFOUND) {ret = 0; break; }
				//printf("Yoid=%lli on layer %i\n",Yoid,marqueYar.layer);
				obMTRACE(ret); goto fin;
			}
			//

			/*******************************************************************
			[C] ALL (offreX,Xoid,stock)
			 * 		such as offreX.nF =moY.offre.nR and stock.qtt != 0         */

			limit = _getLimit(layer,nbTrait,&nbNoeudLayer);
			//printf("limit %i,nF %lli\n",limit,moY.offre.nR);
			cvy_offreX = ob_iternoeud_GetPortalA(envt,Yoid,moY.offre.nR,limit+1);
			if( cvy_offreX == NULL)  {
				ret = ob_chemin_CerIterNoeudErr;obMTRACE(ret);goto fin;
			}
			cnt_cvy_OffreX = 0;
			while(true) { // [C]
				ob_tId Xoid;
				ob_tMarqueOffre moX;
				bool XoidNotFound = false;

				ret = ob_iternoeud_NextA(cvy_offreX,&Xoid,&offreX,&stock);
				//printf("on est la ret=%i\n",ret);
				if( ret != 0 ) {
					// printf("ret=%i\n",ret);
					if(ret == DB_NOTFOUND) { ret=0; break; }
					obMTRACE(ret); goto fin;
				}
				if(cnt_cvy_OffreX == limit+1) {
					ret = ob_chemin_LimitReached; break;
				}
				cnt_cvy_OffreX += 1;
				// printf("layer=%i X %lli->Y %lli\n",layer,Xoid,Yoid);
				//printf("found Xoid %lli,nR %lli\n",Xoid,offreX.nR);
				if( Xoid != pivot->oid ) { // traits[pivot->source] not inserted
					ret = _new_trait(privt,Xoid,Yoid);
					if(ret) { obMTRACE(ret);goto fin; }
					nbTrait +=1;
					//printf("trait %lli->%lli written\n",Xoid,Yoid);
				} else {
					//printf("trait %lli->%lli NOT written\n",Xoid,Yoid);
				}

				ret = getAIterator(&c_point,&Xoid,&moX,DB_SET);
				if( ret != 0 ){
					if(ret == DB_NOTFOUND ) XoidNotFound = true;
					else { obMTRACE(ret); goto fin;}
				}

				/* if points[Xoid] is found nothing is done,
				=> this point will not belong to layer+1, and the path from it
					will be stopped even if traits[X,Y] was written.
				*/
				if( XoidNotFound) {
					ret = _put_stocktemp4(privt,&stock,versionSg);
					if(ret) {obMTRACE(ret);goto fin;}

					memset(&moX,0,sizeof(ob_tMarqueOffre));
					// moX.ar.layer = 0, moY.ar.igraph = 0,
					// moY.av.layer = 0, moY.av.igraph = 0
					memcpy(&moX.offre,&offreX,sizeof(ob_tNoeud));

					if(pivot->nF == moX.offre.nR)  {
						/* moX is client of the pivot
						the path is terminated => layerX_empty unchanged,
						 and moX.ar.layer = 0,  */
						moX.av.layer = 1; // it is a source
						nbSrc +=1;
					} else {
						layerX_empty = false;
						moX.ar.layer = layer+1;
					}

					/*printf("Xoid %lli %lli->%lli written on layer %i igraph %i\n",
							Xoid,moX.offre.nR,moX.offre.nF,moX.ar.layer,moX.ar.igraph);*/
					ret = putAIterator(&c_point,&Xoid,&moX,DB_KEYFIRST);
					if(ret) { obMTRACE(ret);goto fin; }
					nbNoeudLayer +=1;
				}
			}  // end [C]
			SPI_cursor_close(cvy_offreX);cvy_offreX = NULL;
			/*******************************************************************/
			if(ret == ob_chemin_LimitReached) {ret = 0;break;}
		} // end [B]
		if(ret) {obMTRACE(ret); goto fin;}
		/***********************************************************************/

		// break conditions for [A]
		if (layerX_empty)  break;
		/*
		// No point where inserted on layer+1 => max(point.layer) = layer
		if(layer == (obCMAXCYCLE -1)) {
			// some point are inserted on layer+1, max(point.layer) = obCMACCYCLE
			layer +=1; break;
		}
		layer +=1; */
	} // end [A]
	/***************************************************************************/
	// layer is the number of layer inserted, and point.layer in [1,obCMAXCYCLE]
	// mo.ar.layer in [1,layer] since layer is the last inserted
	//privt->versionSg = versionSg;

fin:
	*pnbSrc =nbSrc;
	ret = closeSIterator(&cmar_pointY,ret);
	ret = closeAIterator(&c_point,ret);
	if(cvy_offreX != NULL) SPI_cursor_close(cvy_offreX);
	return ret;
}
/*******************************************************************************/
// sources are moved from the old graph (i_graph) to the new (i_graph+1)

static int _src_move_to_new(ob_tPrivateTemp *privt,ob_tSIterator *cmav_point,
		int i_graph,int *nbSource){

	int ret = 0;
	ob_tId Xoid;
	ob_tPoint pointX;
	ob_tMar marqueXav = {1,i_graph}; // layer,i_graph

	*nbSource = 0;
	ret = openSIterator(cmav_point,&marqueXav);
	if(ret) {obMTRACE(ret); return ret;}
	//elog(INFO,"Find source on igraph=%i.",i_graph);
	while(true) {

		ret = nextSIterator(cmav_point,&Xoid,&pointX);
		if( ret != 0) {
			if(ret == DB_NOTFOUND) return 0;
			else {obMTRACE(ret); return ret;}
		}
		//elog(INFO,"Xoid %lli is source.",Xoid);
		//printf("Xoid %lli is source.\n",Xoid);
		pointX.mo.av.igraph = i_graph+1;
		pointX.mo.av.layer = 1;
		ret = _initPoint(privt,&pointX);
		// pointX is written to new_igraph only if ret == 0
		if (ret == 0) *nbSource +=1;
		else if (ret!=ob_chemin_CerStockEpuise) {obMTRACE(ret); return ret;}
	}
}

/*******************************************************************************/

int _parcours_avant(privt,pivot,i_graph,nbSource)

	ob_tPrivateTemp *privt;
	ob_tNoeud 	*pivot;
	int 		i_graph;
	int 		*nbSource;
{

	ob_tSIterator cmav_point,cx_trait;
	ob_tAIterator c_point,c_trait;
	//Portal cvy_offreX = NULL;
	int layer,ret;
	const int new_igraph = i_graph+1;
	bool _path_to_pivot = false;


	initSIterator(&cmav_point,privt->mav_points,
			sizeof(ob_tMar),sizeof(ob_tId),sizeof(ob_tPoint));

	initSIterator(&cx_trait,privt->px_traits,
			sizeof(ob_tId),sizeof(ob_tFleche),sizeof(ob_tTrait));

	initAIterator(&c_point,privt->points,
			sizeof(ob_tId),sizeof(ob_tPoint));

	initAIterator(&c_trait,privt->traits,
			sizeof(ob_tFleche),sizeof(ob_tTrait));


	ret = _src_move_to_new(privt,&cmav_point,i_graph,nbSource);
	if(ret) goto fin;
	if(*nbSource == 0 ) {
			ret = ob_chemin_CerNoSource;
			goto fin;
	}

	layer = 0;
	while(true) { // loop [D] while(!layerY_empty)
		ob_tMar marqueXav = {layer+1,new_igraph}; // layer,i_graph
		bool layerY_empty = true;

		layer += 1;
		/* [E] select (pointX,Xoid) having layer,igraph == layer,new_igraph */
		ret = openSIterator(&cmav_point,&marqueXav);
		if(ret) {obMTRACE(ret); goto fin;}

		while(true) { // loop [E] cmav_point
			ob_tId Xoid;
			ob_tPoint pointX;

			ret = nextSIterator(&cmav_point,&Xoid,&pointX);
			if(ret) {
				if(ret == DB_NOTFOUND) {ret = 0;break;}
				obMTRACE(ret); goto fin;
			}

			// [F] select (trait,fleche) from traits having fleche.Xoid == Xoid
			ret = openSIterator(&cx_trait,&Xoid);
			if(ret) {obMTRACE(ret); goto fin;}

			while(true) { // loop [F] cx_trait
				ob_tFleche fleche;
				ob_tTrait trait;
				ob_tPoint pointY;

				ret = nextSIterator(&cx_trait,&fleche,&trait);
				if(ret != 0) {
					if(ret == DB_NOTFOUND) { ret = 0; break; }
					else {obMTRACE(ret); goto fin;}
				}

				ret = getAIterator(&c_point,&fleche.Yoid,&pointY,DB_SET);
				if(ret) {obMTRACE(ret); goto fin;} // should be found

				pointY.mo.av.igraph = new_igraph;
				pointY.mo.av.layer = layer+1;
				ret = _initPoint(privt,&pointY);

				if(ret == 0 ) { // stock of pointY is not empty
					layerY_empty = false;
					trait.igraph = new_igraph;
					ret = putAIterator(&c_trait,&fleche,&trait,DB_KEYFIRST);
					if (ret) { obMTRACE(ret); goto fin; }

					if(pointY.mo.offre.oid == pivot->oid)
						_path_to_pivot = true;

				} else if ( ret == ob_chemin_CerStockEpuise) ret = 0;
				else {obMTRACE(ret); goto fin;}
			} // end F
		} // end E
		if (layerY_empty) break;
	} // end D
	// should have fount some source
	if(!_path_to_pivot) ret = ob_chemin_CerNoSource;
	//printf("fin de parcours avant nbScr %i\n",*nbSource);
fin:

	ret = closeSIterator(&cmav_point,ret);
	ret = closeSIterator(&cx_trait,ret);
	ret = closeAIterator(&c_point,ret);
	ret = closeAIterator(&c_trait,ret);
	return ret;
}
/*******************************************************************************
bellman_ford

At the beginning, all sources are such as source.chemin=[source,]
for t in [1,obCMAXCYCLE]:
	for all trait[X,Y] of the graph (i_graph+1):
		if X.chemin empty continue
		chemin = X.chemin followed by Y
		if chemin better than X.chemin, then Y.chemin <- chemin
	At the end, Each node.chemin is the best chemin from a source to this node
	with at most t traits
At the end, pivot contains the best chemin from a source to pivot at most obCMAXCYCLE long

the algorithm is usually repeated for all node, but here only
obCMAXCYCLE times. (Paths are NOT at most nblayer long).
_bellman_ford_in is called for each trait of i_graph+1

return ret!=0 on error
*******************************************************************************/

/*******************************************************************************
bellman_ford_in

point.chemin is a path from a source to pivot, or is empty.
on the trait pointX->pointY, if pointX.chemin is empty, nothing is done.
If it is not, we consider the path that follows the path pointX.chemin and goes
to pointY. It is compared with pointY.chemin using their prodOmega.
If this path is better than pointY.chemin, it is written into pointY.chemin.

return ret!=0 on error
*******************************************************************************/
static int _bellman_ford_in(c_point,ppivotId,trait)
	ob_tAIterator *c_point;
	ob_tId *ppivotId;
	ob_tTrait *trait;
{
	int ret;
	ob_tPoint pointX,pointY;
	double oldOmega,newOmega;
	ob_tStock *pstockY;
	ob_tLoop loop;

	ret = getAIterator(c_point,&trait->rid.Xoid,&pointX,DB_SET);
	if(ret) {obMTRACE(ret); goto fin;} // should be found

	// if pointX is empty, pointY is unchanged
	if(ob_flux_McheminGetNbNode(&pointX.chemin) == 0) goto fin;


	ret = getAIterator(c_point,&trait->rid.Yoid,&pointY,DB_SET);
	if(ret) {obMTRACE(ret); goto fin;} // should be found

	oldOmega = ob_flux_McheminGetOmega(&pointY.chemin);
	// 0. if the path is empty

	pstockY = ob_flux_cheminGetAdrStockLastNode(&pointY.chemin);

	ret =ob_flux_cheminAjouterNoeud(
			&pointX.chemin,
			pstockY,
			&pointY.mo.offre,&loop);
	if (ret) {
		if(ret == ob_flux_CerLoopOnOffer) {
			// pointY forms a loop on chemin
			// it is not added to chemin, but bellman continue
			ret = 0; goto fin;
		}
		if(ret == ob_flux_CerCheminTropLong ) {
			//printf("chemin.nbNoeud=%i, Y=%lli, trop long\n",pointX.chemin.nbNoeud,trait->rid.Yoid);
			//prChemin(&pointX.chemin);
			ret = 0; goto fin;
		}
		obMTRACE(ret);goto fin;}

	//printf("c'est pas plante pour XY=(%lli,%lli)\n",trait->rid.Xoid,trait->rid.Yoid);
	//printf("chemin.nbNoeud=%i, Y=%lli, ",pointX.chemin.nbNoeud,trait->rid.Yoid);
	//prChemin(&pointX.chemin);

	if(trait->rid.Yoid == *ppivotId) {
		ret = ob_flux_fluxMaximum(&pointX.chemin);
		if(ret) goto fin; // flow undefined or error
	}
	//printf("ici\n");
	newOmega = ob_flux_McheminGetOmega(&pointX.chemin);
	if (newOmega <= oldOmega)  goto fin;
	// when pointY.chemin is empty, oldOmega == 0.

	// writes pointX.chemin into points[trait->rid.Yoid]
	memcpy(&pointX.mo,&pointY.mo,sizeof(ob_tMarqueOffre));

	ret = putAIterator(c_point,&trait->rid.Yoid,&pointX,DB_CURRENT);
	// the key is ignored
	if(ret) {obMTRACE(ret); goto fin;}

fin:

	return	ret;
}

static int _bellman_ford(privt,ppivotId,chemin,i_graph)
	ob_tPrivateTemp *privt;
	ob_tId *ppivotId;
	ob_tChemin *chemin;
	int i_graph;

{
	int _iter,ret;
	ob_tPoint pointPivot;
	ob_tSIterator cm_trait;
	ob_tAIterator c_point;
	// DBT  ks_pivotId,du_pointPivot;
	int _new_graph = i_graph+1;

	initSIterator(&cm_trait,privt->m_traits,
			sizeof(int),sizeof(ob_tFleche),sizeof(ob_tTrait));

	initAIterator(&c_point,privt->points,sizeof(ob_tId),sizeof(ob_tPoint));



	obMRange(_iter,openbarter_g.maxCommit) {

		ret = openSIterator(&cm_trait,&_new_graph);
		if (ret) { obMTRACE(ret); goto fin;}

		while(true) {
			ob_tTrait trait;
			ob_tFleche rid;

			ret = nextSIterator(&cm_trait,&rid,&trait);
			if(ret) {
				if(ret == DB_NOTFOUND) {ret = 0;break;}
				obMTRACE(ret); goto fin;
			}

			ret = _bellman_ford_in(&c_point,ppivotId,&trait);
			if(ret) goto fin;
		}
	}

	ret = getAIterator(&c_point,ppivotId,&pointPivot,DB_SET);
	if(ret) {obMTRACE(ret); goto fin;} // should be found
	//printf("Chemin trouve\n");
	// pivot should be found since it was found by parcours_avant
	memcpy(chemin,&(pointPivot.chemin),ob_flux_cheminGetSize(&pointPivot.chemin));

fin:
	ret = closeSIterator(&cm_trait,ret);
	ret = closeAIterator(&c_point,ret);
	//if(ret) printf("Err %i à la fin\n",ret);
	return ret;
}


/*******************************************************************************
int ob_chemin_get_commit(ob_getdraft_ctx *ctx)

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

********************************************************************************
USAGE:
	ob_getdraft_ctx ctx;


	//  ctx.pivot,ctx.stockPivot are set
	// in ob_getdraft_getcommit_init_new(&ctx)
	ctx.i_graph = 0;ctx.i_commit;ctx.end = false;

	while((ret = ob_chemin_get_commit(&ctx)) == 0) {
		ob_tNo *node  = &ctx->accord.chemin.no[ctx->i_commit];
		.....
	}
*******************************************************************************/

/*******************************************************************************
 *  ATTENTION
remplacer int ob_getdraft_get_commit(ob_getdraft_ctx *ctx)
par ob_chemin_get_commit(ob_getdraft_ctx *ctx)
et ob_getdraft_getcommit_init()
par ob_getdraft_getcommit_init_new()
*******************************************************************************/

void ob_chemin_get_commit_init(ob_getdraft_ctx *ctx) {
	ctx->state = 0;
	ctx->envt = NULL;
}
static int _get_draft_next(ob_getdraft_ctx *ctx);
int ob_chemin_get_commit(ob_getdraft_ctx *ctx) {
	int ret;

	if(ctx->state == 2)
		return ob_chemin_CerNoDraft;

	if(ctx->state == 1) {
		ctx->i_commit += 1;
		if(ctx->i_commit < ctx->accord.chemin.nbNoeud)
			return 0;
	}

	ctx->i_commit = 0;
	ret = _get_draft_next(ctx);
	if(ret) ctx->state = 2;
	else ctx->state = 1;

	return ret;

}

/*******************************************************************************
* ctx->pivot et ctx->stockPivot are set
* ob_chemin_get_commit_init(ctx) has been called
*******************************************************************************/
static int _get_draft_next(ob_getdraft_ctx *ctx) {

	int ret,ret_t,_nbSource;
	DB_ENV *envt;
	ob_tPrivateTemp *privt ;
	ob_tAccord *paccord = &ctx->accord;

	if(ctx->envt == NULL) {
		envt = NULL;
		ret = ob_dbe_openEnvTemp(&envt);
		if (ret) { ctx->envt = NULL; obMTRACE(ret); return ret;}

		ctx->envt = envt;
		privt = envt->app_private;

		ctx->i_graph = 0;
		privt->cflags = 0;
		// privt->quotaTrait = 1<<15;

		if(ctx->pivot.stockId == 0) {
			privt->cflags |= ob_flux_CLastIgnore;
			privt->deposOffre = false;
		} else  {
			privt->cflags &= ~ob_flux_CLastIgnore;
			privt->deposOffre = true;
		}
		//elog(INFO,"begin sid=%lli=%lli\n",ctx->pivot.stockId,ctx->stockPivot.sid);
		ret = _parcours_arriere(envt,&ctx->pivot,
				&ctx->stockPivot,privt->deposOffre,&privt->versionSg,&_nbSource);
		if(ret) goto closeEnv;
		//elog(INFO,"parcours_arriere nbSrc=%i version=%lli\n",_nbSource,privt->versionSg);
		//printf("fin parcours_arriere,ret==0, nbSrc %i\n",_nbSource);

		if(!_nbSource) {
			ret = ob_chemin_CerNoDraft;
			goto closeEnv;
		}
	} else {
		envt = ctx->envt;
		privt = ctx->envt->app_private;
		ctx->i_graph = ctx->i_graph + 1;
	}

	ret = _parcours_avant(privt,&ctx->pivot,ctx->i_graph,&_nbSource);
	if(ret == ob_chemin_CerNoSource) {
		ret = ob_chemin_CerNoDraft; // normal termination
		goto closeEnv;
	}
	if(ret) goto closeEnv;
	//elog(INFO,"parcours_avant nbSrc %i\n",_nbSource);
	//printf("fin parcours_avant nbSrc %i\n",_nbSource);


	// competition on omega
	ret = _bellman_ford(privt,&ctx->pivot.oid,&paccord->chemin,ctx->i_graph);
	if(ret)	goto closeEnv;

	// normal end when the flow is undefined
	if(!(paccord->chemin.cflags & ob_flux_CFlowDefined)) {
		ret = ob_chemin_CerNoDraft;
		goto closeEnv;
	}
	// an agreement was found
	paccord->status = DRAFT;
	paccord->versionSg = privt->versionSg;
	paccord->nbSource = _nbSource;
	// elog(INFO,"bellman draft found with %i nodes",ob_flux_McheminGetNbNode(&paccord->chemin));
	//printf("accord found with %i nodes\n",ob_flux_McheminGetNbNode(&paccord->chemin));

	ret = _diminuer(privt,&paccord->chemin,&ctx->pivot.stockId);
	return ret;

closeEnv:
	ret_t = ob_dbe_closeEnvTemp(envt);
	if (ret_t) obMTRACE(ret_t);
	ctx->envt = NULL;
	return ret;
}


/*******************************************************************************
diminuer
	decreases stocks after a draft has been found
	if privt->deposOffre, the stock of the pivot is considered
	else, it is not
*******************************************************************************/
static int _diminuer(privt,pchemin,stockPivotId)
	ob_tPrivateTemp *privt;
	ob_tChemin *pchemin;
	ob_tId* stockPivotId;

{
	int _i,nbNoeud,nbStock,ret = 0;
	ob_tStock stock;
	ob_tId oid;
	ob_tPoint point;
	ob_tStock tabFlux[obCMAXCYCLE];
	bool _someStockExhausted = false;
	ob_tSIterator cst_point;
	ob_tAIterator c_stock;

	initSIterator(&cst_point,privt->st_points,
			sizeof(ob_tId),sizeof(ob_tId),sizeof(ob_tPoint));
	initAIterator(&c_stock,privt->stocktemps,
			sizeof(ob_tId),sizeof(ob_tStock));
	//printf("in _diminuer\n");
	nbNoeud = ob_flux_GetTabStocks(pchemin,tabFlux,&nbStock);
	//printf("in _diminuer\n");
	obMRange(_i,nbStock) {
		ob_tStock *pflux = &tabFlux[_i];

		// when the stock is that of the pivot,
		// it is never shared with other nodes. The stock is reduced
		// only if privt->deposOffre, otherwise, it remains empty.
		if(	(pflux->sid == *stockPivotId)
			&&	(!privt->deposOffre)) continue;

		// stock <-stocktemps[pflux->sid], should be found
		ret = getAIterator(&c_stock,&pflux->sid,&stock,DB_SET);
		if (ret) {obMTRACE(ret); goto fin;}

		if (stock.qtt != pflux->qtt) {
			if (stock.qtt > pflux->qtt) {
				// stocktemps[sid]  updated to stock if it is not empty
				stock.qtt -= pflux->qtt;
				ret = putAIterator(&c_stock,&pflux->sid,&stock,DB_CURRENT);
				if(ret) {obMTRACE(ret);goto fin;}
				continue; // obMRange
			} else {
				// the stocktemps[sid] cannot afford this flow
				ret = ob_point_CerStockNotNeg;obMTRACE(ret);goto fin;
			}
		}

		/* the stock is empty: stock.qtt == pflux->qtt.
		it is useless to update it, since points and traits that use it
		will not belong to the next graph.
		The stock is now empty */
		_someStockExhausted = true;


		// all point and traits that use it are deleted
		// ************************************************************
		ret = openSIterator(&cst_point,&pflux->sid);
		if (ret) { obMTRACE(ret); goto fin;}

		while(true) {
			//DBT *dbt = &cst_point.du_key;

			ret = nextSIterator(&cst_point,&oid,&point);
			if(ret) {
				if(ret == DB_NOTFOUND) {ret = 0;break;}
				obMTRACE(ret); goto fin;
			}

#ifndef NDEBUG // mise au point
			// elog(INFO,"NDEBUG is undefined"); IT IS UNDEFINED
			if(point.mo.offre.oid != oid) //*((ob_tId*)dbt->data))
			{ret = ob_chemin_CerPointIncoherent;obMTRACE(ret); goto fin;}
			if(point.mo.offre.stockId != pflux->sid)
			{ret = ob_chemin_CerPointIncoherent;obMTRACE(ret); goto fin;}
#endif
			// the point are deleted
			ret = iterators_idDel(privt->points,&oid,sizeof(ob_tId));
			// ret = privt->points->del(privt->points,0,dbt,0);
			if (ret) {obMTRACE(ret); goto fin;}

			// all traits that touch this point are deleted
			ret = iterators_idDel(privt->px_traits,&oid,sizeof(ob_tId));
			//ret = privt->px_traits->del(privt->px_traits,0,dbt,0);
			if (ret) {
				if(ret==DB_NOTFOUND) ret = 0;
				else {obMTRACE(ret); goto fin;}
			}

			ret = iterators_idDel(privt->py_traits,&oid,sizeof(ob_tId));
			//ret = privt->py_traits->del(privt->py_traits,0,dbt,0);
			if (ret) {
				if(ret == DB_NOTFOUND) ret = 0;
				else {obMTRACE(ret); goto fin;}
			}
		}
		// end loop cst_point
		// ************************************************************
	}
	/* if no stock is exhausted, it is not the maximum flow,
	and the draft would make a len(girth) <= obCMAXCYCLE
	 */
	if(!_someStockExhausted) {
		ret = ob_flux_CerCheminNotMax;obMTRACE(ret); goto fin;
	}
fin:
	ret = closeSIterator(&cst_point,ret);
	ret = closeAIterator(&c_stock,ret);
	// obMCloseCursor(cst_point);
	return ret;
}
