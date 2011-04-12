/* $Id: dbe.c 22 2010-01-15 16:00:22Z olivier.chaussavoine $ */
/*
 openbarter - The maximum wealth for the lowest collective effort
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
#include <dbe.h>
#include "openbarter.h"
//#include <errno.h>
#include <sys/stat.h>
//#include <utils.h>

static int point_get_nX(DB *sdbp, const DBT *pkey, const DBT *pdata, DBT *skey);
static int point_get_nY(DB *sdbp, const DBT *pkey, const DBT *pdata, DBT *skey);
static int
		point_get_mar(DB *sdbp, const DBT *pkey, const DBT *pdata, DBT *skey);
static int
		point_get_mav(DB *sdbp, const DBT *pkey, const DBT *pdata, DBT *skey);
static int point_get_stockId(DB *sdbp, const DBT *pkey, const DBT *pdata,
		DBT *skey);
static int trait_get_Xoid(DB *sdbp, const DBT *pkey, const DBT *pdata,
		DBT *skey);
static int trait_get_Yoid(DB *sdbp, const DBT *pkey, const DBT *pdata,
		DBT *skey);
static int trait_get_marque(DB *sdbp, const DBT *pkey, const DBT *pdata,
		DBT *skey);

static void errcallback(const DB_ENV *dbenv, const char *errpfx,
		const char *msg);

static int openBasesTemp(DB_ENV *envt, u_int32_t flagsdb);
static int closeBasesTemp(ob_tPrivateTemp *privt);

/******************************************************************************
 directory creation
 ******************************************************************************/
int ob_dbe_dircreate(char * path) {
	struct stat sb;
	int ret = 0;

	/* * If the directory exists, we're done. We do not further check
	 * the type of the file, DB will fail appropriately if it's the
	 * wrong type. */
	if (stat(path, &sb) == 0)
		goto fin;

	/* Create the directory, read/write/access owner only. */
	if (mkdir(path, S_IRWXU) != 0) {
		fprintf(stderr, "obarter: mkdir: %s: %s\n", path, strerror(errno));
		ret = ob_dbe_CerDirErr;
	}
	fin: return (ret);
}


/*******************************************************************************
 * open temporary env, next tables
 * flagsdb,
 * 	unused
 * path_db,
 * 	a string, absolute path of the database
 * penvt,
 * 	(out) a pointer to the new environment
 *
 * return 0 or an error
 *******************************************************************************/

/*
static void *_palloc(Size size) {
	return palloc(size);
}
*/
int ob_dbe_openEnvTemp(DB_ENV **penvt) {
	int ret = 0, ret_t;
	DB_ENV *envt = NULL;
	u_int32_t _flagsdb, _flagsenv;
	ob_tPrivateTemp *privt;

	ret = ob_makeEnvDir(openbarter_g.pathEnv);
	if(ret) return(ob_dbe_CerDirErr);

	ret = db_env_create(&envt, 0);
	if (ret) {
		obMTRACE(ret);
		goto abort;
	}

	envt->set_errcall(envt, errcallback);
	envt->set_errpfx(envt, "envit");
	/* supprimé car on est outofscape lors des appels
	ret = envt->set_alloc(envt,_palloc,repalloc,pfree);
	if (ret) {
		obMTRACE(ret);
		goto abort;
	} */
	// the size of the in memory cache
	ret = envt->set_cachesize(envt, 0, ob_dbe_CCACHESIZETEMP, 1);
	if (ret) {
		obMTRACE(ret);
		goto abort;
	}

	_flagsenv = DB_CREATE | DB_INIT_MPOOL | DB_PRIVATE;
	// to activate TXN
	// _flagsenv |= DB_INIT_LOCK | DB_INIT_LOG | DB_INIT_TXN;

	ret = envt->open(envt, openbarter_g.pathEnv, _flagsenv, 0);
	if (ret) {
		obMTRACE(ret);
		goto abort;
	}

	privt = palloc(sizeof(ob_tPrivateTemp));
	if (!privt) {
		ret = ENOMEM;
		obMTRACE(ret);
		goto abort;
	}
	memset(privt, 0, sizeof(ob_tPrivateTemp));
	envt->app_private = privt;

	// DB_PRIVATE is not used to open db,
	// but to avoid the opening transaction
	_flagsdb = DB_CREATE | DB_PRIVATE | DB_TRUNCATE;
	// to activate  TXN
	// _flagsdb |= DB_AUTO_COMMIT;

	ret = openBasesTemp(envt, _flagsdb);
	if (ret)
		goto abort;

	*penvt = envt;
	return 0;

abort:
	if (envt != NULL) {
		ret_t = ob_dbe_closeEnvTemp(envt);
		if (!ret)
			ret = ret_t;
		*penvt = NULL;
	}
	return (ret);
}

