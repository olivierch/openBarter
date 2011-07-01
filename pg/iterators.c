#ifndef TBDB
#include <postgres.h>
#endif
#include "common.h"
#include "iterators.h"
// #define DIAG_ITERATORS
/*
define iterators on bdb used by chemin
 */

/* SIterator
in parcours_arriere, iterator on privt->mar_points.
usage:
	ob_tSIterator iter;
	ob_tMarqueOffre mo;
	ob_tId oid;
	ob_tMar marque;

	....
	initSIterator(&iter,db,sizeof(ob_tMar),sizeof(ob_tId),sizeof(ob_tMarqueOffre));
	....
	ret = openSIterator(&iter,&marque);
	if(ret) goto fin;

	while(true) {
		ret = nextSIterator(&iter,&oid,&mo);
		if(ret) {
			if(ret == DB_NOTFOUND) {ret = 0;break;}
			goto fin;
		}
		..............................................................
	}
	if (ret == DB_NOTFOUND) ret = 0;
	else goto fin;
	....
fin:
	ret = closeSIterator(&iter,ret);
 */


int closeSIterator(ob_tSIterator *iter,int ret) {
	if(iter->cursor) {
		int ret_t;

		ret_t = iter->cursor->close(iter->cursor);
		iter->cursor = NULL;
		iter->state = 0;
		if(ret_t){
			elog(LOG,"error %i",ret_t);
			if(iter->error == 0) iter->error = ret_t;
		}
	}
	if(ret) return ret;
	return iter->error;
}

void initSIterator(ob_tSIterator *iter,DB *db, u_int32_t size_skey,u_int32_t size_key,u_int32_t size_data) {

	memset(iter,0,sizeof(ob_tSIterator));

	iter->ks_skey.size = size_skey;
	iter->db = db;

	iter->du_key.size = size_key;
	iter->du_key.flags = DB_DBT_USERMEM;
	iter->du_key.ulen = size_key;

	iter->du_data.size = size_data;
	iter->du_data.flags = DB_DBT_USERMEM;
	iter->du_data.ulen = size_data;

	return;
}

int openSIterator(ob_tSIterator *iter,void *skey) {
	int ret;

	if(iter->error) return iter->error;
	if(iter->cursor == NULL) {
		ret = iter->db->cursor(iter->db,NULL,&iter->cursor,0);
		if(ret) {
			elog(LOG,"error %i",ret);
			iter->error = ret;
			return closeSIterator(iter,ret);
		}
	}
	iter->ks_skey.data = skey;
	iter->state=1;
	return 0;
}

int nextSIterator(ob_tSIterator *iter,void *key,void *data) {
	u_int32_t flags;
	int ret;

	if(iter->error) return iter->error;

	if(iter->cursor == NULL || (iter->state == 0)) {
		printf("state %i\n",iter->state);
		iter->error = ob_chemin_CerIterNoeudErr;
		return ob_chemin_CerIterNoeudErr;
	}

	if(iter->state == 1) {
		flags = DB_SET;
		iter->state = 2;
	}
	else flags = DB_NEXT_DUP;

	iter->du_key.data = key;
	iter->du_data.data = data;

#ifdef DIAG_ITERATORS
	{
		ob_tMar* mar = iter->ks_skey.data;
		//ob_tPoint* point = iter->du_data.data;

		printf("pget layer=%i,igraph=%i flags=%i\n",
			mar->layer,mar->igraph,flags);
	}
#endif

	ret = iter->cursor->pget(iter->cursor,&iter->ks_skey,&iter->du_key,&iter->du_data,flags);
	if(ret == DB_NOTFOUND) { // || ret == DB_SECONDARY_BAD) {
		ret = DB_NOTFOUND;
		return closeSIterator(iter,ret);
	}

#ifdef DIAG_ITERATORS
	{
		ob_tId* id = iter->du_key.data;
		//ob_tPoint* point = iter->du_data.data;

		printf("found oid=%lli\n",
			*id,flags);
	}
#endif

	if(ret) {
		elog(LOG,"error %i",ret);
		iter->error = ret;
		return closeSIterator(iter,ret);
	}
	return 0;
}
/* AIterator

usage:
	ob_tAIterator iter;
	ob_tMarqueOffre mo;
	ob_tId oid;

	....
	initAIterator(&iter,db,sizeof(ob_tId),sizeof(ob_tMarqueOffre));
	....
	ret = getAIterator(&iter,&oid,&mo,0);
	if(ret) {
		if(ret == DB_NOTFOUND) {ret = 0;}
		else goto fin;
	}
	....
	ret = putAIterator(&iter,&oid,&mo,DB_NOOVERWRITE);
	if(ret) goto fin;
	....
fin:
	ret = closeAIterator(&iter,ret);
 */


