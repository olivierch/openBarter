#include <postgres.h>
#include "catalog/pg_type.h"
#include "fmgr.h"
#include "funcapi.h"
#include "executor/spi.h"
#include "common.h"
#include "openbarter.h"
#include "balance.h"
#include "utils/timestamp.h"
#include "utils/array.h"
#include <math.h>

/*
create table ob_tconnectdesc (
    conninfo text UNIQUE,
    conn_datas int8[], -- list of 8 int8 expressed in milliseconds
    valid		bool,
    PRIMARY KEY (conninfo)
);
INSERT INTO ob_tconnectdesc (conninfo,valid) VALUES ('dbname = mp user=olivier',true);

*/

#define ob_balance_getBinValue(dst,row,tupdesc,indice,type,isnull) \
do { \
	Datum datum; \
	datum = SPI_getbinval(row, tupdesc, indice, &isnull); \
	if(SPI_result == SPI_ERROR_NOATTRIBUTE || isnull) { \
		elog( ERROR,"pgGetBinValue: failed" ); \
		goto err; \
	} \
	if(isnull) { \
		elog( ERROR,"pgGetBinValue: returned null value" ); \
		goto err; \
	} \
	if(sizeof(type) > sizeof(Datum)) dst = *((type*)datum); \
	else if(sizeof(type) <= sizeof(Datum)) dst = (type) datum; \
	else { \
		elog( ERROR,"pgGetBinValue: failed for %i",indice ); \
		goto err; \
	} \
} while(false);

static ob_tConnectDescp* _ob_balance_getConnect(void);

#define UNE_MINUTE 60*1000*1000 // en microsecondes
ob_tConnectDescp ob_balance_getBestConnect(void) {
	int i,im;
	ob_tConnectDescp pconnect,_pconnect,*tabconnect;
	float min;
	int64 now;

	now = (int64) GetCurrentTimestamp();
	
	tabconnect = _ob_balance_getConnect();
	//elog(INFO,"_ob_balance_getConnect done");
	if(tabconnect == NULL) return NULL;

	for(i=0,im=0,min=0.0;((pconnect = tabconnect[i])!=NULL); i +=1) {
		int j = 0;
		float pondere = 0.0,factor;
		int64 start,delay;

		while(j < pconnect->lenDatas) {
			start = pconnect->connDatas[j];
			delay = pconnect->connDatas[j+1];
			j +=2;
			factor = (float)((now-start)/UNE_MINUTE);
			pondere += ((float)delay)/(factor+1.);
		}
		if((i == 0) || (pondere < min)) {
			min = pondere;
			im = i;
		}
	}
	pconnect = tabconnect[im];

	/* tabconnect is freed */
	i = 0;
	while((_pconnect = tabconnect[i])) {
		if(i != im)
			ob_balance_free_connect(_pconnect);
		i +=1;
	}
	//elog(INFO, "fin de getbest avec '%s'",pconnect->conninfo);
	pfree(tabconnect);
	return pconnect;
}
/* adds now-start to the stats into the table ob_tconnectdesc for the connection
 * returns the error of SPI_execute */
int ob_balance_recordStat(ob_tConnectDescp connect,TimestampTz start) {
	char sql[obCMAXBBUF];
	int64 *datas,delay,now;
	long		secs;
	int		microsecs,ret;
	


	now = (int64) GetCurrentTimestamp();
	TimestampDifference(start, now,&secs, &microsecs);

	delay = ((int64) microsecs) + (((int64)secs) * 1000 * 1000);
	//elog(INFO,"recordStat");
	// return 0;
	datas = connect->connDatas;	
	// {old[0],old[1],old[2],old[3]..old[9]} -> {new,old[0],old[1],old[2]..old[7]}
	ret = snprintf(sql,obCMAXBBUF,"UPDATE ob_tconnectdesc SET conn_datas='{%lli,%lli,%lli,%lli,%lli,%lli,%lli,%lli,%lli,%lli}' WHERE conninfo='%s' ",
				now,delay,
				datas[0],datas[1],datas[2],datas[3],datas[4],datas[5],datas[6],datas[7],
				connect->conninfo);
	//elog(INFO,"snprintf of %s returned %i",sql,ret);
	ret = SPI_execute(sql,false,0);
	if(SPI_tuptable) SPI_freetuptable(SPI_tuptable);
	if(ret != SPI_OK_UPDATE) {
		elog(ERROR, "SPI_execute failed:%i %s",ret,sql);
		return ret;
	}
	return 0;
}

