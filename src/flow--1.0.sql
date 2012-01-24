
CREATE FUNCTION flow_in(cstring)
RETURNS flow
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION flow_out(flow)
RETURNS cstring
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION flow_omegay(flow,flow,int8,int8)
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

/*
CREATE FUNCTION flow_testb(bool)
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;
*/

CREATE FUNCTION flow_proj(flow,int)
RETURNS int8[]
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION flow_refused(flow)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION flow_dim(flow)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION flow_uuid()
RETURNS cstring
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE TYPE flow (
	INTERNALLENGTH = variable,
	INPUT = flow_in,
	OUTPUT = flow_out,
	ALIGNMENT = double
);

--COMMENT ON TYPE flow IS 'flow ''[(id,nr,qtt_prov,qtt_requ,sid,own,qtt,np), ...]''';
COMMENT ON TYPE flow IS 'flow ''[(id,nr,qtt_prov,qtt_requ,own,qtt,np), ...]''';

-- (Y.flow,X.flow,id,nr,qtt_prov,qtt_requ,own,qtt,np)
--CREATE FUNCTION flow_cat(flow,flow,int8,int8,int8,int8,int8,int8,int8,int8)
CREATE FUNCTION flow_cat(flow,int8,int8,int8,int8,int8,int8,int8)
RETURNS flow
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

--CREATE FUNCTION flow_init(int8,int8,int8,int8,int8,int8,int8,int8)
CREATE FUNCTION flow_init(int8,int8,int8,int8,int8,int8,int8)
RETURNS flow
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION flow_to_matrix(flow)
RETURNS int8[]
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE TYPE __flow_to_commits AS (qtt_r int8,nr int8,qtt_p int8,np int8);
COMMENT ON TYPE __flow_to_commits IS '(qtt_r int8,nr int8,qtt_p int8,np int8)';
CREATE FUNCTION flow_to_commits(flow)
RETURNS SETOF __flow_to_commits
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;



