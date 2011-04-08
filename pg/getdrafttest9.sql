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
--insert into ob_towner (name) values ('market');
--
-- INSERT INTO ob_tdepositary (name) VALUES ('d');
INSERT INTO ob_tquality (name) VALUES 
	('q1'),
	('q2'),
	('q3'),
	('q4'),
	('q5'),
	('q6');
INSERT INTO ob_towner (name) VALUES ('o1'),('o2'),('o3'),('o4'),('o5'),('o6');

select ob_fadd_account('o1','olivier>q1',1000);
select ob_fadd_account('o2','olivier>q2',1000);
select ob_fadd_account('o3','olivier>q3',1000);

select ob_finsert_bid('o1','olivier>q1',100,50,'olivier>q3'); /* sid=7,bid=1 */
select ob_finsert_bid('o2','olivier>q2',50,50,'olivier>q1'); /* sid=8,bid=2 */
select ob_finsert_sbid(2,200,'olivier>q4');

select ob_finsert_bid('o3','olivier>q3',100,50,'olivier>q2');

select * from ob_fbalance(); /* corrupted account olivier expected empty */
select ob_faccept_draft(100,'o1');
select ob_faccept_draft(100,'o2');
select ob_faccept_draft(100,'o3');
select * from ob_fbalance(); 





