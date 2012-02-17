/* contrib/flow/flowdata.h */

#define FLOW_MAX_DIM (8)
#define FLOW_MAX_REFUSED (30)
#define obMRange(v,S) for (v=0;v<(S);v++)


typedef struct BID {
	//int64	id,nr,qtt_prov,qtt_requ,sid,own,qtt,np,flowr;
	int64	id,nr,qtt_prov,qtt_requ,own,qtt,np,flowr;
} BID;
//typedef BID SBID;

typedef struct ob_tNo {
	double 	omega;
	int	flags;
	int 	stockIndex,ownIndex;
} ob_tNo;


typedef enum STATUSNDFLOW {
	noloop, // it is not a loop perhaps empty
	draft, // solution found, accepted
	refused, // solution found, refused
	undefined // no solution found, (rounding did not find any solution)
} STATUSNDFLOW;

typedef struct NDFLOW {
	int32		vl_len_; /* varlena header (do not touch directly!) */
	unsigned int dim;
	STATUSNDFLOW	status;
	int 	iworst; // defined when status=refused, iworst is the index refused
	BID	x[1];
} NDFLOW;

#define ob_flux_CLastIgnore 	(32<<0)
#define ob_flux_CVerify 	(32<<1)
typedef struct ob_tChemin {
	int 	cflags;
	// cflags = or of ob_flux_*
	int	nbOwn; //,nbStock;
	int 	occOwn[FLOW_MAX_DIM]; //,occStock[FLOW_MAX_DIM];
	double	gain,prodOmega;
	NDFLOW 	*box;
	double 	omegaCorrige[FLOW_MAX_DIM],fluxExact[FLOW_MAX_DIM],piom[FLOW_MAX_DIM]; //,spiom[FLOW_MAX_DIM];
	int64	flowNodes[FLOW_MAX_DIM]; //,flowStocks[FLOW_MAX_DIM],
	int64	floor[FLOW_MAX_DIM];
	ob_tNo	no[FLOW_MAX_DIM];
	
} ob_tChemin;

typedef struct FTCOMMIT {
	struct {
		int64 qtt_r,nr,qtt_p,np;
	} c[FLOW_MAX_DIM];
} FTCOMMIT;


typedef struct ob_tGlobales {
	bool verify;
} ob_tGlobales;
extern ob_tGlobales globales; //defined in flow.c

#define DatumGetNDFLOW(x)	((NDFLOW*)DatumGetPointer(x))
#define PG_GETARG_NDFLOW(x)	DatumGetNDFLOW( PG_DETOAST_DATUM(PG_GETARG_DATUM(x)) )
#define PG_RETURN_NDFLOW(x)	PG_RETURN_POINTER(x)
#define SIZE_NDFLOW(dim)	(offsetof(NDFLOW, x[0])+(dim)*sizeof(BID))

extern bool 	flowc_maximum(NDFLOW *box,bool verify);
extern double 	flowc_getProdOmega(NDFLOW *box);
extern double 	flowc_getpOmega(NDFLOW *box);
extern char *flow_ndboxToStr(NDFLOW *flow,bool internal);
extern char * flowc_cheminToStr(ob_tChemin *pchemin);
extern bool flowc_idInBox(NDFLOW *box,int64 id);
extern bool flowc_isCycle(NDFLOW *box);
// extern int flowc_refused(NDFLOW *box);
