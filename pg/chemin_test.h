#ifndef chemin__test_h_defined
#define chemin__test_h_defined

struct TestCtxData {
	int testNum;
	ob_tId id;
	ob_tId q;
	ob_tId nlMax;
	ob_tId nlc;
};
typedef struct TestCtxData *TestCtx;
/* TupleDesc tuple_desc; has been removed */
struct ob__getdraft_ctx {
	int 	i_commit,i_graph;
	DB_ENV	*envt;
	ob_tNoeud	pivot;
	ob_tStock 	stockPivot;
	int nblayer;
	ob_tAccord accord;
	ob_tLoop	loop;
	int state;
};
typedef struct ob__getdraft_ctx ob_getdraft_ctx;
/******************************************************************************/
extern const TestCtx testCtx;

// tbdb.c
Portal ob_iternoeud_GetPortalA(DB_ENV *envt,ob_tId  yoid,ob_tId  nr,int limit);
int ob_iternoeud_NextA(Portal portal,ob_tId *Xoid,ob_tNoeud *offreX,ob_tStock *stock);
void SPI_cursor_close(Portal p);
int ob_point_initPoint(ob_tPrivateTemp *privt, ob_tPoint *point);
void prChemin(ob_tChemin* ch);

// dbe.c
int ob_dbe_openEnvTemp(DB_ENV **penvt);
int ob_dbe_resetEnvTemp(DB_ENV **penvt);
int ob_dbe_closeEnvTemp(DB_ENV *envt);
int truncateBasesTemp(ob_tPrivateTemp *privt);
//void errcallback(const DB_ENV *dbenv, const char *errpfx,const char *msg);

// chemin.c
int ob_chemin_parcours_arriere(DB_ENV *envt,ob_tNoeud *pivot,
		ob_tStock *stockPivot,bool deposOffre,ob_tId *versionSg);
int _parcours_avant(ob_tPrivateTemp *privt,ob_tNoeud *pivot,
		int i_graph,int *nbSource);
void ob_chemin_get_commit_init(ob_getdraft_ctx *ctx);
int ob_chemin_get_commit(ob_getdraft_ctx *ctx);

//int _bellman_ford_in(ob_tPrivateTemp *privt,ob_tTrait *trait);
//size_t ob_flux_cheminGetSize(ob_tChemin *pchemin);
//int ob_flux_GetTabStocks(ob_tChemin *pchemin, ob_tStock *tabStocks,int *nbStock);



// 1<<16 256K, cache 1<<24 soit 16 Mo
#define ob_dbe_CCACHESIZE (1<<21)	// cache durable
// 32 Mo
#define ob_dbe_CCACHESIZETEMP (1<<25) // cache temporaire

#endif // chemin__test_h_defined
