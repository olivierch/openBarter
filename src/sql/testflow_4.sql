
/*
\i sql/model.sql

RESET client_min_messages;
RESET log_error_verbosity;
SET client_min_messages = notice;
SET log_error_verbosity = terse;
*/
SET search_path TO market;
truncate torder;
truncate tstack;
SELECT setval('tstack_id_seq',1,false);
truncate tmvt;
SELECT setval('tmvt_id_seq',1,false);
truncate towner;
SELECT setval('towner_id_seq',1,false);


select * from fsubmitbarter(1,'a',NULL,'q2',10,'q1',20,'1 hour'::interval);
select * from fproducemvt();
select * from fsubmitbarter(1,'b',NULL,'q3',20,'q2',40,'1 hour'::interval);
select * from fproducemvt();
select * from fsubmitbarter(1,'b',2   ,'q1',20,NULL,40,'1 hour'::interval);
select * from fproducemvt();
-- select * from femptystack();
select id,nbc,nbt,grp,xid,xoid,own_src,own_dst,qtt,nat,ack from tmvt order by id desc limit 2;
select * from fsubmitbarter(1,'a',NULL,'q2',10,'q1',20,'1 hour'::interval);
select * from fproducemvt();
select id,nbc,nbt,grp,xid,xoid,own_src,own_dst,qtt,nat,ack from tmvt order by id desc limit 2;
