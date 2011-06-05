/*
 * openbarter.h
 *
 *  Created on: 12 nov. 2010
 *      Author: olivier
 */

#ifndef OPENBARTER_H_
#define OPENBARTER_H_
#include <postgres.h>
#include <db.h>
#include "funcapi.h"
#include "executor/spi.h"
#include "common.h"
#include <../interfaces/libpq/libpq-fe.h>
#include "utils/timestamp.h"

#define OB_SRTLEN_MAX 1024

struct ob__Glob;
typedef struct ob__Glob ob_tGlob;

/* used by balance.h */
typedef struct ob_ConnectDesc {
	char * conninfo;
	int lenDatas;
	int64 connDatas[];
} ob_tConnectDesc;

/* Used  by getdraft.c */
typedef struct {
	TupleDesc tuple_desc;
	int 	i_commit,i_graph;
	DB_ENV	*envt;
	ob_tNoeud	pivot;
	int nblayer;
	ob_tAccord accord;
	ob_tLoop	loop;
	bool	end;
} ob_getdraft_ctx;

/* Used  by appel.c */
typedef struct {
	TupleDesc tuple_desc;
	ob_tConnectDesc *connDesc;
	PGconn *conn;
	TimestampTz start;
} ob_appel_ctx;

struct ob__Glob {
	DB_ENV *envt;
	TupleDesc tupDescQuality;
	TupleDesc tupDescStock;
	TupleDesc tupDescNoeud;
	SPIPlanPtr planIterNoeuds2;
	SPIPlanPtr planGetStock;
	char pathEnv[MAXPGPATH];
	ob_getdraft_ctx ctx;
	ob_appel_ctx	actx;
};

// utils.c
extern int ob_makeEnvDir(char *direnv);
extern int ob_rmPath(char *path,bool also_me);
extern int ob_utils_Init(ob_tGlob *ob);
extern int ob_utils_PrepareIterNoeuds(ob_tGlob *ob);
extern int ob_utils_PrepareGetStock(ob_tGlob *ob);

// getdraft.c
extern int ob_getdraft_init(void);

// global variables
extern ob_tGlob openbarter_g;
#endif /* OPENBARTER_H_ */
