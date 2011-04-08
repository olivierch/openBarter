/* $Id: test_chemin.c 22 2010-01-15 16:00:22Z olivier.chaussavoine $ */

#include <point.h>
//#include <ut.h>
#include <flux.h>
#include <dbe.h>
#include <tests.h>
#include <chemin.h>
#include <iternoeud.h>

//ob_tGlobal global;
#define PATH_TEST "/tmp/test"
#define PATHDBTEMP "/tmp/test/tmp"

typedef struct ob__Stocktest {
	ob_tId	own;
	ob_tId	nF;
	ob_tQtt	qtt;
} ob_tStocktest;
#define OB_STOCK_NULL {0,0}

typedef struct ob__Interdittest {
	ob_tId	Xoid;
	ob_tId	Yoid;
} ob_tInterdittest;
#define OB_INTERDIT_NULL {0,0}

typedef struct ob__Noeudtest {
	ob_tId	stockId;
	ob_tId	nR;
	double	omega;
} ob_tNoeudtest;
#define OB_NOEUD_NULL {0,0,0.}

typedef struct ob__Restest {
	ob_tId	oid;
	ob_tQtt	qtt;
} ob_tRestest;
#define OB_RES_NULL {0,0}

// a chemin envelope
typedef struct ob__CheminEnv {
	ob_tChemin chemin;
	ob_tNo	__no[obCMAXCYCLE];
} ob_tCheminEnv;


DB_ENV *environnement;

ob_tPortal ob_iternoeud_GetPortal(DB_ENV *envt, ob_tId Yoid,ob_tId nR) {
	ob_tPortal port;
	ob_tPrivate *priv = environnement->app_private; 
	int ret;
	/* cursor for iteration on offres for a given moY.offre.nR */
	
	port = malloc(sizeof(ob_cPortal));
	if(port == NULL) {
		obMTRACE(ob_chemin_CerMalloc);
		return NULL;
	}
	memset(port,0,sizeof(ob_cPortal));
	
	ret = priv->vy_offres->cursor(priv->vy_offres,NULL,&port->dbc,0);
	if(ret) {obMTRACE(ret); goto fin;}
	
	port->begin = true;
	port->envt = envt;
	
	port->Yoid = Yoid;
	port->nR = nR;
	
	port->ks_nR.size = sizeof(ob_tId);
	port->ks_nR.data = &port->nR;
	
	port->ku_Xoid.size = sizeof(ob_tId);
	port->ku_Xoid.ulen = sizeof(ob_tId);
	port->ku_Xoid.flags = DB_DBT_USERMEM;
	
	port->du_offreX.size = sizeof(ob_tNoeud);
	port->du_offreX.ulen = sizeof(ob_tNoeud);
	port->du_offreX.flags = DB_DBT_USERMEM;
	
	return port;
fin:
	free(port);
	return NULL;
}
int ob_iternoeud_Next(ob_tPortal port,ob_tId *Xoid,ob_tNoeud *offreX) {
	DBC *dbc = port->dbc;
	int ret = 0,ret_t;
	u_int32_t flags;
	bool refuse = true;
	
	if(port == NULL) return ob_chemin_CerMalloc;
	
	port->ku_Xoid.data = Xoid;
	port->du_offreX.data = offreX;
	
	while(ret == 0 && refuse) {
		flags = (port->begin)?DB_SET:DB_NEXT_DUP;
		port->begin = false;
			
		ret = dbc->pget(dbc,&port->ks_nR,&port->ku_Xoid,&port->du_offreX,flags);
		if(ret) {
			if(ret!= DB_NOTFOUND) obMTRACE(ret);
			goto fin;
		}
		//printf("fleche %lli->%lli lue\n",*Xoid,port->Yoid);
		
		ret = ob_point_pas_accepte(environnement,port->envt,NULL,Xoid,&port->Yoid,&refuse);
		if(ret) goto fin;
		//if(refuse) printf("refuséé\n");
	}
fin:
	if(ret != 0) {
		if(dbc) {
			ret_t = dbc->close(dbc);
			if(ret_t) obMTRACE(ret_t);
		}
		free(port);
	}
	return ret;
}
int ob_makeEnvDir(char *direnv)
{
	return -1;
}

