
#include <point.h>
#include <flux.h>
#include <tests.h>

typedef struct ob__Stocktest {
	ob_tId own;
	ob_tQtt qtt;
} ob_tStocktest;
#define OB_STOCK_NULL {0,0}

typedef struct ob__Noeudtest {
	ob_tId stockId;
	double omega;
} ob_tNoeudtest;
#define OB_NOEUD_NULL {0,0.}

// a chemin envelope
typedef struct ob__CheminEnv {
	ob_tChemin chemin;
	ob_tNo __no[obCMAXCYCLE];
} ob_tCheminEnv;

void
elog_start(const char *filename, int lineno, const char *funcname)
{
}

void
elog_finish(int elevel, const char *fmt,...)
{
	fprintf(stderr, "ERROR: %s\n", fmt);
	exit(1);
}

static int taille(ob_tNoeudtest *noeuds) {
	int j = 0;
	ob_tNoeudtest *pnoeud = noeuds;
	while (!((pnoeud->stockId == 0) && (pnoeud->omega == 0.))) {
		pnoeud++;
		j++;
	}
	//j -=1;
	// printf("taille %i\n",j);
	return j;
}
static void voirStock(ob_tStock *ps) {
	printf("Stock :");
	ob_flux_MVoirDBT(&ps->sid);
	printf("\tnF ");
	ob_flux_MVoirDBT(&ps->nF);
	printf("\tqtt %lli\n", ps->qtt);
	printf("\town ");
	ob_flux_MVoirDBT(&ps->own);
	return;
}
static void voirNoeud(ob_tNoeud *pn) {
	printf("Noeud:");
	ob_flux_MVoirDBT(&pn->oid);
	printf("\tsid ");
	ob_flux_MVoirDBT(&pn->stockId);
	printf("\tnR ");
	ob_flux_MVoirDBT(&pn->nR);
	printf("\tnF ");
	ob_flux_MVoirDBT(&pn->nF);
	printf("\tomega %f\n", pn->omega);
	printf("\town ");
	ob_flux_MVoirDBT(&pn->own);
	return;
}
static void setStockNoeud(svn_error_t **perr, ob_tStocktest *st,
		ob_tNoeudtest *nt, ob_tStock **s, ob_tNoeud **n, int *len) {
	int _len, i, j, _sid, _nF, _nR;
	ob_tStock *_s, *_ps;
	ob_tNoeud *_n, *_pn;
	ob_tStocktest *_pst;
	ob_tNoeudtest *_pnt;

	_len = taille(nt);
	_s = calloc((size_t) _len, sizeof(ob_tStock));
	_n = calloc((size_t) _len, sizeof(ob_tNoeud));

	obMRange(i,_len) {
		_pnt = &nt[i];
		_sid = _pnt->stockId;
		if(_sid >=_len) {
			_sid %= _len;
			MAKE_ERROR("_sid >=_len",perr);
		}
		_pst = &st[_sid];
		_pn = &_n[i];
		_ps = &_s[_sid];
		_nF = _sid;_nF +=1;
		// stock
		_ps->sid = (int64) _sid;
		//voirDBT(&_ps->sid);
		_ps->own = _pst->own;
		_ps->qtt =  _pst->qtt;
		_ps->nF = (int64) _nF;

		// noeud
		_pn->oid = (int64) i;
		_pn->stockId = _ps->sid;
		_pn->omega = _pnt->omega;
		_pn->nR = 0;
		// _pn->nR = _nR;
		_pn->nF = _ps->nF;
		_pn->own = _ps->own;
	}
	obMRange(i,_len) {
		j = (i-1) %_len;
		if(j<0) j +=_len;
		_n[i].nR = _n[j].nF;
	} /*
	 obMRange(i,_len) {
	 voirStock(&_s[i]);
	 voirNoeud(&_n[i]);
	 }*/
	*s = _s;
	*n = _n;
	*len = _len;
	return;
}

static void freeStockNoeud(ob_tStock *s, ob_tNoeud *n) {
	if (s)
		free(s);
	if (n)
		free(n);
	return;
}

