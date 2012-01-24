set search_path='t';
insert into tuser(name) values ('olivier');
select fuser('olivier',0);
select fspendquota(current_timestamp::timestamp);
select fconnect(false);
select fexplodequality('olivier/q1');
select fupdate_quality('olivier/q1',0);
select fverify();

select fadmin(); -- market opened

select fdroporder(1::int8);
-- finsertorder(_owner text,_qualityprovided text,_qttprovided int8,_qttrequired int8,_qualityrequired text)
-- 1 q1 -> 2 q2 -> 3 q3

select finsertorder('o1','olivier/q1',1,3,'olivier/q3');
select finsertorder('o2','olivier/q2',2,1,'olivier/q1');
select finsertorder('o3','olivier/q3',3,2,'olivier/q2');

-- 2 owners
-- update tconst set value=0 where name='VERIFY';
select finsertorder('o1','olivier/q1',1,3,'olivier/q3');
select finsertorder('o2','olivier/q2',2,1,'olivier/q1');
select finsertorder('o2','olivier/q3',3,2,'olivier/q2'); 

-- no barter
select finsertorder('o1','olivier/q1',1,2,'olivier/q2');
select finsertorder('o2','olivier/q2',2,1,'olivier/q1');


-- long barter
select finsertorder('o1','olivier/q1',2,2,'olivier/q2');
select finsertorder('o2','olivier/q2',2,1,'olivier/q1');

-- short barter
select finsertorder('o1','olivier/q1',1,4,'olivier/q2'); -- [1]
select finsertorder('o2','olivier/q2',2,1,'olivier/q1'); -- refused

-- cycle with [1]
select finsertorder('o2','olivier/q2',4,1,'olivier/q1');

select fdroporder(12);
select fadmin();
select fadmin(); --closed

select fadmin();
select finsertorder('o2','olivier/q2',4,1,'olivier/q1');
select finsertorder('o2','olivier/q2',4,1,'olivier/q1');
select fadmin();
select fadmin(); --closed
select * from vmarket;
