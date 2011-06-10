/*
 * utils.c
 *
 *  Created on: 14 nov. 2010
 *      Author: olivier
 */
#include <postgres.h>
#include "catalog/pg_type.h"
#include "fmgr.h"
#include "funcapi.h"
#include "executor/spi.h"
#include "lib/stringinfo.h"
#include "miscadmin.h"
#include "utils/builtins.h"
#include "utils/guc.h"
#include "utils/lsyscache.h"
#include "openbarter.h"
static int ob_makeEnvDir_int(char *direnv);

/* creates a directory DataDir/openbarter/pid
 * direnv should be a char[MAXPGPATH] */
int ob_makeEnvDir(char *direnv)
{
	int ret;
	pid_t pid;
	char pid_str[32];

	join_path_components(direnv,DataDir,"openbarter");
	ret = ob_makeEnvDir_int(direnv);
	if(ret) return ret;

	pid = getpid();
	ret = snprintf(pid_str,32,"%d",pid);
	if(ret >=32) {
		ereport(ERROR,
				(errmsg("32 char was not enough to print the pid")));
		return -3;
	}
	join_path_components(direnv,direnv,pid_str);
	ret = ob_makeEnvDir_int(direnv);
	return ret;
}
/* removes recursively all files under a directory.
 * the directory is removed when also_me=true */
int ob_rmPath(char *path,bool also_me)
{
	DIR		   *dir;
	struct dirent *temp_de;
	char		rm_path[MAXPGPATH];
	struct stat stat_buf;
	int ret = 0;

	if(path[0]==0) return 0;
	if (stat(path, &stat_buf) != 0) return 0;
	if (!S_ISDIR(stat_buf.st_mode)) {
		ret = unlink(path);	/* note we ignore any error */
		if(ret) ereport(ERROR,
				(errmsg("path %s 1 errno %d",path,errno)));
		return 0;
	}

	dir = AllocateDir(path);
	while ((temp_de = ReadDir(dir, path)) != NULL) {
			if (strcmp(temp_de->d_name, ".") == 0 ||
				strcmp(temp_de->d_name, "..") == 0)
				continue;
			snprintf(rm_path, sizeof(rm_path), "%s/%s",
					 path, temp_de->d_name);
			ob_rmPath(rm_path,true);
	 }
	FreeDir(dir);
	if(also_me) {
		ret = rmdir(path);
		if(ret) ereport(ERROR,
				(errmsg("path %s errno %d",path,errno)));
		/* else ereport(INFO,
				(errmsg("path %s deleted",path))); */
	}
	return 0;
}
static int ob_makeEnvDir_int(char *direnv)
{
	struct stat stat_buf;
	int ret = 0;

	if (stat(direnv, &stat_buf) == 0)
	{
		/* Check for weird cases where it exists but isn't a directory */
		if (!S_ISDIR(stat_buf.st_mode)) {
			ereport(ERROR,
					(errmsg("required directory \"%s\" does not exist",
							direnv)));
			ret = -1;
		} else {

		}

	}
	else
	{
		/*
		// this message is reported to server but not to client, prefix LOG
		ereport(LOG,
				(errmsg("creating missing directory \"%s\"", direnv))); */
		if (mkdir(direnv, 0700) < 0) {
			ereport(ERROR,
					(errmsg("could not create missing directory \"%s\": %m",
							direnv)));
			ret = -2;
		}
	}
	return ret;
}
/*
// all timers should be zeroed
static TimestampTz *currentTimer;

void ob_utils_timerStart(ob_tTimer *timer) {

	memset(&penbarter_g.timerBDB,0,sizeof(ob_tTimer));
	memset(&penbarter_g.timerPG,0,sizeof(ob_tTimer));

	if(timer != &openbarter.timerBDB || timer != &openbarter.timerPG)
		elog(ERROR,"Not a timer");

	timer->start_time = GetCurrentTimestamp();
	currentTimer = timer;
	return;
}
void ob_utils_timerSwitch(ob_tTimer *newTimer) {
	TimestampTz ts;

	ts = GetCurrentTimestamp();
	currentTimer->cumul += ts - currentTimer->start_time;
	newTimer->start_time = ts;
	currentTimer = newTimer;
}
void ob_utils_timerStop(void) {
	TimestampTz ts;

	ts = GetCurrentTimestamp();
	currentTimer->cumul = ts - currentTimer->start_time;
}
void ob_utils_gettime(ob_tTimer *timer,long *secs,int *microsecs) {
	TimestampTz ts;

	if(timer == currentTimer) {
		ts = GetCurrentTimestamp();
		timer->cumul += ts - timer->start_time;
		timer->start_time = ts;
	}
	ts = timer->start_time+timer->cumul;
	TimestampDifference(timer->start_time,ts,secs,microsecs);
}
*/