static svn_error_t * test_flux(stocks, noeuds, fluxArrondi, flags)
	ob_tStocktest *stocks;ob_tNoeudtest *noeuds;ob_tQtt *fluxArrondi;int flags; {
	ob_tCheminEnv envchemin;
	ob_tChemin *pchem;
	int _i = 0, _nid = 0, _sid;
	bool _flux_nul;
	int _ret = 0;
	svn_error_t *err = SVN_NO_ERROR;
	char buf[128];
	//ob_tBoucle boucle;
	int _len;
	ob_tStock *_stocks;
	ob_tNoeud *_noeuds;

	pchem = &envchemin.chemin;

	setStockNoeud(&err, stocks, noeuds, &_stocks, &_noeuds, &_len);
	// printf("de test flags=%x\n",flags);
	ob_flux_cheminVider(pchem, flags);
	// printf("len %i\n",_len);
	_nid = 0;
	while ((_nid < _len) && (_ret == 0)) {
		_sid = noeuds[_nid].stockId;
		// c'est un ut_DBT!!!
		// printf("_nid %i _sid %i\n",_nid,_sid);
		_ret
				= ob_flux_cheminAjouterNoeud(pchem, &_stocks[_sid],
						&_noeuds[_nid]);
		if (_ret) {
			MAKE_ERROR("incoherent chemin 0", &err);
		}
		// printf("_nid %i _sid %i _ret %i\n",_nid,_sid,_ret);
		_nid += 1;
	}
	freeStockNoeud(_stocks, _noeuds);
	_len = ob_flux_cheminGetNbNode(pchem);
	// printf("_len %i\n",_len);
	_ret = ob_flux_cheminError(pchem);
	if (_ret) {
		MAKE_ERROR("incoherent chemin 1", &err);
	}
	// ob_flux_voirChemin(stdout,pchem,0);

	_ret = ob_flux_fluxMaximum(pchem);
	if (_ret != 1) {
		MAKE_ERROR("flow null or error", &err);
	}

	_ret = ob_flux_cheminError(pchem);
	if (_ret) {
		MAKE_ERROR("incoherent chemin 2", &err);
		goto fin;
	}

	_len = ob_flux_cheminGetNbNode(pchem);
	obMRange(_i,_len)
	if (pchem->no[_i].fluxArrondi!=fluxArrondi[_i]) {
		sprintf(buf,"indice %5i: %lli != %lli\n",_i,pchem->no[_i].fluxArrondi,fluxArrondi[_i]);
		MAKE_ERROR(buf,&err);
	}
	fin: if (err) {
		ob_flux_voirChemin(stdout,pchem,0);
		printf("attendu: ");
		_len = ob_flux_cheminGetNbNode(pchem);
		obMRange(_i,_len)
		printf("%lli ",fluxArrondi[_i]);
		printf("\n");
	}
	//handle_error(err, stdout, "ob_tests: ");
	return err;
}

static svn_error_t *
test1(const char **msg, bool msg_only, svn_test_opts_t *opts) {
	*msg = "chemin 1: boucle 3 noeuds, 3 stocks, 3 owners";
	if (msg_only)
		return SVN_NO_ERROR;
	ob_tStocktest stocks[] = { { 1, 20 }, { 2, 80 }, { 3, 120 } };
	ob_tNoeudtest noeuds[] = { { 0, 1.0 }, { 1, 8.0 }, { 2, 1.0 },
			OB_NOEUD_NULL };
	ob_tQtt fluxArrondi[] = { 20, 80, 40 };
	//	printf("st->%i,->%f\n",noeuds->stockId,noeuds->omega);
	return test_flux(stocks, noeuds, fluxArrondi, 0);
}

static svn_error_t *
test1_A(const char **msg, bool msg_only, svn_test_opts_t *opts) {
	*msg = "chemin 2: tous stocks épuisés";
	if (msg_only)
		return SVN_NO_ERROR;
	ob_tStocktest stocks[] = { { 1, 20 }, { 2, 80 }, { 3, 40 } };
	ob_tNoeudtest noeuds[] = { { 0, 1.0 }, { 1, 8.0 }, { 2, 1.0 },
			OB_NOEUD_NULL };
	ob_tQtt fluxArrondi[] = { 20, 80, 40 };

	return test_flux(stocks, noeuds, fluxArrondi, 0);
}

