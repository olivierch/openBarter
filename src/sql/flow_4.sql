-- \i sql/drop_model.sql
-- \i sql/model.sql

\i sql/truncate_model.sql
set search_path = ob;
-- the fisrt draft.id used will be 1
select setval('ob_tdraft_id_seq',1,false);
-- the first noeud.id used will be 5
select setval('ob_tnoeud_id_seq',4);

select ob_fadd_account('own1','q1',100);
select ob_fadd_account('own2','q2',200);
select ob_finsert_bid('own1','q1',50,100,'q2');
select ob_finsert_bid('own2','q2',100,50,'q1');
--draft 1 formed
select ob_faccept_draft(1,'own1');
select ob_faccept_draft(1,'own2');
select count(*) from ob_tnoeud; -- bids are removed after the draft is accepted, since corresponding stocks are empty

select ob_finsert_bid('own1','q1',50,100,'q2');
select ob_finsert_bid('own2','q2',100,50,'q1'); -- bid 8
--draft 2 formed
select ob_frefuse_draft(2,'own1');
-- select * from ob_trefused; -- relation (x->y) = (8->7) refused
select refused from ob_tnoeud where id=7;
-- bid 8 remains
select ob_fadd_account('own3','q2',200);
select ob_finsert_bid('own3','q2',100,50,'q1');
-- draft 3 formed
select ob_faccept_draft(3,'own1');
select ob_faccept_draft(3,'own3');

select ob_fadd_account('own4','q1',100);
select ob_finsert_bid('own3','q1',50,100,'q2'); -- bid 10
-- draft 4 formed with bid 10 and 8


select ob_fdelete_bid(10); 
select ob_fdelete_bid(8);

select ob_fadd_account('own1','qa1',200);
select ob_fadd_account('own2','qa2',200);
select ob_fadd_account('own3','qa3',200);
select ob_fadd_account('own4','qa4',200);
select ob_fadd_account('own5','qa5',200);
select ob_fadd_account('own6','qa6',200);
select ob_fadd_account('own7','qa7',200);
select ob_fadd_account('own8','qa8',200);

select ob_finsert_bid('own1','qa1',100,100,'qa2');
select ob_finsert_bid('own2','qa2',100,100,'qa3');
select ob_finsert_bid('own3','qa3',100,100,'qa4');
select ob_finsert_bid('own4','qa4',100,100,'qa5');
select ob_finsert_bid('own5','qa5',100,100,'qa6');
select ob_finsert_bid('own6','qa6',100,100,'qa7');
select ob_finsert_bid('own7','qa7',100,100,'qa8');
select ob_finsert_bid('own8','qa8',100,100,'qa1');
--draft 5 formed
select ob_faccept_draft(5,'own1');
select ob_faccept_draft(5,'own2');
select ob_faccept_draft(5,'own3');
select ob_faccept_draft(5,'own4');
select ob_faccept_draft(5,'own5');
select ob_faccept_draft(5,'own6');
select ob_faccept_draft(5,'own7');
select ob_faccept_draft(5,'own8');
--draft 5 accepted
select count(*) from ob_tnoeud; -- bids are removed after the draft is accepted, since corresponding stocks are empty 

