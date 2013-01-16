/* An order inserted produces an id when inserted
this id is used in movements
if the order references a previous , oid= this reference order
*/
CREATE TYPE yorder AS (
	id int,
	own text,
	oid int, -- reference the order of the stock (can be id itself)
    qtt_requ int8,
    qua_requ text,
    -- pos_requ cube,
    qtt_prov int8,
    qua_prov text,
    -- pos_prov cube,
    -- carre_prov cube, -- carre_prov @> pos_requ
    qtt int8,
    flowr int8
    -- dist	float,
    
);


/*  ywolf_dim(yorder[])   == array_length(yorder[],1) */
/* ywolf_get(yorder) == ARRAY[ord]::yorder[] 		select array[row('a','b')::yorder]; */
/* ywolf_get(yorder,yorder[]) == yorder || yorder[] */

CREATE FUNCTION ywolf_cat(yorder,yorder[])
RETURNS yorder[]
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;


CREATE FUNCTION ywolf_qtts(yorder[])
RETURNS int8[]
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION ywolf_reduce(yorder[],yorder[])
RETURNS yorder[]
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION ywolf_to_lines(yorder[])
RETURNS SETOF yorder
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION ywolf_follow(int,yorder,yorder[])
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION ywolf_status(yorder[])
RETURNS int
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION ywolf_is_draft(yorder[])
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;
--------------------------------------------------------------------------------
-- AGGREGATE ywolf_max(yflow) 
--------------------------------------------------------------------------------
CREATE FUNCTION ywolf_maxg(yorder[],yorder[])
RETURNS yorder[]
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE AGGREGATE ywolf_max(yorder[])
(
sfunc = ywolf_maxg,
stype = yorder[],
initcond = '{}'
);

/* ywolf_to_json(_yorder)   array_to_json(yorder[]) */

--------------------------------------------------------------------------------
-- returns an empty set if the flow has some qtt ==0, and otherwise set of order[.].oid

CREATE FUNCTION ywolf_iterid(yorder[])
    RETURNS SETOF integer
    AS 'MODULE_PATHNAME'
    LANGUAGE C IMMUTABLE STRICT;


