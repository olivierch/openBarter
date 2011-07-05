#define TBDB_C_
/*
 * tbdb.c
 *
 *  Created on: 8 juin 2011
 *      Author: olivier
 */

#include <stdlib.h>
#include <unistd.h>
typedef long long int int64;

#include <stdbool.h>
#include "common.h"
#include "pg_test.h"
#include "svn_tests.h"
#include "chemin_test.h"
#include "iterators.h"

#define MakeBdbErr(ret,err) do { \
	MAKE_ERROR(db_strerror(ret), &err); \
	return err; \
} while(false)

#define NF_PIVOT (1<<30)

struct TestCtxData testCtxData;
const TestCtx testCtx = &testCtxData;
static int _getIdArbre(Portal portal,ob_tId id,ob_tId *idr,ob_tId *nl);
static int _getIdFuseau(Portal portal,ob_tId id,ob_tId *idr,ob_tId *nl);

static int _Next3(Portal portal,ob_tNoeud *offreX,ob_tStock *stock);
static int _Next6(Portal portal,ob_tNoeud *offreX,ob_tStock *stock);


/* ========================================================================== */
void initGuc(int testNum) {

	ob_tGlob *glob = &openbarter_g;

	memset(testCtx,0,sizeof(struct TestCtxData));
	testCtx->testNum = testNum;

	// guc normally set by _obinit_guc in iternoeud.c
	glob->cacheSizeKb = 16*1024;
	glob->maxArrow = 1<<15;
	glob->maxCommit = 8; // MUST be equal to obCMAXCYCLE
}

void prChemin(ob_tChemin* ch){
	int i;

	printf("chemin:");
	obMRange(i,ch->nbNoeud) {
		printf("->%lli",ch->no[i].noeud.oid);
	}
	printf("\n");
}
/*
void errcallback(const DB_ENV *dbenv, const char *errpfx,
		const char *msg) {
	printf("ob>%s> %s\n", errpfx, msg);
	return;
}*/
static void _reset_stock(ob_tNoeud *offre,ob_tStock *stock) {
	// keep stock and offreX related
	memset(stock,0,sizeof(ob_tStock));
	stock->sid = offre->stockId;
	stock->nF = offre->nF;
	stock->own = offre->own;
	return;
}
int initEnv(DB_ENV **penv) {
	int ret;
	DB_ENV *envt;

	ret = db_env_create(penv, 0);
	if (ret) return ret;

	envt = *penv;
	//envt->set_errcall(envt, errcallback);
	envt->set_errpfx(envt, "envit");
	return 0;

}

//svn_error_t *test1(const char **msg, bool msg_only, svn_test_opts_t *opts) {
SVN_DECLARE_FCT(test1) {
	svn_error_t *err = SVN_NO_ERROR;
	char buf[128];

	*msg = "explication du test";
	if (msg_only)
		return SVN_NO_ERROR;
	return SVN_NO_ERROR;

	printf("opts.record = %i\n",opts->record);
	MAKE_ERROR("err 1", &err);
	// free_error(&err);
	MAKE_ERROR("err 2", &err);
	MAKE_ERROR("err 3", &err);

	return err;
}

SVN_DECLARE_FCT(test2) {
	DB_ENV *env;
	int ret;
	SVN_BEGIN_FCT("ouverture fermeture d'environnement");

	initGuc(2);

	ret = initEnv(&env);
	if(ret) MakeBdbErr(ret,err);
	// l'env est ouvert
	ret = env->close(env, 0);
	if (ret) MakeBdbErr(ret,err);
	return SVN_NO_ERROR;

}

SVN_DECLARE_FCT(test3) {
	DB_ENV *env;
	int ret;
	Portal portal;
	ob_tId id,p,idMax;
	ob_tId Xoid;
	ob_tNoeud offreX;
	ob_tStock stock;

	SVN_BEGIN_FCT("test gtIdArbre");

	initGuc(3); // ob_iternoeud_NextA() uses _Next3()

	testCtx->q = 3;
	testCtx->nlMax = 4;

	// computes idMax = sum(q^i for i in [0,testCtx->nlMax])
	for (idMax =0,id =0,p = 1;
			id <= testCtx->nlMax;
			idMax += p,p *= testCtx->q, id +=1 );
	//printf("idMax %lli\n",idMax);

	for(id=1;id <= idMax;id+=1) {
		portal = ob_iternoeud_GetPortalA(env,0,id,100000);
		// testCtx->id = id;
		while(!ob_iternoeud_NextA(portal,&Xoid,&offreX,&stock)) {
			;
		}
		free(portal);
	}

	return SVN_NO_ERROR;
}


