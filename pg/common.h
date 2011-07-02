#ifndef defined__common_h
#define defined__common_h
#ifndef TBDB_C_
#include <c.h>
#endif
//#include <stdbool.h>
#include <assert.h>
#include <stdlib.h>
#include <errno.h>
#include <syslog.h>

// includes necessary for replication
#include <string.h> // memset
#include <stdio.h> // printf
#include <pthread.h>
#include <stdarg.h>
#include "db.h"
#define prId(id) printf("%x-%x\n",(id)->data[0],(id)->data[1])
/*********************************************************************
error code offset:
the error name space from -30,100 to -30,299.
*********************************************************************/
#define ob_iternoeud_CerOff					-30100
#define ob_flux_CerOff						-30120
#define ob_chemin_CerOff					-30140
#define ob_point_CerOff 					-30160
#define ob_nom_CerOff						-30180
#define ob_dbe_CerOff						-30200
#define ob_fct_CerOff						-30220
#define ob_balance_CerOff					-30230
//Berkeleydb [db.h]
//	the error name space from -30,800 to -30,999.

#define ob_iternoeud_CerSPI_execute_plan 		ob_iternoeud_CerOff-1
#define ob_iternoeud_CerBinValue 		ob_iternoeud_CerOff-2

#define ob_balance_CerSPI_execute_plan 		ob_balance_CerOff-1
#define ob_balance_CerBinValue 		ob_balance_CerOff-2

#define ob_chemin_CerMalloc			ob_chemin_CerOff-1
#define ob_chemin_CerPointIncoherent 	ob_chemin_CerOff-2
#define ob_chemin_CerParcoursAvant 		ob_chemin_CerOff-3
#define ob_chemin_CerLoopOnOffer		ob_chemin_CerOff-4
#define ob_chemin_CerStockEmpty		ob_chemin_CerOff-5
#define ob_chemin_CerNoDraft	 	ob_chemin_CerOff-6
#define ob_chemin_CerIterNoeudErr	 ob_chemin_CerOff-7
#define ob_chemin_LimitReached		ob_chemin_CerOff-8
#define ob_chemin_CerNoSource		ob_chemin_CerOff-9
#define ob_chemin_CerStockEpuise	ob_chemin_CerOff-10

#define ob_dbe_CerInit				ob_dbe_CerOff-1
#define ob_dbe_CenvUndefined			ob_dbe_CerOff-2
#define ob_dbe_CerMalloc				ob_dbe_CerOff-3
#define ob_dbe_CerPrivUndefined		ob_dbe_CerOff-4
#define ob_dbe_CerStr				ob_dbe_CerOff-5
#define ob_dbe_CerDirErr				ob_dbe_CerOff-6

#define ob_fct_CerStockNotFoundInA 		ob_fct_CerOff-1
#define ob_fct_CerNotDraft				ob_fct_CerOff-2
#define ob_fct_CerAccordNotFound		ob_fct_CerOff-6

#define ob_flux_CerCheminTropLong 		ob_flux_CerOff-1
#define ob_flux_CerCheminTropStock 		ob_flux_CerOff-2
#define ob_flux_CerCheminPbOccStock 	ob_flux_CerOff-3
#define ob_flux_CerCheminPbOccOwn 		ob_flux_CerOff-4
#define ob_flux_CerCheminPbIndexStock 	ob_flux_CerOff-5
#define ob_flux_CerCheminPbOwn 			ob_flux_CerOff-6
#define ob_flux_CerCheminPbIndexOwn 	ob_flux_CerOff-7
#define ob_flux_CerCheminPom 			ob_flux_CerOff-8
#define ob_flux_CerCheminCuillere 		ob_flux_CerOff-9
#define ob_flux_CerLoopOnOffer	 		ob_flux_CerOff-10
#define ob_flux_CerOmegaNeg	 			ob_flux_CerOff-11
#define ob_flux_CerNoeudNotStock	 	ob_flux_CerOff-12
#define ob_flux_CerCheminPom2 			ob_flux_CerOff-13
#define ob_flux_CerCheminPom3 			ob_flux_CerOff-14
#define ob_flux_CerCheminNoOwn 			ob_flux_CerOff-15
#define ob_flux_CerCheminNotMax 		ob_flux_CerOff-16
#define ob_flux_CerCgain 				ob_flux_CerOff-17
#define ob_flux_CerStockPivotUsed 		ob_flux_CerOff-18
#define ob_flux_CerStockPb 				ob_flux_CerOff-19
#define ob_flux_CerFlowNotFound 		ob_flux_CerOff-20


