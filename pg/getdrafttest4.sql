truncate table ob_tlomega restart identity cascade;
truncate table ob_tomega restart identity cascade;

truncate table ob_tcommit restart identity ;
truncate table ob_tdraft restart identity cascade;

truncate table ob_tnoeud restart identity cascade;
truncate table ob_tstock restart identity cascade;
truncate table ob_towner restart identity cascade;
insert into ob_towner (name) values ('market');
truncate table ob_tquality restart identity cascade;
-- truncate table ob_tdepositary restart identity cascade;
truncate table ob_tmvt restart identity cascade;
truncate table ob_tldraft restart identity cascade;
select setval('ob_tdraft_id_seq',100);
insert into ob_towner (name) values ('market');

select ob_fcreate_quality('q1');
select ob_fcreate_quality('q2');
select ob_fcreate_quality('q3');
select ob_fcreate_quality('q4');
select ob_fcreate_quality('q5');
select ob_fcreate_quality('q6');

select ob_fadd_account('o1','olivier>q1',1000);
select ob_fadd_account('o2','olivier>q2',1000);
select ob_fadd_account('o3','olivier>q3',1000);

select ob_finsert_bid('o1','olivier>q1',100,50,'olivier>q3');
select ob_finsert_bid('o2','olivier>q2',100,50,'olivier>q1');
select ob_finsert_bid('o3','olivier>q3',100,50,'olivier>q2');
-- executes ob_getdraft_get(6,2,3,2)

-- should be 0
SELECT corrupted_stock_a+corrupted_stock_s+unbananced_qualities+corrupted_draft as errors from ob_fstats();
/*
select ob_faccept_draft(100,'o1');
select ob_faccept_draft(100,'o2');
select ob_faccept_draft(100,'o3');

-- should be 0
SELECT corrupted_stock_a+corrupted_stock_s+unbananced_qualities+corrupted_draft as errors from ob_fstats();

select * from ob_vowned;
select * from ob_vbalance;
select * from ob_vmvt;
*/