/******************************************************************************
 close the temporary environment
 envt
 a pointer to the environment to be closed
 returns 0 or an error
 ******************************************************************************/
int ob_dbe_closeEnvTemp(DB_ENV *envt) {
	int ret = 0, ret_t;

	ob_tPrivateTemp *privt = envt->app_private;
	if (privt != NULL) {
		ret = closeBasesTemp(privt);
		pfree(privt);
		envt->app_private = NULL;
	}
	ret_t = envt->close(envt, 0);
	if (ret_t != 0 && ret == 0)
		ret = ret_t;
	// elog( ERROR,"Appel de ob_rmPath avec %s",openbarter_g.pathEnv );
	// ob_rmPath(openbarter_g.pathEnv,true);
	return ret;
}

static int open_db(DB_ENV *env, bool is_secondary, DB *db, char *name,

		DB_TXN *txn_e, // ne sert plus
		int size, DBTYPE type, u_int32_t flags, int(*bt_compare_fcn)(DB *db,
				const DBT *dbt1, const DBT *dbt2), int(*dup_compare_fcn)(
				DB *db, const DBT *dbt1, const DBT *dbt2)) {
	int ret, ret_t, _flags;
	//char strid[obCMAXBUF];
	char *pname = name;
	//DB_MPOOLFILE *mpf;
	DB_TXN *txn = NULL;
	u_int32_t flagsenv;

	if (bt_compare_fcn) {
		ret = db->set_bt_compare(db, bt_compare_fcn);
		if (ret) {
			obMTRACE(ret);
			goto err;
		}
	}
	if (dup_compare_fcn) {
		ret = db->set_dup_compare(db, dup_compare_fcn);
		if (ret) {
			obMTRACE(ret);
			goto err;
		}
	}

	if (is_secondary) {
		ret = db->set_flags(db, DB_DUPSORT);
		if (ret) {
			obMTRACE(ret);
			goto err;
		}
		_flags = flags & ~DB_TRUNCATE;
	} else
		_flags = flags;

	ret = env->get_open_flags(env, &flagsenv);
	if (ret) {
		obMTRACE(ret);
		goto err;
	}
	if (flagsenv & DB_INIT_TXN) {
		// start transaction
		ret = env->txn_begin(env, NULL, &txn, 0);
		if (ret != 0) {
			obMTRACE(ret);
			goto err;
		}
		ret = db->open(db, txn, pname, NULL, type, _flags, 0644);
		if (!ret) {
			ret = txn->commit(txn, 0);
			if (ret) {
				obMTRACE(ret);
				goto err;
			}
		} else {
			ret_t = txn->abort(txn);
			if (ret_t) {
				obMTRACE(ret_t);
				goto err;
			}
		}
	} else if (_flags & DB_PRIVATE) {
		// if DB_PRIVATE, region file resides in memory
		ret = db->open(db, NULL, NULL, pname, type, _flags, 0644);
		if (ret) {
			obMTRACE(ret);
			goto err;
		}
	} else {
		ret = db->open(db, NULL, pname, NULL, type, _flags, 0644);
		if (ret) {
			obMTRACE(ret);
			goto err;
		}
	}
	return 0;
	err: return (ret);
}



/*******************************************************************************
 * temporary environment
 ******************************************************************************/