int ob_balance_invalidConnect(ob_tConnectDescp connect) {
	char sql[obCMAXBUF];
	int ret;
	
	snprintf(sql,obCMAXBUF,"UPDATE ob_tconnectdesc SET valid=false WHERE conninfo='%s' ",connect->conninfo);
	ret = SPI_execute(sql,false,0);
	if(SPI_tuptable) SPI_freetuptable(SPI_tuptable);
	if(ret != SPI_OK_UPDATE) {
		elog(ERROR, "SPI_execute failed %i %s",ret,sql);
		return ret;
	}
	return 0;
}
/************************************************************************
Stores valid records of ob_tconnectdesc into tab_connect.
It is is a list of pointers to ob_tConnectDesc terminated by NULL pointer

Returns NULL when no record is found.
*************************************************************************/
static ob_tConnectDescp* _ob_balance_getConnect(void)
{	
	int ret,j;
	ob_tConnectDescp *_tabconnect = NULL;
	size_t _s;
	TupleDesc tupdesc;

	//*ptabconnect = NULL;

	const char *sql = "SELECT conn_datas,conninfo FROM ob.tconnectdesc where valid=true ";
	ret = SPI_execute(sql,true,0);
	if(ret != SPI_OK_SELECT) {
		elog(ERROR, "SPI_execute failed %i for %s",ret,sql);
	}

	if(SPI_tuptable == NULL) 
		return NULL;

	if(SPI_processed ==0) {
		SPI_freetuptable(SPI_tuptable);
		return NULL;
	}
	_s = (SPI_processed+1) * sizeof(ob_tConnectDescp);
	_tabconnect = (ob_tConnectDescp *) palloc(_s);
	MemSet(_tabconnect,0,_s);
	
	tupdesc = SPI_tuptable->tupdesc;
	//elog(INFO, "SPI_execute %s ok",sql);

	obMRange(j,SPI_processed) {
		HeapTuple row = SPI_tuptable->vals[j];
		ob_tConnectDesc *_pconnect;
		bool isnull;
		Datum datum;
		char * _text;
		ArrayType *array = NULL;
		int nbElem;
		size_t _sizeArr;

		// ob_tconnectdesc.conn_datas
		datum = SPI_getbinval(row, tupdesc, 1, &isnull);
		if(SPI_result == SPI_ERROR_NOATTRIBUTE)
			return NULL;
		// nbElem = dim1*dim2*..dimN
		if(isnull) nbElem = 0;
		else {
			array = DatumGetArrayTypeP(datum);
			nbElem = ArrayGetNItems(ARR_NDIM(array), ARR_DIMS(array));
		}
		// elog(INFO, "nbElemn %i",nbElem);
		 /*
		* Construct _pconnect.
		* Must allocate this in upper executor context
		* to keep it alive after SPI_finish().
		*/
		_sizeArr = (size_t) (8*(Max(nbElem,10)));
		_pconnect = (ob_tConnectDesc *) palloc( _sizeArr + sizeof(ob_tConnectDesc));

		MemSet(_pconnect,0,_sizeArr + sizeof(ob_tConnectDesc));
		_pconnect->lenDatas = nbElem;
		if(nbElem) {
			memcpy(&_pconnect->connDatas[0], ARR_DATA_PTR(array), _sizeArr);
		}
		/* ob_tconnectdesc.conninfo */
		_text = SPI_getvalue(row, tupdesc, 2);
		// ob_balance_getBinValue(_str,row,tupdesc,2,char *,isnull);
		//elog(INFO, "retour de getBinValue avec '%s'",_text);
		_pconnect->conninfo = palloc(strlen(_text)+1);
		strcpy(_pconnect->conninfo,_text);
		_tabconnect[j] = _pconnect;

	}
	SPI_freetuptable(SPI_tuptable);
	//elog(INFO, "retour de tabconnect avec '%s'",_tabconnect[0]->conninfo);
	return _tabconnect;

/*	// free _tabconnect
err:
	i = 0;
	while((_connect = _tabconnect[i])) {
		ob_balance_free_connect(_connect);
		i +=1;
	}
	pfree(_tabconnect);
	return NULL;
*/
}
void ob_balance_free_connect(ob_tConnectDescp connect) {
	pfree(connect->conninfo);
	pfree(connect);
	return;
}

void ob_balance_testtabconnect(void) {
	ob_tConnectDescp connect;
	TimestampTz start;

	start = GetCurrentTimestamp();
	
	connect = ob_balance_getBestConnect();
	if(connect == NULL) {
		elog(ERROR,"ob_balance_getBestConnect failed");
		return;
	}
	elog(INFO,"ob_balance_getBestConnect ok");
	if(ob_balance_recordStat(connect,start)) {
		elog(ERROR,"ob_balance_recordStat failed");
		return;
	}
	ob_balance_free_connect(connect);
	elog(INFO,"ob_balance_recordStat ok");
	connect = ob_balance_getBestConnect();
	if(connect == NULL) {
		elog(ERROR,"ob_balance_getBestConnect failed");
		return;
	}
	elog(INFO,"conninfo:'%s' {%lli,%lli,%lli,%lli,%lli,%lli,%lli,%lli,%lli,%lli}",connect->conninfo,
			connect->connDatas[0],connect->connDatas[1],connect->connDatas[2],connect->connDatas[3],connect->connDatas[4],
			connect->connDatas[5],connect->connDatas[6],connect->connDatas[7],connect->connDatas[8],connect->connDatas[9]);

	ob_balance_free_connect(connect);
	elog(INFO,"All done");
	return;
}
