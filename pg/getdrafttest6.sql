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
select ob_fadd_account('o4','olivier>q4',1000);
select ob_fadd_account('o5','olivier>q5',1000);
select ob_fadd_account('o6','olivier>q2',1000);

select ob_finsert_bid('o1','olivier>q1',100,50,'olivier>q3'); /* ->q3 S1 q1-> */
select ob_finsert_bid('o2','olivier>q2',100,50,'olivier>q1'); /* ->q1 S2 q2-> */
select ob_finsert_bid('o4','olivier>q4',50 ,50,'olivier>q3'); /* ->q3 S4 q4-> */
select ob_finsert_bid('o5','olivier>q5',50 ,50,'olivier>q4'); /* ->q4 S5 q5-> */
select ob_finsert_bid('o6','olivier>q2',50 ,50,'olivier>q5'); /* ->q5 S6 q2-> */

INSERT INTO ob_tnoeud (sid,omega,nr,nf,own,provided_quantity,required_quantity) 
	VALUES(12,1.0,2,1,2,100,100); /* ->q2 S1 q1-> */
select ob_finsert_bid('o3','olivier>q3',200,50,'olivier>q2'); /* ->q2 S3 q3-> */
/* expected 1 loop exception and 1 draft of 4 commits */
select * from ob_fbalance(); /* corrupted account olivier expected empty */





