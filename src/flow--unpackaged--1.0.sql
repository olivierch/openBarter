/* contrib/flow/flow--unpackaged--1.0.sql */

ALTER EXTENSION flow ADD type flow;
ALTER EXTENSION flow ADD function flow_in(cstring);
ALTER EXTENSION flow ADD function flow_out(flow);

ALTER EXTENSION flow ADD function flow_cat(flow,int8,int8,int8,int8,int8,int8,int8,int8);
ALTER EXTENSION flow ADD function flow_status(flow);
ALTER EXTENSION flow ADD function flow_omega(flow);
ALTER EXTENSION flow ADD function flow_proj(flow,int);
/*
ALTER EXTENSION flow ADD function flow(double precision[],double precision[]);
ALTER EXTENSION flow ADD function flow(double precision[]);

ALTER EXTENSION flow ADD function flow_eq(flow,flow);
ALTER EXTENSION flow ADD function flow_ne(flow,flow);
ALTER EXTENSION flow ADD function flow_lt(flow,flow);
ALTER EXTENSION flow ADD function flow_gt(flow,flow);
ALTER EXTENSION flow ADD function flow_le(flow,flow);
ALTER EXTENSION flow ADD function flow_ge(flow,flow);
ALTER EXTENSION flow ADD function flow_cmp(flow,flow);
ALTER EXTENSION flow ADD function flow_contains(flow,flow);
ALTER EXTENSION flow ADD function flow_contained(flow,flow);
ALTER EXTENSION flow ADD function flow_overlap(flow,flow);
ALTER EXTENSION flow ADD function flow_union(flow,flow);
ALTER EXTENSION flow ADD function flow_inter(flow,flow);
ALTER EXTENSION flow ADD function flow_size(flow);
ALTER EXTENSION flow ADD function flow_subset(flow,integer[]);
ALTER EXTENSION flow ADD function flow_distance(flow,flow);
ALTER EXTENSION flow ADD function flow_dim(flow);
ALTER EXTENSION flow ADD function flow_ll_coord(flow,integer);
ALTER EXTENSION flow ADD function flow_ur_coord(flow,integer);
ALTER EXTENSION flow ADD function flow(double precision);
ALTER EXTENSION flow ADD function flow(double precision,double precision);
ALTER EXTENSION flow ADD function flow(flow,double precision);
ALTER EXTENSION flow ADD function flow(flow,double precision,double precision);
ALTER EXTENSION flow ADD function flow_is_point(flow);
ALTER EXTENSION flow ADD function flow_enlarge(flow,double precision,integer);
ALTER EXTENSION flow ADD operator >(flow,flow);
ALTER EXTENSION flow ADD operator >=(flow,flow);
ALTER EXTENSION flow ADD operator <(flow,flow);
ALTER EXTENSION flow ADD operator <=(flow,flow);
ALTER EXTENSION flow ADD operator &&(flow,flow);
ALTER EXTENSION flow ADD operator <>(flow,flow);
ALTER EXTENSION flow ADD operator =(flow,flow);
ALTER EXTENSION flow ADD operator <@(flow,flow);
ALTER EXTENSION flow ADD operator @>(flow,flow);
ALTER EXTENSION flow ADD operator ~(flow,flow);
ALTER EXTENSION flow ADD operator @(flow,flow);
ALTER EXTENSION flow ADD function g_flow_consistent(internal,flow,integer,oid,internal);
ALTER EXTENSION flow ADD function g_flow_compress(internal);
ALTER EXTENSION flow ADD function g_flow_decompress(internal);
ALTER EXTENSION flow ADD function g_flow_penalty(internal,internal,internal);
ALTER EXTENSION flow ADD function g_flow_picksplit(internal,internal);
ALTER EXTENSION flow ADD function g_flow_union(internal,internal);
ALTER EXTENSION flow ADD function g_flow_same(flow,flow,internal);
ALTER EXTENSION flow ADD operator family flow_ops using btree;
ALTER EXTENSION flow ADD operator class flow_ops using btree;
ALTER EXTENSION flow ADD operator family gist_flow_ops using gist;
ALTER EXTENSION flow ADD operator class gist_flow_ops using gist;
*/
