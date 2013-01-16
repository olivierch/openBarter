#include "postgres.h"
#include "fmgr.h"
#include "tsearch/ts_type.h"
#include "executor/executor.h"  /* for GetAttributeByName() */
#include "funcapi.h" 
#include <string.h>

extern bool tsquery_match_vq(TSVector,TSQuery);

// using src/backend/utils/adt/tsvector_op.c
typedef struct
{
	WordEntry  *arrb;
	WordEntry  *arre;
	char	   *values;
	char	   *operand;
} CHKVAL;

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

Datum hello( PG_FUNCTION_ARGS );
Datum hello2( PG_FUNCTION_ARGS );
Datum matchts( PG_FUNCTION_ARGS );
Datum retcomposite(PG_FUNCTION_ARGS);

PG_FUNCTION_INFO_V1( hello );
PG_FUNCTION_INFO_V1(hello2);
PG_FUNCTION_INFO_V1( matchts );
PG_FUNCTION_INFO_V1(retcomposite);


// bien meilleur exemple dans file:///home/olivier/pr92/pgsql/doc/src/sgml/html/xfunc-c.html#AEN52664
Datum
hello( PG_FUNCTION_ARGS )
{
   // variable declarations
   char greet[] = "Hello, ";
   text *towhom;
   int greetlen;
   int towhomlen;
   int reslen;
   text *res;
   char *greeting;
   //struct varlena
   // Get arguments.  If we declare our function as STRICT, then
   // this check is superfluous.
   if( PG_ARGISNULL(0) ) {
      PG_RETURN_NULL();
   }
   towhom = PG_GETARG_TEXT_P(0);

   // Calculate string sizes.
   greetlen = strlen(greet);
   towhomlen = VARSIZE(towhom) - VARHDRSZ;

   // Allocate memory and set data structure size.
   reslen = greetlen + towhomlen   + VARHDRSZ;
   res = (text *)palloc(reslen);
   //VARATT_SIZEP( greeting ) = greetlen + towhomlen  + VARHDRSZ;
   SET_VARSIZE(res,reslen);
   greeting = (char*)VARDATA(res);

   // Construct greeting string.
   strncpy( greeting, greet, greetlen );
   strncpy( greeting + greetlen, VARDATA(towhom), towhomlen );

   PG_RETURN_TEXT_P( res );
}
/* entrée type composite,
la mémoire contenant la donnée est identifiée 
select hello2((ROW('aa','bb')::ctext)); */
Datum
hello2(PG_FUNCTION_ARGS)
{
    HeapTupleHeader t1, t = PG_GETARG_HEAPTUPLEHEADER(0);
    bool isnull;
    Datum dleft,dright;
    text *left,*right,*res;
    int32 lenres;
    
    t1 = (HeapTupleHeader) palloc(VARSIZE(t));
    memcpy(t1,VARDATA(t),VARSIZE(t));
    // t est un varlena UNTOASTED, sa taille est VARSIZE(t)

    dleft = GetAttributeByName(t1, "tleft", &isnull);
    if (isnull)
        PG_RETURN_NULL();
    dright = GetAttributeByName(t1, "tright", &isnull);
    if (isnull)
        PG_RETURN_NULL();
        
    left = PG_DETOAST_DATUM(dleft);
    right = PG_DETOAST_DATUM(dright);
    lenres = VARSIZE(left) + VARSIZE(right) - VARHDRSZ;
    res = (text *) palloc(lenres);
    
    SET_VARSIZE(res,lenres);
    memcpy(VARDATA(res),VARDATA(left),VARSIZE(left) - VARHDRSZ);
    memcpy(VARDATA(res) + VARSIZE(left) - VARHDRSZ, VARDATA(right), VARSIZE(right) - VARHDRSZ);
    
    PG_RETURN_TEXT_P(res);
}

Datum
retcomposite(PG_FUNCTION_ARGS)
{
    FuncCallContext     *funcctx;
    int                  call_cntr;
    int                  max_calls;
    TupleDesc            tupdesc;
    AttInMetadata       *attinmeta;

    /* stuff done only on the first call of the function */
    if (SRF_IS_FIRSTCALL())
    {
        MemoryContext   oldcontext;

        /* create a function context for cross-call persistence */
        funcctx = SRF_FIRSTCALL_INIT();

        /* switch to memory context appropriate for multiple function calls */
        oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

        /* total number of tuples to be returned */
        funcctx->max_calls = PG_GETARG_UINT32(0);

        /* Build a tuple descriptor for our result type */
        if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
            ereport(ERROR,
                    (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                     errmsg("function returning record called in context "
                            "that cannot accept type record")));

        /*
         * generate attribute metadata needed later to produce tuples from raw
         * C strings
         */
        
        attinmeta = TupleDescGetAttInMetadata(tupdesc);
        funcctx->attinmeta = attinmeta;

        MemoryContextSwitchTo(oldcontext);
    }

    /* stuff done on every call of the function */
    funcctx = SRF_PERCALL_SETUP();

    call_cntr = funcctx->call_cntr;
    max_calls = funcctx->max_calls;
    attinmeta = funcctx->attinmeta;

    if (call_cntr < max_calls)    /* do when there is more left to send */
    {
        char       **values;
        HeapTuple    tuple;
        Datum        result;

        /*
         * Prepare a values array for building the returned tuple.
         * This should be an array of C strings which will
         * be processed later by the type input functions.
         */
        values = (char **) palloc(3 * sizeof(char *));
        values[0] = (char *) palloc(16 * sizeof(char));
        values[1] = (char *) palloc(16 * sizeof(char));
        values[2] = (char *) palloc(16 * sizeof(char));

        snprintf(values[0], 16, "%d", 1 * PG_GETARG_INT32(1));
        snprintf(values[1], 16, "%d", 2 * PG_GETARG_INT32(1));
        snprintf(values[2], 16, "%d", 3 * PG_GETARG_INT32(1));

        /* build a tuple */
        tuple = BuildTupleFromCStrings(attinmeta, values);

        /* make the tuple into a datum */
        result = HeapTupleGetDatum(tuple);

        /* clean up (this is not really necessary) */
        pfree(values[0]);
        pfree(values[1]);
        pfree(values[2]);
        pfree(values);

        SRF_RETURN_NEXT(funcctx, result);
    }
    else    /* do when there is no more left */
    {
        SRF_RETURN_DONE(funcctx);
    }
}

Datum
matchts(PG_FUNCTION_ARGS)
{
	TSVector	val = PG_GETARG_TSVECTOR(1);
	TSQuery		query = PG_GETARG_TSQUERY(0);
	bool		result;
	

	result = tsquery_match_vq(val,query);
	PG_FREE_IF_COPY(val, 0);
	PG_FREE_IF_COPY(query, 1);
	PG_RETURN_BOOL(result);
} 