int ob_iternoeud_put_stocktemp2(DB_ENV *envt, ob_tStock *pstock) {
	int ret;

	ob_tPrivate *priv = environnement->app_private;
	ob_tPrivateTemp *privt = envt->app_private;

	obMDbtpS(ks_sid, &pstock->sid);
	obMDbtpU(du_stock, pstock);

	if(pstock->sid != 0) {
		ret = priv->stocks->get(priv->stocks, NULL,
				&ks_sid, &du_stock, 0);
		if (ret) { obMTRACE(ret); goto fin; }

		if (privt->versionSg <pstock->version) {
			privt->versionSg = pstock->version;
		}
	}
	ret = privt->stocktemps->put(privt->stocktemps, 0,
			&ks_sid, &du_stock, 0);
	if (ret) { obMTRACE(ret); goto fin; }

fin:
	return ret;
}

static void voirAccords(ob_tAccord *accords,int nbAcc);
/*****************************************************************************/
static int tailleNoeuds(ob_tNoeudtest *noeuds) {
	int j = 0;
	ob_tNoeudtest *pnoeud=noeuds;
	while(!((pnoeud->stockId==0) && (pnoeud->nR==0) && (pnoeud->omega==0.))) {
		pnoeud++; j++;
	}
	return j;
}
// env is opened
// oid between 1 and _len
static int insertNoeuds(svn_error_t **perr,ob_tPrivate *priv,DB_TXN * txn,ob_tNoeudtest *nt,ob_tNoeud *pivot) {
	int i,_ret,_oid,_len;
	ob_tStock stock;
	ob_tNoeud noeud;
	ob_tNoeudtest *_pnt;

	_len = tailleNoeuds(nt);
	obMRange(i,_len) {
		_pnt = &nt[i];
		_oid = i+1;
		if((_oid >_len) || (_oid<=0)){
			MAKE_ERROR("sid not in [1,_len]",perr);
			_ret = -1;
			goto fin;
		}
		// noeud
		memset(&noeud,0,sizeof(noeud));
		noeud.oid = _oid;
		noeud.stockId = _pnt->stockId;
		noeud.omega = _pnt->omega;
		noeud.nR = _pnt->nR;

		obMDbtS(ks_sid,noeud.stockId);
		obMDbtU(du_stock,stock);
		_ret = priv->stocks->get(priv->stocks,txn,&ks_sid,&du_stock,0);
		if(_ret) { obMTRACE(_ret);
			MAKE_ERROR("could not read stock",perr); goto fin; }
		noeud.nF = stock.nF;
		noeud.own = stock.own;

		//ob_point_voirNoeud(&noeud);

		if(i==0) {
			memcpy(pivot,&noeud,sizeof(ob_tNoeud));
			//ob_point_voirNoeud(pivot);
		} else {
			obMDbtS(ks_oid,noeud.oid);
			obMDbtS(ds_noeud,noeud);
			_ret = priv->offres->put(priv->offres,txn,&ks_oid,&ds_noeud,0);
			if(_ret) { obMTRACE(_ret);
				MAKE_ERROR("could not write",perr); goto fin; }
		}

	}
fin:
	return _ret;
}

