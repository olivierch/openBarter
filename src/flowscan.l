%{
/*
 * A scanner for EMP-style numeric ranges
 * contrib/flow/flowscan.l
 */

#include "postgres.h"

/* No reason to constrain amount of data slurped */
#define YY_READ_BUF_SIZE 16777216

/* Avoid exit() on fatal scanner errors (a bit ugly -- see yy_fatal_error) */
#undef fprintf
#define fprintf(file, fmt, msg)  ereport(ERROR, (errmsg_internal("%s", msg)))

/* Handles to the buffer that the lexer uses internally */
static YY_BUFFER_STATE scanbufhandle;
static char *scanbuf; 
static int	scanbuflen; 

/* flex 2.5.4 doesn't bother with a decl for this */
int flow_yylex(void);

void flow_scanner_init(const char *str);
void flow_scanner_finish(void);
%}

%option 8bit
%option never-interactive
%option nodefault
%option noinput
%option nounput
%option noyywrap
%option prefix="flow_yy"


n            [0-9]+
integer      [+-]?{n}
%%
draft 		yylval.status = draft; return STATUS;
refused 	yylval.status = refused; return STATUS;
undefined 	yylval.status = undefined; return STATUS;
{integer}    yylval.text = yytext; return FLOWINT;
\[           yylval.text = "("; return O_BRACKET;
\]           yylval.text = ")"; return C_BRACKET;
\(           yylval.text = "("; return O_PAREN;
\)           yylval.text = ")"; return C_PAREN;
\,           yylval.text = ")"; return COMMA;
t		yylval.unBool = true;return BOOL;
f		yylval.unBool = false;return BOOL;
[ \t\n\r\f]+ /* discard spaces */
.            return yytext[0]; /* alert parser of the garbage */

%%

void
yyerror(const char *message)
{
	if (*yytext == YY_END_OF_BUFFER_CHAR)
	{
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				 errmsg("bad flow representation"),
				 /* translator: %s is typically "syntax error" */
				 errdetail("%s at end of input", message)));
	}
	else
	{
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				 errmsg("bad flow representation"),
				 /* translator: first %s is typically "syntax error" */
				 errdetail("%s at or near \"%s\"", message, yytext)));
	}
}


/*
 * Called before any actual parsing is done
 */
void
flow_scanner_init(const char *str)
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
 * Called after parsing is done to clean up after flow_scanner_init()
 */
void
flow_scanner_finish(void)
{
	yy_delete_buffer(scanbufhandle);
	pfree(scanbuf);
}
