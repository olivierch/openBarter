/*
 * 
 *
 ******************************************************************************

******************************************************************************/
// maximum length of flow
#define FLOW_MAX_DIM (8)
#define obMRange(v,S) for ((v)=0;(v)<(S);(v)++)

#define PG_GETARG_TFLOW(x)	((Tflow*)PG_GETARG_POINTER(x))
#define PG_RETURN_TFLOW(x)	PG_RETURN_POINTER(x)

#define  PG_GETARG_TORDER(x)	((Torder*)PG_GETARG_POINTER(x))
#define PG_RETURN_TORDER(x)	PG_RETURN_POINTER(x)

/*
#define GL_VERIFY
#define GL_WARNING_FOLLOW
#define GL_WARNING_GET
*/

typedef struct Torder {
	int64	qtt_prov,qtt_requ,qtt;
	int32	id,own,np,nr;
	int64 	flowr;
} Torder; 

typedef struct Tno {
	double 	omega;
	short 	ownIndex;
} Tno;

// defines the status of the flow
typedef enum Tstatusflow {
	empty, // flow empty, ( dim==0 or some qtt ==0 )
	noloop, //  end.np != begin.nr
	refused, // refused OMEGA < 1
	undefined, // no solution found, (rounding did not find any solution)
	draft // solution found, accepted
} Tstatusflow;

typedef struct Tflow {
	int32		vl_len_;		/* varlena header (do not touch directly!) */
	short 		dim;
	bool		lastignore;
	Tstatusflow	status; 
	Torder		x[FLOW_MAX_DIM];
	// status and x[.].flowr are set by set by flowc_maximum
} Tflow; // sizeof(Tflow)=392 when FLOW_MAX_DIM=8

/*
typedef struct ob_tGlobales {
	bool verify;
	bool warning_follow;
	bool warning_get;
} ob_tGlobales;
extern ob_tGlobales globales; //defined in yflow.c
*/

extern Tstatusflow flowc_maximum(Tflow *box);
extern char *flowc_toStr(Tflow *box);

extern char *yflow_ndboxToStr(Tflow *flow,bool internal);
extern char *yflow_statusBoxToStr(Tflow *flow);

extern Tflow *flowm_cextends(Torder *o,Tflow *f, bool before);
extern Tflow *flowm_extends(Torder *o,Tflow *f, bool before);
extern Tflow *flowm_copy(Tflow *f);
extern Tflow *flowm_init(void);
// extern Tflow *flowm_8(void);
 

