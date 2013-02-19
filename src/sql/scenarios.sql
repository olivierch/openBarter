-- use cases of the documentation

select * from fsubmitbarter(1,'a',NULL,'q2',10,'q1',20); 
select * from fsubmitbarter(1,'b',NULL,'q3',10,'q2',20); 
select * from fsubmitbarter(1,'c',NULL,'q1',10,'q3',20); 
select * from femptystack();
select * from fackmvt();
select * from fackmvt();
select * from fackmvt();

select * from fsubmitbarter(1,'a',NULL,'q2',10,'q1',10);  
select * from fsubmitbarter(1,'a',4,'q3',10,NULL,NULL);  
select * from fsubmitbarter(1,'b',NULL,'q1',5,'q2',5);
select * from femptystack();
select id,nbc,grp,own_src,own_dst,qtt,nat from tmvt;
select id,own,oid,qtt_requ,qua_requ,qtt_prov,qua_prov,qtt from vorder;
select * from fsubmitbarter(1,'c',NULL,'q1',5,'q3',5);
select * from femptystack();
select id,nbc,grp,own_src,own_dst,qtt,nat from tmvt;
select id,own,oid,qtt_requ,qua_requ,qtt_prov,qua_prov,qtt from vorder;
select * from fackmvt();
select * from fackmvt();
select * from fsubmitbarter(2,'a',NULL,'q2',20,'q1',10);
select * from fsubmitbarter(2,'b',NULL,'q1',20,'q2',10);
select * from femptystack();
select id,nbc,grp,own_src,own_dst,qtt,nat from tmvt;
select * from fackmvt();
select * from fackmvt();
select * from fackmvt();
select * from fackmvt();

select * from fsubmitbarter(1,'a',NULL,'q2',20,'q1',80); 
select * from fsubmitbarter(1,'b',NULL,'q3',10,'q2',20);
select * from fsubmitbarter(1,'c',NULL,'q3',10,'q1',10);
select * from fsubmitquote(1,'d','q1','q3');
select * from femptystack();
select json from tmvt;
select * from fackmvt();
select * from fsubmitquote(1,'d','q1',80,'q3',10);
select * from femptystack();
select json from tmvt;
select * from fackmvt();
select * from fsubmitquote(1,'d','q1',100,'q3',100);
select * from femptystack();
select json from tmvt;
select * from fackmvt();
select fsubmitbarter(1,'d',NULL,'q1',30,'q3',30);
select * from femptystack();
select id,nbc,grp,own_src,own_dst,qtt,nat from tmvt;
-- select * from fackmvt();
/*
select fsubmitbarter(1,'d',NULL,'q1',80,'q3',10);
select * from femptystack();
select * from fackmvt();
select * from fackmvt();
select * from fackmvt();
*/

