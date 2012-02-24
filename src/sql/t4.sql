/*
SET client_min_messages = warning;
\set ECHO none
\i sql/model2.sql
*/
set search_path='t';
\set ECHO all
-- RESET client_min_messages;

insert into tuser(name) values (current_user);

select finsertorder('o1',current_user || '/q1',1,3,current_user || '/q3',-1);
select finsertorder('o2',current_user || '/q2',2,1,current_user || '/q1',-1);
select finsertorder('o3',current_user || '/q3',3,2,current_user || '/q2',-1);




