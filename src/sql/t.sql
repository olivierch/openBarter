SET client_min_messages = warning;
\set ECHO none
\i sql/model2.sql
set search_path='t';
\set ECHO all
-- RESET client_min_messages;

insert into tuser(name) values (current_user);

select finsertorder('o1',current_user || '/q1',1,3,current_user || '/q3',-1);
select finsertorder('o2',current_user || '/q2',2,1,current_user || '/q1',-1);
select finsertorder('o3',current_user || '/q3',3,2,current_user || '/q2',-1);

-- 2 owners
-- update tconst set value=0 where name='VERIFY';
select finsertorder('o1',current_user || '/q1',1,3,current_user || '/q3');
select finsertorder('o2',current_user || '/q2',2,1,current_user || '/q1');
select finsertorder('o2',current_user || '/q3',3,2,current_user || '/q2'); 

-- no barter
select finsertorder('o1',current_user || '/q1',1,2,current_user || '/q2');
select finsertorder('o2',current_user || '/q2',2,1,current_user || '/q1');


-- long barter
select finsertorder('o1',current_user || '/q1',2,2,current_user || '/q2');
select finsertorder('o2',current_user || '/q2',2,1,current_user || '/q1');

-- short barter
select finsertorder('o1',current_user || '/q1',1,4,current_user || '/q2'); -- [1]
select finsertorder('o2',current_user || '/q2',2,1,current_user || '/q1'); -- refused

-- cycle with [1]
select finsertorder('o2',current_user || '/q2',4,1,current_user || '/q1');

select finsertorder('o2',current_user || '/q2',4,1,current_user || '/q1');
select finsertorder('o2',current_user || '/q2',4,1,current_user || '/q1');

-- 8 - cycle no barter
select finsertorder('o1',current_user || '/q1',1,1,current_user || '/q8');
select finsertorder('o2',current_user || '/q2',1,1,current_user || '/q1');
select finsertorder('o3',current_user || '/q3',1,1,current_user || '/q2');
select finsertorder('o4',current_user || '/q4',1,1,current_user || '/q3');
select finsertorder('o5',current_user || '/q5',1,1,current_user || '/q4');
select finsertorder('o6',current_user || '/q6',1,1,current_user || '/q5');
select finsertorder('o7',current_user || '/q7',1,1,current_user || '/q6');
select finsertorder('o8',current_user || '/q8',1,1,current_user || '/q7');


