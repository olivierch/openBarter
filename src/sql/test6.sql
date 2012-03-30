\i sql/model.sql

select fcreateuser(session_user);
select setseed(0.5);

select * from finsertorder('x','b',160,40,'a');
select * from finsertorder('y','c',160,80,'b');
select * from finsertorder('t','c',100,100,'a');

select * from fgetquote('z','a','c'); -- expected (dim,qtt_prov,qtt_requ)= (3,20,160)
select * from finsertorder('z','a',20,160,'c'); -- one agreements
select * from fgetagr(1) where _own='z'; -- expected as first quote
select * from fgetquote('z','a','c'); -- expected (dim,qtt_prov,qtt_requ)= (2,100,100)
select * from finsertorder('z','a',100,100,'c'); -- one agreements
select * from fgetagr(4) where _own='z'; -- expected as first quote

select * from finsertorder('x','b2',160,40,'a2');
select * from finsertorder('y','c2',160,80,'b2');
select * from finsertorder('t','c2',90,10,'a2');

select * from fgetquote('z','a2','c2'); -- expected (dim,qtt_prov,qtt_requ)= (2,10,90)
select * from finsertorder('z','a2',10,90,'c2'); 
select * from fgetagr(6) where _own='z'; -- expected as first quote
select * from fgetquote('z','a2','c2'); -- expected (dim,qtt_prov,qtt_requ)= (3,20,160)
select * from finsertorder('z','a2',20,160,'c2');
select * from fgetagr(8) where _own='z'; -- expected as first quote
