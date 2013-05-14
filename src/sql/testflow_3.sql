\set ECHO none
\i sql/model.sql
RESET client_min_messages;
RESET log_error_verbosity;
SET client_min_messages = notice;
SET log_error_verbosity = terse;
--\set ECHO queries -- équivalent de psql -e

\set ECHO all -- repeate commands in results

/* fsubmitbarter(_type dtypeorder,_own,_oid,_qua_requ,_qtt_requ,_qua_prov,_qtt_prov,_qtt,_interval) */
select * from fsubmitbarter(1,'a',NULL,'q2',10,'q1',20,'1 hour'::interval);
select * from fproducemvt();
select * from fsubmitbarter(1,'b',NULL,'q3',10,'q2',20,'1 hour'::interval);
select * from fproducemvt();
select * from fsubmitbarter(1,'c',NULL,'q1',10,'q3',20,'1 hour'::interval);
select * from fproducemvt();
-- select * from femptystack();
select id,nbc,nbt,grp,xid,xoid,own_src,own_dst,qtt,nat,ack from tmvt order by id desc limit 3; 

/*cycle with 5 partners */
select * from fsubmitbarter(1,'a',NULL,'q2',10,'q1',20,'1 hour'::interval);
select * from fproducemvt();
select * from fsubmitbarter(1,'b',NULL,'q3',10,'q2',20,'1 hour'::interval);
select * from fproducemvt();
select * from fsubmitbarter(1,'d',NULL,'q3',10,'q1',20,'1 hour'::interval);
select * from fproducemvt();
select * from fsubmitbarter(1,'c',NULL,'q1',20,'q3',40,'1 hour'::interval);
select * from fproducemvt();
select id,nbc,nbt,grp,xid,xoid,own_src,own_dst,qtt,nat,ack from tmvt order by id desc limit 5;
select count(*) from torder;
/* order book empty */

