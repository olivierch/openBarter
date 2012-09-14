/*
 * 
 *
 ******************************************************************************

******************************************************************************/
#include <math.h>

#include "postgres.h"

#include "lib/stringinfo.h"
#include "libpq/pqformat.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h" 
#include "catalog/pg_type.h" 
#include "funcapi.h" 

#include "flowdata.h"
//#include "fmgr.h"

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
PG_FUNCTION_INFO_V1(yorder_to_vector);
PG_FUNCTION_INFO_V1(yorder_moyen);
	
Datum		yorder_in(PG_FUNCTION_ARGS);
Datum		yorder_out(PG_FUNCTION_ARGS);
Datum		yorder_spos(PG_FUNCTION_ARGS);
Datum		yorder_np(PG_FUNCTION_ARGS);
Datum		yorder_nr(PG_FUNCTION_ARGS);
Datum		yorder_get(PG_FUNCTION_ARGS);
Datum		yorder_eq(PG_FUNCTION_ARGS);
Datum		yorder_left(PG_FUNCTION_ARGS);
Datum		yorder_to_vector(PG_FUNCTION_ARGS);
Datum		yorder_moyen(PG_FUNCTION_ARGS);

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

	if (sscanf(str, "(%i,%i,%i," INT64_FORMAT ",%i," INT64_FORMAT "," INT64_FORMAT ")", &id, &own, &nr, &qtt_requ, &np, &qtt_prov, &qtt) != 7)
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
	snprintf(result, 100, "(%i,%i,%i," INT64_FORMAT ",%i," INT64_FORMAT "," INT64_FORMAT ")", 
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

	if(o1->id != 0) result = o1; // TODO ????
	else result = o2;
	PG_RETURN_POINTER(result);
}
/*****************************************************************************
// int8 res[7] = yorder_to_vector(yorder)
 *****************************************************************************/
Datum
yorder_to_vector(PG_FUNCTION_ARGS)
{
	Torder    *o = PG_GETARG_TORDER(0);
	Datum	*_datum_out;
	bool	*_isnull;
	
	ArrayType  *result;
	
	int16       _typlen;
	bool        _typbyval;
	char        _typalign;
	int	    _ndims = 1;
	int         _dims[1];
	int         _lbs[1];

	
	_datum_out = palloc(sizeof(Datum) * 7);
	_isnull = palloc(sizeof(bool) *7);
	
	_isnull[0] = false; _datum_out[0] = Int64GetDatum((int64)o->id); 
	_isnull[1] = false; _datum_out[1] = Int64GetDatum((int64)o->own); 
	_isnull[2] = false; _datum_out[2] = Int64GetDatum((int64)o->nr); 
	_isnull[3] = false; _datum_out[3] = Int64GetDatum(o->qtt_requ);
	_isnull[4] = false; _datum_out[4] = Int64GetDatum((int64)o->np);
	_isnull[5] = false; _datum_out[5] = Int64GetDatum(o->qtt_prov);
	_isnull[6] = false; _datum_out[6] = Int64GetDatum(o->qtt);

	_dims[0] = 7;
	_lbs[0] = 1;
				 
	/* get required info about the INT8 */
	get_typlenbyvalalign(INT8OID, &_typlen, &_typbyval, &_typalign);

	/* now build the array */
	result = construct_md_array(_datum_out, _isnull, _ndims, _dims, _lbs,
		                INT8OID, _typlen, _typbyval, _typalign);
	PG_FREE_IF_COPY(o,0);
	PG_RETURN_ARRAYTYPE_P(result);
}
/*****************************************************************************
 int8[2] res_in,res_out = yorder_moyen(res_in,res_out,qtt_in,qtt_out)
 res is an aggregate that starts at: res_in=0, res_out=0
 it cumulates couples of quantities in such a way that the omega of the sum is the maximum
 of omegas already cumulated
 *****************************************************************************/
Datum yorder_moyen(PG_FUNCTION_ARGS)
{
	int64 i_in 	= PG_GETARG_INT64(0);
	int64 i_out 	= PG_GETARG_INT64(1);
	int64 qtt_in 	= PG_GETARG_INT64(2);
	int64 qtt_out 	= PG_GETARG_INT64(3);
	int64 res_in;
	int64 res_out;
	double om_i,om_q;
	ArrayType  *result;
	
	if(i_in ==0 && i_out ==0 && qtt_in >=1 && qtt_out >=1) {
		res_in = qtt_in;
		res_out = qtt_out;
	} else {
		if ( i_in < 1 || i_out < 1 || qtt_in < 1 || qtt_out < 1)
			ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("invalid input for yorder_moyen")));
	
		om_i = ((double)i_out)/((double)i_in);
		om_q = ((double)qtt_out)/((double)qtt_in);
	
		if(om_i > om_q) {
			int64 q = (int64) floor((((double)qtt_out)/om_i)+0.5);
			// q < qtt_in
			res_in = i_in + q;
		} else {
			int64 q = (int64) floor((((double)i_out)/om_q)+0.5);
			// q < i_in
			res_in = q + qtt_in;
		}
		res_out = i_out + qtt_out;
	}
	{
		Datum	*_datum_out;
		bool	*_isnull;	
		
	
		int16       _typlen;
		bool        _typbyval;
		char        _typalign;
		int	    _ndims = 1;
		int         _dims[1];
		int         _lbs[1];

	
		_datum_out = palloc(sizeof(Datum) * 2);
		_isnull = palloc(sizeof(bool) *2);
	
		_isnull[0] = false; _datum_out[0] = Int64GetDatum(res_in); 
		_isnull[1] = false; _datum_out[1] = Int64GetDatum(res_out); 

		_dims[0] = 2;
		_lbs[0] = 1;
					 
		/* get required info about the INT8 */
		get_typlenbyvalalign(INT8OID, &_typlen, &_typbyval, &_typalign);

		/* now build the array */
		result = construct_md_array(_datum_out, _isnull, _ndims, _dims, _lbs,
				        INT8OID, _typlen, _typbyval, _typalign);
	}
	
	PG_RETURN_ARRAYTYPE_P(result);
}


