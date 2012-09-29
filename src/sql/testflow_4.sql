-- set schema 't';

select * from finsertorder('x','b',160,40,'a');
select * from finsertorder('y','c',160,80,'b');
select * from finsertorder('t','c',100,100,'a');

select * from fgetquote('z','a',20,0,'c'); -- expected (qtt_prov,qtt_requ)= (20,160)
select qtt_in,qtt_out from fgetquote('z','a',20,160,'c');
select qtt_in,qtt_out from fexecquote('z',4);
select id,uuid,nb,oruuid,grp,provider,quality,qtt,receiver from vmvt order by uuid;
select * from fgetagr('1-9') where _own='z'; -- expected as first quote (_qtt_prov,_qtt_requ)=(20,160)
select * from fgetquote('z','a',100,0,'c'); -- expected (qtt_in,qtt_out)= (100,100)

select * from finsertorder('z','a',100,100,'c'); -- one agreements
select * from fgetagr('1-12') where _own='z'; -- expected as first quote

select * from finsertorder('x','b2',160,40,'a2');
select * from finsertorder('y','c2',160,80,'b2');
select * from finsertorder('t','c2',90,10,'a2');
select * from fgetquote('z','a2',10,0,'c2');-- expected (qtt_in,qtt_out)= (90,10)
select * from finsertorder('z','a2',10,90,'c2'); 
select * from fgetagr('1-14') where _own='z'; -- expected as first quote

select * from fgetquote('z','a2',20,0,'c2'); -- expected (qtt_in,qtt_out)= (160,20)
select * from finsertorder('z','a2',20,160,'c2');
select * from fgetagr('1-16') where _own='z'; -- expected as first quote
/*
-- select * from vmvt;
*/
