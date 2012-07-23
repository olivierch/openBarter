set role admin;
/*
select id,sess,action from fclose();
reset role;
select ftruncatetables();
set role admin;
select id,sess,action from fprepare();

-- market is opened
select id,sess,action from fopen();
*/
select * from vmarket;
select fresetmarket();
set role client;
select * from vmarket;

select finsertorder('u','b',1000,1000,'a');
select finsertorder('v','c',1000,1000,'b');
select fgetquote('w','a',1000,0,'c');
select finsertorder('w','a',1000,1000,'c');
select id,nb,oruuid,grp,provider,quality,qtt,receiver from vmvt;
select fremoveagreement(1);
select id,qtt from tquality;

select finsertorder('u','b',2000,1000,'a');
select finsertorder('v','c',2000,1000,'b');
select fgetquote('w','a',500,0,'c');
select finsertorder('w','a',500,2000,'c');
select id,nb,oruuid,grp,provider,quality,qtt,receiver from vmvt;
select fremoveagreement(4);

select fgetquote('w','a',500,0,'b');
select finsertorder('w','a',500,1000,'b');

set role admin;
select * from fchangestatemarket(true);
-- market is closed
set role client;
select * from vmarket;
select fremoveagreement(7);

set role admin;
select id,qtt from tquality;
select * from fgetstats(true);
select * from fgeterrs(true) where cnt != 0;

/*
select * from fchangestatemarket(true);
select * from vmarket;
select * from fchangestatemarket(true);
select * from vmarket;
select * from fchangestatemarket(true);
select * from vmarket;
*/

/*
select id,sess,action from fprepare();
select id,sess,action from fopen();
-- select id,qtt from tquality;

-- select * from fgetstats(true);
*/
