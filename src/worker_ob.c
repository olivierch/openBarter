/* -------------------------------------------------------------------------
 *
 * worker_ob.c
 *		Code based on worker_spi.c
 *
 * This code connects to a database, lauches two background workers.
 for i in [0,1],workeri do the following:
 	while(true)
 		dowait := market.workeri()
 		if (dowait):
 			wait(dowait) // dowait millisecond
 These worker do nothing if the schema market is not installed
 To force restarting of a bg_worker,send a SIGHUP signal to the worker process
 *
 * -------------------------------------------------------------------------
 */
#include "postgres.h"

/* These are always necessary for a bgworker */
#include "miscadmin.h"
#include "postmaster/bgworker.h"
#include "storage/ipc.h"
#include "storage/latch.h"
#include "storage/lwlock.h"
#include "storage/proc.h"
#include "storage/shmem.h"

/* these headers are used by this particular worker's code */
#include "access/xact.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "lib/stringinfo.h"
#include "pgstat.h"
#include "utils/builtins.h"
#include "utils/snapmgr.h"
#include "tcop/utility.h"

#define BGW_NBWORKERS 2
static char *worker_names[] = {"openclose","consumestack"};
 
#define BGW_OPENCLOSE 0
#define BGW_CONSUMESTACK 1

// PG_MODULE_MAGIC;

void		_PG_init(void);

/* flags set by signal handlers */
static volatile sig_atomic_t got_sighup = false;
static volatile sig_atomic_t got_sigterm = false;

/* GUC variable */
static char *worker_ob_database = "market";

/* others */
static char *worker_ob_user = "user_bo";
/* two connexions are allowed for this user */

typedef struct worktable
{
	const char *function_name;
	int 		dowait;
} worktable;

/*
 * Signal handler for SIGTERM
 *		Set a flag to let the main loop to terminate, and set our latch to wake
 *		it up.
 */
static void
worker_spi_sigterm(SIGNAL_ARGS)
{
	int			save_errno = errno;

	got_sigterm = true;
	if (MyProc)
		SetLatch(&MyProc->procLatch);

	errno = save_errno;
}

/*
 * Signal handler for SIGHUP
 *		Set a flag to tell the main loop to reread the config file, and set
 *		our latch to wake it up.
 */
static void
worker_spi_sighup(SIGNAL_ARGS)
{
	int			save_errno = errno;

	got_sighup = true;
	if (MyProc)
		SetLatch(&MyProc->procLatch);

	errno = save_errno;
}

static int _spi_exec_select_ret_int(StringInfoData buf) {
	int			ret;
	int			ntup;
	bool		isnull;

	ret = SPI_execute(buf.data, true, 1); // read_only -- one row returned
	pfree(buf.data);
	if (ret != SPI_OK_SELECT)
		elog(FATAL, "SPI_execute failed: error code %d", ret);


	if (SPI_processed != 1)
		elog(FATAL, "not a singleton result");

	ntup = DatumGetInt32(SPI_getbinval(SPI_tuptable->vals[0],
									   SPI_tuptable->tupdesc,
									   1, &isnull));
	if (isnull)
		elog(FATAL, "null result");	
	return ntup;
}

static bool _test_market_installed() {
	int			ret;
	StringInfoData buf;	

	initStringInfo(&buf);
	appendStringInfo(&buf, "select count(*) from pg_namespace where nspname = 'market'");
	ret = _spi_exec_select_ret_int(buf);
	if(ret == 0)
		return false;

	initStringInfo(&buf);
	appendStringInfo(&buf, "select value from market.tvar where name = 'INSTALLED'");	
	ret = _spi_exec_select_ret_int(buf);
	if(ret == 0)
		return false;
	return true;
}
/*
static bool _test_bgw_active() {
	int				ret;
	StringInfoData 	buf;	

	initStringInfo(&buf);
	appendStringInfo(&buf, "select value from market.tvar where name = 'OC_BGW_ACTIVE'");	
	ret = _spi_exec_select_ret_int(buf);
	if(ret == 0)
		return false;
	return true;
} */

/*
 */
static bool
_worker_ob_installed()
{
	bool		installed;

	SetCurrentStatementStartTimestamp();
	StartTransactionCommand();
	SPI_connect();
	PushActiveSnapshot(GetTransactionSnapshot());
	pgstat_report_activity(STATE_RUNNING, "initializing spi_worker");

	installed = _test_market_installed();

	if (installed) 
		elog(LOG, "%s starting",MyBgworkerEntry->bgw_name);
	else 
		elog(LOG, "%s waiting for installation",MyBgworkerEntry->bgw_name);

	SPI_finish();
	PopActiveSnapshot();
	CommitTransactionCommand();
	pgstat_report_activity(STATE_IDLE, NULL);
	return installed;
}

	/* "VACUUM FULL" fails with an exception:
	ERROR:  VACUUM cannot be executed from a function or multi-command string
	CONTEXT:  SQL statement "VACUUM FULL"
	*/


