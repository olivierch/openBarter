
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

COMMENT ON TYPE flow IS 'flow ''[r,(id,nr,qtt_prov,qtt_requ,own,qtt,np), ...]''';

CREATE FUNCTION flow_catt(flow,int8,int8,int8,int8,int8,int8,int8,int8[])
RETURNS flow
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION flow_omegaz(flow,flow,int8,int8,int8,int8,int8,int8,int8,int8[],int8[])
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION flow_show(flow)
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION flow_tarr(int8[])
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION flow_maxdimrefused(int8[],int)
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION flow_isloop(flow)
RETURNS bool
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

--CREATE TYPE __torder AS (id int8,qtt int8,nr int8,np int8,qtt_prov int8,qtt_requ int8,own int8,refused int8[],created timestamp,updated timestamp);
/*SELECT id,max(nr) as nr,max(qtt_prov)as qtt_prov,max(qtt_requ) as qtt_requ,max(own) as own,max(qtt) as qtt,max(np) as np,NULL::flow as flow,0 as cntgraph,max(depthb) as depthb,0 as depthf,max(refused) as refused,false as loop */
/*
CREATE TYPE __tmp AS (id int8,nr int8,qtt_prov int8,qtt_requ int8,own int8,qtt int8,np int8,flow flow, cntgraph int, depthb int, depthf int,refused int8[],loop bool); 
CREATE FUNCTION flow_orderaccepted(__tmp,int)
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT; 
CREATE FUNCTION flow_orderaccepted(torder,int)
RETURNS bool
AS 'MODULE_PATHNAME'
LANGUAGE C IMMUTABLE STRICT;*/