SVN_DECLARE_FCT(test4) {
	DB_ENV *env;
	int ret;


	SVN_BEGIN_FCT("test ouverture fermeture de bases");

	initGuc(4);

	ret = ob_dbe_openEnvTemp(&env);
	if(ret) MakeBdbErr(ret,err);
	// l'env est ouvert

	ret = ob_dbe_closeEnvTemp(env);
	if (ret) MakeBdbErr(ret,err);
	return SVN_NO_ERROR;
}


SVN_DECLARE_FCT(test5) {
	DB_ENV *env;
	int ret;

	SVN_BEGIN_FCT("lancement de parcours arriere");

	initGuc(5); // ob_iternoeud_NextA() uses _Next3()

	ret = ob_dbe_openEnvTemp(&env);

	if(ret) MAKE_ERROR("erreur d'ouverture", &err);
	// l'env est ouvert
	{
		ob_tNoeud pivot;
		ob_tStock stock;
		ob_tId versionSg;
		int nbSrc;

		memset(&pivot,0,sizeof(ob_tNoeud));
		pivot.stockId = 1;pivot.oid = 1; pivot.omega = 1.;
		pivot.nF = NF_PIVOT; pivot.nR = 1;pivot.own = 1;
		_reset_stock(&pivot,&stock);
		stock.qtt=1;stock.version=1;

		ret = _parcours_arriere(env,&pivot,&stock,true,&versionSg,&nbSrc);
		if (ret) MAKE_ERROR("erreur dans parcours arriere", &err);

	}
	ret = ob_dbe_closeEnvTemp(env);
	if (ret) MAKE_ERROR("erreur a la fermeture de la base", &err);
	return SVN_NO_ERROR;
}
static void _getIdLevel(ob_tId nlMax,ob_tId q,ob_tId *sum) {
	ob_tId idMax,id,p;

	// computes idMax = sum(q^i for i in [0,nlMax])
	for (idMax =0,id =0,p = 1;
			id <= nlMax;
			idMax += p,p *= q, id +=1 );
	*sum = idMax;
	return;
}
SVN_DECLARE_FCT(test6) {
	DB_ENV *env;
	int ret;
	Portal portal;
	ob_tId id,idMax;
	ob_tId Xoid;
	ob_tNoeud offreX;
	ob_tStock stock;

	SVN_BEGIN_FCT("test getIdFuseau");

	initGuc(6);  // ob_iternoeud_NextA() uses _Next6()

	testCtx->q = 3;
	testCtx->nlMax = 1;

	_getIdLevel(testCtx->nlMax,testCtx->q,&idMax);

	for(id=1;id <= idMax+30;id+=1) {
		portal = ob_iternoeud_GetPortalA(env,0,id,100000);
		// testCtx->id = id;
		while(!(ret = ob_iternoeud_NextA(portal,&Xoid,&offreX,&stock))) {
			; //printf("Xoid %lli %lli->%lli\n",Xoid,offreX.nR,offreX.nF);
		}
		free(portal);
	}
	if(ret != DB_NOTFOUND)MAKE_ERROR("erreur dans ob_iternoeud", &err);

	return SVN_NO_ERROR;
}

SVN_DECLARE_FCT(test7) {
	DB_ENV *env;
	int ret;

	SVN_BEGIN_FCT("lancement de parcours avant");

	initGuc(7);  // ob_iternoeud_NextA() uses _Next6()
	testCtx->q = 3;
	testCtx->nlMax = 1;

	ret = ob_dbe_openEnvTemp(&env);
	if(ret) MAKE_ERROR("erreur d'ouverture", &err);
	ret = truncateBasesTemp(env->app_private);
	if(ret) MAKE_ERROR("erreur truncate", &err);
	// l'env est ouvert
	{
		ob_tNoeud pivot;
		ob_tStock stock;
		int nbSource;
		ob_tPrivateTemp *privt = env->app_private;
		ob_tId versionSg;

		memset(&pivot,0,sizeof(ob_tNoeud));
		pivot.stockId = 1;pivot.oid = 1; pivot.omega = 1.;
		pivot.nF = NF_PIVOT; pivot.nR = 1;pivot.own = 1;
		_reset_stock(&pivot,&stock);
		stock.qtt=1;stock.version=1;

		ret = _parcours_arriere(env,&pivot,&stock,true,&versionSg,&nbSource);
		if (ret) {
			MAKE_ERROR("erreur dans parcours arriere", &err);
		} //else printf("parcours arriere well terminated\n");

		ret = _parcours_avant(privt,&pivot,0,&nbSource);
		if (ret) {
			printf("ret=%i %s\n",ret,db_strerror(ret));
			MAKE_ERROR("erreur dans parcours avant", &err);
		}
		//printf("parcours avant well terminated with nbSource %i\n",nbSource);

	}
	ret = ob_dbe_closeEnvTemp(env);
	if (ret) MAKE_ERROR("erreur a la fermeture de la base", &err);
	return SVN_NO_ERROR;
}

