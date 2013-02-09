#include "postgres.h"
#include "fmgr.h"
#include "lib/stringinfo.h"
#include "utils/array.h"
// #include "tsearch/ts_type.h" // define TSQuery and TSVector

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

#define PG_GETARG_TFLOW(x)	((Tflow*)PG_GETARG_POINTER(x))
#define PG_RETURN_TFLOW(x)	PG_RETURN_POINTER(x)

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

#define GET_OMEGA(b) (((double)(b.qtt_prov)) / ((double)(b.qtt_requ)))
#define GET_OMEGA_P(b) (((double)(b->qtt_prov)) / ((double)(b->qtt_requ)))
/******************************************************************************
 * 
 *****************************************************************************/
#define GL_VERIFY
/******************************************************************************
 * 
 *****************************************************************************/
#define ORDER_LIMIT 1
#define ORDER_BEST  2

#define ORDER_TYPE_MASK 3

#define ORDER_NOQTTLIMIT 4 // ORDER_TYPE_MASK+1
#define ORDER_IGNOREOMEGA 8

#define ORDER_TYPE(o) ((o) & ORDER_TYPE_MASK)
#define ORDER_IS_NOQTTLIMIT(o) ((o) & ORDER_NOQTTLIMIT)
#define ORDER_IS_IGNOREOMEGA(o) ((o) & ORDER_IGNOREOMEGA)

#define ORDER_TYPE_IS_VALID(o) ((0 < (o)) && ((o) <= 15))

#define FLOW_IS_NOQTTLIMIT(f) ORDER_IS_NOQTTLIMIT(((f)->x[(f)->dim-1].type))
#define FLOW_IS_IGNOREOMEGA(f) ORDER_IS_IGNOREOMEGA(((f)->x[(f)->dim-1].type))

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
	Datum	qua_requ; // text 
	int64	qtt_prov;
	Datum	qua_prov; // text 
	int64	qtt;
	int64	flowr;
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
	bool	lnNoQttLimit;
	bool	lnIgnoreOmega;
	Tstatusflow status;
	short	nbOwn; 
	short 	occOwn[FLOW_MAX_DIM];
	short   ownIndex[FLOW_MAX_DIM]; 
	double	gain,prodOmega;
	Tflow 	*flow;
	double 	omegaCorrige[FLOW_MAX_DIM],fluxExact[FLOW_MAX_DIM],piom[FLOW_MAX_DIM],omega[FLOW_MAX_DIM]; 
	int64	flowNodes[FLOW_MAX_DIM]; // result == Torder.flowr
	int64	floor[FLOW_MAX_DIM];
} TresChemin;

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
extern bool yorder_match(Torder *prev,Torder *next);
extern bool yorder_matche(Datum *prev,Datum *next);
extern double yorder_match_proba(Torder *prev,Torder *next);


