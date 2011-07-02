

#include "openbarter.h"
#include <utils/guc.h>
#include "iternoeud.h"
#include "point.h"
// #include "funcapi.h"
/*********************************************************************
 * implements two utilities
 * 	int ob_iternoeud_getStock(stock)
 * and
 * 	Portal ob_iternoeud_GetPortal(yoid,nr)
 * 	int ob_iternoeud_Next(portal,Xoid,offreX)
 ********************************************************************/

static int _ob_iternoeud_PrepareGetStock(void);
//static int _ob_iternoeud_PrepareIterNoeuds(void);
static int _ob_iternoeud_PrepareIterNoeuds2(void);


/********************************************************************
 * general utilities
 ********************************************************************/
/* gives TupleDesc of a table */
int ob_iternoeud_getTupleDesc(const char *table,TupleDesc *ptupdesc) {
	char fmt[] = "SELECT * FROM %s LIMIT 1";
	int ret;
	char buf[OB_SRTLEN_MAX];

	snprintf(buf,OB_SRTLEN_MAX,fmt,table);
	ret = SPI_exec(buf, 1);
	if(ret != SPI_OK_SELECT || SPI_tuptable == NULL) {
		elog(ERROR,"EXCQ: %s failed",buf);
		*ptupdesc = NULL;
		return 1;
	}
	*ptupdesc = SPI_tuptable->tupdesc;
	return 0;
}

/* gives the Oid of a column */
Oid ob_iternoeud_SPI_gettypeid(const TupleDesc rowdesc, const char * colname) {
	int i;
	Oid oid;
	//TupleDesc rowdesc;

	i = SPI_fnumber(rowdesc,colname);
	if(i == SPI_ERROR_NOATTRIBUTE || i==0) {
		elog(ERROR, "SPI_fnumber for %s not found",colname);
		return 0;
	}
	oid = SPI_gettypeid(rowdesc,i);
	if(SPI_result == SPI_ERROR_NOATTRIBUTE) {
		elog(ERROR, "SPI_gettypeid for %i not found",i);
		return 0;
	}
	if (!OidIsValid(oid)) {
		elog(ERROR, "could not determine data type of %s",colname);
		return 0;
	}
	return oid;

}
/*******************************************************************************
init guc in postgres.conf

********************************************************************************
shared_preload_libraries = 'openbarter'

custom_variable_classes = 'openbarter'
#------------------------------------------------------------------------------
# OPENBARTER
#------------------------------------------------------------------------------
openbarter.cachesize = 16MB	# more than 1MB
openbarter.maxarrow = 32768		# 32*1024
openbarter.maxcommit = 8

 ******************************************************************************/
static void _obinit_guc(void) {

	/* Define custom GUC variables. */
	DefineCustomIntVariable("openbarter.cachesize",
		 "Sets the cache size of berkeley database.",
						 "Sets the cache size of berkeley database.",
							&openbarter_g.cacheSizeKb,
							16*1024,
							1024, INT_MAX,
							PGC_SUSET,
							GUC_UNIT_KB,
							NULL,
							NULL);

	DefineCustomIntVariable("openbarter.maxarrow",
		 "Sets the maximum number of arrow.",
						 "Sets the maximum number of arrow of the graph of bids.",
							&openbarter_g.maxArrow,
							32*1024,
							128, INT_MAX,
							PGC_SUSET,
							0,
							NULL,
							NULL);

	DefineCustomIntVariable("openbarter.maxcommit",
		 "Sets the maximum number of commits in agreement.",
						 "Sets the maximum number of commits in agreement.",
							&openbarter_g.maxCommit,
							obCMAXCYCLE,
							3, obCMAXCYCLE,
							PGC_SUSET,
							0,
							NULL,
							NULL);

	EmitWarningsOnPlaceholders("openbarter");

}
void		_PG_init(void) {
	//int ret;

	memset(&openbarter_g,0,sizeof(ob_tGlob));
	_obinit_guc(); /*
	ret = _ob_iternoeud_Init();
	if(ret) elog(ERROR,"_PG_init() failed");
	ob_getdraft_init(); */

	return;
}
void		_PG_fini(void) {
	return;
}
/*****************************************************************
 *  to be called once before
 *  		ob_iternoeud_getStock or ob_iternoeud_GetPortal
 *****************************************************************/
int ob_iternoeud_Init(void) {
	int failed = 1,ret;
	bool connected = false;
	ob_tGlob *ob = &openbarter_g;

	ret = SPI_connect();
	if(ret != SPI_OK_CONNECT) {
		elog(INFO,":SPI_connect() -> %i",ret);
		goto err;
	}
	connected = true;
	if(ob_iternoeud_getTupleDesc("ob_tquality",&ob->tupDescQuality)) goto err;
	if(ob_iternoeud_getTupleDesc("ob_tstock",&ob->tupDescStock)) goto err;
	if(ob_iternoeud_getTupleDesc("ob_tnoeud",&ob->tupDescNoeud)) goto err;
	if(_ob_iternoeud_PrepareIterNoeuds2()) goto err;
	if(_ob_iternoeud_PrepareGetStock()) goto err;
	failed = 0;
err:
	if(connected) {
		ret=SPI_finish();
		if(ret != SPI_OK_FINISH) elog(INFO,":SPI_finish() -> %i",ret);
	}
	if(failed) elog(ERROR,"_ob_iternoeud_Init failed");

	return failed;
}

