/* contrib/flow/flow--unpackaged--1.0.sql */
ALTER EXTENSION flow ADD type flow;
ALTER EXTENSION flow ADD function flow_in(cstring);
ALTER EXTENSION flow ADD function flow_out(flow);

ALTER EXTENSION flow ADD function flow_omegay(flow,flow,int8,int8);
ALTER EXTENSION flow ADD function flow_proj(flow,int);
ALTER EXTENSION flow ADD function flow_refused(flow);
ALTER EXTENSION flow ADD function flow_dim(flow);
ALTER EXTENSION flow ADD function flow_cat(flow,int8,int8,int8,int8,int8,int8,int8);
ALTER EXTENSION flow ADD function flow_init(int8,int8,int8,int8,int8,int8,int8);
ALTER EXTENSION flow ADD function flow_to_matrix(flow);
ALTER EXTENSION flow ADD function flow_to_commits(flow);

