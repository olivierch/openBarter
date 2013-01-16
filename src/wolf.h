#include "postgres.h"
#include "fmgr.h"
#include "lib/stringinfo.h"
#include "tsearch/ts_type.h" // define TSQuery and TSVector

// #define ACTIVATE_DISTANCE
/* ACTIVATE_FULLTEXT is defined when qua_prov and qua_requ are tsvector and tsquery
when undefines, both are texts
*/
// #define ACTIVATE_FULLTEXT
/******************************************************************************
 * 
 *****************************************************************************/
// maximum length of flow
#define FLOW_MAX_DIM (64)
#define obMRange(v,S) for ((v)=0;(v)<(S);(v)++)

/* used to compare two Datum representing a text */
#define IDEMTXT(a,b,res) \
do { \
	int32 __i = VARSIZE(a); \
	if(__i != VARSIZE(b)) res = false; \
	else { \
		if(memcmp(VARDATA(a),VARDATA(b),__i-VARHDRSZ) == 0) res = true; \
		else res = false; \
	} \
} while(0)


#define DATUM_TO_STR(d,s) \
do { \
	int __i = VARSIZE(d); \
	s = palloc(__i+1); \
	memcpy(s,VARDATA(d),__i); \
	s[__i] = '\0'; \
} while(0);

/******************************************************************************
 * 
 *****************************************************************************/
#define GL_VERIFY
/******************************************************************************
 * 
 *****************************************************************************/

// defines the status of the flow
typedef enum Tstatusflow {
	empty, // flow empty, ( dim==0 or some qtt ==0 )
	noloop, //  end.np != begin.nr
	refused, // refused OMEGA < 1
	undefined, // no solution found, (rounding did not find any solution)
	draft // solution found, accepted
} Tstatusflow;

typedef struct Torder {
	int 	id;
	Datum 	own; // text
	int		oid;
	int64	qtt_requ;
	Datum	qua_requ; // text or tsquery
	#ifdef 	ACTIVATE_DISTANCE
	Point   pos_requ;
	#endif
	int64	qtt_prov;
	Datum	qua_prov; // text or tsvector
	#ifdef 	ACTIVATE_DISTANCE
	Point	pos_prov;
	#endif
	int64	qtt;
	int64	flowr;
	#ifdef  ACTIVE_DISTANCE
	double	dist;
	#endif
} Torder;

typedef struct Twolf {
	short 		dim;
	Datum		*alld; // Datum to be freed
	Torder		x[];
} Twolf;

typedef struct TresChemin {
	bool	lastignore;
	Tstatusflow status;
	short	nbOwn; 
	short 	occOwn[FLOW_MAX_DIM];
	short   ownIndex[FLOW_MAX_DIM]; 
	double	gain,prodOmega;
	Twolf 	*wolf;
	double 	omegaCorrige[FLOW_MAX_DIM],fluxExact[FLOW_MAX_DIM],piom[FLOW_MAX_DIM],omega[FLOW_MAX_DIM]; 
	int64	flowNodes[FLOW_MAX_DIM]; // result == Torder.flowr
	int64	floor[FLOW_MAX_DIM];
} TresChemin;

/******************************************************************************
 * 
 *****************************************************************************/
// looks like NDBOX of cube extension
typedef struct Tcarre {
	int32		vl_len_;		/* varlena header (do not touch directly!) */
	unsigned int dim;
	double		latmin,latmax,lonmin,lonmax;
} Tcarre;

typedef struct Tpoint {
	int32		vl_len_;		/* varlena header (do not touch directly!) */
	unsigned int dim;
	double		x,y;
} Tpoint;
#define PG_RETURN_NDBOX(x)	PG_RETURN_POINTER(x)

/******************************************************************************
 * 
 *****************************************************************************/
extern char * wolfc_vecIntStr(short dim,int64 *vecInt);
extern char * wolfc_vecDoubleStr(short dim,double *vecDouble);
extern TresChemin *wolfc_maximum(Twolf *wolf);
extern char * wolfc_cheminToStr(TresChemin *chem);

extern bool follow_orders(Torder *prev,Torder *next);
extern double follow_rank(bool end,Torder *prev,Torder *next);
extern char *follow_qua_provToStr(Datum d);
extern char *follow_qua_requToStr(Datum d);
extern char *follow_DatumTxtToStr(Datum d);


extern bool tsquery_match_vq(TSVector val,TSQuery query);

extern char *ywolf_allToStr(Twolf *wolf);
extern char *ywolf_statusToStr(Tstatusflow s);

extern double earth_distance_internal(Tpoint *pt1, Tpoint *pt2);


