%{

/* contrib/yflow/yflowparse.y */

#define YYPARSE_PARAM resultat  /* need this to pass a pointer (void *) to yyparse */
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
#define BID_DIM  7
extern int 	yflow_yylex(void);

static char 	*scanbuf;
static int	scanbuflen;

void 	yflow_yyerror(const char *message);
int 	yflow_yyparse(void *resultat);

void add_order(Tflow **pf, int64 *vals);


%}

/* BISON Declarations */
%expect 0
%name-prefix="yflow_yy"

%union {
  struct BND {
    int64 vals[BID_DIM];
    int dim;
  } bnd;
  char * text;
}
%token <text> O_PAREN
%token <text> C_PAREN
%token <text> O_BRACKET
%token <text> C_BRACKET
%token <text> COMMA
%token <text>  FLOWINT
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
          	//((Tflow * )result)->lastRelRefused = $2;
          	//yflow_compute((Tflow * )result);
             }
      ;
      
bid_list:	
	    bid {
		;
	    }
	|
	    bid_list COMMA bid {
	    	Tflow **pf = resultat;
	        if ((*pf)->dim > FLOW_MAX_DIM) {
                   ereport(ERROR,
                      (errcode(ERRCODE_SYNTAX_ERROR),
                       errmsg("bad yflow representation"),
                       errdetail("A yflow cannot have more than %d orders.",FLOW_MAX_DIM)));
                   YYABORT;
                }
	}
	
bid:	
	O_PAREN list C_PAREN {
		
		if($2.dim != BID_DIM) {
			ereport(ERROR,
			      (errcode(ERRCODE_SYNTAX_ERROR),
			       errmsg("bad order representation"),
			       errdetail("An order should have %d elements.",BID_DIM)));
			YYABORT;
		}
		add_order(resultat,$2.vals);
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
			       errmsg("bad order representation"),
			       errdetail("An order should have %d elements.",BID_DIM)));
			YYABORT;
		}
		//elog(WARNING,"red \"%lli\" ",atoll($3));	  	
		$$.vals[$$.dim] = atoll($3);
		$$.dim += 1;
	  }
      ;

%%

void add_order(Tflow **pf, int64 *vals) {
	int i;
	Torder *s;
	Tflow *box = *pf;
	
	s = &box->x[box->dim];
	box->dim +=1;
	
	// id,own,nr,qtt_requ,np,qtt_prov,qtt
	i = 0;
	s->id = (int32) vals[i];i +=1;
	s->own = (int32) vals[i];i +=1;
	s->nr = (int32) vals[i];i +=1;
	s->qtt_requ = vals[i];i +=1;
	s->np = (int32) vals[i];i +=1;
	s->qtt_prov = vals[i];i +=1;
	s->qtt = vals[i];i +=1;
	*pf = box;
	return;	
	
}


#include "yflowscan.c"
