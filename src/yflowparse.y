%{

/* contrib/yflow/yflowparse.y */

#define YYPARSE_PARAM resultat  /* need this to pass a pointer (void *) to yyparse */
// #define YYSTYPE char *
#define YYDEBUG 1

#include "postgres.h"

#include "wolf.h"

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
extern int 	yflow_yylex(void);

static char 	*scanbuf;
static int	scanbuflen;

void 	yflow_yyerror(const char *message);
int 	yflow_yyparse(void *resultat);


%}

/* BISON Declarations */
%expect 0
%name-prefix="yflow_yy"

%union {
  char * text;
  double dval;
  int64	 in;
}
%token <text> O_PAREN
%token <text> C_PAREN
%token <text> O_BRACKET
%token <text> C_BRACKET
%token <text> COMMA
%token <in>  FLOWINT
%token <dval>  NUMBER
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
	O_PAREN FLOWINT COMMA FLOWINT COMMA FLOWINT COMMA FLOWINT COMMA FLOWINT COMMA FLOWINT COMMA NUMBER C_PAREN {
			Tflow **pf = resultat;
			Tfl s;
	
			// id,oid,own,qtt_requ,qtt_prov,qtt,proba

			s.id = (int32) ($2);
			s.oid = (int32) ($4);
			s.own = (int32) $6;
			s.qtt_requ = $8;
			s.qtt_prov = $10;
			s.qtt = $12;
			s.proba = $14;
			*pf = flowm_extends(&s,*pf,false);
	}


%%



#include "yflowscan.c"
