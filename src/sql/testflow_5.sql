
select ftruncatetables();
-- own,qual_prov,qtt_prov,qtt_requ,qual_requ

select finsertorder('u','b',1000,1000,'a');
select finsertorder('v','c',1000,1000,'b');
select fgetquote('w','a','c');
select finsertorder('w','a',1000,1000,'c');
select id,nb,oruuid,grp,provider,quality,qtt,receiver from vmvt;
select fremoveagreement(1);
select id,qtt from tquality;

select finsertorder('u','b',2000,1000,'a');
select finsertorder('v','c',2000,1000,'b');
select fgetquote('w','a','c');
select finsertorder('w','a',500,2000,'c');
select id,nb,oruuid,grp,provider,quality,qtt,receiver from vmvt;
select fremoveagreement(4);

select fgetquote('w','a','b');
select finsertorder('w','a',500,1000,'b');
select fremoveagreement(7);
select id,qtt from tquality;

select * from fgetstats(true);

