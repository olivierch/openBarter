CREATE TYPE yorder AS (
	id int,
	own int,
	oid int, -- reference the order of the stock (can be id itself)
    qtt_requ int8,
    qua_requ text,
    -- pos_requ cube,
    qtt_prov int8,
    qua_prov text,
    -- pos_prov cube,
    -- carre_prov cube, -- carre_prov @> pos_requ
    qtt int8
    --- flowr int8,
    -- dist	float,
    
);

CREATE FUNCTION yflow_in(cstring)
RETURNS yflow
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yflow_out(yflow)
RETURNS cstring
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE TYPE yflow (
	INTERNALLENGTH = variable, 
	INPUT = yflow_in,
	OUTPUT = yflow_out,
	ALIGNMENT = double
);
COMMENT ON TYPE yflow IS 'yflow ''[(id,oid,own,qtt_requ,qtt_prov,qtt,proba), ...]''';

CREATE FUNCTION yflow_dim(yflow)
RETURNS int
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yflow_show(yflow)
RETURNS cstring
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yflow_init(yorder)
RETURNS yflow
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yflow_grow(yorder,yorder,yflow)
RETURNS yflow
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yflow_finish(yorder,yflow,yorder)
RETURNS yflow
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yflow_contains_id(int,yflow)
RETURNS boolean
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yflow_match(yorder,yorder)
RETURNS boolean
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

--------------------------------------------------------------------------------
-- AGGREGATE ywolf_max(yflow) 
--------------------------------------------------------------------------------
CREATE FUNCTION yflow_maxg(yflow,yflow)
RETURNS yflow
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE AGGREGATE yflow_max(yflow)
(
sfunc = yflow_maxg,
stype = yflow,
initcond = '[]'
);

CREATE FUNCTION yflow_reduce(yflow,yflow)
RETURNS yflow
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yflow_is_draft(yflow)
RETURNS boolean
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yflow_to_matrix(yflow)
RETURNS int8[][]
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yflow_qtts(yflow)
RETURNS int8[]
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;
