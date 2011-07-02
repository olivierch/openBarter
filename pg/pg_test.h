/*
 * pg_test.h
 *
 *  Created on: 30 juin 2011
 *      Author: olivier
 */

#ifndef PG_TEST_H_
#define PG_TEST_H_
#include <stdarg.h>
#include <stdio.h>
#include <stdbool.h>


/* Which __func__ symbol do we have, if any? */
#ifdef HAVE_FUNCNAME__FUNC
#define PG_FUNCNAME_MACRO	__func__
#else
#ifdef HAVE_FUNCNAME__FUNCTION
#define PG_FUNCNAME_MACRO	__FUNCTION__
#else
#define PG_FUNCNAME_MACRO	NULL
#endif
#endif

#define obMTRACE(err) printf("%s:%i error %i\n",__FILE__,__LINE__,(err))

/******************************************************************************/
// elog simulation

// from src/include/utils/elog.h
#define LOG			15			/* Server operational messages; sent only to
								 * server log by default. */
#define COMMERROR	16			/* Client communication problems; same as LOG
								 * for server reporting, but never sent to
								 * client. */
#define INFO		17			/* Messages specifically requested by user (eg
								 * VACUUM VERBOSE output); always sent to
								 * client regardless of client_min_messages,
								 * but by default not sent to server log. */
#define NOTICE		18			/* Helpful messages to users about query
								 * operation; sent to client and server log by
								 * default. */
#define WARNING		19			/* Warnings.  NOTICE is for expected messages
								 * like implicit sequence creation by SERIAL.
								 * WARNING is for unexpected messages. */
#define ERROR		20			/* user error - abort transaction; return to
								 * known state */


#define elog	elog_start(__FILE__, __LINE__, PG_FUNCNAME_MACRO), elog_finish

void elog_finish(int elevel, const char *fmt, ...)
/* This extension allows gcc to check the format string for consistency with
   the supplied arguments. */
__attribute__((format(printf, 2, 3)));
void elog_start(const char *filename, int lineno, const char *funcname);

/******************************************************************************/


void* repalloc(void* prt,size_t size);
void pfree(void* ptr);
#ifdef palloc
#undef palloc
#endif
void* palloc(size_t size);

/******************************************************************************/


FILE *AllocateFile(const char *name, const char *mode);
int FreeFile(FILE *file);

/******************************************************************************/
#define MAXPGPATH		1024
// defined in openbarter.h
struct ob__Glob;
typedef struct ob__Glob ob_tGlob;
struct ob__Glob {
	char pathEnv[MAXPGPATH];
	int	cacheSizeKb; // number of kBytes
	int maxArrow;
	int maxCommit;
};
extern ob_tGlob openbarter_g;
int ob_rmPath(char *path,bool also_me);
#endif /* PG_TEST_H_ */