/*******************************************************************************
 * usage:
	 * ob_tStock stock;
	 * ret = ob_iternoeud_getStock(&stock);
	 * ret == 0 OK
	 * ret == DB_NOTFOUND
	 * ret == -1 error
 ******************************************************************************/
static int _ob_iternoeud_PrepareGetStock(void) { // called by _SPI_init->_ob_iternoeud_Init()
	char cmde[] = "SELECT * FROM ob_tstock WHERE id=$1";
	Oid oids[1];
	ob_tGlob *ob = &openbarter_g;

	oids[0] = ob_iternoeud_SPI_gettypeid(ob->tupDescStock,"id");
	if(!oids[0]) goto err;

	/* prepare plan and save it. */
	ob->planGetStock =  SPI_prepare(cmde,1,oids);
	if(ob->planGetStock == NULL) {
		elog(ERROR, "_ob_iternoeud_PrepareGetStock SPI_prepare failure");
		goto err;
	}
	ob->planGetStock = SPI_saveplan(ob->planGetStock);
	if(ob->planGetStock == NULL) {
		elog(ERROR, "save _ob_iternoeud_PrepareGetStock SPI_saveplan failure");
		goto err;
	}
	return 0;
err:
	return -1;
}
	
/* get the ob_tStock from stock->id */
int ob_iternoeud_getStock(stock) 
	ob_tStock *stock;
{	
	SPIPlanPtr planPtr = openbarter_g.planGetStock;
	int ret;
	char nulls[] = {' '};
	Datum values[1];
	
	values[0] = Int64GetDatum(stock->sid);
	ret = SPI_execute_plan(planPtr,values,nulls, true,1);
	if(ret != SPI_OK_SELECT) {
		elog(ERROR, "SPI_execute_plan failed %i",ret);
		ret = ob_iternoeud_CerSPI_execute_plan;
		goto err;
	}
	ret = ob_iternoeud_CerBinValue;
	if(SPI_processed != 0 && SPI_tuptable != NULL) {

		TupleDesc tupdesc = SPI_tuptable->tupdesc;
		HeapTuple row = SPI_tuptable->vals[0];
		bool isnull;
		Datum datum;

		// ob_iternoeud_getBinValue(stock->sid,1,ob_tId);
		ob_iternoeud_getBinValue(stock->own,2,ob_tId);
		ob_iternoeud_getBinValue(stock->qtt,3,ob_tQtt);
		ob_iternoeud_getBinValue(stock->nF,4,ob_tId);
		ob_iternoeud_getBinValue(stock->version,5,ob_tId);
		//elog(NOTICE,"Stock id=%lli own %lli qtt %lli nF %lli version %lli",stock->sid,stock->own,stock->qtt,stock->nF,stock->version);
		
		SPI_freetuptable(SPI_tuptable);
		ret= 0;
	} else ret = DB_NOTFOUND;
err:
	return ret;
}

/* ob_iternoeud_put_stocktemp3(envt,pstock)
 * pstock is put into stocktemps[pstock->sid],
 * and privt->versionsg = max(privt->versionsg,pstock->version) if pstock->sid !=0
 *
 */
int ob_iternoeud_put_stocktemp3(envt,pstock)
	DB_ENV *envt;
	ob_tStock *pstock;
// int ob_iternoeud_put_stocktemp2	(DB_ENV *envt,ob_tStock *pstock)
{
	ob_tPrivateTemp *privt = envt->app_private;
	int ret;
	DBT ks_sid,du_stock;

	obMtDbtpS(ks_sid, &pstock->sid);
	obMtDbtpU(du_stock, pstock);

	if((pstock->sid != 0) && (privt->versionSg < pstock->version)) 
		privt->versionSg = pstock->version;
	ret = privt->stocktemps->put(privt->stocktemps, 0,&ks_sid, &du_stock, 0);
	if (ret) { obMTRACE(ret); goto fin; }
	//elog(INFO,"stocktemp[%lli] inserted with putstocktemp3",pstock->sid);
	// ob_point_voirStock(pstock);
fin: 
	return ret;
}
/****************************************************************************
 * performs:
 * SELECT NOX.*,S.* FROM ob_tnoeud NOX INNER JOIN ob_tstock S ON (NOX.sid =S.id) WHERE NOX.nf=Y_nR
	and returns NO.*,S.* into offreX and Xoid

 *
	ret = _ob_iternoeud_PrepareIterNoeuds2() done in _ob_iternoeud_Init() done in _SPI_init
	...........................
	Portal *portal_noeuds=NULL;
	int64 *Y_oid,*Y_nR;
	........................
	portal_noeuds = ob_iternoeud_GetPortal2(Y_oid,Y_nR);
	do {
		int64 X_oid;
		ob_tnoeud X_offre;
		ret = ob_iternoeud_Next2(portal_noeuds,&X_oid,&X_offre,&stock);
		if(ret) break;
		..............................................................
	} while (ret == 0);
	if (ret == DB_NOTFOUND) ret = 0;
			
	
******************************************************************************/