/*****************************************************************************/
static int tailleStocks(ob_tStocktest *stocks) {
	int j = 0;
	ob_tStocktest *pstock=stocks;
	while(!((pstock->own==0) && (pstock->nF==0) && (pstock->qtt==0))) {
		pstock++; j++;
	}
	return j;
}
// env is opened
// sid between 1 and _len
static int insertStocks(svn_error_t **perr,ob_tPrivate *priv,DB_TXN * txn,ob_tStocktest *st) {

	int _i,_ret,_sid,_len;
	ob_tStock stock;
	ob_tStocktest *_pst;

	_len = tailleStocks(st);
	obMRange(_i,_len) {
		_sid = _i+1;
		_pst = &st[_i];
		if((_sid >_len) || (_sid<=0)){
			MAKE_ERROR("sid not in [1,_len]",perr);
			_ret = -1;
			goto fin;
		}

		// stock
		memset(&stock,0,sizeof(stock));
		stock.sid = (int64) _sid;
		//voirDBT(&stock.sid);
		stock.own = _pst->own;
		stock.sid = _sid;
		//voirDBT(&stock.sid);
		stock.own = _pst->own;
		stock.qtt = _pst->qtt;
		stock.nF = _pst->nF;
		stock.version = 0;
		//ob_point_voirStock(&stock);
		obMDbtS(ks_sid,stock.sid);
		obMDbtS(ds_stock,stock);
		_ret = priv->stocks->put(priv->stocks,txn,&ks_sid,&ds_stock,0);
		if(_ret) {obMTRACE(_ret);
			MAKE_ERROR("could not write",perr); goto fin;}
	}
	fin: return _ret;
}
/*****************************************************************************/
static int tailleInterdits(ob_tInterdittest *interdits) {
	int j = 0;
	ob_tInterdittest *pinterdit = interdits;
	while (!((pinterdit->Xoid == 0) && (pinterdit->Yoid == 0))) {
		pinterdit++;
		j++;
	}
	return j;
}
static int insertInterdits(svn_error_t **perr, ob_tPrivate *priv, DB_TXN * txn,
		ob_tInterdittest *it) {

	int _i, _ret = 0, _len;
	ob_tInterdit interdit;

	_len = tailleInterdits(it);
	obMRange(_i,_len) {
		// interdit
		memset(&interdit,0,sizeof(interdit));
		interdit.rid.Xoid = it[_i].Xoid;
		interdit.rid.Yoid = it[_i].Yoid;

		obMDbtS(ks_iid,interdit.rid);
		obMDbtS(ds_interdit,interdit);
		//ob_point_voirInterdit(&interdit);

		_ret = priv->interdits->put(priv->interdits,txn,&ks_iid,&ds_interdit,0);
		//printf("insertion interdit ret=%i\n",_ret);
		if(_ret) {obMTRACE(_ret);
			MAKE_ERROR("could not write",perr); goto fin;}
	}
	fin: return _ret;
}
/*****************************************************************************
 * Verifies accords produced and expected (stored in results) are identical
 * returns 1 if yes
 * TODO: the order of oid is not checked
 ****************************************************************************/
static int accordsAttendus(svn_error_t **perr, ob_tAccord *accords, int nbAcc,
		ob_tRestest *results) {
	ob_tRestest *prDebut, *pr = results;
	ob_tChemin *pchemin;
	ob_tNoeud *_pn;
	ob_tId oidAtt;
	int _ia, _i, _j, _lon;
	ob_tQtt _qtt;

	_ia = 0;
	while (!((pr->oid == 0) && (pr->qtt == 0))) {
		prDebut = pr;
		if (_ia >= nbAcc)
			goto fin;

		oidAtt =  pr->oid;

		pchemin = &accords[_ia].chemin;
		//ob_flux_voirChemin(stdout,pchemin,0);
		_lon = ob_flux_cheminGetNbNode(pchemin);
		obMRange(_j,_lon) {
			_pn = ob_flux_cheminGetAdrNoeud(pchemin,_j);
			// the node is found
			if(_pn->oid == oidAtt) break;
		}
		if (_j == _lon)
			goto fin; // was not found

		while (!((pr->oid == 0) && (pr->qtt == 0))) {
			oidAtt = pr->oid;
			_i = _j % _lon;
			_pn = ob_flux_cheminGetAdrNoeud(pchemin, _i);
			if (_pn->oid != oidAtt)
				goto fin; // not equal
			_qtt = ob_flux_cheminGetQtt(pchemin, _i);
			if (_qtt != pr->qtt)
				goto fin; // not equal
			pr++;
			_j++;
		}
		pr++;
		_ia++;
	}
	// equal number of agreements expected and produced
	if (_ia != nbAcc)
		goto fin;
	return 0;
fin: 
	if ((_ia == 1) && (nbAcc == 0))
		return 0;
	MAKE_ERROR("accords different", perr);
	voirAccords(accords, nbAcc);
	return 1;
}

static void voirAccords(ob_tAccord *accords, int nbAcc) {
	int _ia;
	ob_tChemin *pchemin;

	if (!nbAcc)
		printf("pas d'accords obtenus\n");
obMRange(_ia,nbAcc) {
	pchemin = &accords[_ia].chemin;
	ob_flux_voirChemin(stdout,pchemin,0);
}
}