static void
worker_ob_main(Datum main_arg)
{
	int			index = DatumGetInt32(main_arg);
	worktable  *table;
	StringInfoData buf;
	bool 		installed;	

	table = palloc(sizeof(worktable)); 

	table->function_name = pstrdup(worker_names[index]);
	table->dowait = 0;

	/* Establish signal handlers before unblocking signals. */
	pqsignal(SIGHUP, worker_spi_sighup);
	pqsignal(SIGTERM, worker_spi_sigterm);

	/* We're now ready to receive signals */
	BackgroundWorkerUnblockSignals();

	/* Connect to the database */
	if(!(worker_ob_database && *worker_ob_database))
		elog(FATAL, "database name undefined");
	
	BackgroundWorkerInitializeConnection(worker_ob_database, worker_ob_user);

	installed = _worker_ob_installed();

	initStringInfo(&buf);
	appendStringInfo(&buf,"SELECT %s FROM market.%s()",
					 table->function_name, table->function_name);

	/*
	 * Main loop: do this until the SIGTERM handler tells us to terminate
	 */
	while (!got_sigterm)
	{
		int			ret;
		int			rc;
		int 		_worker_ob_naptime; // = worker_ob_naptime * 1000L;
		//bool 		bgw_active;

		if(installed) // && !table->dowait)
			_worker_ob_naptime = table->dowait;
		else
			_worker_ob_naptime = 1000L; // 1 second		
		/*
		 * Background workers mustn't call usleep() or any direct equivalent:
		 * instead, they may wait on their process latch, which sleeps as
		 * necessary, but is awakened if postmaster dies.  That way the
		 * background process goes away immediately in an emergency.
		 */
		 /* done even if _worker_ob_naptime == 0 */
		// elog(LOG, "%s start waiting for %i",table->function_name,_worker_ob_naptime);
		rc = WaitLatch(&MyProc->procLatch,
					   WL_LATCH_SET | WL_TIMEOUT | WL_POSTMASTER_DEATH,
					   _worker_ob_naptime );

		ResetLatch(&MyProc->procLatch);


		/* emergency bailout if postmaster has died */
		if (rc & WL_POSTMASTER_DEATH)
			proc_exit(1);

		/*
		 * In case of a SIGHUP, just reload the configuration.
		 */
		if (got_sighup)
		{
			got_sighup = false;
			ProcessConfigFile(PGC_SIGHUP);
			installed = _worker_ob_installed();
		}
		if(  !installed) continue;

		/*
		 * Start a transaction on which we can run queries.  Note that each
		 * StartTransactionCommand() call should be preceded by a
		 * SetCurrentStatementStartTimestamp() call, which sets both the time
		 * for the statement we're about the run, and also the transaction
		 * start time.	Also, each other query sent to SPI should probably be
		 * preceded by SetCurrentStatementStartTimestamp(), so that statement
		 * start time is always up to date.
		 *
		 * The SPI_connect() call lets us run queries through the SPI manager,
		 * and the PushActiveSnapshot() call creates an "active" snapshot
		 * which is necessary for queries to have MVCC data to work on.
		 *
		 * The pgstat_report_activity() call makes our activity visible
		 * through the pgstat views.
		 */
		SetCurrentStatementStartTimestamp();
		StartTransactionCommand();
		SPI_connect();
		PushActiveSnapshot(GetTransactionSnapshot());
		//bgw_active = _test_bgw_active();

		if (true) { // bgw_active) {
			pgstat_report_activity(STATE_RUNNING, buf.data);

			/* We can now execute queries via SPI */
			ret = SPI_execute(buf.data, false, 0);

			if (ret != SPI_OK_SELECT) // SPI_OK_UPDATE_RETURNING)
				elog(FATAL, "cannot execute market.%s(): error code %d",
					 table->function_name, ret);

			if (SPI_processed != 1) // number of tuple returned
					elog(FATAL, "market.%s() returned %d tuples instead of one",
					 table->function_name, SPI_processed);
				
			{
				bool		isnull;
				int32		val;

				val = DatumGetInt32(SPI_getbinval(SPI_tuptable->vals[0],
												  SPI_tuptable->tupdesc,
												  1, &isnull));
				
				if (isnull) 
					elog(FATAL, "market.%s() returned null",table->function_name);

				table->dowait = 0;
				if (val >=0) 
					table->dowait = val;
				else {
					if ((index == BGW_OPENCLOSE) && (val == -100))
						; // _openclose_vacuum();
					else 
						elog(FATAL, "market.%s() returned illegal <0",table->function_name);
				}

			}
		}

		/*
		 * And finish our transaction.
		 */
		SPI_finish();
		PopActiveSnapshot();
		CommitTransactionCommand();
		pgstat_report_activity(STATE_IDLE, NULL);
	}

	proc_exit(0);
}

/*
 * Entrypoint of this module.
 *
 * We register more than one worker process here, to demonstrate how that can
 * be done.
 */
void
_PG_init(void)
{
	BackgroundWorker worker;
	unsigned int i;

	/* get the configuration */
	/*
	DefineCustomIntVariable("worker_ob.naptime",
							"Mimimum duration of wait time (in milliseconds).",
							NULL,
							&worker_ob_naptime,
							100,
							1,
							INT_MAX,
							PGC_SIGHUP,
							0,
							NULL,
							NULL,
							NULL); */

	DefineCustomStringVariable("worker_ob.database",
							"Name of the database.",
							NULL,
							&worker_ob_database,
							"market",
							PGC_SIGHUP, 0,
							NULL,NULL,NULL);


	/* set up common data for all our workers */
	worker.bgw_flags = BGWORKER_SHMEM_ACCESS |
		BGWORKER_BACKEND_DATABASE_CONNECTION;
	worker.bgw_start_time = BgWorkerStart_RecoveryFinished;
	worker.bgw_restart_time = 60; // BGW_NEVER_RESTART;
	worker.bgw_main = worker_ob_main;

	/*
	 * Now fill in worker-specific data, and do the actual registrations.
	 */
	for (i = 0; i < BGW_NBWORKERS; i++)
	{
		snprintf(worker.bgw_name, BGW_MAXLEN, "market.%s", worker_names[i]);
		worker.bgw_main_arg = Int32GetDatum(i);

		RegisterBackgroundWorker(&worker);
	}
}
