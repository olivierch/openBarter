/*drop schema if exists t cascade;
create schema t;
set schema 't';*/
SET client_min_messages = warning;
\set ECHO none
\i sql/model.sql
-- set search_path='t';
\set ECHO all
 RESET client_min_messages;
 
select '(1,2,3,4,5,6,7)'::yorder;
select '(1,2,3,4,5,6,7)'::yorder='(1,5,6,7,8,9,10)'::yorder; --true
select yorder_np('(1,2,3,4,5,6,7)'::yorder); -- 5
select yorder_nr('(1,2,3,4,5,6,7)'::yorder); -- 3
select yorder_spos('(1,2,3,4,5,6,7)'::yorder); -- true
select yorder_spos('(1,2,3,4,5,6,0)'::yorder); -- false
select yorder_get(1,2,3,4,5,6,7);

select yflow('[]');
select yflow('[(1,2,3,4,5,6,7)]');
-- select yflow_show('[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1),(102,12,5,1,3,1,1)]');

select yflow('[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1),(102,12,5,1,6,1,1)]'); -- noloop
-- select yflow_show('[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1),(102,12,5,1,3,1,1)]'); -- loop
select yflow_status('[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1),(102,12,5,1,3,1,1)]'); --3

-- select yflow_show('[(100,10,3,1,4,1,1),(101,11,4,1,5,8,8),(0,12,5,1,3,1,0)]'); -- loop lastignore
select yflow_get('(1,2,3,4,5,6,7)'::yorder);

select yflow_follow(3,'[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1)]'::yflow,'(102,12,5,1,6,1,1)'::yorder); -- true
select yflow_get('[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1)]'::yflow,'(102,12,5,1,6,1,1)'::yorder);
select yflow_follow(3,'[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1)]'::yflow,'(102,12,5,1,6,1,0)'::yorder); -- false,qtt=0
select yflow_follow(3,'[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1)]'::yflow,'(102,12,6,1,7,1,1)'::yorder); -- false,np!=nr
select yflow_follow(2,'[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1)]'::yflow,'(102,12,5,1,6,1,1)'::yorder); -- false,maxlen reached
select yflow_follow(3,'[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1)]'::yflow,'(100,12,5,1,6,1,1)'::yorder); -- false, order in flow
select yflow_follow(3,'[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1)]'::yflow,'(102,12,5,1,3,1,1)'::yorder); -- true, cycle expected
select yflow_follow(3,'[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1)]'::yflow,'(102,12,5,1,4,1,1)'::yorder); -- false, cycle unexpected


select yflow_follow(3,'(102,12,2,1,3,1,1)'::yorder,'[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1)]'::yflow); -- true
select yflow_get('(102,12,2,1,3,1,1)'::yorder,'[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1)]'::yflow);
select yflow_follow(3,'(102,12,2,1,3,1,0)'::yorder,'[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1)]'::yflow); -- false,qtt=0
select yflow_follow(3,'(102,12,2,1,1000,1,1)'::yorder,'[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1)]'::yflow); -- false np!=nr
select yflow_follow(2,'(102,12,2,1,3,1,1)'::yorder,'[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1)]'::yflow); -- false maxlen reached
select yflow_follow(3,'(100,12,2,1,3,1,1)'::yorder,'[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1)]'::yflow); -- false order in flow
select yflow_follow(3,'(102,12,2,1,3,1,1)'::yorder,'[(100,10,3,1,4,1,1),(101,11,4,1,2,1,1)]'::yflow); -- true, cycle expected
select yflow_follow(3,'(102,12,4,1,3,1,1)'::yorder,'[(100,10,3,1,4,1,1),(101,11,4,1,2,1,1)]'::yflow); -- false, cycle unexpected

-- all orders reduced
select yflow_reduce('[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1),(102,12,5,1,3,1,1)]','[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1),(102,12,5,1,3,1,1)]');
select yflow_reduce('[(100,10,3,1,4,1,10),(101,11,4,1,5,1,10),(102,12,5,1,3,1,10)]','[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1),(102,12,5,1,3,1,1)]');
-- with lastignore (qtt_requ = 0)
select yflow_reduce('[(100,10,3,1,4,1,10),(101,11,4,1,5,1,10),(0,12,5,1,3,1,1)]','[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1),(12345,12,5,0,3,1,1)]');
-- just some orders reduced
select yflow_reduce('[(900,10,3,1,4,1,10),(101,11,4,1,5,1,10),(904,12,5,1,3,1,10)]','[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1),(102,12,5,1,3,1,1)]');
-- empty flow is unchanged
select yflow_reduce('[(900,10,3,1,4,1,10),(101,11,4,1,5,1,10),(904,12,5,1,3,1,0)]','[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1),(102,12,5,1,3,1,1)]');

