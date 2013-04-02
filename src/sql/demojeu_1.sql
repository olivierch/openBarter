
drop schema IF EXISTS market CASCADE;
CREATE SCHEMA market;
SET search_path TO market;
grant usage on schema market to public;
\i sql/model.sql
RESET client_min_messages;
RESET log_error_verbosity;
SET client_min_messages = notice;
SET log_error_verbosity = terse;


select * from fsubmitbarter(1,'luc',NULL,'Kg of carrots',10,'Kg of onions',20,'1 hour'::interval);
select * from fproducemvt();
select * from fsubmitbarter(1,'cecile',NULL,'Kg of garlic',10,'Kg of carrots',20,'1 hour'::interval);
select * from fproducemvt();
select * from fsubmitbarter(1,'rose',NULL,'Kg of onions',10,'Kg of garlic',20,'1 hour'::interval);
select * from fproducemvt();
-- select * from femptystack();
select id,nbc,nbt,grp,xid,xoid,own_src,own_dst,qtt,nat,ack from tmvt order by id desc limit 3; 

select * from fsubmitbarter(1,'luc',NULL,'Kg of carrots',10,'Kg of onions',20,'1 hour'::interval);
select * from fproducemvt();
select * from fsubmitbarter(1,'cecile',NULL,'Kg of garlic',10,'Kg of carrots',20,'1 hour'::interval);
select * from fproducemvt();
select * from fsubmitbarter(1,'paul',NULL,'Kg of garlic',10,'Kg of onions',20,'1 hour'::interval);
select * from fproducemvt();
select * from fsubmitbarter(1,'rose',NULL,'Kg of onions',20,'Kg of garlic',40,'1 hour'::interval);
select * from fproducemvt();
select id,nbc,nbt,grp,xid,xoid,own_src,own_dst,qtt,nat,ack from tmvt order by id desc limit 5;

select * from fsubmitbarter(1,'luc',NULL,'ctEuro',10,'ctDollar',20,'1 hour'::interval);
select * from fproducemvt();
select * from fsubmitbarter(1,'cecile',NULL,'ctDirham',10,'ctEuro',20,'1 hour'::interval);
select * from fproducemvt();

--select * from fgetquote(78,'test','ctEuro',NULL,'ctDirham',NULL,NULL);