SVN_DECLARE_FCT(test8) {
	DB_ENV *env;
	int ret;


	SVN_BEGIN_FCT("test iterateurs");

	initGuc(8);

	ret = ob_dbe_openEnvTemp(&env);
	if(ret) MakeBdbErr(ret,err);
	{
		ob_tPrivateTemp *privt = env->app_private;
		ob_tId id,r;
		ob_tMarqueOffre mo;
		ob_tMar mar;
		ob_tSIterator cmar_pointY;
		ob_tAIterator c_point;

		initSIterator(&cmar_pointY,privt->mar_points,
				sizeof(ob_tMar),sizeof(ob_tId),sizeof(ob_tMarqueOffre));
		initAIterator(&c_point,privt->points,
				sizeof(ob_tId),sizeof(ob_tMarqueOffre));

		for(r=1;r<5;r +=1) {
			mo.offre.oid = r;
			mo.ar.layer = 1;
			mo.ar.igraph = 0;
			ret = putAIterator(&c_point,&r,&mo,DB_KEYFIRST);
			if(ret) {obMTRACE(ret);goto fin;}
		}

		mar.layer = 1;
		mar.igraph = 0;
		//printf("init layer: %i\n",layer);
		ret = openSIterator(&cmar_pointY,&mar);
		if(ret) {obMTRACE(ret); goto fin;}

		r = 1;
		while(true) {
			ret = nextSIterator(&cmar_pointY,&id,&mo);
			if(ret == DB_NOTFOUND) {ret = 0; break; }
			if(ret) {obMTRACE(ret);goto fin;}
			if(r != id) {obMTRACE(ret);goto fin;}
			r +=1;
		}
	}
fin:
	ret = ob_dbe_closeEnvTemp(env);
	if (ret) MakeBdbErr(ret,err);
	return SVN_NO_ERROR;
}

svn_error_t *in_test9(svn_error_t *err) {
	int ret;
	ob_getdraft_ctx ctx;

	memset(&ctx.pivot,0,sizeof(ob_tNoeud));
	ctx.pivot.stockId = 1;ctx.pivot.oid = 1; ctx.pivot.omega = 2.;
	ctx.pivot.nF = NF_PIVOT; ctx.pivot.nR = 1;ctx.pivot.own = 1;

	_reset_stock(&ctx.pivot,&ctx.stockPivot);
	ctx.stockPivot.qtt=100;ctx.stockPivot.version=1;

	ob_chemin_get_commit_init(&ctx);

	while((ret = ob_chemin_get_commit(&ctx)) == 0) {
		ob_tNo *node  = &ctx.accord.chemin.no[ctx.i_commit];
		char *s;
		;/*
		s=(ctx.i_commit < ctx.accord.chemin.nbNoeud-1)?"":"\n";
		if(ctx.i_commit == 0)

			printf("graph %i\tcommit %i: ",ctx.i_graph,ctx.i_commit);
		printf("->%lli%s",node->noeud.oid,s);
		//printf("%lli,%lli->%s",node->noeud.nF,node->fluxArrondi,s);
		*/
	}
	if((ctx.i_commit ==0 && ctx.i_graph ==0))
		MAKE_ERROR("should find some draft", &err);
	// printf("i_graph %i\n",ctx.i_graph);

	if(ret != ob_chemin_CerNoDraft) {
		printf("err %i\n",ret);
		MAKE_ERROR("err ret!=0", &err);
	}

	return err;
}

