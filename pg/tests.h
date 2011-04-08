/* $Id: tests.h 22 2010-01-15 16:00:22Z olivier.chaussavoine $ */
#ifndef defined__tests_h
#define defined__tests_h
#include "common.h"

/** Subversion error object.
 *
 * Defined here, rather than in svn_error.h, to avoid a recursive @#include
 * situation.
 */
typedef struct svn_error_t
{

  /** details from producer of error */
 char *message;

  /** ptr to the error we "wrap" */
  struct svn_error_t *child;

  /** Source file where the error originated.  Only used iff @c SVN_DEBUG. */
  const char *file;

  /** Source line where the error originated.  Only used iff @c SVN_DEBUG. */
 int line;

} svn_error_t;



/* Baton for any arguments that need to be passed from main() to svn
 * test functions.
 */
typedef struct svn_test_opts_t
{
  /* Description of the fs backend that should be used for testing. */
  const char *fs_type;
  /* Add future "arguments" here. */
  int record;
} svn_test_opts_t;

/* Prototype for test driver functions. */
typedef svn_error_t* (*svn_test_driver_t)(const char **msg,
                                          bool msg_only,
                                          svn_test_opts_t *opts);
/* Each test gets a test descriptor, holding the function and other
 * associated data.
 */
extern void make_error(char *,svn_error_t **,char *,long);
extern void svn_tests_trace(int,char *,long);
#define MAKE_ERROR(msg,err) make_error(msg,err,__FILE__,__LINE__)
extern void handle_error(svn_error_t *,FILE *,const char *);

/* Test modes. */
enum svn_test_mode_t
  {
    svn_test_pass,
    svn_test_xfail,
    svn_test_skip
  };

  struct svn_test_descriptor_t
  {
    /* A pointer to the test driver function. */
    svn_test_driver_t func;

    /* Is the test marked XFAIL? */
    enum svn_test_mode_t mode;
  };

  extern struct svn_test_descriptor_t test_funcs[];

/* A null initializer for the test descriptor. */
#define SVN_TEST_NULL  {NULL, 0}

/* Initializer for PASS tests */
#define SVN_TEST_PASS(func)  {func, svn_test_pass}

/* Initializer for XFAIL tests */
#define SVN_TEST_XFAIL(func) {func, svn_test_xfail}

/* Initializer for conditional XFAIL tests */
#define SVN_TEST_XFAIL_COND(func, p)\
                                {func, (p) ? svn_test_xfail : svn_test_pass}

/* Initializer for SKIP tests */
#define SVN_TEST_SKIP(func, p) {func, ((p) ? svn_test_skip : svn_test_pass)}

#define SVN_NO_ERROR 0


// extern void obmake_trace(int,char *,ob_tErrorType,char *,int);


#endif /* defined__tests_h */