#define ob_point_CerMalloc				ob_point_CerOff-1
#define ob_point_CerStockEpuise 		ob_point_CerOff-2
#define ob_point_CerGetPoint			ob_point_CerOff-3
#define ob_point_CerOffreInconsistant		ob_point_CerOff-4
#define ob_point_CerStockNotNeg		ob_point_CerOff-5
#define ob_point_CerAbort				ob_point_CerOff-6
#define ob_point_CerRefusXY				ob_point_CerOff-7

struct ob__StrError; typedef struct ob__StrError ob_tStrError;
struct ob__StrError {
	char *error;
	int id;
};
#define NULLSTRERROR {NULL,0}



/*
tests.h
fct.h

assert.h
	if NDEBUG is defined, the instruction is not compiled
	add to gcc -DNDEBUG
 *
 */
/*********************************************************************
error code offset:
*********************************************************************/
#define obCMAXBUF 256
#define obCMAXBBUF 1024
#define obCMAXPATH 512
#define obMRange(v,S) for (v=0;v<(S);v++)
#define obMMax(a,b) ((a)<(b))?(a):(b)

#ifndef obCTEST
#define obMTRACE(err) do { \
	if( -30999 <=err && err <=-30800 ) \
		ereport(INFO,(errmsg("Error BDB %s:%i err=%i: %s",__FILE__,__LINE__,err,db_strerror(err)))); \
	else 	\
		ereport(INFO,(errmsg("Error C module %s:%i err=%i",__FILE__,__LINE__,err))); \
} while(false)
#endif

#define ob_flux_MVoirDBT(a) ob_flux_voirDBT(stdout,a,1);



#define obCOFPROFONDEUR 3
#define obCMAXCYCLE (1<<obCOFPROFONDEUR)
#define obCGIRTH (obCMAXCYCLE+1)

// it is the girth of the graph.

/*********************************************************************
DB
*********************************************************************/
//#define PATHDBTEST "/tmp/obt"
//#define PATHDBTEMP "/tmp/obt_tmp"
/*********************************************************************
DBT
*********************************************************************/

#define obMDbtR(dbt) DBT dbt;memset(&(dbt),0,sizeof(DBT))
#define obMDbtS(dbt,var) DBT dbt;memset(&(dbt),0,sizeof(DBT)); \
		dbt.size = sizeof(var); \
		dbt.data = &(var)

#define obMDbtU(dbt,var) obMDbtS(dbt,var); \
		dbt.flags = DB_DBT_USERMEM; \
		dbt.ulen = sizeof(var)

#define obMDbtpS(dbt,ptr) DBT dbt;memset(&(dbt),0,sizeof(DBT)); \
		dbt.size = sizeof(*(ptr)); \
		dbt.data = ptr

#define obMDbtpU(dbt,ptr) obMDbtpS(dbt,ptr); \
		dbt.flags = DB_DBT_USERMEM; \
		dbt.ulen = sizeof(*(ptr))

#define obMCloseCursor(cursor) if (cursor) {\
		ret_t = (cursor)->close(cursor);\
		cursor = NULL; \
		if(ret_t) {\
			obMTRACE(ret_t);\
			if(!ret) ret = ret_t;\
		}\
	}


