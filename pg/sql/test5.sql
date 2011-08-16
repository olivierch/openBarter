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

select market.fadd_account('o1','olivier>q1',1000);
select market.fadd_account('o2','olivier>q2',1000);
select market.fadd_account('o3','olivier>q3',1000);
select market.fadd_account('o4','olivier>q4',1000);
select market.fadd_account('o5','olivier>q5',1000);
select market.fadd_account('o6','olivier>q2',1000);

select market.finsert_bid('o1','olivier>q1',100,50,'olivier>q3'); /* ->q3 S1 q1-> */
select market.finsert_bid('o2','olivier>q2',100,50,'olivier>q1'); /* ->q1 S2 q2-> */
select market.finsert_bid('o4','olivier>q4',50 ,50,'olivier>q3'); /* ->q3 S4 q4-> */
select market.finsert_bid('o5','olivier>q5',50 ,50,'olivier>q4'); /* ->q4 S5 q5-> */
select market.finsert_bid('o6','olivier>q2',50 ,50,'olivier>q5'); /* ->q5 S6 q2-> */

select market.finsert_bid('o3','olivier>q3',200,100,'olivier>q2'); /* ->q2 S3 q3-> */
/* expected 2 draft with 3 and 4 partners */
select did,status,owner,cntcommit,flags from market.vdraft order by did,owner;
select id,status,versionsg,nbsource,nbnoeud,cflags from ob.tdraft;
select * from ob.tcommit where did=100;

select id,did,provider,nat,qtt,receiver from market.vmvt where provider!='market' and receiver!='market';

select market.faccept_draft(100,'o1');
-- select id,did,provider,nat,qtt,receiver from tcommit where did=100;
select market.faccept_draft(100,'o2');
select market.faccept_draft(100,'o3');
/* draft 100 accepted */
select id,did,provider,nat,qtt,receiver from market.vmvt where provider!='market' and receiver!='market';

select market.faccept_draft(101,'o3');
select market.faccept_draft(101,'o4');
select market.faccept_draft(101,'o5');
select market.faccept_draft(101,'o6');
/* draft 101 accepted */
select id,did,provider,nat,qtt,receiver from market.vmvt where provider!='market' and receiver!='market';

-- should be 0
SELECT corrupted_stock_a+corrupted_stock_s+unbananced_qualities+corrupted_draft as errors from market.fstats();