SVN_DECLARE_FCT(test9) {
	DB_ENV *env;
	int ret;

	SVN_BEGIN_FCT("draft with 8 nodes");

	initGuc(7);  // ob_iternoeud_NextA() uses _Next6()
	testCtx->q = 3;
	testCtx->nlMax = 6; // 8 nodes

	return in_test9(err);
}

SVN_DECLARE_FCT(test10) {
	DB_ENV *env;
	int ret;

	SVN_BEGIN_FCT("draft with 6 nodes,maxCommit=6");

	initGuc(7);  // ob_iternoeud_NextA() uses _Next6()
	testCtx->q = 3;
	testCtx->nlMax = 4; // 6 nodes
	openbarter_g.maxCommit =6;

	return in_test9(err);
}
SVN_DECLARE_FCT(test11) {
	DB_ENV *env;
	int ret;

	SVN_BEGIN_FCT("no draft with 9 nodes");

	initGuc(7); // ob_iternoeud_NextA() uses _Next6()
	testCtx->q = 3;
	testCtx->nlMax = 7; // 9 nodes

	// l'env est ouvert
	{
		ob_getdraft_ctx ctx;

		memset(&ctx.pivot,0,sizeof(ob_tNoeud));
		ctx.pivot.stockId = 1;ctx.pivot.oid = 1; ctx.pivot.omega = 2.;
		ctx.pivot.nF = NF_PIVOT; ctx.pivot.nR = 1;ctx.pivot.own = 1;

		_reset_stock(&ctx.pivot,&ctx.stockPivot);
		ctx.stockPivot.qtt=100;ctx.stockPivot.version=1;

		ob_chemin_get_commit_init(&ctx);

		while((ret = ob_chemin_get_commit(&ctx)) == 0) {
			ob_tNo *node  = &ctx.accord.chemin.no[ctx.i_commit];
			char *s;
			;/*
			s=(ctx.i_commit < ctx.accord.chemin.nbNoeud-1)?"":"\n";
			if(ctx.i_commit == 0)

				printf("graph %i\tcommit %i: ",ctx.i_graph,ctx.i_commit);
			printf("->%lli%s",node->noeud.oid,s);
			//printf("%lli,%lli->%s",node->noeud.nF,node->fluxArrondi,s);
			*/
		}
		if(!(ctx.i_commit ==0 && ctx.i_graph ==0))
			MAKE_ERROR("should not find any draft", &err);
		if(ret != ob_chemin_CerNoDraft) {
			printf("err %i\n",ret);
			MAKE_ERROR("err ret!=0", &err);
		}

	}
	return err;
}

struct svn_test_descriptor_t test_funcs[] = {
		SVN_TEST_NULL,
		SVN_TEST_PASS(test1),
		SVN_TEST_PASS(test2),
		SVN_TEST_PASS(test3),
		SVN_TEST_PASS(test4),
		SVN_TEST_PASS(test5),
		SVN_TEST_PASS(test6),
		SVN_TEST_PASS(test7),
		SVN_TEST_PASS(test8),
		SVN_TEST_PASS(test9),
		SVN_TEST_PASS(test10),
		SVN_TEST_PASS(test11),
		SVN_TEST_NULL
};
/*****************************************************************************/

Portal ob_iternoeud_GetPortalA(envt,yoid,nr,limit)
	DB_ENV *envt;
	ob_tId  yoid;
	ob_tId  nr;
	int limit;
{
	Portal portal;

	portal = malloc(sizeof(struct PortalData));
	if(portal == NULL) return NULL;

	memset(portal,0,sizeof(struct PortalData));
	portal->yoid = yoid;
	portal->nr = nr;
	portal->limit = (ob_tId) limit;
	return portal;
}
void SPI_cursor_close(Portal p) {
	free(p);
	return;
}

