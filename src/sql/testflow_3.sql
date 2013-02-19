
\i sql/model.sql
RESET client_min_messages;
RESET log_error_verbosity;
SET client_min_messages = notice;
SET log_error_verbosity = terse;


select * from fsubmitbarter(1,'a',NULL,'q2',10,'q1',20);
select * from fproducemvt();
select * from fsubmitbarter(1,'b',NULL,'q3',10,'q2',20);
select * from fproducemvt();
select * from fsubmitbarter(1,'c',NULL,'q1',10,'q3',20);
select * from fproducemvt();
-- select * from femptystack();
select id,nbc,nbt,grp,xid,xoid,own_src,own_dst,qtt,nat,ack from tmvt order by id desc limit 3; 

select * from fsubmitbarter(1,'a',NULL,'q2',10,'q1',20);
select * from fproducemvt();
select * from fsubmitbarter(1,'b',NULL,'q3',10,'q2',20);
select * from fproducemvt();
select * from fsubmitbarter(1,'d',NULL,'q3',10,'q1',20);
select * from fproducemvt();
select * from fsubmitbarter(1,'c',NULL,'q1',20,'q3',40);
select * from fproducemvt();
select id,nbc,nbt,grp,xid,xoid,own_src,own_dst,qtt,nat,ack from tmvt order by id desc limit 5;

