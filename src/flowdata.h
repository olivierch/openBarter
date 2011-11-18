/* contrib/flow/flowdata.h */

#define FLOW_MAX_DIM (8)
#define obMRange(v,S) for (v=0;v<(S);v++)


typedef struct BID {
	int64	id,nr,qtt_prov,qtt_requ,sid,own,qtt,np,flowr;
} BID;
//typedef BID SBID;

typedef struct ob_tNo {
	double 	omega;
	int	flags;
	int 	stockIndex,ownIndex;
} ob_tNo;


typedef enum STATUSNDBOX {
	empty,noloop,loop,draft,undefined
} STATUSNDBOX;

typedef struct NDBOX
{
	int32		vl_len_; /* varlena header (do not touch directly!) */
	unsigned int dim;
	STATUSNDBOX	status;
	BID	x[1];
} NDBOX;

#define ob_flux_CLastIgnore 	(32<<0)
#define ob_flux_CVerify 	(32<<1)
typedef struct ob_tChemin {
	int 		cflags;
	// cflags = or of ob_flux_*
	int		nbOwn,nbStock;
	int *		occOwn,*occStock;
	double	gain,prodOmega;
	NDBOX *	box;
	double *	omegaCorrige,*fluxExact,*piom,*spiom;
	ob_tNo	no[];
	
} ob_tChemin;


typedef struct ob_tGlobales {
	bool verify;
} ob_tGlobales;
extern ob_tGlobales globales; //defined in flow.c

#define DatumGetNDBOX(x)	((NDBOX*)DatumGetPointer(x))
#define PG_GETARG_NDBOX(x)	DatumGetNDBOX( PG_DETOAST_DATUM(PG_GETARG_DATUM(x)) )
#define PG_RETURN_NDBOX(x)	PG_RETURN_POINTER(x)
#define SIZE_NDBOX(dim)		(offsetof(NDBOX, x[0])+(dim)*sizeof(BID))

extern void 	flowc_maximum(NDBOX *box,bool verify);
extern double 	flowc_getProdOmega(NDBOX *box);
extern char *flow_ndboxToStr(NDBOX *flow,bool internal);
extern char * flowc_cheminToStr(ob_tChemin *pchemin);
extern bool flowc_idInBox(NDBOX *box,int64 id);