static int createBasesTemp(ob_tPrivateTemp *privt, DB_ENV *envt) {
	int ret = 0;
	if (!privt) {
		ret = ob_dbe_CerPrivUndefined;
		goto fin;
	}

	if ((ret = db_create(&privt->px_traits, envt, 0)) != 0) {
		privt->px_traits = NULL;
		goto fin;
	}
	if ((ret = db_create(&privt->py_traits, envt, 0)) != 0) {
		privt->py_traits = NULL;
		goto fin;
	}
	if ((ret = db_create(&privt->m_traits, envt, 0)) != 0) {
		privt->m_traits = NULL;
		goto fin;
	}
	if ((ret = db_create(&privt->traits, envt, 0)) != 0) {
		privt->traits = NULL;
		goto fin;
	}

	if ((ret = db_create(&privt->vx_points, envt, 0)) != 0) {
		privt->vx_points = NULL;
		goto fin;
	}
	if ((ret = db_create(&privt->vy_points, envt, 0)) != 0) {
		privt->vy_points = NULL;
		goto fin;
	}
	if ((ret = db_create(&privt->mar_points, envt, 0)) != 0) {
		privt->mar_points = NULL;
		goto fin;
	}
	if ((ret = db_create(&privt->mav_points, envt, 0)) != 0) {
		privt->mav_points = NULL;
		goto fin;
	}
	if ((ret = db_create(&privt->st_points, envt, 0)) != 0) {
		privt->st_points = NULL;
		goto fin;
	}
	if ((ret = db_create(&privt->points, envt, 0)) != 0) {
		privt->points = NULL;
		goto fin;
	}

	if ((ret = db_create(&privt->stocktemps, envt, 0)) != 0) {
		privt->stocktemps = NULL;
		goto fin;
	}

	return 0;
	fin: return (ret);
}
static char *extendPid(char *res,char *name){
	int ret;
	size_t l;
	pid_t pid;
	char *str;

	l =strlen(name);
	memcpy(res,name,l);
	str = res+l;
	pid = getpid();
	ret = snprintf(str,32,"%d",pid);
	if(ret >=32) {
		ereport(ERROR,
				(errmsg("32 char was not enough to print the pid")));
		return name;
	}
	return res;
}
static int openBasesTemp(DB_ENV *envt, u_int32_t flagsdb) {
	int ret;
	char nam[obCMAXPATH];

	ob_tPrivateTemp *privt = envt->app_private;
	if (!privt) {
		ret = ob_dbe_CerPrivUndefined;
		return ret;
	}

	// provisoire
	ret = createBasesTemp(privt, envt);
	if(ret) goto fin;

	// traits
	ret = open_db(envt, false, privt->traits, extendPid(nam,"traits"), NULL, 0, DB_BTREE,flagsdb, NULL, NULL);
	if(ret) goto fin;

	ret = open_db(envt, true, privt->m_traits, extendPid(nam,"m_traits"), NULL, 0,DB_BTREE, flagsdb, NULL, NULL);
	if(ret) goto fin;

	ret = privt->traits->associate(privt->traits, 0, privt->m_traits,trait_get_marque, 0);
	if(ret) goto fin;

	ret = open_db(envt, true, privt->px_traits, extendPid(nam,"px_traits"), NULL, 0,DB_BTREE, flagsdb, NULL, NULL);
	if(ret) goto fin;
	ret = privt->traits->associate(privt->traits, 0, privt->px_traits,trait_get_Xoid, 0);
	if(ret) goto fin;

	ret = open_db(envt, true, privt->py_traits,extendPid(nam, "py_traits"), NULL, 0,DB_BTREE, flagsdb, NULL, NULL);
	if(ret) goto fin;
	ret = privt->traits->associate(privt->traits, 0, privt->py_traits,trait_get_Yoid, 0);
	if(ret) goto fin;

	//points
	ret = open_db(envt, false, privt->points,extendPid(nam, "points"), NULL, 0, DB_BTREE,flagsdb, NULL, NULL);
	if(ret) goto fin;
	// the size of points is not constant

	ret = open_db(envt, true, privt->mar_points, extendPid(nam,"mar_points"), NULL, 0,DB_BTREE, flagsdb, NULL, NULL);
	if(ret) goto fin;
	ret = privt->points->associate(privt->points, 0, privt->mar_points,point_get_mar, 0);
	if(ret) goto fin;

	ret = open_db(envt, true, privt->mav_points, extendPid(nam,"mav_points"), NULL, 0,DB_BTREE, flagsdb, NULL, NULL);
	if(ret) goto fin;
	ret = privt->points->associate(privt->points, 0, privt->mav_points,point_get_mav, 0);
	if(ret) goto fin;

	ret = open_db(envt, true, privt->vx_points, extendPid(nam,"vx_points"), NULL, 0,DB_BTREE, flagsdb, NULL, NULL);
	if(ret) goto fin;
	ret = privt->points->associate(privt->points, 0, privt->vx_points,point_get_nX, 0);
	if(ret) goto fin;

	ret = open_db(envt, true, privt->vy_points, extendPid(nam,"vy_points"), NULL, 0,DB_BTREE, flagsdb, NULL, NULL);
	if(ret) goto fin;
	ret = privt->points->associate(privt->points, 0, privt->vy_points,point_get_nY, 0);
	if(ret) goto fin;

	ret = open_db(envt, true, privt->st_points,extendPid(nam, "st_points"), NULL, 0,DB_BTREE, flagsdb, NULL, NULL);
	if(ret) goto fin;
	ret = privt->points->associate(privt->points, 0, privt->st_points,point_get_stockId, 0);
	if(ret) goto fin;

	// stocktemps
	ret = open_db(envt, false, privt->stocktemps, extendPid(nam,"stocktemps"), NULL, 0,DB_BTREE, flagsdb, NULL, NULL);
	if(ret) goto fin;

	return 0;
fin:
	//syslog(LOG_DEBUG,"Erreur a l'ouverture d'envit");
	(void) closeBasesTemp(privt);
	return (ret);
}
/******************************************************************************/
#define ob_dbe_MCloseBase(base) if((base)!=NULL) { \
		ret_t = (base)->close((base),0); \
		if( ret_t) { \
			if(!ret) ret = ret_t; \
		} \
		(base) = NULL; \
	}
