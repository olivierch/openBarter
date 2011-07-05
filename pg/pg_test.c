/*
 * pg_test.c
 *
 * functions replacing those included into postgres
 *
 *  Created on: 30 juin 2011
 *      Author: olivier
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
// for stat_buf
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
// #include "common.h"
//
#include "pg_test.h"

ob_tGlob openbarter_g;

void
elog_start(const char *filename, int lineno, const char *funcname)
{
	fprintf(stderr,"%s:%i in %s: ",filename,lineno,funcname);
}

void
elog_finish(int elevel, const char *fmt,...)
{
	 va_list ap;
	 char buf[1024];

	 va_start(ap, fmt);
	 vsnprintf(buf,1024, fmt, ap);
	 buf[1024-1] = 0;
	 fprintf(stderr, "%s\n", buf);
	 va_end(ap);
	//exit(1);
}
/*
       void *calloc(size_t nmemb, size_t size);
       void *malloc(size_t size);
       void free(void *ptr);
       void *realloc(void *ptr, size_t size);
 */
void* palloc(size_t size) {
	return malloc(size);
}
void* repalloc(void* prt,size_t size) {
	return realloc(prt,size);
}
void pfree(void* ptr) {
	free(ptr);
	return;
}
FILE *AllocateFile(const char *name, const char *mode) {
	return fopen(name,mode);
}
int FreeFile(FILE *file) {
	return fclose(file);
}

int ob_rmPath(char *path,bool also_me)
{
	return 0;
}

int ob_makeEnvDir(ob_tGlob* glob)
{
	struct stat stat_buf;
	int ret = 0;

	strcpy(glob->pathEnv,"./bdb");
	if (stat(glob->pathEnv, &stat_buf) == 0)
	{
		/* Check for weird cases where it exists but isn't a directory */
		if (!S_ISDIR(stat_buf.st_mode)) {
			elog(ERROR,"required directory \"%s\" does not exist",
					glob->pathEnv);
			ret = -1;
		}
	}
	else
	{
		/*
		// this message is reported to server but not to client, prefix LOG
		ereport(LOG,
				(errmsg("creating missing directory \"%s\"", direnv))); */
		if (mkdir(glob->pathEnv, 0700) < 0) {
			elog(ERROR,"could not create missing directory \"%s\" ",
					glob->pathEnv);
			ret = -2;
		}
	}

	return ret;
}