static int ouverture_tmp(char *pathdb, char *pathdbtemp) {
	int ret;
	ret = ob_dbe_dircreate(pathdb);
	if (ret)
		return ret;
	ret = ob_dbe_dircreate(pathdbtemp);
	return ret;
}

static int test_flux(perr, stocks, noeuds, results, flags, interdits,
		pnbAccord, paccords)
	svn_error_t **perr;ob_tStocktest *stocks;ob_tNoeudtest *noeuds;ob_tRestest
			*results;ob_tInterdittest *interdits;int flags;int *pnbAccord;ob_tAccord
			**paccords; {
	ob_tCheminEnv envchemin;
	ob_tChemin *pchem;
	ob_tPrivate *priv;
	int _i = 0, _nid = 0, _sid;
	bool _flux_nul;
	int ret = 0, ret_t;
	// ob_tAccord *paccords = NULL;
	ob_tPoint *point;
	DB_TXN *txn = NULL;
	DB_ENV *env;
	ob_tNoeud pivot;
	ob_tId versionSg, oid;
	int _nbAccord;
	ob_tAccord *_accords = NULL;

	ret = ouverture_tmp(PATH_TEST, PATHDBTEMP);
	if (ret) {
		MAKE_ERROR("error at opening", perr);
		return;
	}

	//ret = ob_dbe_ouverture(PATH_TEST);
	//if(ret) { MAKE_ERROR("error at opening",perr); return; }
	/*
	 ret = ob_dbe_openEnvDurable(DB_CREATE,PATH_TEST,&env);
	 if(ret) { MAKE_ERROR("opening sustainable database",perr); goto fin; }
	 priv = (ob_tPrivate *) env->app_private;

	 ret = ob_dbe_clearBases(priv);
	 if(ret) { MAKE_ERROR("clearing sustainable database",perr); goto fin; }
	 */
	ret = ob_dbe_openEnvDurable(DB_INIT_MPOOL | DB_CREATE, PATH_TEST, &env);
	if (ret) {
		MAKE_ERROR("error at opening sustainable env with DB_CREATE", perr);
		goto fin;
	}
	environnement = env;
	ret = ob_dbe_createBasesDurable(env);
	if (ret) {
		MAKE_ERROR("error at creating sustainable database", perr);
		goto fin;
	}
	ret = ob_dbe_openBasesDurable(env, NULL, DB_CREATE);
	if (ret) {
		MAKE_ERROR("error at opening sustainable database", perr);
		goto fin;
	}
	ret = ob_dbe_clearBases(env);
	if (ret) {
		MAKE_ERROR("error at clearing sustainable database", perr);
		goto fin;
	}
	priv = (ob_tPrivate *) env->app_private;

	ret = insertStocks(perr, priv, txn, stocks);
	if (ret) {
		MAKE_ERROR("set stocks pb", perr);
		goto fin;
	}
	ret = insertNoeuds(perr, priv, txn, noeuds, &pivot);
	if (ret) {
		MAKE_ERROR("set stocks pb", perr);
		goto fin;
	}
	if (interdits) {
		ret = insertInterdits(perr, priv, txn, interdits);
		if (ret) {
			MAKE_ERROR("set interdits pb", perr);
			goto fin;
		}
	}
	if (flags & 1) {
		pivot.stockId = 0;
	}
	//printf("faire_accords\n");
	if (pnbAccord != NULL) {
		ret = ob_chemin_faire_accords(env, NULL,PATHDBTEMP, &versionSg, &pivot,
				pnbAccord, paccords);
		//printf("ret=%i\n",ret);
		if (flags & 2)
			if (ret)
				goto fin;

		// printf("nbAccord=%i\n",nbAccord);
		// if(nbAccord) ob_flux_voirChemin(stdout,&paccords[0].chemin,0);
		if (ret) {
			MAKE_ERROR("faire_accords", perr);
			goto fin;
		}
		ret = accordsAttendus(perr, *paccords, *pnbAccord, results);
		if (ret) {
			MAKE_ERROR("accords incorrects", perr);
			goto fin;
		}
	} else {
		ret = ob_chemin_faire_accords(env, NULL, PATHDBTEMP, &versionSg, &pivot,
				&_nbAccord, &_accords);
		if (ret) {
			MAKE_ERROR("faire_accords", perr);
			goto fin;
		}
		ret = accordsAttendus(perr, _accords, _nbAccord, results);
		if (ret) {
			MAKE_ERROR("accords incorrects", perr);
			goto fin;
		}
	}

	fin:
	//printf("retour B %i\n",ret);
	//MAKE_ERROR("pour voir",perr);
	//if (paccords) free(paccords);
	if (_accords)
		free(_accords);

	if (env != NULL) {
		ret_t = ob_dbe_closeBasesDurable(env);
		if (ret_t) {
			MAKE_ERROR("error at closing sustainable database", perr);
		}
		ret_t = ob_dbe_closeEnvDurable(env);
		if (ret_t) {
			MAKE_ERROR("error at closing sustainable env", perr);
		}
	}

	// ret_t = ob_dbe_closeEnvDurable(env);
	//printf("retour C %i\n",ret);
	//if(ret_t)  MAKE_ERROR("error at closing sustainable database",perr);
	/*ret_t = ob_dbe_fermeture();
	 if(ret_t)  MAKE_ERROR("error at closing",perr);*/
	return ret;

}
static svn_error_t *
test1(const char **msg, bool msg_only, svn_test_opts_t *opts) {
	svn_error_t *err = SVN_NO_ERROR;
	*msg = "boucle a trois";
	if (msg_only)
		return err;

	/* begin of test */
	ob_tStocktest stocks[] = { { 1, 1, 5 }, { 2, 2, 10 }, { 3, 3, 5 },
			OB_STOCK_NULL };
	ob_tNoeudtest noeuds[] = { { 1, 3, 2. }, { 2, 1, 2. }, { 3, 2, 2. },
			OB_NOEUD_NULL };
	ob_tRestest results[] = {  { 2, 5 }, { 3, 5 }, { 1, 5 },OB_RES_NULL,
			OB_RES_NULL };
	int ret;

	test_flux(&err, stocks, noeuds, results, 0, NULL, NULL, NULL);
	return err;
}

