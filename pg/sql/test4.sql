SET client_min_messages = warning;
\set ECHO none
\i uninstall_openbarter.sql
\i openbarter.sql
set search_path=market;
\set ECHO all
RESET client_min_messages;
select setval('ob.tdraft_id_seq',100);
select market.fcreate_quality('q1');
select market.fcreate_quality('q2');
select market.fcreate_quality('q3');
select market.fcreate_quality('q4');
select market.fcreate_quality('q5');
select market.fcreate_quality('q6');

select market.fadd_account('o1','olivier>q1',1000);
select market.fadd_account('o2','olivier>q2',1000);
select market.fadd_account('o3','olivier>q3',1000);

select market.finsert_bid('o1','olivier>q1',100,50,'olivier>q3');
select market.finsert_bid('o2','olivier>q2',100,50,'olivier>q1');
select market.finsert_bid('o3','olivier>q3',100,50,'olivier>q2');
-- executes getdraft_get(6,2,3,2)

-- should be 0
SELECT corrupted_stock_a+corrupted_stock_s+unbananced_qualities+corrupted_draft as errors from market.fstats();

select market.faccept_draft(100,'o1');
select market.faccept_draft(100,'o2');
select market.faccept_draft(100,'o3');

-- should be 0
SELECT corrupted_stock_a+corrupted_stock_s+unbananced_qualities+corrupted_draft as errors from market.fstats();

select qown,qname,owner,qtt from market.vowned;
select qown,qname,qtt from market.vbalance;
select id,did,provider,nat,qtt,receiver from market.vmvt;






