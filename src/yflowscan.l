%{
/*
 * A scanner for EMP-style numeric ranges
 * contrib/yflow/yflowscan.l
 */

#include "postgres.h"

/* No reason to constrain amount of data slurped */
#define YY_READ_BUF_SIZE 16777216

/*
 * flex emits a yy_fatal_error() function that it calls in response to
 * critical errors like malloc failure, file I/O errors, and detection of
 * internal inconsistency.  That function prints a message and calls exit().
 * Mutate it to instead call our handler, which jumps out of the parser.
 */
#undef fprintf
#define fprintf(file, fmt, msg) yflow_flex_fatal(msg)

/* Handles to the buffer that the lexer uses internally */
static YY_BUFFER_STATE scanbufhandle;
static char *scanbuf; 
static int	scanbuflen; 

/* flex 2.5.4 doesn't bother with a decl for this */
int yflow_yylex(void);

void yflow_scanner_init(const char *str);
void yflow_scanner_finish(void);
static int yflow_flex_fatal(const char *msg);
/*
([0-9]+|([0-9]*\.[0-9]+)([eE][-+]?[0-9]+)?)
*/
%}

%option 8bit
%option never-interactive
%option nodefault
%option noinput
%option nounput
%option noyywrap
%option prefix="yflow_yy"


%%

([0-9]*\.[0-9]+)([eE][-+]?[0-9]+)? 	{
		yylval.dval = atof(yflow_yytext);
		return NUMBER;
		}
([0-9]+)    {
		yylval.in = atoll(yflow_yytext); return FLOWINT;
		}
\[           yylval.text = "("; return O_BRACKET;
\]           yylval.text = ")"; return C_BRACKET;
\(           yylval.text = "("; return O_PAREN;
\)           yylval.text = ")"; return C_PAREN;
\,           yylval.text = ")"; return COMMA;
[ \t\n\r\f]+ /* discard spaces */
.            return yflow_yytext[0]; /* alert parser of the garbage */

%%

void
yflow_yyerror(Tflow **resultat, const char *message)
{
	if (*yflow_yytext == YY_END_OF_BUFFER_CHAR)
	{
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				 errmsg("bad yflow representation"),
				 /* translator: %s is typically "syntax error" */
				 errdetail("%s at end of input", message)));
	}
	else
	{
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				 errmsg("bad yflow representation"),
				 /* translator: first %s is typically "syntax error" */
				 errdetail("%s at or near \"%s\"", message, yflow_yytext)));
	}
}


/*
 * Called before any actual parsing is done
 */
void
yflow_scanner_init(const char *str)
{
	Size	slen = strlen(str);

	/*
	 * Might be left over after ereport()
	 */
	if (YY_CURRENT_BUFFER)
		yy_delete_buffer(YY_CURRENT_BUFFER);

	/*
	 * Make a scan buffer with special termination needed by flex.
	 */
	scanbuflen = slen;
	scanbuf = palloc(slen + 2);
	memcpy(scanbuf, str, slen);
	scanbuf[slen] = scanbuf[slen + 1] = YY_END_OF_BUFFER_CHAR;
	scanbufhandle = yy_scan_buffer(scanbuf, slen + 2);

	BEGIN(INITIAL);
}


/*
 * Called after parsing is done to clean up after yflow_scanner_init()
 */
void
yflow_scanner_finish(void)
{
	yy_delete_buffer(scanbufhandle);
	pfree(scanbuf);
}

static int
yflow_flex_fatal(const char *msg)
{
	elog(FATAL, "%s\n",msg);
	return 0;	/* keep compiler quiet */
}
