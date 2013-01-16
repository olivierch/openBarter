
drop extension if exists cube cascade;
create extension cube with version '1.0';

drop extension if exists wolf cascade;
create extension wolf with version '1.0';

RESET client_min_messages;
RESET log_error_verbosity;
SET client_min_messages = notice;
SET log_error_verbosity = terse;

/*  ywolf_dim(yorder[])   == array_length(yorder[],1) */
/* ywolf_get(yorder) == ARRAY[ord]::yorder[] 		select array[row('a','b')::yorder]; */
/* ywolf_get(yorder,yorder[]) == yorder || yorder[] */


SELECT ywolf_reduce( ARRAY[
ROW(1,'a',2,100,'q1',200,'q2',50,0)::yorder,
ROW(3,'b',4,100,'q2',200,'q1',50,0)::yorder
],
ARRAY[
ROW(1,'a',8,100,'q1',200,'q2',50,1)::yorder,
ROW(3,'b',4,100,'q2',200,'q1',50,1)::yorder
]);
/*
result:
 {"(1,a,2,100,q1,200,q2,50,0)","(3,b,4,100,q2,200,q1,49,0)"}

*/
SELECT ywolf_cat( 
ROW(1,'a',2,100,'q1',200,'q2',50,0)::yorder,
ARRAY[
ROW(3,'b',4,100,'q2',200,'q1',50,1)::yorder
]);

SELECT ywolf_to_lines( ARRAY[
ROW(1,'a',2,100,'q1',200,'q2',50,0)::yorder,
ROW(3,'b',4,100,'q2',200,'q1',50,0)::yorder
]);

SELECT ywolf_qtts( ARRAY[
ROW(1,'a',2,100,'q1',200,'q2',50,30)::yorder,
ROW(3,'b',4,100,'q2',200,'q1',50,12)::yorder
]);

SELECT ywolf_follow(8, 
ROW(1,'a',2,100,'q1',200,'q2',50,0)::yorder,
ARRAY[ROW(3,'b',4,100,'q2',200,'q1',50,0)::yorder
]);

SELECT ywolf_follow(8, 
ROW(1,'a',2,100,'q1',200,'q2',50,0)::yorder,
ARRAY[ROW(3,'b',4,100,'q2',200,'q3',50,0)::yorder
]);

SELECT ywolf_status( ARRAY[
ROW(1,'a',2,100,'q1',200,'q2',50,0)::yorder,
ROW(3,'b',4,100,'q2',200,'q1',50,0)::yorder
]);


--------------------------------------------------------------------------------
-- AGGREGATE ywolf_max(yflow) 
--------------------------------------------------------------------------------

SELECT ywolf_maxg(
 ARRAY[
ROW(1,'a',2,100,'q1',300,'q2',50,1)::yorder,
ROW(3,'b',4,100,'q2',300,'q1',50,1)::yorder
]
, ARRAY[
ROW(1,'a',2,100,'q1',200,'q2',50,1)::yorder,
ROW(3,'b',4,100,'q2',200,'q1',50,1)::yorder
]);
/*
returns:
 ARRAY[
ROW(1,'a',2,100,'q1',300,'q2',50,1)::yorder,
ROW(3,'b',4,100,'q2',300,'q1',50,1)::yorder
]
*/

/* ywolf_to_json(_yorder)   array_to_json(yorder[]) */

--------------------------------------------------------------------------------
-- returns an empty set if the flow has some qtt ==0, and otherwise set of order[.].oid


SELECT ywolf_iterid( ARRAY[
ROW(1,'a',2,100,'q1',200,'q2',1,0)::yorder,
ROW(3,'a',4,100,'q1',200,'q2',1,0)::yorder
]);
/*
return 2,4
*/

 

