reset role;

-- SELECT ftruncatetables();
select fresetmarket();

-- two concurrent paths, (a) is the best
-- path (b)
-- select finsertorder('A','x',25  ,100 ,'z');
select finsertorder('A','z',200 ,200 ,'x');
-- path (a)
-- select finsertorder('B','x',25  ,200 ,'y');
select finsertorder('B','y',200 ,25  ,'x');
--select finsertorder('C','y',100 ,100 ,'z');
select finsertorder('C','z',100 ,100 ,'y');

-- no exchange
select id,nb,oruuid,grp,provider,quality,qtt,receiver from vmvt;

--select finsertorder('D','z',250 ,250 ,'x');
select finsertorder('D','x',250 ,250 ,'z');
--two exchanges in a single transaction
select id,nb,oruuid,grp,provider,quality,qtt,receiver from vmvt;

select id,qtt from tquality;
select * from fgetstats(true);

