#include "postgres.h"
#include "fmgr.h"
#include "lib/stringinfo.h"
#include "utils/array.h"
#include "utils/geo_decls.h"	/* for Point and Box*/

/******************************************************************************
 * 
 *****************************************************************************/
// maximum length of flow
#define FLOW_MAX_DIM (64)
#define obMRange(v,S) for ((v)=0;(v)<(S);(v)++)

#define PG_GETARG_TFLOW(x)	((Tflow*)PG_GETARG_POINTER(x))
#define PG_RETURN_TFLOW(x)	PG_RETURN_POINTER(x)

#define DATUM_TO_STR(d,s) \
do { \
	int __i = VARSIZE(d); \
	s = palloc(__i+1); \
	memcpy(s,VARDATA(d),__i); \
	s[__i] = '\0'; \
} while(0)

#define GET_OMEGA(b) (((double)(b.qtt_prov)) / ((double)(b.qtt_requ)))
#define GET_OMEGA_P(b) (((double)(b->qtt_prov)) / ((double)(b->qtt_requ)))
/******************************************************************************
 * 
 *****************************************************************************/
#define GL_VERIFY
// #define WHY_REJECTED
/******************************************************************************
 * 
 *****************************************************************************/
#define ORDER_LIMIT 1
#define ORDER_BEST  2

#define ORDER_TYPE_MASK 3

#define ORDER_NOQTTLIMIT 4 // ORDER_TYPE_MASK+1
#define ORDER_IGNOREOMEGA 8
/* reserved for pl/pgsql , but not used in c
#define ORDER_REMOVE 32
#define ORDER_PREQUOTE 64
#define ORDER_QUOTE 128
*/

#define ORDER_TYPE(o) 	((o) & ORDER_TYPE_MASK)
#define BIT_IS_SET(o,m)	(((o) & m) == m)

#define ORDER_IS_NOQTTLIMIT(o) 	BIT_IS_SET(o,ORDER_NOQTTLIMIT)
#define ORDER_IS_IGNOREOMEGA(o) BIT_IS_SET(o,ORDER_IGNOREOMEGA)
/*#define ORDER_IS_PREQUOTE(o) 	BIT_IS_SET(o,ORDER_PREQUOTE)
#define ORDER_IS_QUOTE(o) 		BIT_IS_SET(o,ORDER_QUOTE)
*/
#define ORDER_TYPE_IS_VALID(o) ((0 < (o)) && ((o) <= 256))

#define FLOW_TYPE(f) ((f)->x[(f)->dim-1].type)

#define FLOW_IS_NOQTTLIMIT(f) 	ORDER_IS_NOQTTLIMIT(FLOW_TYPE(f))
#define FLOW_IS_IGNOREOMEGA(f) 	ORDER_IS_IGNOREOMEGA(FLOW_TYPE(f))
/*#define FLOW_IS_PREQUOTE(f) 	ORDER_IS_PREQUOTE(FLOW_TYPE(f))
#define FLOW_IS_QUOTE(f) 		ORDER_IS_QUOTE(FLOW_TYPE(f))
*/
#define OB_PRECISION 1.E-12
#define QTTFLOW_UNDEFINED -1
/******************************************************************************
 * yorder_checktxt
 *****************************************************************************/
#define TEXT_NOT_EMPTY 1
#define TEXT_PREFIX_NOT_EMPTY 2
#define TEXT_SUFFIX_NOT_EMPTY 4

// defines the status of the flow
typedef enum Tstatusflow {
	empty, // flow empty, ( dim==0 or some qtt ==0 )
	noloop, //  end.np != begin.nr
	refused, // refused OMEGA < 1
	undefined, // no solution found, (rounding did not find any solution)
	draft // solution found, accepted
} Tstatusflow;

typedef enum TypeFlow {
	CYCLE_LIMIT = ORDER_LIMIT,
	CYCLE_BEST = ORDER_BEST
} TypeFlow;

typedef struct Torder {
	int		type;
	int 	id;
	int 	own; 
	int		oid;
	int64	qtt_requ;
	// HStore	*qua_requ;
	Datum	qua_requ;
	int64	qtt_prov;
	// HStore	*qua_prov;
	Datum   qua_prov;
	int64	qtt;
	int64	flowr;

	Point   pos_requ;
	Point	pos_prov;
	double	dist;
} Torder;

typedef struct Tfl {
	int64	qtt_prov,qtt_requ,qtt;
	double 	proba;
	int32 	type;
	int32	id,oid,own;
	int64 	flowr;
} Tfl; 

typedef struct Tflow {
	int32		vl_len_;		/* varlena header (do not touch directly!) */
	short 		dim;
	//TypeFlow	type;
	Tfl			x[FLOW_MAX_DIM];
} Tflow; // sizeof(Tflow)=392 when FLOW_MAX_DIM=8

