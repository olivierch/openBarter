SET client_min_messages = warning;
\set ECHO none
\i sql/model.sql
set search_path='t';
\set ECHO all
-- RESET client_min_messages;

insert into tuser(name) values (current_user);
select fuser(current_user,0);
select fspendquota(current_timestamp::timestamp);
select fconnect(false);
select fexplodequality(current_user || '/q1');
select fupdate_quality(current_user || '/q1',0);
select fverify();
select current_user;

select fadmin(); -- market opened

select id from fdroporder(1::int8);
-- finsertorder(_owner text,_qualityprovided text,_qttprovided int8,_qttrequired int8,_qualityrequired text)
-- 1 q1 -> 2 q2 -> 3 q3

select finsertorder('o1',current_user || '/q1',1,3,current_user || '/q3');
select finsertorder('o2',current_user || '/q2',2,1,current_user || '/q1');
select finsertorder('o3',current_user || '/q3',3,2,current_user || '/q2');

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

select id from fdroporder(12);
select fadmin();
select fadmin(); --closed

select fadmin();
select finsertorder('o2',current_user || '/q2',4,1,current_user || '/q1');
select finsertorder('o2',current_user || '/q2',4,1,current_user || '/q1');
select fadmin();
select fadmin(); --closed
select state,backup,diagnostic from vmarket;