/******************************************************************************/
/******************************************************************************/
static int closeBasesTemp(ob_tPrivateTemp *privt) {
	int ret = 0, ret_t;
	if (!privt) {
		ret = ob_dbe_CerPrivUndefined;
		return ret;
	}

	ob_dbe_MCloseBase(privt->px_traits);
	ob_dbe_MCloseBase(privt->py_traits);
	ob_dbe_MCloseBase(privt->m_traits);
	ob_dbe_MCloseBase(privt->traits);

	ob_dbe_MCloseBase(privt->vx_points);
	ob_dbe_MCloseBase(privt->vy_points);
	ob_dbe_MCloseBase(privt->mar_points);
	ob_dbe_MCloseBase(privt->mav_points);
	ob_dbe_MCloseBase(privt->st_points);
	ob_dbe_MCloseBase(privt->points);

	ob_dbe_MCloseBase(privt->stocktemps);

	// stat_env(envit->env,0);

	return (ret);
}

/*******************************************************************************
 Callback error
 *******************************************************************************/
static void errcallback(const DB_ENV *dbenv, const char *errpfx,
		const char *msg) {

#ifdef obCTESTCHEM
	fprintf(stderr, "ob>%s> %s\n", errpfx, msg);
#else
	elog(ERROR, "ob>%s> %s\n", errpfx, msg);
#endif
	return;
}

/*******************************************************************************
 dup compare
 *******************************************************************************/
