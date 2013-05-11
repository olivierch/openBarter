
create extension cube with version '1.0';
create extension hstore with version '1.1';
create extension flowf; -- with version '1.0';

RESET client_min_messages;
RESET log_error_verbosity;
SET client_min_messages = notice;
SET log_error_verbosity = terse;

SELECT '[(1,1,2,3,4,5,6,7.00)]'::yflow;
SELECT yflow_init(ROW(1,1,1,1,100,'q1',200,'q2',50)::yorder);

SELECT yflow_grow(ROW(1,2,1,2,100,'q2',200,'q1',50)::yorder, ROW(1,1,1,1,100,'q1',200,'q2',50)::yorder, yflow_init(ROW(1,1,1,1,100,'q1',200,'q2',50)::yorder) );

SELECT yflow_finish(ROW(1,2,1,2,100,'q2',200,'q1',50)::yorder,
yflow_grow(ROW(1,2,1,2,100,'q2',200,'q1',50)::yorder, ROW(1,1,1,1,100,'q1',200,'q2',50)::yorder, yflow_init(ROW(1,1,1,1,100,'q1',200,'q2',50)::yorder) ),
ROW(1,1,1,1,100,'q1',200,'q2',50)::yorder);

SELECT yflow_dim(yflow_init(ROW(1,1,1,2,100,'q1',200,'q2',50)::yorder));

SELECT yflow_contains_oid(1,yflow_init(ROW(1,1,1,2,100,'q1',200,'q2',50)::yorder));
SELECT yflow_contains_oid(2,yflow_init(ROW(1,1,1,2,100,'q1',200,'q2',50)::yorder));


select yflow_is_draft('[(1,35, 93, 35, 21170, 2685, 2685, 1.000000),(1,636, 50, 636, 12213, 95415, 95415, 1.000000
),(1,389, 68, 389, 23785, 29283, 29283, 1.000000),(1,274, 12, 274, 58834, 80362, 80362, 1.000000),(1,12, 
55, 12, 35136, 55490, 55490, 1.000000)]'::yflow);

select yflow_reduce(x.f1,x.f1,true) from (select '[(1,35, 93, 35, 21170, 2685, 2685, 1.000000),(1,636, 50, 636, 12213, 95415, 95415, 1.000000
),(1,389, 68, 389, 23785, 29283, 29283, 1.000000),(1,274, 12, 274, 58834, 80362, 80362, 1.000000),(1,12, 
55, 12, 35136, 55490, 55490, 1.000000)]'::yflow as f1) x;

select yflow_show('[(1,35, 93, 35, 21170, 2685, 2685, 1.000000),(1,636, 50, 636, 12213, 95415, 95415, 1.000000
),(1,389, 68, 389, 23785, 29283, 29283, 1.000000),(1,274, 12, 274, 58834, 80362, 80362, 1.000000),(1,12, 
55, 12, 35136, 55490, 55490, 1.000000)]'::yflow);
select yflow_to_matrix('[(1,35, 93, 35, 21170, 2685, 2685, 1.000000),(1,636, 50, 636, 12213, 95415, 95415, 1.000000
),(1,389, 68, 389, 23785, 29283, 29283, 1.000000),(1,274, 12, 274, 58834, 80362, 80362, 1.000000),(1,12, 
55, 12, 35136, 55490, 55490, 1.000000)]'::yflow);

select yflow_show('[(1,35, 93, 35, 21170, 2685, 2685, 1.000000),(1,636, 50, 636, 12213, 95415, 95415, 1.000000
),(1,389, 68, 389, 23785, 29283, 29283, 1.000000),(1,274, 12, 274, 58834, 80362, 80362, 1.000000),(1,12, 
55, 12, 35136, 55490, 55490, 1.000000)]'::yflow);
select yflow_qtts('[(1,35, 93, 35, 21170, 2685, 2685, 1.000000),(1,636, 50, 636, 12213, 95415, 95415, 1.000000
),(1,389, 68, 389, 23785, 29283, 29283, 1.000000),(1,274, 12, 274, 58834, 80362, 80362, 1.000000),(1,12, 
55, 12, 35136, 55490, 55490, 1.000000)]'::yflow);

select yflow_show('[(1,62, 62, 6, 49210, 60487, 55111, 1.000000),(1,64, 64, 4, 64784, 55162, 53296, 1.000000),(1,52, 52, 14, 34697, 57236, 56208, 1.000000),(1,86, 86, 11, 19239, 28465, 27569, 1.000000),(1,87, 87, 4, 20786, 61473, 60554, 1.000000),(1,33, 33, 16, 828, 12515, 12515, 1.000000),(1,1, 1, 1, 35542, 66945, 17677, 1.000000),(1,102, 102, 15, 87633, 69633, 33223, 1.000000)]'::yflow);
select yflow_qtts('[(1,62, 62, 6, 49210, 60487, 55111, 1.000000),(1,64, 64, 4, 64784, 55162, 53296, 1.000000),(1,52, 52, 14, 34697, 57236, 56208, 1.000000),(1,86, 86, 11, 19239, 28465, 27569, 1.000000),(1,87, 87, 4, 20786, 61473, 60554, 1.000000),(1,33, 33, 16, 828, 12515, 12515, 1.000000),(1,1, 1, 1, 35542, 66945, 17677, 1.000000),(1,102, 102, 15, 87633, 69633, 33223, 1.000000)]'::yflow);

select yflow_show('[(2, 3298, 3298, 25, 87502, 61824, 20450, 1.000000),(2, 1090, 1090, 91, 41375, 55121, 1, 1.000000),(78, 10013, 10013, 72, 55121, 58560, 58559, 1.000000)]'::yflow);

/* IGNOREOMEGA QTTNOLIMIT */
select yflow_show('[
(2, 3298, 3298, 25, 10, 20, 20, 1.000000),
(2, 1090, 1090, 91, 10, 10, 10, 1.000000),
(78, 10013, 10013, 72, 0, 0, 0, 1.000000)]'::yflow);
