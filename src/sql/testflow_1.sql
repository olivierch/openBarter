drop schema IF EXISTS t2 CASCADE;
CREATE SCHEMA t2;
SET search_path TO t2;

drop extension if exists flow cascade;
create extension flow with version '1.0';

RESET client_min_messages;
RESET log_error_verbosity;
SET client_min_messages = notice;
SET log_error_verbosity = terse;

SELECT '[(1,2,3,4,5,6,7.00)]'::yflow;
SELECT yflow_init(ROW(1,1,2,100,'q1',200,'q2',50)::yorder);

SELECT yflow_grow(ROW(2,1,2,100,'q2',200,'q1',50)::yorder, ROW(1,1,2,100,'q1',200,'q2',50)::yorder, yflow_init(ROW(1,1,2,100,'q1',200,'q2',50)::yorder) );

SELECT yflow_finish(ROW(2,1,2,100,'q2',200,'q1',50)::yorder,
yflow_grow(ROW(2,1,2,100,'q2',200,'q1',50)::yorder, ROW(1,1,2,100,'q1',200,'q2',50)::yorder, yflow_init(ROW(1,1,2,100,'q1',200,'q2',50)::yorder) ),
ROW(1,1,2,100,'q1',200,'q2',50)::yorder);

SELECT yflow_dim(yflow_init(ROW(1,1,2,100,'q1',200,'q2',50)::yorder));

SELECT yflow_contains_id(1,yflow_init(ROW(1,1,2,100,'q1',200,'q2',50)::yorder));
SELECT yflow_contains_id(2,yflow_init(ROW(1,1,2,100,'q1',200,'q2',50)::yorder));
