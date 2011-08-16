SET client_min_messages = warning;
\set ECHO none
-- CREATE LANGUAGE PLPGSQL;
\i openbarter.sql
set search_path=market;
\set ECHO all
RESET client_min_messages;
-- insert into towner (name) values ('market');

select market.fcreate_quality('q1');
select market.fcreate_quality('q2');
select market.fcreate_quality('q3');
select market.fcreate_quality('q4');
select market.fcreate_quality('q5');
select market.fcreate_quality('q6');

-- owners are created
SELECT market.fadd_account('o1','olivier>q1',1000); 
SELECT market.fadd_account('o1','olivier>q2',1000); 
SELECT market.fadd_account('o1','olivier>q3',1000); 
SELECT market.fsub_account('o1','olivier>q1',1000); 
SELECT market.fsub_account('o1','olivier>q2',1000); 
SELECT market.fsub_account('o1','olivier>q3',500); 

-- should be 0
SELECT corrupted_stock_a+corrupted_stock_s+unbananced_qualities+corrupted_draft as errors from market.fstats();

select qown,qname,owner,qtt from market.vowned;
select qown,qname,qtt from market.vbalance;
select id,did,provider,nat,qtt,receiver from market.vmvt;




