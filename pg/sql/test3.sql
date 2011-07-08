/*truncate table ob.tlomega restart identity cascade;
truncate table ob.tomega restart identity cascade;

truncate table ob.tcommit restart identity ;
truncate table ob.tdraft restart identity cascade;

truncate table ob.tnoeud restart identity cascade;
truncate table ob.tstock restart identity cascade;
truncate table ob.towner restart identity cascade;
insert into ob.towner (name) values ('market');
truncate table ob.tquality restart identity cascade;
-- truncate table ob.tdepositary restart identity cascade;
truncate table ob.tmvt restart identity cascade;
truncate table ob.tldraft restart identity cascade;
*/
SET client_min_messages = warning;
\set ECHO none
\i uninstall_openbarter.sql
\i openbarter.sql
\set ECHO all
RESET client_min_messages;
select setval('ob.tdraft_id_seq',100);

select ob.fcreate_quality('q1');
select ob.fcreate_quality('q2');

select ob.fadd_account('o1','olivier>q1',1000);
select ob.fadd_account('o2','olivier>q2',1000);

select ob.finsert_bid('o1','olivier>q1',100,50,'olivier>q2');
select ob.finsert_bid('o2','olivier>q2',100,50,'olivier>q1');
-- executes ob.getdraft_get(6,2,3,2)

-- should be 0
SELECT corrupted_stock_a+corrupted_stock_s+unbananced_qualities+corrupted_draft as errors from ob.fstats();

select ob.faccept_draft(100,'o1');
select ob.faccept_draft(100,'o2');

-- should be 0
SELECT corrupted_stock_a+corrupted_stock_s+unbananced_qualities+corrupted_draft as errors from ob.fstats();

select qown,qname,owner,qtt from ob.vowned;
select qown,qname,qtt from ob.vbalance;
select id,did,provider,nat,qtt,receiver from ob.vmvt;






