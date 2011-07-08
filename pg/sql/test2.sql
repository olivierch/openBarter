SET client_min_messages = warning;
\set ECHO none
-- CREATE LANGUAGE PLPGSQL;
\i openbarter.sql
\set ECHO all
RESET client_min_messages;
/*
truncate table tlomega restart identity cascade;
truncate table tomega restart identity cascade;

truncate table tcommit restart identity ;
truncate table tdraft restart identity cascade;

truncate table tnoeud restart identity cascade;
truncate table tstock restart identity cascade;
truncate table towner restart identity cascade;
truncate table tquality restart identity cascade;
-- truncate table tdepositary restart identity cascade;
truncate table tmvt restart identity cascade;
truncate table tldraft restart identity cascade;
select setval('tdraft_id_seq',1);
*/
-- insert into towner (name) values ('market');

select fcreate_quality('q1');
select fcreate_quality('q2');
select fcreate_quality('q3');
select fcreate_quality('q4');
select fcreate_quality('q5');
select fcreate_quality('q6');

-- owners are created
SELECT fadd_account('o1','olivier>q1',1000); 
SELECT fadd_account('o1','olivier>q2',1000); 
SELECT fadd_account('o1','olivier>q3',1000); 
SELECT fsub_account('o1','olivier>q1',1000); 
SELECT fsub_account('o1','olivier>q2',1000); 
SELECT fsub_account('o1','olivier>q3',500); 

-- should be 0
SELECT corrupted_stock_a+corrupted_stock_s+unbananced_qualities+corrupted_draft as errors from fstats();

select qown,qname,owner,qtt from vowned;
select qown,qname,qtt from vbalance;
select id,did,provider,nat,qtt,receiver from vmvt;