static int _ob_iternoeud_PrepareIterNoeuds2(void) { // called by _SPI_init->_ob_iternoeud_Init()
	char cmde[] = "SELECT NOX.id,NOX.sid,NOX.omega,NOX.nr,NOX.nf,NOX.own,S.qtt,S.version FROM ob_tnoeud NOX INNER JOIN ob_tstock S ON (NOX.sid =S.id) WHERE NOX.nf=$2 AND S.qtt!=0 and S.type='S' LIMIT $3";
	Oid oids[3];
	ob_tGlob *ob = &openbarter_g;
	const char s_Yid[] = "id";
	const char s_Ynr[] = "nr";

	//elog(INFO,"%s",cmde);

	oids[0] = ob_iternoeud_SPI_gettypeid(ob->tupDescNoeud,s_Yid);
	if(!oids[0]) goto err;
	oids[1] = ob_iternoeud_SPI_gettypeid(ob->tupDescNoeud,s_Ynr);
	if(!oids[1]) goto err;
	oids[2] = oids[1];


	/* prepare plan and save it. */
	ob->planIterNoeuds2 =  SPI_prepare(cmde,3,oids);
	if(ob->planIterNoeuds2 == NULL) {
		elog(ERROR, "prepare _ob_iternoeud_PrepareIterNoeuds failure");
		goto err;
	}
	ob->planIterNoeuds2 = SPI_saveplan(ob->planIterNoeuds2);
	if(ob->planIterNoeuds2 == NULL) {
		elog(ERROR, "save _ob_iternoeud_PrepareIterNoeuds failure");
		goto err;
	}
	return 0;
err:
	return ob_chemin_CerIterNoeudErr;
}
Portal ob_iternoeud_GetPortalA(envt,yoid,nr,limit)
	DB_ENV *envt;
	ob_tId  yoid;
	ob_tId  nr;
	int limit;
{
	char nulls[] = {' ',' ',' '};
	Datum values[3];
	Portal portal;
	SPIPlanPtr planPtr = openbarter_g.planIterNoeuds2;
	int64  _yoid =(int64) yoid;
	int64  _nr =(int64) nr;
	int64 _limit = (int64) limit;
	
	values[0] = Int64GetDatum(_yoid);
	values[1] = Int64GetDatum(_nr);
	values[2] = Int64GetDatum(_limit);

	// elog(INFO,"yoid=%lli,nr=%lli",_yoid,_nr);
	if (!SPI_is_cursor_plan(planPtr)) {
		elog(ERROR,"the cursor is not a plan");
		return NULL;
	}

	portal = SPI_cursor_open(NULL, planPtr,values,nulls,true);
	if(portal == NULL) { 
		elog(ERROR, "SPI_cursor_open failed");
		return NULL;
	}
	return portal;
}

int ob_iternoeud_NextA(portal,Xoid,offreX,stock)
	Portal portal;
	ob_tId *Xoid;
	ob_tNoeud *offreX;
	ob_tStock *stock;
{
	TupleDesc tupdesc;
	HeapTuple row;
	bool isnull;
	int ret;
	Datum datum;

	if(portal == NULL) return ob_chemin_CerIterNoeudErr;
	SPI_cursor_fetch(portal,true,1);

	ret = -1;
	if(SPI_processed != 0 && SPI_tuptable != NULL) {
		row = SPI_tuptable->vals[0];
		tupdesc = SPI_tuptable->tupdesc;

		ob_iternoeud_getBinValue(offreX->oid,1,ob_tId);
		ob_iternoeud_getBinValue(offreX->stockId,2,ob_tId);
		ob_iternoeud_getBinValue(offreX->omega,3,float8);
		ob_iternoeud_getBinValue(offreX->nR,4,ob_tId);
		ob_iternoeud_getBinValue(offreX->nF,5,ob_tId);
		ob_iternoeud_getBinValue(offreX->own,6,ob_tId);
		
		ob_iternoeud_getBinValue(stock->qtt,7,ob_tQtt);
		ob_iternoeud_getBinValue(stock->version,8,ob_tId);

		stock->sid = offreX->stockId;
		stock->own = offreX->own;
		stock->nF = offreX->nF;

		//elog(INFO,"offreX oid=%lli stockId=%lli omega=%f nR=%lli nF=%lli own=%lli",offreX->oid,offreX->stockId,offreX->omega,offreX->nR,offreX->nF,offreX->own);
		//elog(INFO,"stock sid=%lli, own=%lli, qtt=%lli, nF=%lli,version=%lli",stock->sid,stock->own,stock->qtt,stock->nF,stock->version);
		memcpy(Xoid,&offreX->oid,sizeof(ob_tId));

		SPI_freetuptable(SPI_tuptable);
		return 0;
	} else 
		return DB_NOTFOUND;
err:
	SPI_cursor_close(portal);
	return ret;
}


