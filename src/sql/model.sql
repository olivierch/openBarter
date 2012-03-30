/*
drop schema if exists t cascade;
create schema t;
set schema 't';
*/
create extension flow;

\i sql/init.sql
\i sql/order.sql
\i sql/quote.sql
\i sql/admin.sql
\i sql/user.sql
\i sql/stat.sql

/* By default, public has no access to the schema t
roles market and admin can only read tables and views
they can only execute functions when specified by previous scripts.
*/
/*
GRANT USAGE ON SCHEMA t TO market,admin;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA t FROM public;
REVOKE ALL ON ALL TABLES IN SCHEMA t FROM public;
GRANT SELECT ON ALL TABLES IN SCHEMA t TO market,admin;
*/
GRANT market TO client; -- market is opened

