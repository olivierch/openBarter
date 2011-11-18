\i sql/drop_model.sql
\i sql/model.sql
insert into ob_tquality (name) values ('q1'),('q2'),('q3'),('q4'),('q5'),('q6'),('q7'),('q8');
insert into ob_towner (name) values ('w1'),('w2'),('w3'),('w4'),('w5'),('w6'),('w7'),('w8');
insert into ob_tstock (own,qtt,np) values (1,100,1),(2,200,2),(3,300,3),(4,400,4),(5,500,5),(6,600,6),(7,700,7),(8,800,8);
insert into ob_tnoeud (sid,nr,qtt_prov,qtt_requ) values
(1,5,1,1),(2,1,1,1),(3,2,1,1),(4,3,1,1);
-- np: 5->1->2->3->4
-- bid: 1  2  3  4

-- ob_get_omegas(_nr int8,_np int8) RETURNS SETOF int8[]
select ob_get_omegas(4,5); -- {100,100}
select ob_get_omegas(4,1); -- {200,200}
select ob_get_omegas(4,2); -- {300,300}
select ob_get_omegas(4,3); -- {400,400}
select ob_get_omegas(3,5); -- {100,100} -- pb
select ob_get_omegas(3,1); -- {200,200}
select ob_get_omegas(300,1); -- not results

truncate ob_tquality cascade;

