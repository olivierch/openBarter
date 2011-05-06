/* $Id: svn_test_main.c 22 2010-01-15 16:00:22Z olivier.chaussavoine $ */
/*
 * tests-main.c:  shared main() & friends for SVN test-suite programs
 *
 */
#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h> /* getopt_long() */
#include <tests.h>

/* Some Subversion test programs may want to parse options in the
 argument list, so we remember it here. */
int test_verbose_mode;

void usage(char *progname)

{
	printf("USAGE:\n%s\n	executes all tests\n", progname);
	printf("%s --list\n	provides the list of tests\n", progname);
	printf("%s --record\n	record mode\n", progname);
	printf(
			"%s 1 3 5\n	with a list of integers, executes corresponding tests\n",
			progname);
	return;
}

/* Determine the array size of test_funcs[], the inelegant way.  :)  */
static int get_array_size(void) {
	int i;

	for (i = 1; test_funcs[i].func; i++) {
	}

	return (i - 1);
}
/* work!!! */
void free_error(svn_error_t **perr) {
	svn_error_t *err;
	err = *perr;
	if (err == SVN_NO_ERROR)
		return;
	free(err->message);
	free_error(&err->child);
	free(err);
	*perr = SVN_NO_ERROR;
}
void handle_error(svn_error_t *err, FILE *stream, const char *prefix) {
	svn_error_t *perr;

	perr = err;

	while (perr) {
		if (test_verbose_mode)
			fprintf(stream, "%s %s %d %s\n", 
					prefix, perr->file, perr->line,
					perr->message);
		perr = perr->child;
	}
	return;
}
/* used by #define MAKE_ERROR(msg,err) make_error(msg,err,__FILE__,__LINE__) */
void make_error(char *message, svn_error_t **err, char *file, long line) {
	svn_error_t *perr;
	char *mess;

	printf("msg %s, file %s,line %li\n",message,file,line);
	mess = malloc(strlen(message) + 1);
	if (!mess) {
		fprintf(stderr, "malloc in make_error (b)");
		goto make_error_1;
	}
	perr = malloc(sizeof(svn_error_t));
	if (!perr) {
		fprintf(stderr, "malloc in make_error (a)");
		goto make_error_2;
	}
	perr->message = mess;

	strcpy(perr->message, message);

	perr->line = line;
	perr->file = file;
	perr->child = *err;

	*err = perr;
	return;

	make_error_2: free(mess);
	make_error_1: return;
}
void svn_tests_trace(int ret, char *file, long line) {
	printf("obMTRACE in %s:%i %i\n", file, (int) line, ret);
	return;
}

/* Execute a test number TEST_NUM.  Pretty-print test name and dots
 according to our test-suite spec, and return the result code. */
static int do_test_num(const char *progname, int test_num, bool msg_only,
		svn_test_opts_t *opts) {

	svn_test_driver_t func;
	bool skip, xfail;
	svn_error_t *err, *err1;
	int array_size = get_array_size();
	int test_failed = 0;

	const char *msg = 0; /* the message this individual test prints out */

	/* Check our array bounds! */
	if ((test_num > array_size) || (test_num <= 0)) {
		printf("FAIL: %s: THERE IS NO TEST NUMBER %2d\n", progname, test_num);
		return (1);
	} else {

		func = test_funcs[test_num].func;
		skip = (test_funcs[test_num].mode == svn_test_skip);
		xfail = (test_funcs[test_num].mode == svn_test_xfail);
	}

	/* Do test */
	err = func(&msg, msg_only || skip, opts);

	/* Failure means unexpected results -- FAIL or XPASS. */
	test_failed = ((err != SVN_NO_ERROR) != (xfail != 0));

	/* If we got an error, print it out.  */
	if (err) {
		err1 = err;
		handle_error(err1, stdout, "> ");
		//printf("on est sorti\n");
		free_error(&err1);
	}

	if (msg_only) {
		printf(" %2d     %-5s  %s\n", test_num, (xfail ? "XFAIL"
				: (skip ? "SKIP" : "")), msg ? msg
				: "(test did not provide name)");
	} else if (test_verbose_mode || test_failed) {
		printf("%s %s %d: %s\n", (err ? (xfail ? "XFAIL:" : "FAIL: ")
				: (xfail ? "XPASS:" : (skip ? "SKIP: " : "PASS: "))), progname,
				test_num, msg ? msg : "(test did not provide name)");
	} else
		printf("%s", err ? (xfail ? "x" : "*") : (xfail ? "!" : (skip ? "?"
				: ".")));

	if (msg) {
		int len = strlen(msg);
		if (len > 50)
			printf("WARNING: Test docstring exceeds 50 characters\n");
		if (msg[len - 1] == '.')
			printf("WARNING: Test docstring ends in a period (.)\n");
		if (isupper(msg[0]))
			printf("WARNING: Test docstring is capitalized\n");
	}

	return test_failed;
}

/* Standard svn test program */
int main(int argc, char * const argv[]) {
	char *prog_name;
	int test_num;
	int i;
	int got_error = 0;
	int ran_a_test = 0;
	int list_mode = 0;
	int help_mode = 0;
	int opt_id = 1;
	char c;

	//svn_error_t *err;
	enum {
		list_opt = 1, verbose_opt, quiet_opt, help_opt, record_opt
	};

	//char errmsg[200];
	/* How many tests are there? */
	int array_size = get_array_size();

	svn_test_opts_t opts = { NULL,0 };

	prog_name = strrchr(argv[0], '/');
	if (prog_name)
		prog_name++;
	else
		prog_name = argv[0];

	while (1) {
		static const struct option long_options[] = { 
			{ "list", no_argument, 0, list_opt }, 
			{ "help", no_argument, 0, help_opt }, 
			{ "record", no_argument, 0, record_opt },
			{ "verbose", no_argument, &test_verbose_mode, 1 }, 
			{ "quiet", no_argument, &test_verbose_mode, 0 }, 
			{ 0, 0, 0, 0 } };

		// const char *opt_arg;

		c = getopt_long(argc, argv, "lhrvq", long_options, &opt_id);
		//printf("%i \n",c);
		if (c == -1)
			break;

		switch (c) {
		case 0:
			break;
		case list_opt:
			list_mode = 1;
			break;
		case record_opt:
			opts.record = 1;
			break;
		case help_opt:
		default:
			help_mode = 1;
			break;
		}
	}
	/*
	 if (argc >=2) {
	 if (!strcmp(argv[1],"list")) list_mode = 1;	}
	 */

	//
	if (help_mode) {
		usage(prog_name);
		return (0);
	}

	if (list_mode) {
		/* run all tests with MSG_ONLY set to TRUE */

		printf("Test #  Mode   Test Description\n"
			"------  -----  ----------------\n");
		for (i = 1; i <= array_size; i++) {
			if (do_test_num(prog_name, i, true, &opts))
				got_error = 1;
		}
	} else {
		//printf("opt_id:%d argc:%d\n",opt_id,argc);
		if (opt_id < argc) {
			for (i = opt_id; i < argc; i++) {
				if (isdigit(argv[i][0])) {
					ran_a_test = 1;
					test_num = atoi(argv[i]);
					//printf ("test num %i \n",test_num);
					if (do_test_num(prog_name, test_num, false, &opts))
						got_error = 1;
					//printf ("test num %i fait\n",test_num);
				}
			}
		} else { /* just run all tests */
			for (i = 1; i <= array_size; i++) {
				if (do_test_num(prog_name, i, false, &opts))
					got_error = 1;
			}
		}
	}
	return got_error;
}