/*
#define ob_dbe_cmp(a,b) (((a)<(b))?-1:(((a)>(b))?1:0))
static int compare_dup_points(DB *db, const DBT *data1, const DBT *data2) {
	ob_tMarqueOffre mo1, mo2;
	int cmp;

	memcpy(&mo1, data1->data, sizeof(ob_tNoeud));
	memcpy(&mo2, data2->data, sizeof(ob_tNoeud));
	cmp = ob_dbe_cmp(mo1.offre.nF, mo2.offre.nF);
	if (cmp)
		return (cmp);
	cmp = ob_dbe_cmp(mo1.offre.nR, mo2.offre.nR);
	if (cmp)
		return (cmp);
	cmp = ob_dbe_cmp(mo1.offre.stockId, mo2.offre.stockId);
	if (cmp)
		return (cmp);
	// ajouté
	cmp = ob_dbe_cmp(mo1.offre.oid, mo2.offre.oid);
	if (cmp)
		return (cmp);
	return (0);
}
*/
/*******************************************************************************
 Key extractors de l'environnement durable
 *******************************************************************************/
/*
// pour stock.valF
static int stock_get_nF(DB *sdbp, const DBT *pkey, const DBT *pdata, DBT *skey) {
	ob_tStock *stock;

	stock = pdata->data;

	memset(skey, 0, sizeof(DBT));
	skey->data = &(stock->nF);
	skey->size = sizeof(ob_tQuaId);
	return (0);
}

static int stock_get_own(DB *sdbp, const DBT *pkey, const DBT *pdata, DBT *skey) {
	ob_tStock *stock;

	stock = pdata->data;

	memset(skey, 0, sizeof(DBT));
	skey->data = &(stock->own);
	skey->size = sizeof(ob_tOwnId);
	return (0);
}

static int offre_get_nY(DB *sdbp, const DBT *pkey, const DBT *pdata, DBT *skey) {
	ob_tNoeud *offre;

	offre = pdata->data;

	memset(skey, 0, sizeof(DBT));
	skey->data = &(offre->nF);
	skey->size = sizeof(ob_tQuaId);
	return (0);
}

static int offre_get_nX(DB *sdbp, const DBT *pkey, const DBT *pdata, DBT *skey) {
	ob_tNoeud *offre;

	offre = pdata->data;

	memset(skey, 0, sizeof(DBT));
	skey->data = &(offre->nR);
	skey->size = sizeof(ob_tQuaId);
	return (0);
}

static int offre_get_stockId(DB *sdbp, const DBT *pkey, const DBT *pdata,
		DBT *skey) {
	ob_tNoeud *offre;

	offre = pdata->data;

	memset(skey, 0, sizeof(DBT));
	skey->data = &(offre->stockId);
	skey->size = sizeof(ob_tId);
	return (0);
} */
/*
static int accord_get_oid(DB *sdbp, const DBT *pkey, const DBT *pdata,
		DBT *skey) {

	DBT *tmpdbt;
	int nbo, io;
	ob_tId *poid;
	ob_tAccord *accord;
	ob_tNoeud *pnoeud;
	ob_tChemin *pchem;

	memset(skey, 0, sizeof(DBT));

	accord = pdata->data;
	nbo = ob_flux_cheminGetNbNode(&accord->chemin);
	//ob_accord_voirAccord(accord);
	tmpdbt = malloc(sizeof(DBT) * nbo);
	if (!tmpdbt) // TODO
		return (ob_dbe_CerMalloc);
	memset(tmpdbt, 0, sizeof(DBT) * nbo);

	obMRange(io,nbo) {
		pnoeud = ob_flux_cheminGetAdrNoeud(&accord->chemin, io);
		tmpdbt[io].data = &pnoeud->oid;
		tmpdbt[io].size = ob_ut_size(&pnoeud->oid);
	}

	skey->flags = DB_DBT_MULTIPLE | DB_DBT_APPMALLOC;
	skey->data = tmpdbt;
	skey->size = nbo;
	return (0);
} */
/*
static int accord_get_own(DB *sdbp, const DBT *pkey, const DBT *pdata, DBT *skey) {

	DBT *tmpdbt;
	int nbw, iw;
	ob_tId *pown;
	ob_tAccord *accord;
	ob_tChemin *pchem;

	memset(skey, 0, sizeof(DBT));

	accord = pdata->data;
	pchem = &accord->chemin;
	nbw = ob_flux_cheminGetNbOwn(pchem);
	//ob_accord_voirAccord(accord);
	tmpdbt = malloc(sizeof(DBT) * nbw);
	if (!tmpdbt) // TODO
		return (ob_dbe_CerMalloc);
	memset(tmpdbt, 0, sizeof(DBT) * nbw);

	obMRange(iw,nbw) {
		pown = ob_flux_cheminGetOwn(pchem,iw);
		tmpdbt[iw].data = pown;
		tmpdbt[iw].size = ob_ut_size(pown);
	}

	skey->flags = DB_DBT_MULTIPLE | DB_DBT_APPMALLOC;
	skey->data = tmpdbt;
	skey->size = nbw;
	return (0);
}*/
/*
static int interdit_get_Xoid(DB *sdbp, const DBT *pkey, const DBT *pdata,
		DBT *skey) {
	ob_tInterdit *interdit;

	interdit = pdata->data;

	memset(skey, 0, sizeof(DBT));
	skey->data = &(interdit->rid.Xoid);
	skey->size = sizeof(ob_tId);
	return (0);
}
static int interdit_get_Yoid(DB *sdbp, const DBT *pkey, const DBT *pdata,
		DBT *skey) {
	ob_tInterdit *interdit;

	interdit = pdata->data;

	memset(skey, 0, sizeof(DBT));
	skey->data = &(interdit->rid.Yoid);
	skey->size = sizeof(ob_tId);
	return (0);
}
*/
/*
static int nom_get_nom(DB *sdbp, const DBT *pkey, const DBT *pdata, DBT *skey) {
	memset(skey, 0, sizeof(DBT));
	skey->data = pdata->data;
	skey->size = pdata->size;
	return (0);
} */
/*******************************************************************************
 Fonctions d'extraction de clef sur l'evt temporaire
 *******************************************************************************/
