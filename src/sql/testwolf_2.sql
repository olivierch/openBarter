
\i sql/model.sql
RESET client_min_messages;
RESET log_error_verbosity;
SET client_min_messages = notice;
SET log_error_verbosity = terse;

select * from fsubmitorder('a',NULL,'q2',10,'q1',20);
select * from fproducemvt();

select * from fsubmitorder('b',NULL,'q3',10,'q2',20);
select * from fproducemvt();
select * from fsubmitorder('c',NULL,'q1',10,'q3',20);
select * from fproducemvt();

select id,nbc,nbt,grp,xid,xoid,own_src,own_dst,qtt,nat from tmvt;