int ob_iternoeud_NextA(portal,Xoid,offreX,stock)
	Portal portal;
	ob_tId *Xoid;
	ob_tNoeud *offreX;
	ob_tStock *stock;
{
	int ret;

	if(portal == NULL) return ob_chemin_CerIterNoeudErr;

	portal->nbCallNext += 1;
	if(portal->nbCallNext > portal->limit)
			return ob_chemin_LimitReached;
	switch(testCtx->testNum) {
	case 3:
	case 5:
		ret = _Next3(portal,offreX,stock);
		break;
	case 6:
	case 7:
		ret = _Next6(portal,offreX,stock);
		break;
	default:
		ret = ob_chemin_CerIterNoeudErr;
	}

	*Xoid = offreX->oid;
	return ret;
}
// test3 and test5
static int _Next3(portal,offreX,stock)
	Portal portal;
	ob_tNoeud *offreX;
	ob_tStock *stock;
{
	int ret;
	ob_tId id,nl;

	testCtx->q = 3;
	testCtx->nlMax = 2;

	ret = _getIdArbre(portal,portal->nr,&id,&nl);
	if(ret) return DB_NOTFOUND; // leaves are reached
	//printf("Next3 %lli: %lli->%lli\n",nl,portal->nr,id);

	offreX->oid = id;
	offreX->nF = portal->nr;
	offreX->nR = id;
	offreX->stockId = id;
	offreX->omega = 2.;

	_reset_stock(offreX,stock);
	stock->qtt = 10;
	stock->version = 1;
	stock->own = id;

	return 0;
}
// test6 AND test7
static int _Next6(portal,offreX,stock)
	Portal portal;
	ob_tNoeud *offreX;
	ob_tStock *stock;
{
		int ret;
		ob_tId id,nl;


		ret = _getIdFuseau(portal,portal->nr,&id,&nl);
		if(ret) return DB_NOTFOUND; // leaves are reached
		if(portal->nr ==0){
			printf("nr=0,id %lli nl %lli\n",id,nl);
		}

		offreX->oid = id;
		offreX->nF = portal->nr;

		if (nl == testCtx->nlMax) offreX->nR = NF_PIVOT;
		else offreX->nR = id;

		offreX->stockId = id;
		offreX->omega = 2.;

		//printf("Next6 %lli %lli: %lli->%lli\n",nl,id,offreX->nF,offreX->nR);

		_reset_stock(offreX,stock);
		stock->qtt = 10;
		stock->version = 1;
		stock->own = id;

		return 0;
}
/*
example:
q=3
niveau 0 (3^1) 		s = 3^0 = 1
1 -> 1+1
1 -> 1+2
1 -> 1+3=4

niveau 1 (3^2) 		s = 3^1+3^0 = 4
2 -> 4+1
2 -> 4+2
2 -> 4+3

3 -> 7+1
3 -> 7+2
3 -> 7+3

4 -> 10+1
4 -> 10+2
4 -> 10+3

niveau 2 (3^3) 		s = 3^2+3^1+3^0 =13
5 -> 13+1
...
6 -> 16+1
...
7 -> 19+1
....
 */
static int _getIdArbreInt(ob_tId id,ob_tId *idr,ob_tId *nl) {
	ob_tId sp=0,s=1,_p;
	ob_tId _nl = 0;
	const ob_tId q=testCtx->q;//,nlMax=testCtx->nlMax;
	int ret = 0;

	if(id==1) {
		*idr = 1;
		goto fin;
	}
	_p = 1;
	while(!((sp < id) && (id <= s)) ) {
		_nl += 1;
		_p *= q;
		sp = s;
		s += _p;
	};
	//if(_nl > nlMax) { ret = 1; goto fin; }
	*idr = s + q*(id-sp-1);
fin:
	*nl = _nl;
	return 0;
}
static int _getIdArbre(Portal portal,ob_tId id,ob_tId *idr,ob_tId *nl) {
	int ret;

	portal->nbCallArbre +=1;
	if(portal->nbCallArbre > testCtx->q) return 1;

	ret = _getIdArbreInt(id,idr,nl);
	if(*nl >testCtx->nlMax) return 1;
	//if(ret) return ret;
	*idr += portal->nbCallArbre;
	//printf("%lli->%lli\n",id,*idr);
	return 0;
}

static int _getIdFuseau(Portal portal,ob_tId id,ob_tId *idr,ob_tId *nl) {
	int ret;

	portal->nbCallArbre +=1;
	if(portal->nbCallArbre > testCtx->q) return 1;

	ret = _getIdArbreInt(id,idr,nl);

	if(*nl < testCtx->nlc) return 1;
	testCtx->nlc = *nl;

	if(*nl > (testCtx->nlMax)) return 1;
	if(*nl == testCtx->nlMax) {
		*idr +=1;
		portal->nbCallArbre = testCtx->q;
		// on next call will return DB_NOTFOUND
	} else
		*idr += portal->nbCallArbre;
	return 0;
}