static int point_get_nX(DB *sdbp, const DBT *pkey, const DBT *pdata, DBT *skey) {
	ob_tPoint *point;
	// risque de bp d'alignement
	point = pdata->data;

	memset(skey, 0, sizeof(DBT));
	skey->data = &(point->mo.offre.nR);
	skey->size = sizeof(ob_tQuaId);
	return (0);
}
static int point_get_nY(DB *sdbp, const DBT *pkey, const DBT *pdata, DBT *skey) {
	ob_tPoint *point;

	point = pdata->data;
	memset(skey, 0, sizeof(DBT));
	skey->data = &(point->mo.offre.nF);
	skey->size = sizeof(ob_tQuaId);
	return (0);
}
/*
static int point_get_mar(DB *sdbp, const DBT *pkey, const DBT *pdata, DBT *skey) {
	ob_tPoint *point;
	ob_tMar *tmpmar;
	int layer,res;

	point = pdata->data;
	tmpmar = malloc(sizeof(ob_tMar));

	layer = point->mo.ar.layer;
	res = 1;
	while (layer) {
		res <<=1;
		layer >>=1;
	} ;
	res >>=1;
	// res contains the most significant bit of point->mo.ar.layer
	tmpmar->layer = res;
	tmpmar->igraph = point->mo.ar.igraph; // unchanged
	
	memset(skey, 0, sizeof(DBT));
	skey->data = tmpmar;
	skey->size = sizeof(ob_tMar);
	skey->flags = DB_DBT_APPMALLOC;
	return (0);
} 
*/
static int point_get_mar(DB *sdbp, const DBT *pkey, const DBT *pdata, DBT *skey) {
	ob_tPoint *point;
	point = pdata->data;
	
	memset(skey, 0, sizeof(DBT));
	skey->data = &(point->mo.ar);
	skey->size = sizeof(ob_tMar); 
	return (0);
} 

