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
select * from fsubmitbarter(1,'own82',NULL,'qlt22',67432,'qlt23',30183,30183);select * from fproducemvt();

select * from fsubmitquote(2,'own82','qlt22','qlt23');select * from fproducemvt(); 
select * from fsubmitbarter(2,'own82',NULL,'qlt22',61017,'qlt23',45276,45276);select * from fproducemvt();
select id,type,json from tmvt where type >3;




