-- SET search_path TO test;
truncate torder;
truncate tstack;
truncate tmvt;
truncate towner;
SELECT setval('tstack_id_seq',1,false);

copy torder from '/home/olivier/ob92/src/sql/torder_test_10000.sql';
copy towner from '/home/olivier/ob92/src/sql/towner_test_10000.sql';
truncate tstack;
SELECT setval('tstack_id_seq',10000,true);

select * from fsubmitquote(1,'own82','qlt22','qlt23');select * from fproducemvt();
select json from tmvt where id=1;
select * from fsubmitbarter(1,'own82',NULL,'qlt22',67432,'qlt23',30183);select * from fproducemvt();
select xid,own_src,own_dst,qtt,nat from tmvt order by id desc limit 3;


select * from fsubmitquote(1,'own82','qlt22','qlt23');select * from fproducemvt(); 
select json from tmvt order by id desc limit 1;
select * from fsubmitquote(1,'own82','qlt22',61017,'qlt23',45276);select * from fproducemvt(); 
select json from tmvt order by id desc limit 1;
select * from fsubmitquote(1,'own82','qlt22',60000,'qlt23',45276);select * from fproducemvt(); 
select json from tmvt order by id desc limit 1;
select * from fsubmitbarter(1,'own82',NULL,'qlt22',60000,'qlt23',45276);select * from fproducemvt();
select xid,own_src,own_dst,qtt,nat from tmvt order by id desc limit 2;

select * from fsubmitquote(1,'own82','qlt2',60000,'qlt23',45276);select * from fproducemvt();
select json from tmvt order by id desc limit 1;
select * from fsubmitbarter(1,'own82',NULL,'qlt2',60000,'qlt23',45276);select * from fproducemvt();
select id,nbt,nbc,xid,own_src,own_dst,qtt,nat from tmvt order by id desc limit 12;
select sum(qtt) from tmvt where own_src='own82' and nat='qlt23' and id>18;
select sum(qtt) from tmvt where own_dst='own82' and nat='qlt2' and id>18;




