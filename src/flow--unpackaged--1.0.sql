/* contrib/flow/flow--unpackaged--1.0.sql */
ALTER EXTENSION flow ADD type flow;
ALTER EXTENSION flow ADD function flow_in(cstring);
ALTER EXTENSION flow ADD function flow_out(flow);

ALTER EXTENSION flow ADD function flow_omegay(flow,flow,int8,int8);
ALTER EXTENSION flow ADD function flow_omegaz(flow,flow,int8,int8,int8,int8,int8,int8,int8,int8[],int8[]);
ALTER EXTENSION flow ADD function flow_show(flow);
ALTER EXTENSION flow ADD function flow_proj(flow,int);
ALTER EXTENSION flow ADD function flow_refused(flow);
ALTER EXTENSION flow ADD function flow_dim(flow);
ALTER EXTENSION flow ADD function flow_catt(flow,int8,int8,int8,int8,int8,int8,int8,int8[]);
ALTER EXTENSION flow ADD function flow_init(int8,int8,int8,int8,int8,int8,int8);
ALTER EXTENSION flow ADD function flow_to_matrix(flow);
ALTER EXTENSION flow ADD function flow_to_commits(flow);
ALTER EXTENSION flow ADD function flow_tarr(int8[]); 
ALTER EXTENSION flow ADD function flow_isloop(flow);
ALTER EXTENSION flow ADD function flow_maxdimrefused(int8[],int); /*
ALTER EXTENSION flow ADD function flow_orderaccepted(torder,int);*/