/*
static int point_get_mav(DB *sdbp, const DBT *pkey, const DBT *pdata, DBT *skey) {

	
	ob_tPoint *point;
	ob_tMar *tmpmav;
	int layer,res;

	point = pdata->data;
	tmpmav = malloc(sizeof(ob_tMar));

	layer = point->mo.av.layer;
	res = 1;
	while (layer) {
		res <<=1;
		layer >>=1;
	} ;
	res >>=1;
	// res contains the most significant bit of point->mo.ar.layer
	tmpmav->layer = res;
	tmpmav->igraph = point->mo.av.igraph; // unchanged
	
	memset(skey, 0, sizeof(DBT));
	skey->data = tmpmav;
	skey->size = sizeof(ob_tMar);
	skey->flags = DB_DBT_APPMALLOC;
	return (0);
} */
static int point_get_mav(DB *sdbp, const DBT *pkey, const DBT *pdata, DBT *skey) {
	ob_tPoint *point;
	point = pdata->data;
	
	memset(skey, 0, sizeof(DBT));
	skey->data = &(point->mo.av);
	skey->size = sizeof(ob_tMar); 
	return (0);
}	

static int point_get_stockId(DB *sdbp, const DBT *pkey, const DBT *pdata,
		DBT *skey) {
	ob_tPoint *point;

	point = pdata->data;
	memset(skey, 0, sizeof(DBT));
	skey->data = &(point->mo.offre.stockId);
	skey->size = sizeof(ob_tId);
	return (0);
}

static int trait_get_Xoid(DB *sdbp, const DBT *pkey, const DBT *pdata,
		DBT *skey) {
	ob_tTrait *trait;
	trait = pdata->data;

	memset(skey, 0, sizeof(DBT));
	skey->data = &(trait->rid.Xoid);
	skey->size = sizeof(ob_tId);
	return (0);
}

static int trait_get_Yoid(DB *sdbp, const DBT *pkey, const DBT *pdata,
		DBT *skey) {
	ob_tTrait *trait;
	trait = pdata->data;

	memset(skey, 0, sizeof(DBT));
	skey->data = &(trait->rid.Yoid);
	skey->size = sizeof(ob_tId);
	return (0);
}

static int trait_get_marque(DB *sdbp, const DBT *pkey, const DBT *pdata,
		DBT *skey) {
	ob_tTrait *trait;

	trait = pdata->data;

	memset(skey, 0, sizeof(DBT));
	skey->data = &(trait->igraph);
	skey->size = sizeof(int);
	return (0);
}
/*
static int message_get_own(DB *sdbp, const DBT *pkey, const DBT *pdata,
		DBT *skey) {
	ob_tMessage *message;
	message = pdata->data;

	memset(skey, 0, sizeof(DBT));
	skey->data = &(message->own);
	skey->size = sizeof(ob_tId);
	return (0);
} */

void ob_dbe_resetStock(ob_tStock *pstock) {
	memset(pstock, 0, sizeof(ob_tStock));
	pstock->sid = 0;
	pstock->own = 0;
	// ob_tQtt qtt
	pstock->nF = 0;
	pstock->version = 0;
	return;
}

void ob_dbe_resetNoeud(ob_tNoeud *pnoeud) {
	memset(pnoeud, 0, sizeof(ob_tNoeud));
	pnoeud->oid = 0;
	pnoeud->stockId = 0;
	// double omega;
	pnoeud->nR = 0;
	pnoeud->nF = 0;
	pnoeud->own = 0;
	return;
}

void ob_dbe_resetFleche(ob_tFleche *pfleche) {
	memset(pfleche, 0, sizeof(ob_tFleche));
	pfleche->Xoid  = 0;
	pfleche->Xoid = 0;
	return;
}
void ob_dbe_resetTrait(ob_tTrait *ptrait) {
	memset(ptrait, 0, sizeof(ob_tTrait));
	ob_dbe_resetFleche(&ptrait->rid);
	// int igraph
	return;
}
void ob_dbe_resetMarqueOffre(ob_tMarqueOffre *pmo) {
	memset(pmo, 0, sizeof(ob_tMarqueOffre));
	ob_dbe_resetNoeud(&pmo->offre);
	// int ar.layer,ar.igraph,av.layer,av.igraph
	return;
}
