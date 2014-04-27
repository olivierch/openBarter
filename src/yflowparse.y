%{

/* contrib/yflow/yflowparse.y */

// #define YYPARSE_PARAM resultat  /* need this to pass a pointer (void *) to yyparse */
// #define YYSTYPE char *
#define YYDEBUG 1

#include "postgres.h"

#include "wolf.h"


#define YYMALLOC palloc
#define YYFREE   pfree
extern int 	yflow_yylex(void);

static char 	*scanbuf;
static int	scanbuflen;

extern int	yflow_yyparse(Tflow **resultat);
extern void yflow_yyerror(Tflow **resultat, const char *message);


%}

/* BISON Declarations */
%parse-param {Tflow **resultat}
%expect 0
// %name-prefix="yflow_yy"

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
	O_PAREN FLOWINT COMMA FLOWINT COMMA FLOWINT COMMA FLOWINT COMMA FLOWINT COMMA FLOWINT COMMA FLOWINT COMMA NUMBER C_PAREN {
			Tflow **pf = resultat;
			Tfl s;
	
			// id,oid,own,qtt_requ,qtt_prov,qtt,proba
			s.type = (int32) ($2);
	        if (!ORDER_TYPE_IS_VALID(s.type)) {
                   ereport(ERROR,
                      (errcode(ERRCODE_SYNTAX_ERROR),
                       errmsg("bad order representation in yflow"),
                       errdetail("A order in yflow cannot have type %d.",s.type)));
                   YYABORT;
            }
			s.id = (int32) ($4);
			s.oid = (int32) ($6);
			s.own = (int32) $8;
			s.qtt_requ = $10;
			s.qtt_prov = $12;
			s.qtt = $14;
			s.proba = $16;
			*pf = flowm_extends(&s,*pf,false);
	}


%%



#include "yflowscan.c"
