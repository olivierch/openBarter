/*
 * iterators.h
 *
 *  Created on: 17 juin 2011
 *      Author: olivier
 */

#ifndef ITERATORS_H_
#define ITERATORS_H_

typedef struct  {
	DB *db;
	DBC *cursor;
	DBT ks_skey;
	DBT du_key,du_data;
	int error;
	int state;
} ob_tSIterator;

typedef struct  {
	DB *db;
	DBC *cursor;
	DBT ks_key,du_data;
	int error;
} ob_tAIterator;


void initSIterator(ob_tSIterator *iter,DB *db, u_int32_t size_skey,u_int32_t size_key,u_int32_t size_data);
int openSIterator(ob_tSIterator *iter,void *skey);
int nextSIterator(ob_tSIterator *iter,void *key,void *data);
int closeSIterator(ob_tSIterator *iter,int ret);

int closeAIterator(ob_tAIterator *iter,int ret);
void initAIterator(ob_tAIterator *iter,DB *db, u_int32_t size_key,u_int32_t size_data);
int getAIterator(ob_tAIterator *iter,void *key,void *data,u_int32_t flags);
int putAIterator(ob_tAIterator *iter,void *key,void *data,u_int32_t flags);

int iterators_idPut(DB *db,void *key,void *data,size_t size_data,u_int32_t flags);
int iterators_idGet(DB *db,void *key,void *data,size_t size_data,u_int32_t flags);


#endif /* ITERATORS_H_ */
