/* $Id: test_exemple.c 22 2010-01-15 16:00:22Z olivier.chaussavoine $ */
//#include <common.h>
#include <stdio.h>
#include <stdbool.h>
#include <tests.h>

static svn_error_t *
test1(const char **msg, bool msg_only, svn_test_opts_t *opts) {

	svn_error_t *err = SVN_NO_ERROR;
	char buf[128];

	*msg = "explication du test";
	if (msg_only)
		return SVN_NO_ERROR;
	printf("opts.record = %i\n",opts->record);
	MAKE_ERROR("err 1", &err);
	// free_error(&err);
	MAKE_ERROR("err 2", &err);
	MAKE_ERROR("err 3", &err);

	return err;
}

static svn_error_t *
test2(const char **msg, bool msg_only, svn_test_opts_t *opts) {

	svn_error_t *err = SVN_NO_ERROR;
	char buf[128];

	*msg = "explication du test";
	if (msg_only)
		return SVN_NO_ERROR;

	return err;
}
/* ========================================================================== */

struct svn_test_descriptor_t test_funcs[] = { SVN_TEST_NULL, SVN_TEST_PASS(
		test1), SVN_TEST_PASS(test2), SVN_TEST_NULL };
