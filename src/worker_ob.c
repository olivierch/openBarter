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

#define OB_DOWAIT 1

// PG_MODULE_MAGIC;

void		_PG_init(void);

/* flags set by signal handlers */
static volatile sig_atomic_t got_sighup = false;
static volatile sig_atomic_t got_sigterm = false;

/* GUC variable */
//static int	worker_ob_naptime = 100;
static char *worker_ob_database = "market";

/* others */
static char	*openclose = "openclose",
			*consumestack = "consumestack";
static char *worker_ob_user = "user_bo";



typedef struct worktable
{
	const char *schema;
	const char *function_name;
	bool installed;
	int dowait;
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


static char* _get_worker_function_name(int index) {
	if(index ==1) 
		return openclose;
	else
		return consumestack;
}

/*
 * Initialize workspace for a worker process: create the schema if it doesn't
 * already exist.
 */
static void
initialize_worker_ob(worktable *table)
{
	int			ret;
	int			ntup;
	bool		isnull;
	StringInfoData buf;

	SetCurrentStatementStartTimestamp();
	StartTransactionCommand();
	SPI_connect();
	PushActiveSnapshot(GetTransactionSnapshot());
	pgstat_report_activity(STATE_RUNNING, "initializing spi_worker schema");

	/* XXX could we use CREATE SCHEMA IF NOT EXISTS? */
	initStringInfo(&buf);
	appendStringInfo(&buf, "select count(*) from pg_namespace where nspname = '%s'",
					 table->schema);

	ret = SPI_execute(buf.data, true, 0);
	if (ret != SPI_OK_SELECT)
		elog(FATAL, "SPI_execute failed: error code %d", ret);

	if (SPI_processed != 1)
		elog(FATAL, "not a singleton result");

	ntup = DatumGetInt64(SPI_getbinval(SPI_tuptable->vals[0],
									   SPI_tuptable->tupdesc,
									   1, &isnull));
	if (isnull)
		elog(FATAL, "null result");

	if (ntup != 0) {
		table->installed = true;
		elog(LOG, "%s function %s.%s installed",
		 MyBgworkerEntry->bgw_name, table->schema, table->function_name);
	} else {
		table->installed = false;
		elog(LOG, "%s function %s.%s not installed",
		 MyBgworkerEntry->bgw_name, table->schema, table->function_name);
	}

	SPI_finish();
	PopActiveSnapshot();
	CommitTransactionCommand();
	pgstat_report_activity(STATE_IDLE, NULL);
}


static void
worker_ob_main(Datum main_arg)
{
	int			index = DatumGetInt32(main_arg);
	worktable  *table;
	StringInfoData buf;
	//char		function_name[20];	

	table = palloc(sizeof(worktable));
	table->schema = pstrdup("market"); 
	//sprintf(function_name, "worker%d", index);
	table->function_name = pstrdup(_get_worker_function_name(index));

	/* Establish signal handlers before unblocking signals. */
	pqsignal(SIGHUP, worker_spi_sighup);
	pqsignal(SIGTERM, worker_spi_sigterm);

	/* We're now ready to receive signals */
	BackgroundWorkerUnblockSignals();

	/* Connect to our database */
	if(!(worker_ob_database && *worker_ob_database))
		elog(FATAL, "database name undefined");
	
	BackgroundWorkerInitializeConnection(worker_ob_database, worker_ob_user);



	initialize_worker_ob(table);

	/*
	 * Quote identifiers passed to us.	Note that this must be done after
	 * initialize_worker_ob, because that routine assumes the names are not
	 * quoted.
	 *
	 * Note some memory might be leaked here.
	 */
	table->schema = quote_identifier(table->schema);
	table->function_name = quote_identifier(table->function_name);

	initStringInfo(&buf);
	appendStringInfo(&buf,"SELECT %s FROM %s.%s()",
					 table->function_name, table->schema, table->function_name);

	/*
	 * Main loop: do this until the SIGTERM handler tells us to terminate
	 */
	while (!got_sigterm)
	{
		int			ret;
		int			rc;
		int 		_worker_ob_naptime; // = worker_ob_naptime * 1000L;

		if(table->installed) // && !table->dowait)
			_worker_ob_naptime = table->dowait;
		else
			_worker_ob_naptime = 1000L; // 1 second		
		/*
		 * Background workers mustn't call usleep() or any direct equivalent:
		 * instead, they may wait on their process latch, which sleeps as
		 * necessary, but is awakened if postmaster dies.  That way the
		 * background process goes away immediately in an emergency.
		 */
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
			initialize_worker_ob(table);
		}
		if(  !table->installed) continue;

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
		pgstat_report_activity(STATE_RUNNING, buf.data);

		/* We can now execute queries via SPI */
		ret = SPI_execute(buf.data, false, 0);

		if (ret != SPI_OK_SELECT) // SPI_OK_UPDATE_RETURNING)
			elog(FATAL, "cannot execute %s.%s(): error code %d",
				 table->schema, table->function_name, ret);

		if (SPI_processed > 0)
		{
			bool		isnull;
			int32		val;

			val = DatumGetInt32(SPI_getbinval(SPI_tuptable->vals[0],
											  SPI_tuptable->tupdesc,
											  1, &isnull));
			if (!isnull) {
				//elog(LOG, "%s: execution of %s.%s() returned %d",
				//	 MyBgworkerEntry->bgw_name,
				//	 table->schema, table->function_name, val);

				table->dowait = val; //((val & OB_DOWAIT) == OB_DOWAIT);
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
	for (i = 1; i <= 2; i++)
	{
		snprintf(worker.bgw_name, BGW_MAXLEN, "market.%s", _get_worker_function_name(i));
		worker.bgw_main_arg = Int32GetDatum(i);

		RegisterBackgroundWorker(&worker);
	}
}
