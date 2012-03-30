/*
 * 
 *
 ******************************************************************************

******************************************************************************/

#include "postgres.h"
#include "flowdata.h"
#include "fmgr.h"
// #include "libpq/pqformat.h"		/* needed for send/recv functions */


// PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(yorder_in);
PG_FUNCTION_INFO_V1(yorder_out);
PG_FUNCTION_INFO_V1(yorder_spos);
PG_FUNCTION_INFO_V1(yorder_np);
PG_FUNCTION_INFO_V1(yorder_nr);
PG_FUNCTION_INFO_V1(yorder_get);
PG_FUNCTION_INFO_V1(yorder_eq);
PG_FUNCTION_INFO_V1(yorder_left);
	
Datum		yorder_in(PG_FUNCTION_ARGS);
Datum		yorder_out(PG_FUNCTION_ARGS);
Datum		yorder_spos(PG_FUNCTION_ARGS);
Datum		yorder_np(PG_FUNCTION_ARGS);
Datum		yorder_nr(PG_FUNCTION_ARGS);
Datum		yorder_get(PG_FUNCTION_ARGS);
Datum		yorder_eq(PG_FUNCTION_ARGS);
Datum		yorder_left(PG_FUNCTION_ARGS);

/*****************************************************************************
 * Input/Output functions
 *****************************************************************************/
Datum
yorder_in(PG_FUNCTION_ARGS)
{
	char	   *str = PG_GETARG_CSTRING(0);
	int32	id,nr,np,own;
	int64	qtt,qtt_prov,qtt_requ;
	Torder    *result;

	if (sscanf(str, "(%i,%i,%i,%lli,%i,%lli,%lli)", &id, &own, &nr, &qtt_requ, &np, &qtt_prov, &qtt) != 7)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
				 errmsg("invalid input syntax for yorder: \"%s\"",
						str)));

	result = (Torder *) palloc(sizeof(Torder));
	result->id = id;
	result->own = own;
	result->np = np;
	result->qtt_prov = qtt_prov;
	result->qtt = qtt;
	result->nr = nr;
	result->qtt_requ = qtt_requ;
	PG_RETURN_POINTER(result);
}
/*****************************************************************************
 * Input/Output functions
 *****************************************************************************/
Datum
yorder_out(PG_FUNCTION_ARGS)
{
	Torder    *order = PG_GETARG_TORDER(0);
	char	   *result;

	result = (char *) palloc(100);
	snprintf(result, 100, "(%i,%i,%i,%lli,%i,%lli,%lli)", 
		order->id, order->own, 
		order->nr, order->qtt_requ, 
		order->np, order->qtt_prov, order->qtt);
	PG_RETURN_CSTRING(result);
}
/*****************************************************************************
 *****************************************************************************/
Datum
yorder_spos(PG_FUNCTION_ARGS)
{
	Torder    *o = PG_GETARG_TORDER(0);
	
	PG_RETURN_BOOL(o->qtt > 0);
}
/*****************************************************************************
 *****************************************************************************/
Datum
yorder_np(PG_FUNCTION_ARGS)
{
	Torder    *o = PG_GETARG_TORDER(0);
	
	PG_RETURN_INT32(o->np);
}
/*****************************************************************************
 *****************************************************************************/
Datum
yorder_nr(PG_FUNCTION_ARGS)
{
	Torder    *o = PG_GETARG_TORDER(0);
	
	PG_RETURN_INT32(o->nr);
}
/*****************************************************************************
yorder_get(id,own,nr,qtt_requ,np,qtt_prov,qtt)
 *****************************************************************************/
Datum
yorder_get(PG_FUNCTION_ARGS)
{
	Torder	*o = palloc(sizeof(Torder));
	
	o->id = PG_GETARG_INT32(0);
	o->own = PG_GETARG_INT32(1);
	o->nr = PG_GETARG_INT32(2);
	o->qtt_requ = PG_GETARG_INT64(3);
	o->np = PG_GETARG_INT32(4);
	o->qtt_prov = PG_GETARG_INT64(5);
	o->qtt = PG_GETARG_INT64(6);
	
	PG_RETURN_TORDER(o);
}
/******************************************************************************
******************************************************************************/
Datum yorder_eq(PG_FUNCTION_ARGS)
{
	Torder	*o1 = PG_GETARG_TORDER(0);
	Torder	*o2 = PG_GETARG_TORDER(1);
	
	if(o1->id != o2->id) PG_RETURN_BOOL(false);
	PG_RETURN_BOOL(true);

}
/*****************************************************************************
aggregate yorder_agg(yorder)
 *****************************************************************************/
Datum
yorder_left(PG_FUNCTION_ARGS)
{
	Torder    *o1 = PG_GETARG_TORDER(0);
	Torder    *o2 = PG_GETARG_TORDER(1);
	Torder	   *result;

	if(o1->id != 0) result = o1;
	else result = o2;
	PG_RETURN_POINTER(result);
}

