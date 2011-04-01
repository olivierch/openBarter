/* $Id: test_dbe.c 22 2010-01-15 16:00:22Z olivier.chaussavoine $ */
#include <db.h>
#include <dbe.h>
#include <ut.h>
#include <tests.h>

//ob_tGlobal global;
#define PATH_TEST "/tmp/test"
#define PATHDBTEMP "/tmp/test/tmp"

static int ouverture_tmp(char *pathdb,char *pathdbtemp) {
	int ret;
	// printf("les dir %s et %s sont bien ouverts\n",pathdb,pathdbtemp);
	ret = ob_dbe_dircreate(pathdb);
	if(ret) return ret;
	ret = ob_dbe_dircreate(pathdbtemp);
	return ret;
}

static svn_error_t *
test1(const char **msg,bool msg_only, svn_test_opts_t *opts)
{
	svn_error_t *err=SVN_NO_ERROR;
	*msg = "ob_dbe_ouverture";
  if (msg_only)
    return err;

  /* begin of test */
  char *envtest = PATH_TEST;
  int ret;

  ret = ouverture_tmp(PATH_TEST,PATHDBTEMP);
  if(ret) { MAKE_ERROR("error at preopening",&err); return err; }
  /*ret = ob_dbe_ouverture(envtest);
  if(ret) { MAKE_ERROR("error at opening",&err); return err; }
  ret = ob_dbe_fermeture();
  if(ret) { MAKE_ERROR("error at closing",&err); return err; }*/
  return err;
}
static svn_error_t *
test2(const char **msg,bool msg_only, svn_test_opts_t *opts)
{
	svn_error_t *err=SVN_NO_ERROR;
	*msg = "ob_dbe_openEnvDurable(DB_CREATE)";
	if (msg_only)
		return err;

	/* begin of test */
	char *pathtest = PATH_TEST;
	int ret;
	u_int32_t _flagsenv;
	DB_ENV *env=NULL;

	_flagsenv = DB_CREATE | DB_INIT_MPOOL;
	ret = ob_dbe_openEnvDurable(_flagsenv,pathtest,&env);
	if(ret) { MAKE_ERROR("error at opening sustainable env with DB_CREATE",&err); goto fin; }
	ret = ob_dbe_createBasesDurable(env);
	if(ret) { MAKE_ERROR("error at creating sustainable database",&err); goto fin; }
	ret = ob_dbe_openBasesDurable(env,NULL,DB_CREATE);
	if(ret) { MAKE_ERROR("error at opening sustainable database",&err); goto fin; }

	ret = ob_dbe_clearBases(env);
	if(ret) { MAKE_ERROR("error at clearing sustainable database",&err); goto fin; }
	ret = ob_dbe_closeBasesDurable(env);
	if(ret) { MAKE_ERROR("error at closing sustainable database",&err); goto fin; }
	ret = ob_dbe_closeEnvDurable(env);
	if(ret) { MAKE_ERROR("error at closing sustainable env",&err); return err; }
 	return err;
fin:
	if(env != NULL) ret = ob_dbe_closeEnvDurable(env);
 	return err;
}
static svn_error_t *
test3(const char **msg,bool msg_only, svn_test_opts_t *opts)
{
	svn_error_t *err=SVN_NO_ERROR;
	*msg = "nothing";
	if (msg_only)
		return err;

	/* begin of test */
 	return err;
}
static svn_error_t *
test4(const char **msg,bool msg_only, svn_test_opts_t *opts)
{
	svn_error_t *err=SVN_NO_ERROR;
	*msg = "read write on openEnvDurable";
	if (msg_only)
		return err;

	/* begin of test */
	char *pathtest = PATH_TEST;
	int ret,i;
	DB_ENV *env=NULL;
	ob_tPrivate *priv;
	DB_TXN *txn = NULL;
	ob_tStock stock;
	ob_tId sid;
	u_int32_t _flagsenv;

	ret = ob_dbe_dircreate(pathtest);
	if(ret) goto fin;
	_flagsenv = DB_CREATE | DB_INIT_MPOOL;
	ret = ob_dbe_openEnvDurable(_flagsenv,pathtest,&env);
	if(ret) { MAKE_ERROR("error at opening sustainable env with DB_CREATE",&err); goto fin; }
	ret = ob_dbe_createBasesDurable(env);
	if(ret) { MAKE_ERROR("error at creating sustainable database",&err); goto fin; }
	ret = ob_dbe_openBasesDurable(env,NULL,DB_CREATE);
	if(ret) { MAKE_ERROR("error at opening sustainable database",&err); goto fin; }
	ret = ob_dbe_clearBases(env);
	if(ret) { MAKE_ERROR("error at clearing sustainable database",&err); goto fin; }

	priv = (ob_tPrivate *) env->app_private;

	/* write read */

	ob_dbe_resetStock(&stock);
	obMDbtS(ks_sid,stock.sid);
	obMDbtS(ds_stock,stock);
	obMRange(i,100) {
		stock.sid +=1;
		stock.qtt = (i+1)*5;
		ret = priv->stocks->put(priv->stocks,txn,&ks_sid,&ds_stock,0);
		if(ret) { obMTRACE(ret); MAKE_ERROR("could not write",&err); goto fin; }
	}
	sid = 0;
	ks_sid.data = &sid;
	obMDbtU(du_stock,stock);
	obMRange(i,100) {
		sid +=1;
		ret = priv->stocks->get(priv->stocks,txn,&ks_sid,&du_stock,0);
		if(ret) { obMTRACE(ret); MAKE_ERROR("could not write",&err); goto fin; }
		if(stock.qtt != ((i+1)*5)) { MAKE_ERROR("read!=write",&err); goto fin; }
		if(stock.sid != sid) { MAKE_ERROR("pb on index",&err); goto fin; }
	}
fin:
	if(env !=NULL) {
		ret = ob_dbe_closeBasesDurable(env);
		if(ret) { MAKE_ERROR("error at closing sustainable database",&err);}
		ret = ob_dbe_closeEnvDurable(env);
		if(ret) { MAKE_ERROR("error at closing sustainable env",&err); }
	}
	return err;
}
static svn_error_t *
test5(const char **msg,bool msg_only, svn_test_opts_t *opts)
{
	svn_error_t *err=SVN_NO_ERROR;
	*msg = "open close EnvTemp";
	if (msg_only)
		return err;

	/* begin of test */
	char *pathtest = PATH_TEST;
	int ret;
	DB_ENV *envt;

	ret = ob_dbe_openEnvTemp(pathtest,&envt);
	if(ret) { MAKE_ERROR("error at opening temporary database with DB_CREATE",&err); goto fin; }
fin:
	ret = ob_dbe_closeEnvTemp(envt);
	if(ret) { MAKE_ERROR("error at closing temporary database",&err); goto fin; }
	return err;
}
static svn_error_t *
test6(const char **msg,bool msg_only, svn_test_opts_t *opts)
{
	svn_error_t *err=SVN_NO_ERROR;
	*msg = "read write on EnvTemp";
	if (msg_only)
		return err;

	/* begin of test */
	char *pathtest = PATH_TEST;
	int ret,ret_t,i;
	DB_ENV *envt=NULL;
	ob_tPrivate *priv;
	DB_TXN *txn = NULL;
	ob_tTrait trait;
	ob_tFleche rid;

	ret = ob_dbe_openEnvTemp(pathtest,&envt);
	if(ret) { MAKE_ERROR("error at opening temporary database with DB_CREATE",&err); goto fin; }

	/*TODO read write */
	ob_tPrivateTemp *privt = envt->app_private;

	ob_dbe_resetTrait(&trait);
	obMDbtS(ks_rid,trait.rid);
	obMDbtS(ds_trait,trait);
	obMRange(i,100) {
		trait.rid.Xoid +=1;
		trait.igraph = (i+1)*5;
		ret = privt->traits->put(privt->traits,txn,&ks_rid,&ds_trait,0);
		if(ret) { obMTRACE(ret); MAKE_ERROR("could not write",&err); goto fin; }
	}
	ob_dbe_resetFleche(&rid);
	ks_rid.data = &rid;
	obMDbtU(du_trait,trait);
	obMRange(i,100) {
		rid.Xoid +=1;
		ret = privt->traits->get(privt->traits,txn,&ks_rid,&du_trait,0);
		if(ret) { obMTRACE(ret); MAKE_ERROR("could not write",&err); goto fin; }
		if(trait.igraph != ((i+1)*5)) { MAKE_ERROR("read!=write",&err); goto fin; }
		if(rid.Xoid != trait.rid.Xoid) { MAKE_ERROR("pb on index Xoid",&err); goto fin; }
		if(rid.Yoid != trait.rid.Yoid) { MAKE_ERROR("pb on index Yoid",&err); goto fin; }
	}
fin:
	ret_t = ob_dbe_closeEnvTemp(envt);
	if(ret_t) {
		MAKE_ERROR("error at closing temporary database",&err);
		if(!ret) ret = ret_t;
	}
 	return err;
}
/* ========================================================================== */

struct svn_test_descriptor_t test_funcs[] =
  {
    SVN_TEST_NULL,
    SVN_TEST_PASS(test1),
    SVN_TEST_PASS(test2),
    SVN_TEST_PASS(test3),
    SVN_TEST_PASS(test4),
    SVN_TEST_PASS(test5),
    SVN_TEST_PASS(test6),
    SVN_TEST_NULL
  };