#define obMtDbtR(dbt) memset(&(dbt),0,sizeof(DBT))
#define obMtDbtS(dbt,var) memset(&(dbt),0,sizeof(DBT)); \
		dbt.size = sizeof(var); \
		dbt.data = &(var)

#define obMtDbtU(dbt,var) obMtDbtS(dbt,var); \
		dbt.flags = DB_DBT_USERMEM; \
		dbt.ulen = sizeof(var)

#define obMtDbtpS(dbt,ptr) memset(&(dbt),0,sizeof(DBT)); \
		dbt.size = sizeof(*(ptr)); \
		dbt.data = ptr

#define obMtDbtpU(dbt,ptr) obMtDbtpS(dbt,ptr); \
		dbt.flags = DB_DBT_USERMEM; \
		dbt.ulen = sizeof(*(ptr))
/*********************************************************************
common
*********************************************************************/
/* typedef unsigned long ob_tQtt;
struct ob__Id; typedef struct ob__Id ob_tId;
typedef struct ob__Id ob_tQuaId;
typedef struct ob__Id ob_tOwnId; */
typedef int64 ob_tQtt;
typedef int64 ob_tId;
typedef int64 ob_tQuaId;
typedef int64 ob_tOwnId;


struct ob__Stock;typedef struct ob__Stock ob_tStock;
struct ob__Noeud;typedef struct ob__Noeud ob_tNoeud;
struct ob__No;typedef struct ob__No ob_tNo;
struct ob__Chemin;typedef struct ob__Chemin ob_tChemin;
struct ob__Msg;typedef struct ob__Msg ob_tMsg;

/*
#ifdef obCTESTCHEM

typedef struct  {
	DBC *dbc;
	bool begin;
	DBT ks_nR,ku_Xoid,du_offreX;
	ob_tId Yoid,nR;
	DB_ENV *envt;
} ob_cPortal;
typedef ob_cPortal* ob_tPortal;

#else */
#ifdef obCTEST
struct  PortalData {
	ob_tId yoid,nr;
	ob_tId limit;
	ob_tId nbCallNext;
	ob_tId nbCallArbre;
}  ;
typedef struct PortalData *Portal;

#else

typedef struct PortalData *ob_tPortal;
#endif

//#endif


/*
#define ob_CSIZEID 2

struct ob__Id {
	u_int32_t data[ob_CSIZEID];
};
*/
struct ob__Stock {
	ob_tId sid;
	ob_tOwnId own;
	ob_tQtt qtt;
	ob_tQuaId nF;
	ob_tId version;
} ;

struct ob__Noeud {
	ob_tId oid;
	ob_tId stockId;
	double omega;
	ob_tQuaId nR;
	// data unchanged for the lifetime of the node
	ob_tQuaId nF;
	ob_tId own;
} ;
/* the secondary index of priv->offres are 
	priv->vx_offres
	ob__Noeud.nR extracted by offre_get_nX
	priv->vy_offres
	ob__Noeud.nF extracted by offre_get_nX
*/

struct ob__No {
	// indexed by node
	ob_tNoeud	noeud;
	// double		gain;
	// double		omegaCorrige;
	ob_tQtt		fluxArrondi;
	unsigned char		ownIndex;
	unsigned char		stockIndex;
	// indexed by ownIndex
	ob_tOwnId	own;
	uint32_t	flags;
#define obCNODESIGNED 1
#define obCNODEEXHAUSTED 1<<1 // the accord exhausted the stock
	unsigned char		ownOcc;
	// indexed by stockIndex
	ob_tStock	stock;
	unsigned char		stockOcc;

};
/* for a given index i of offer:
	chemi.no[chemi.no[i].ownIndex].own is the owner
	chemi.no[chemi.no[i].stockIndex].stock is the stock
*/

