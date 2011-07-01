
SET client_min_messages = warning;
\set ECHO none
\i uninstall_openbarter.sql
\i openbarter.sql
\set ECHO all
RESET client_min_messages;
SET client_min_messages = INFO;
SET log_min_messages = INFO;
select setval('ob_tdraft_id_seq',100);

select ob_fcreate_quality('q1');
select ob_fcreate_quality('q2');

select ob_fadd_account('o1','olivier>q1',1000);
select ob_fadd_account('o2','olivier>q2',1000);

select ob_finsert_bid('o1','olivier>q1',100,50,'olivier>q2');
insert into ob_tstock (own,qtt,nf,type) values (3,100,2,'S');
select ob_getdraft_get(4,2.,2,1);

