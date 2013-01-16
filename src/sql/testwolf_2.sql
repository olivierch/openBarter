
\i sql/model.sql
RESET client_min_messages;
RESET log_error_verbosity;
SET client_min_messages = notice;
SET log_error_verbosity = terse;

select * from fsubmitorder('a',NULL,'q2',10,NULL,'q1',20,NULL,NULL);
-- select * from fproducemvt();

select * from fsubmitorder('b',NULL,'q3',10,NULL,'q2',20,NULL,NULL);
-- select * from fproducemvt();
select * from fsubmitorder('c',NULL,'q1',10,NULL,'q3',20,NULL,NULL);
-- select * from fproducemvt();
select * from femptystack();
select id,nbc,nbt,grp,xid,xoid,own_src,own_dst,qtt,nat,ack from tmvt;

select * from acceptmvt();
select * from acceptmvt();
select * from acceptmvt();

select count(*) from tmvt;