static svn_error_t *
test2(const char **msg, bool msg_only, svn_test_opts_t *opts) {
	svn_error_t *err = SVN_NO_ERROR;
	*msg = "boucle a 7";
	if (msg_only)
		return err;

	/* begin of test */
	ob_tStocktest stocks[] = { { 1, 1, 5 }, { 2, 2, 10 }, { 3, 3, 5 }, { 4, 4,
			5 }, { 5, 5, 10 }, { 6, 6, 5 }, { 7, 7, 5 }, OB_STOCK_NULL };
	ob_tNoeudtest noeuds[] = { { 1, 7, 2. }, { 2, 1, 2. }, { 3, 2, 2. }, { 4,
			3, 2. }, { 5, 4, 2. }, { 6, 5, 2. }, { 7, 6, 2. }, OB_NOEUD_NULL };
	ob_tRestest results[] = { { 1, 5 }, { 2, 5 }, { 3, 5 }, { 4, 5 }, { 5, 5 },
			{ 6, 5 }, { 7, 5 }, OB_RES_NULL, OB_RES_NULL };
	int ret;

	test_flux(&err, stocks, noeuds, results, 0, NULL, NULL, NULL);
	return err;
}

static svn_error_t *
test3(const char **msg, bool msg_only, svn_test_opts_t *opts) {
	svn_error_t *err = SVN_NO_ERROR;
	*msg = "boucle a 8";
	if (msg_only)
		return err;

	/* begin of test */
	ob_tStocktest stocks[] = { { 1, 1, 5 }, { 2, 2, 10 }, { 3, 3, 5 }, { 4, 4,
			5 }, { 5, 5, 10 }, { 6, 6, 5 }, { 7, 7, 5 }, { 8, 8, 6 },
			OB_STOCK_NULL };
	ob_tNoeudtest noeuds[] = { { 1, 8, 2. }, { 2, 1, 2. }, { 3, 2, 2. }, { 4,
			3, 2. }, { 5, 4, 2. }, { 6, 5, 2. }, { 7, 6, 2. }, { 8, 7, 2. },
			OB_NOEUD_NULL };
	ob_tRestest results[] = { { 1, 5 }, { 2, 5 }, { 3, 5 }, { 4, 5 }, { 5, 5 },
			{ 6, 5 }, { 7, 5 }, { 8, 5 }, OB_RES_NULL, OB_RES_NULL };
	int ret;

	test_flux(&err, stocks, noeuds, results, 0, NULL, NULL, NULL);
	return err;
}