// #define obMSizeChemi(pchem) (sizeof(ob_tChemin)+(pchem->nbNoeud*sizeof(ob_tNo)))
struct ob__Chemin {
	unsigned char		nbNoeud;
	unsigned char		nbOwn;
	unsigned char		nbStock;
	char		cflags;
	double		prodOmega;
	double		gain;
	ob_tNo		no[]; // nbNoeud
};

struct ob__Msg {
	char* begin;
	size_t size;
	size_t current;
	int error;
};

// min,max length of name of depos and owners
// these limits exclude the termination null character
#define obCMINDEPOS 1
#define obCMAXDEPOS 128
// max length of name of quality
#define obCMINQUALITY 1
#define obCMAXQUALITY 512
// max length of name, 1 for the prefix, 1 for the '/' char
#define obCMAXNAME 1+obCMAXQUALITY+1+obCMAXDEPOS

struct ob__MarqueOffre;typedef struct ob__MarqueOffre ob_tMarqueOffre;
struct ob__Point;typedef struct ob__Point ob_tPoint;
struct ob__Trait;typedef struct ob__Trait ob_tTrait;
struct ob__Fleche;typedef struct ob__Fleche ob_tFleche;
struct ob__Accord;typedef struct ob__Accord ob_tAccord;
struct ob__Interdit;typedef struct ob__Interdit ob_tInterdit;
struct ob__Message;typedef struct ob__Message ob_tMessage;
struct ob__PrivateTemp;typedef struct ob__PrivateTemp ob_tPrivateTemp;
// struct ob__Global;typedef struct ob__Global ob_tGlobal;
// struct ob__Private;typedef struct ob__Private ob_tPrivate;
enum ob__ErrorType;typedef enum ob__ErrorType ob_tErrorType;
struct ob__Mar;typedef struct ob__Mar ob_tMar;
struct ob__Loop;typedef struct ob__Loop ob_tLoop;
struct ob__Batch;typedef struct ob__Batch ob_tBatch;
struct ob__Timer;typedef struct ob__Timer ob_tTimer;


enum ob__ErrorType
{
	DEBUG_TRACE = 0, // for trace
	DEBUG_INFO, // a process requested could not be performed
	DEBUG_WARN, // an error was found on the database that was corrected
	DEBUG_ERR,
	DEBUG_PANIC // whole database integrity is compromized
};

struct ob__Fleche {
	ob_tId Xoid,Yoid;
};

struct ob__Trait { // traits[rid]
	ob_tFleche rid;
	int igraph;
};

struct ob__Mar {
	int layer;
	int igraph;
};
struct ob__MarqueOffre {
	ob_tNoeud offre;
	ob_tMar ar;
	ob_tMar av;
};

struct ob__Point {
	ob_tMarqueOffre mo;
	ob_tChemin chemin;
	ob_tNo	__no[obCMAXCYCLE];
};

struct ob__Loop {
	ob_tFleche rid;
	ob_tId version;
};

struct ob__Accord {
	ob_tId		aid;
	enum { DRAFT=1, DRAFTREFUSE, ACCEPTE, REFUSE } status;
	ob_tId		versionSg,
	// version of the subgraph that produced it
			version_decision;
	int		nbSource;
	ob_tChemin	chemin;
	ob_tNo		__no[obCMAXCYCLE]; // for space reservation
} ;

struct ob__Interdit {
	ob_tFleche 	rid;
	ob_tOwnId	autheur;
	uint32_t	flags;
} ;

struct ob__PrivateTemp {
	int id;
	DB *traits,*px_traits,*py_traits,*m_traits;
	DB *points,*vx_points,*vy_points,*mar_points,*mav_points,*st_points;
	DB *stocktemps;
	unsigned char cflags; // flags for the chemin
	bool deposOffre;
	ob_tId versionSg; // max of stock.version
	ob_tInterdit interdit; // arc interdit, (ret=obCerLoopOnOffer)
	ob_tNoeud *pivot;
	ob_tStock *stockPivot;
};


#endif // defined__common_h