static svn_error_t *
test1_B(const char **msg, bool msg_only, svn_test_opts_t *opts) {
	*msg = "chemin 3: avec obCLastIgnore";
	if (msg_only)
		return SVN_NO_ERROR;
	ob_tStocktest stocks[] = { { 1, 20 }, { 2, 80 }, { 3, 30 } };
	ob_tNoeudtest noeuds[] = { { 0, 1.0 }, { 1, 8.0 }, { 2, 1.0 },
			OB_NOEUD_NULL };
	ob_tQtt fluxArrondi[] = { 10, 80, 10 };
	return test_flux(stocks, noeuds, fluxArrondi, ob_flux_CLastIgnore);
}

static svn_error_t *
test2(const char **msg, bool msg_only, svn_test_opts_t *opts) {
	*msg = "chemin 4: boucle 3 noeuds, 3 stocks, 2 owners";
	if (msg_only)
		return SVN_NO_ERROR;
	ob_tStocktest stocks[] = { { 1, 40 }, { 2, 80 }, { 2, 120 } };
	ob_tNoeudtest noeuds[] = { { 0, 1.0 }, { 1, 16.0 }, { 2, 1.0 },
			OB_NOEUD_NULL };
	ob_tQtt fluxArrondi[] = { 10, 80, 40 };
	return test_flux(stocks, noeuds, fluxArrondi, 0);
}

static svn_error_t *
test3(const char **msg, bool msg_only, svn_test_opts_t *opts) {
	*msg = "chemin 5: boucle 2 noeuds, 2 stocks, 2 owners";
	if (msg_only)
		return SVN_NO_ERROR;
	ob_tStocktest stocks[] = { { 1, 20 }, { 2, 120 } };
	ob_tNoeudtest noeuds[] = { { 0, 2.0 }, { 1, 2.0 }, OB_NOEUD_NULL };
	ob_tQtt fluxArrondi[] = { 20, 20 };
	return test_flux(stocks, noeuds, fluxArrondi, 0);
}

static svn_error_t *
test4(const char **msg, bool msg_only, svn_test_opts_t *opts) {
	*msg = "chemin 6: boucle 4 noeuds, 3 stocks, 3 owners";
	if (msg_only)
		return SVN_NO_ERROR;
	ob_tStocktest stocks[] = { { 1, 240 }, { 2, 80 }, { 3, 120 } };
	ob_tNoeudtest noeuds[] = { { 0, 1.0 }, { 1, 1.0 }, { 0, 1.0 }, { 2, 1.0 },
			OB_NOEUD_NULL };
	ob_tQtt fluxArrondi[] = { 80, 80, 80, 80 };
	return test_flux(stocks, noeuds, fluxArrondi, 0);
}

static svn_error_t *
test5(const char **msg, bool msg_only, svn_test_opts_t *opts) {
	*msg = "chemin 7: boucle 4 noeuds, 3 stocks, 3 owners";
	if (msg_only)
		return SVN_NO_ERROR;
	ob_tStocktest stocks[] = { { 1, 240 }, { 2, 80 }, { 3, 120 } };
	ob_tNoeudtest noeuds[] = { { 0, 2.0 }, { 1, 4.0 }, { 0, 2.0 }, { 2, 4.0 },
			OB_NOEUD_NULL };
	ob_tQtt fluxArrondi[] = { 80, 80, 80, 80 };
	return test_flux(stocks, noeuds, fluxArrondi, 0);
}
/* ========================================================================== */

struct svn_test_descriptor_t test_funcs[] = { SVN_TEST_NULL, SVN_TEST_PASS(
		test1), SVN_TEST_PASS(test1_A), SVN_TEST_PASS(test1_B), SVN_TEST_PASS(
		test2), SVN_TEST_PASS(test3), SVN_TEST_PASS(test4),
		SVN_TEST_PASS(test5), SVN_TEST_NULL };