typedef struct TresChemin {
	TypeFlow	type;
	//bool	lnNoQttLimit;
	//bool	lnIgnoreOmega;
	//bool	lnQuote;
	Tstatusflow status;
	short	nbOwn; 
	short 	occOwn[FLOW_MAX_DIM];
	short   ownIndex[FLOW_MAX_DIM]; 
	// double	gain;
	//double  prodOmega;
	Tflow 	*flow;
	double 	omegaCorrige[FLOW_MAX_DIM],fluxExact[FLOW_MAX_DIM],piom[FLOW_MAX_DIM],omega[FLOW_MAX_DIM]; 
	int64	flowNodes[FLOW_MAX_DIM]; // result == Torder.flowr
	int64	floor[FLOW_MAX_DIM];
	// int64	qttAv[FLOW_MAX_DIM];
} TresChemin;


/******************************************************************************
geographic representations

native type Point of postgres
    Point(latitude,longitude) in radians
double distance in radians
    
cube extension of postgres to represent a square on the sphere
    '(latmin,lonmax),(latmax,lonmax)'::cube in SQL
    is the same as Tsquare(latmin,lonmin,latmax,lonmax)
    
cube_s0 is a cube where min==max with a surface 0



******************************************************************************/
/* defined in geo_delcs.h

typedef struct
{
	double		x,
				y;
} Point;

typedef struct
{
	Point		high,
				low;	// sorted		
} BOX;

#define DatumGetBoxP(X)    ((BOX *) DatumGetPointer(X))
#define BoxPGetDatum(X)    PointerGetDatum(X)
#define PG_GETARG_BOX_P(n) DatumGetBoxP(PG_GETARG_DATUM(n))
#define PG_RETURN_BOX_P(x) return BoxPGetDatum(x)

index gist(box), pas d'extension
*/
typedef struct { // cube dim2
	int32		vl_len_;		/* varlena header (do not touch directly!) */
	unsigned int dim;
	double		latmin,lonmin,latmax,lonmax;
} Tsquare;

#define DatumGetTsquareP(x)	    ((Tsquare*)DatumGetPointer(x))
#define PG_GETARG_TSQUARE(x)	((Tsquare*)PG_GETARG_POINTER(x))
#define PG_RETURN_TSQUARE(x)	PG_RETURN_POINTER(x)


#ifdef GL_VERIFY
#define GL_CHECK_BOX_S0(s) \
do { \
	if(!((s->low.x == s->high.x) && (s->low.y == s->high.y))) \
    		ereport(ERROR, \
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED), \
			errmsg("box_s0 is expected"))); \
} while(0)
#else
#define GL_CHECK_BOX_S0(s)
#endif

/* for the cube extension, we have:
typedef struct NDBOX
{
	int32		vl_len_;		// varlena header (do not touch directly!) 
	unsigned int dim;
	double		x[1];
} NDBOX;

#define DatumGetNDBOX(x)	((NDBOX*)DatumGetPointer(x))
#define PG_GETARG_NDBOX(x)	DatumGetNDBOX( PG_DETOAST_DATUM(PG_GETARG_DATUM(x)) )
#define PG_RETURN_NDBOX(x)	PG_RETURN_POINTER(x)
*/

/******************************************************************************
 * 
 *****************************************************************************/

extern char * flowc_vecIntStr(short dim,int64 *vecInt);
extern char * flowc_vecDoubleStr(short dim,double *vecDouble);
extern TresChemin *flowc_maximum(Tflow *flow);
extern char * flowc_cheminToStr(TresChemin *chem);

extern char *yflow_statusToStr(Tstatusflow s);
extern char *yflow_typeToStr (int32 t);
extern char *yflow_ndboxToStr(Tflow *flow,bool internal);

extern Tflow *flowm_cextends(Tfl *o,Tflow *f, bool before);
extern Tflow *flowm_extends(Tfl *o,Tflow *f, bool before);
extern Tflow *flowm_copy(Tflow *f);
extern Tflow *flowm_init(void);

extern void yorder_get_order(Datum eorder,Torder *orderp);
extern void yorder_to_fl(Torder *o,Tfl *fl);
extern bool yorder_checktxt(Datum texte);
extern bool yorder_match(Torder *prev,Torder *next);
// extern bool yorder_match_quality(HStore *qprov,HStore *qrequ);
extern bool yorder_match_quality(Datum qprov,Datum qrequ);

//extern bool yorder_matche(Datum *prev,Datum *next);
extern double yorder_match_proba(Torder *prev,Torder *next);

extern double earth_points_distance(Point *pt1, Point *pt2);
extern int earth_check_point(Point *p);
extern int earth_check_dist(double d);
extern bool earth_match_position(double dist,Point *pos_prov,Point *pos_requ);