static svn_error_t *
test4(const char **msg, bool msg_only, svn_test_opts_t *opts) {
	svn_error_t *err = SVN_NO_ERROR;
	*msg = "boucle a 9: pas d'accord";
	if (msg_only)
		return err;

	/* begin of test */
	ob_tStocktest stocks[] = { { 1, 1, 5 }, { 2, 2, 10 }, { 3, 3, 5 }, { 4, 4,
			5 }, { 5, 5, 10 }, { 6, 6, 5 }, { 7, 7, 5 }, { 8, 8, 5 },
			{ 9, 9, 5 }, OB_STOCK_NULL };
	ob_tNoeudtest noeuds[] = { { 1, 9, 2. }, { 2, 1, 2. }, { 3, 2, 2. }, { 4,
			3, 2. }, { 5, 4, 2. }, { 6, 5, 2. }, { 7, 6, 2. }, { 8, 7, 2. }, {
			9, 8, 2. }, OB_NOEUD_NULL };
	ob_tRestest results[] = { OB_RES_NULL, OB_RES_NULL };
	int ret;

	test_flux(&err, stocks, noeuds, results, 0, NULL, NULL, NULL);
	return err;
}

static svn_error_t *
test5(const char **msg, bool msg_only, svn_test_opts_t *opts) {
	svn_error_t *err = SVN_NO_ERROR;
	*msg = "boucle a deux";
	if (msg_only)
		return err;

	/* begin of test */
	ob_tStocktest stocks[] = { { 1, 1, 5 }, { 2, 2, 10 }, { 3, 3, 5 }, { 4, 4,
			5 }, OB_STOCK_NULL };
	ob_tNoeudtest noeuds[] = { { 1, 2, 2. }, { 2, 1, 2. }, OB_NOEUD_NULL };
	ob_tRestest results[] = { { 1, 5 }, { 2, 5 }, OB_RES_NULL, OB_RES_NULL };
	int ret;

	test_flux(&err, stocks, noeuds, results, 0, NULL, NULL, NULL);
	return err;
}

static svn_error_t *
test6(const char **msg, bool msg_only, svn_test_opts_t *opts) {
	svn_error_t *err = SVN_NO_ERROR;
	*msg = "deux boucles en concurrence";
	if (msg_only)
		return err;

	/* begin of test */
	ob_tStocktest stocks[] = { // own,nF,qtt
			{ 1, 1, 50 }, { 2, 2, 10 }, { 3, 3, 5 }, { 4, 3, 10 },
					OB_STOCK_NULL };
	ob_tNoeudtest noeuds[] = { //stockId,nR,omega
			{ 1, 3, 2. }, { 2, 1, 1. }, { 3, 2, 0.5 }, { 4, 1, 2. },
					OB_NOEUD_NULL };
	ob_tRestest results[] = { { 1, 10 }, { 4, 10 }, OB_RES_NULL, { 1, 10 }, {
			2, 10 }, { 3, 5 }, OB_RES_NULL, OB_RES_NULL };
	int ret;

	test_flux(&err, stocks, noeuds, results, 0, NULL, NULL, NULL);
	return err;
}

static svn_error_t *
test7(const char **msg, bool msg_only, svn_test_opts_t *opts) {
	svn_error_t *err = SVN_NO_ERROR;
	*msg = "boucles a deux";
	if (msg_only)
		return err;

	/* begin of test */
	ob_tStocktest stocks[] = { { 1, 1, 5 }, { 2, 2, 10 }, { 3, 3, 5 }, { 4, 4,
			5 }, OB_STOCK_NULL };
	ob_tNoeudtest noeuds[] = { { 1, 2, 2. }, { 2, 1, 2. }, OB_NOEUD_NULL };
	ob_tRestest results[] = { { 1, 5 }, { 2, 5 }, OB_RES_NULL, OB_RES_NULL };
	int ret;

	test_flux(&err, stocks, noeuds, results, 0, NULL, NULL, NULL);
	return err;
}

