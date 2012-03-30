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


typedef struct Torder {
	int64	qtt_prov,qtt_requ,qtt;
	int32	id,own,np,nr;
} Torder; // sizeof(Torder)=40

typedef struct Tno {
	double 	omega;
	short 	ownIndex;
} Tno;

// defines the status of the flow
typedef enum Tstatusflow {
	empty, // flow empty
	noloop, //  end.np != begin.nr
	refused, // refused OMEGA < 1
	undefined, // no solution found, (rounding did not find any solution)
	draft // solution found, accepted
} Tstatusflow;

typedef struct Tflow {
	short 		dim;
	bool		lastignore;
	Torder		x[FLOW_MAX_DIM];
	// set by set by flowc_maximum
	Tstatusflow	status; 
	int64		flowr[FLOW_MAX_DIM];
} Tflow; // sizeof(Tflow)=392 when FLOW_MAX_DIM=8


typedef struct ob_tGlobales {
	bool verify;
} ob_tGlobales;
extern ob_tGlobales globales; //defined in flow.c


extern Tstatusflow flowc_maximum(Tflow *box);
extern char *flowc_toStr(Tflow *box);

extern char *yflow_ndboxToStr(Tflow *flow,bool internal);
extern char *yflow_statusBoxToStr(Tflow *flow);
 

