%{
/* NdBox = [(lowerleft),(upperright)] */
/* [(xLL(1)...xLL(N)),(xUR(1)...xUR(n))] */

/* contrib/flow/flowparse.y */

#define YYPARSE_PARAM result  /* need this to pass a pointer (void *) to yyparse */
// #define YYSTYPE char *
#define YYDEBUG 1

#include "postgres.h"

#include "flowdata.h"

/*
 * Bison doesn't allocate anything that needs to live across parser calls,
 * so we can easily have it use palloc instead of malloc.  This prevents
 * memory leaks if we error out during parsing.  Note this only works with
 * bison >= 2.0.  However, in bison 1.875 the default is to use alloca()
 * if possible, so there's not really much problem anyhow, at least if
 * you're building with gcc.
 */
#define YYMALLOC palloc
#define YYFREE   pfree
#define BID_DIM  8
extern int 	flow_yylex(void);

static char 	*scanbuf;
static int	scanbuflen;

void 	flow_yyerror(const char *message);
int 	flow_yyparse(void *result);

static NDBOX * add_bid(NDBOX *result, int64 *vals);
extern NDBOX * Ndbox_enlarge(NDBOX *box);


%}

/* BISON Declarations */
%expect 0
%name-prefix="flow_yy"

%union {
  struct BND {
    int64 vals[9];
    int dim;
  } bnd;
  STATUSNDBOX status;
  char * text;
}
%token <text> O_PAREN
%token <text> C_PAREN
%token <text> O_BRACKET
%token <text> C_BRACKET
%token <text> COMMA
%token <text>  FLOWINT
%token <status> STATUS
%type  <bnd>  list
%start box

/* Grammar follows */
%%

box:
	O_BRACKET C_BRACKET {
          	//empty
          }
          |
          O_BRACKET bid_list C_BRACKET {
          	//((NDBOX * )result)->status = $2;
          	//flow_compute((NDBOX * )result);
          }
      ;
      
bid_list:	
	bid {
		;
	}
	|
	bid_list COMMA bid {
	    if (((NDBOX * )result)->dim > FLOW_MAX_DIM) {
              ereport(ERROR,
                      (errcode(ERRCODE_SYNTAX_ERROR),
                       errmsg("bad flow representation"),
                       errdetail("A flow cannot have more than %d bids.",FLOW_MAX_DIM)));
              YYABORT;
            }
	}
	
bid:	
	O_PAREN list C_PAREN {
		
		if($2.dim != BID_DIM) {
			ereport(ERROR,
			      (errcode(ERRCODE_SYNTAX_ERROR),
			       errmsg("bad bid representation"),
			       errdetail("A bid should have %d elements.",BID_DIM)));
			YYABORT;
		}
		add_bid(result,$2.vals);
	}

list: 
          FLOWINT {
		$$.dim = 0;
		$$.vals[$$.dim] = atoll($1);
		$$.dim += 1;
	  }
      |
	  list COMMA FLOWINT {
		if ($$.dim >= BID_DIM) {
		
		ereport(ERROR,
		      (errcode(ERRCODE_SYNTAX_ERROR),
		       errmsg("bad bid representation"),
		       errdetail("A bid should have %d elements.",BID_DIM)));
		YYABORT;
		}
		//elog(WARNING,"red \"%lli\" ",atoll($3));	  	
		$$.vals[$$.dim] = atoll($3);
		$$.dim += 1;
	  }
      ;

%%

static NDBOX * add_bid(NDBOX *box, int64 *vals) {
	int i;
	BID *s;
	NDBOX *newbox = box;
	
	// newbox = Ndbox_enlarge(box);
	s = &newbox->x[box->dim];
	box->dim +=1;
	
	// id,nr,qtt_prov,qtt_requ,sid,own,qtt,np
	i = 0;
	s->id = vals[i];i +=1;
	s->nr = vals[i];i +=1;
	s->qtt_prov = vals[i];i +=1;
	s->qtt_requ = vals[i];i +=1;
	s->sid = vals[i];i +=1;
	s->own = vals[i];i +=1;
	s->qtt = vals[i];i +=1;
	s->np = vals[i];i +=1;
	s->flowr = 0;
	return newbox;	
	
}


#include "flowscan.c"
