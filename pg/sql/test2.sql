SET client_min_messages = warning;
\set ECHO none
CREATE LANGUAGE PLPGSQL;
\i openbarter.sql
\set ECHO all
RESET client_min_messages;
/*
truncate table ob_tlomega restart identity cascade;
truncate table ob_tomega restart identity cascade;

truncate table ob_tcommit restart identity ;
truncate table ob_tdraft restart identity cascade;

truncate table ob_tnoeud restart identity cascade;
truncate table ob_tstock restart identity cascade;
truncate table ob_towner restart identity cascade;
truncate table ob_tquality restart identity cascade;
-- truncate table ob_tdepositary restart identity cascade;
truncate table ob_tmvt restart identity cascade;
truncate table ob_tldraft restart identity cascade;
select setval('ob_tdraft_id_seq',1);
*/
-- insert into ob_towner (name) values ('market');

select ob_fcreate_quality('q1');
select ob_fcreate_quality('q2');
select ob_fcreate_quality('q3');
select ob_fcreate_quality('q4');
select ob_fcreate_quality('q5');
select ob_fcreate_quality('q6');

-- owners are created
SELECT ob_fadd_account('o1','olivier>q1',1000); 
SELECT ob_fadd_account('o1','olivier>q2',1000); 
SELECT ob_fadd_account('o1','olivier>q3',1000); 
SELECT ob_fsub_account('o1','olivier>q1',1000); 
SELECT ob_fsub_account('o1','olivier>q2',1000); 
SELECT ob_fsub_account('o1','olivier>q3',500); 

-- should be 0
SELECT corrupted_stock_a+corrupted_stock_s+unbananced_qualities+corrupted_draft as errors from ob_fstats();

select qown,qname,owner,qtt from ob_vowned;
select qown,qname,qtt from ob_vbalance;
select id,did,provider,nat,qtt,receiver from ob_vmvt;




