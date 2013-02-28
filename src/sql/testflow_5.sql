

\i sql/model.sql
RESET client_min_messages;
RESET log_error_verbosity;
SET client_min_messages = notice;
SET log_error_verbosity = terse;

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

/*
select * from fsubmitquote(1,'own82','qlt22','qlt23');select * from fproducemvt();
select json from tmvt order by id desc limit 1;
select * from fsubmitbarter(1,'own82',NULL,'qlt22',67432,'qlt23',30183,30183);select * from fproducemvt();
select xid,own_src,own_dst,qtt,nat from tmvt order by id desc limit 3;
*/



