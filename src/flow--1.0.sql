
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
COMMENT ON TYPE yflow IS 'yflow ''[(id,own,nr,qtt_requ,np,qtt_prov,qtt), ...]''';

CREATE FUNCTION yflow_dim(yflow)
RETURNS int
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yflow_show(yflow)
RETURNS cstring
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;


CREATE FUNCTION yflow_left(yflow,yflow)
RETURNS yflow
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yflow_last_iomega(yflow)
RETURNS float8
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE AGGREGATE yflow_agg(yflow)
(
sfunc = yflow_left,
stype = yflow,
initcond = '[]'
);

CREATE FUNCTION yflow_reduce(yflow,yflow)
RETURNS yflow
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yflow_flr_omega(yflow)
RETURNS float8
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yflow_to_matrix(yflow)
RETURNS int8[]
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yflow_eq(yflow, yflow) RETURNS bool
   AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT;
CREATE OPERATOR = (
   leftarg = yflow, rightarg = yflow, procedure = yflow_eq,
   commutator = = ,
   -- leave out negator since we didn't create <> operator
   -- negator = <> ,
   restrict = eqsel, join = eqjoinsel
);
--

CREATE FUNCTION yorder_in(cstring)
RETURNS yorder
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yorder_out(yorder)
RETURNS cstring
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE TYPE yorder (
	INTERNALLENGTH = 40,
	INPUT = yorder_in,
	OUTPUT = yorder_out,
	ALIGNMENT = double
);
COMMENT ON TYPE yorder IS 'yorder ''(id,own,nr,qtt_requ,np,qtt_prov,qtt)''';


CREATE FUNCTION yorder_get(int,int,int,int8,int,int8,int8)
RETURNS yorder
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yorder_to_vector(yorder)
RETURNS int8[]
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yorder_spos(yorder)
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yorder_np(yorder)
RETURNS int
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yorder_nr(yorder)
RETURNS int
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yorder_left(yorder,yorder)
RETURNS yorder
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yflow_get_last_order(yflow)
RETURNS yorder
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;


CREATE FUNCTION yorder_moyen(int8,int8,int8,int8)
RETURNS int8[]
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE AGGREGATE yorder_agg(yorder)
(
sfunc = yorder_left,
stype = yorder,
initcond = '(0,0,0,0,0,0,0)'
);

CREATE FUNCTION yorder_eq(yorder, yorder) RETURNS bool
   AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT;
CREATE OPERATOR = (
   leftarg = yorder, rightarg = yorder, procedure = yorder_eq,
   commutator = = ,
   -- leave out negator since we didn't create <> operator
   -- negator = <> ,
   restrict = eqsel, join = eqjoinsel
);


--------------------------------------------------------------------------------
-- yflow_get
--------------------------------------------------------------------------------

CREATE FUNCTION yflow_get(yorder)
RETURNS yflow
AS 'MODULE_PATHNAME','yflow_get_yorder'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yflow_get(yorder,yflow)
RETURNS yflow
AS 'MODULE_PATHNAME','yflow_get_yorder_yflow'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yflow_get(yflow,yorder)
RETURNS yflow
AS 'MODULE_PATHNAME','yflow_get_yflow_yorder'
LANGUAGE C IMMUTABLE STRICT;


--------------------------------------------------------------------------------
-- yflow_follow
--------------------------------------------------------------------------------

CREATE FUNCTION yflow_follow(int,yorder,yflow)
RETURNS bool
AS 'MODULE_PATHNAME','yflow_follow_yorder_yflow'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yflow_follow(int,yflow,yorder)
RETURNS bool
AS 'MODULE_PATHNAME','yflow_follow_yflow_yorder'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yflow_status(yflow)
RETURNS int
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

--------------------------------------------------------------------------------
-- AGGREGATE yflow_max(yflow) and yflow_min(yflow)
--------------------------------------------------------------------------------
CREATE FUNCTION yflow_maxg(yflow,yflow)
RETURNS yflow
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yflow_ming(yflow,yflow)
RETURNS yflow
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE AGGREGATE yflow_max(yflow)
(
sfunc = yflow_maxg,
stype = yflow,
initcond = '[]'
);

CREATE AGGREGATE yflow_min(yflow)
(
sfunc = yflow_ming,
stype = yflow,
initcond = '[]'
);
--------------------------------------------------------------------------------
CREATE FUNCTION yflow_qtts(yflow)
RETURNS int8[]
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yflow_to_json(yflow)
RETURNS cstring
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION yflows_array_to_json(yflow[])
RETURNS cstring
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;