int closeAIterator(ob_tAIterator *iter,int ret) {
	if(iter->cursor) {
		int ret_t;


		ret_t = iter->cursor->close(iter->cursor);
		iter->cursor = NULL;
		if(ret_t) {
			elog(LOG,"error %i",ret);
			if(iter->error == 0) iter->error = ret_t;
		}
	}
	if(ret) return ret;
	return iter->error;
}

void initAIterator(ob_tAIterator *iter,DB *db, u_int32_t size_key,u_int32_t size_data) {

	memset(iter,0,sizeof(ob_tAIterator));
	iter->db = db;
	iter->ks_key.size = size_key;

	iter->du_data.size = size_data;
	iter->du_data.flags = DB_DBT_USERMEM;
	iter->du_data.ulen = size_data;

	return;
}

int getAIterator(ob_tAIterator *iter,void *key,void *data,u_int32_t flags) {
	int ret;

	if(iter->error) return iter->error;
	if(iter->cursor == NULL) {
		ret = iter->db->cursor(iter->db,NULL,&iter->cursor,0);
		if(ret) {
			elog(LOG,"error %i",ret);
			iter->error = ret;
			return closeAIterator(iter,ret);
		}
	}

	iter->ks_key.data = key;
	iter->du_data.data = data;

	ret = iter->cursor->get(iter->cursor,&iter->ks_key,&iter->du_data,flags);
	if(ret == DB_NOTFOUND) return closeAIterator(iter,ret);
	if(ret) {
		elog(LOG,"error %i",ret);
		iter->error = ret;
		return closeAIterator(iter,ret);
	}
	return 0;
}

int putAIterator(ob_tAIterator *iter,void *key,void *data,u_int32_t flags) {
	int ret;

	if(iter->error) return iter->error;
	if(iter->cursor == NULL) {
		ret = iter->db->cursor(iter->db,NULL,&iter->cursor,0);
		if(ret) {
			iter->error = ret;
			return closeAIterator(iter,ret);
		}
	}

	iter->ks_key.data = key;
	iter->du_data.data = data;

#ifdef DIAG_ITERATORS
	{
		ob_tId* oid = iter->ks_key.data;
		ob_tPoint* point = iter->du_data.data;

		printf("put ks=%lli du.oid=%lli layer=%i igraph=%i lk=%i ld=%i\n",
				*oid,point->mo.offre.oid,point->mo.ar.layer,point->mo.ar.igraph,iter->ks_key.size,iter->du_data.size);
	}
#endif

	ret = iter->cursor->put(iter->cursor,&iter->ks_key,&iter->du_data,flags);
	if(ret == DB_NOTFOUND) return closeAIterator(iter,ret);
	if(ret) {
		elog(LOG,"error %i",ret);
		iter->error = ret;
		return closeAIterator(iter,ret);
	}
	return 0;
}


int iterators_idPut(DB *db,void *key,void *data,size_t size_data,u_int32_t flags) {
	DBT dbt[2];

	memset(dbt,0,sizeof(DBT)*2);
	dbt[0].data = key;
	dbt[0].size = sizeof(ob_tId);

	dbt[1].data = data;
	dbt[1].size = size_data;

	return db->put(db, 0,&dbt[0], &dbt[1], flags);
}


int iterators_idGet(DB *db,void *key,void *data,size_t size_data,u_int32_t flags) {
	DBT dbt[2];

	memset(dbt,0,sizeof(DBT)*2);
	dbt[0].data = key;
	dbt[0].size = sizeof(ob_tId);

	dbt[1].data = data;
	dbt[1].flags = DB_DBT_USERMEM;
	dbt[1].size = size_data;
	dbt[1].ulen = size_data;

	return db->get(db, 0,&dbt[0], &dbt[1], flags);
}