static svn_error_t *
test8(const char **msg, bool msg_only, svn_test_opts_t *opts) {
	svn_error_t *err = SVN_NO_ERROR;
	*msg = "deux boucles en concurrence sans depos d'offre";
	if (msg_only)
		return err;

  /* begin of test */
  ob_tStocktest stocks[] = { // own,nF,qtt
	  {1,1,50},{2,2,10},{3,3,5},{4,3,10},OB_STOCK_NULL};
  ob_tNoeudtest noeuds[] = { //stockId,nR,omega
	  {1,3,2.},{2,1,1.},{3,2,0.5},{4,1,2.},
	  OB_NOEUD_NULL};
  ob_tRestest   results[] = {
	  {1,10},{4,10},OB_RES_NULL,
	  {1,10},{2,10},{3,5},OB_RES_NULL,
	  OB_RES_NULL};
  int ret;

  test_flux(&err,stocks,noeuds,results,1,NULL,NULL,NULL);
  return err;
}

static svn_error_t *
test9(const char **msg,bool msg_only, svn_test_opts_t *opts)
{
	svn_error_t *err=SVN_NO_ERROR;
	*msg = "deux boucles en concurrence avec interdit";
  if (msg_only)
    return err;

  /* begin of test */
  ob_tStocktest stocks[] = { // own,nF,qtt
	  {1,1,50},{2,2,10},{3,3,5},{4,3,10},OB_STOCK_NULL};
  ob_tNoeudtest noeuds[] = { //stockId,nR,omega
	  {1,3,2.},{2,1,1.},{3,2,0.5},{4,1,2.},
	  OB_NOEUD_NULL};
  ob_tInterdittest interdits[] = { // Xoid,Yoid
	  {4,1},OB_INTERDIT_NULL};
  ob_tRestest   results[] = {
	  //{1,10},{4,10},OB_RES_NULL, it is forbidden
	  {1,10},{2,10},{3,5},OB_RES_NULL,
	  OB_RES_NULL};
  int ret,nbAccord;
  ob_tAccord *accords=NULL;

  test_flux(&err,stocks,noeuds,results,1,interdits,&nbAccord,&accords);
  if(accords) free(accords);
  return err;
}

static svn_error_t *
test10(const char **msg,bool msg_only, svn_test_opts_t *opts)
{
	svn_error_t *err=SVN_NO_ERROR;
	*msg = "insertion d'interdit sur boucle inattendue";
  if (msg_only)
    return err;

  /* begin of test */
  ob_tStocktest stocks[] = { // own,nF,qtt
  	{1,1,5},{2,2,10},{3,3,5},{4,2,100},OB_STOCK_NULL};
  ob_tNoeudtest noeuds[] = { //stockId,nR,omega
  	{1,3,2.},{2,1,2.},{3,2,2.},
	{4,3,4.}, // cycle s3<->s4
	OB_NOEUD_NULL};
  ob_tInterdittest interdits[] = { // Xoid,Yoid
	  OB_INTERDIT_NULL};
  ob_tRestest   results[] = {{1,5},{2,5},{3,5},OB_RES_NULL,OB_RES_NULL};
  int ret,nbAccord;
  ob_tAccord *accords = NULL;
  ob_tLoop *loop;
  ob_tId oid;

  ret = test_flux(&err,stocks,noeuds,results,2,interdits,&nbAccord,&accords);
  if(ret!=ob_chemin_CerLoopOnOffer) {
	  printf("%i!=%i\n",ret,ob_chemin_CerLoopOnOffer);
	  MAKE_ERROR("should have provide the error CerLoopOnOffer",&err);
  } else {
		loop = (ob_tLoop *) &accords[nbAccord-1];
		oid = 4;
		if(loop->rid.Xoid != oid)
			MAKE_ERROR("an oid should be found",&err);
	}
  if(accords) free(accords);
  return err;
}


/* ========================================================================== */

struct svn_test_descriptor_t test_funcs[] =
  {
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
    SVN_TEST_NULL
  };
