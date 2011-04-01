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
select setval('ob_tdraft_id_seq',100);
--insert into ob_towner (name) values ('market');
--
-- INSERT INTO ob_tdepositary (name) VALUES ('d');
INSERT INTO ob_tquality (own,name) VALUES 
	('d','q1'),
	('d','q2'),
	('d','q3'),
	('d','q4'),
	('d','q5'),
	('d','q6');
INSERT INTO ob_towner (name) VALUES ('o1'),('o2'),('o3'),('o4'),('o5'),('o6');
/*
SELECT add_account(2,1,1000); -- o2,q1,1000 ->acc 2
SELECT add_account(3,2,1000); -- o3,q2,1000 ->acc 4
SELECT add_account(4,3,1000); -- o4,q3,1000 ->acc 6

select insert_bid(2,50,1.0,3); --o1 q3->(50q1) 1.0
select insert_bid(4,60,1.0,1); --o1 q1->(60q2) 1.0
*/
INSERT INTO ob_tstock (own,qtt,nf,type) VALUES 
	(1,100,1,'S'),
	(2,100,2,'S'),
	(3,500,3,'S'),
	(4,100,4,'S'),
	(5,100,5,'S'),
	(6,100,2,'S');
INSERT INTO ob_tnoeud (sid,omega,nr,nf,own) VALUES 
	(1,2.1,3,1,1), /* ->q3 S1 q1-> */
	(2,2.1,1,2,2), /* ->q1 S2 q2-> */ 
	(4,1.1,3,4,4), /* ->q3 S4 q4-> */
	(5,2.1,4,5,5), /* ->q4 S5 q5-> */
	(6,1.1,5,2,6)  /* ->q5 S6 q2-> */
	;
/* test with SELECT ob_getdraft_get(3,2.1,3,2);  ob_getdraft(stockId,omega,nF,nR)
			   ->q2 S3 q3-> 
expected 2 draft à 3 et à 4 */





