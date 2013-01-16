#include "wolf.h"
#include "tsearch/ts_utils.h"

// using src/backend/utils/adt/tsvector_op.c
typedef struct
{
	WordEntry  *arrb;
	WordEntry  *arre;
	char	   *values;
	char	   *operand;
} CHKVAL;


/****************************************************************************/
// using src/backend/utils/adt/tsvector_op.c
/*
 * check weight info
 */
static bool
checkclass_str(CHKVAL *chkval, WordEntry *val, QueryOperand *item)
{
	WordEntryPosVector *posvec;
	WordEntryPos *ptr;
	uint16		len;

	posvec = (WordEntryPosVector *)
		(chkval->values + SHORTALIGN(val->pos + val->len));

	len = posvec->npos;
	ptr = posvec->pos;

	while (len--)
	{
		if (item->weight & (1 << WEP_GETWEIGHT(*ptr)))
			return true;
		ptr++;
	}
	return false;
}
/*
 * is there value 'val' in array or not ?
 */
static bool
checkcondition_str(void *checkval, QueryOperand *val)
{
	CHKVAL	   *chkval = (CHKVAL *) checkval;
	WordEntry  *StopLow = chkval->arrb;
	WordEntry  *StopHigh = chkval->arre;
	WordEntry  *StopMiddle = StopHigh;
	int			difference = -1;
	bool		res = false;

	/* Loop invariant: StopLow <= val < StopHigh */
	while (StopLow < StopHigh)
	{
		StopMiddle = StopLow + (StopHigh - StopLow) / 2;
		difference = tsCompareString(chkval->operand + val->distance, val->length,
						   chkval->values + StopMiddle->pos, StopMiddle->len,
									 false);

		if (difference == 0)
		{
			res = (val->weight && StopMiddle->haspos) ?
				checkclass_str(chkval, StopMiddle, val) : true;
			break;
		}
		else if (difference > 0)
			StopLow = StopMiddle + 1;
		else
			StopHigh = StopMiddle;
	}

	if (!res && val->prefix)
	{
		/*
		 * there was a failed exact search, so we should scan further to find
		 * a prefix match.
		 */
		if (StopLow >= StopHigh)
			StopMiddle = StopHigh;

		while (res == false && StopMiddle < chkval->arre &&
			   tsCompareString(chkval->operand + val->distance, val->length,
						   chkval->values + StopMiddle->pos, StopMiddle->len,
							   true) == 0)
		{
			res = (val->weight && StopMiddle->haspos) ?
				checkclass_str(chkval, StopMiddle, val) : true;

			StopMiddle++;
		}
	}

	return res;
}
/****************************************************************************/
bool tsquery_match_vq(TSVector val,TSQuery query)
{
	CHKVAL		chkval;
	bool		result;

	if (!val->size || !query->size)
		return false;

	chkval.arrb = ARRPTR(val);
	chkval.arre = chkval.arrb + val->size;
	chkval.values = STRPTR(val);
	chkval.operand = GETOPERAND(query);
	result = TS_execute(
						GETQUERY(query),
						&chkval,
						true,
						checkcondition_str
		);
	return result;
}
