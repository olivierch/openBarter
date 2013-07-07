/* same as testflow_3_1, but with an order BEST in the order book */
\set ECHO all
set search_path to market;
select count(*) from torder;
/* order book empty */

/* one BEST and two LIMIT */
select * from fsubmitbarter(2,'a',NULL,'|q1',10,'|q2',10,'1 hour'::interval);
select * from fproducemvt();
select * from fsubmitbarter(1,'b',NULL,'|q1',10,'|q2',20,'1 hour'::interval);
select * from fproducemvt();
select * from fsubmitbarter(1,'c',NULL,'|q1',10,'|q2',30,'1 hour'::interval);
select * from fproducemvt();
/* 3 competing orders */
select  id,type,own,oid,qtt_requ,qua_requ,qtt_prov,qua_prov,qtt from vorder;

/*  form 0
fsubmitprequote(_own,_qua_requ,_qua_prov)*/
select * from fsubmitprequote('d','|q2','|q1');
/* 3 potential cycles ordered by increasing prices 10/30, 10/20, 10/10*/
select json from fproducemvt();

/* 
ωu,qttu values defined by owner
ωo,qtto defines by others 
*/

/* form 1 
fsubmitquote(_own,_qua_requ,_qua_prov)
flow limited by best price 10/30 and qtto */
select * from fsubmitquote(1,'d','|q2','|q1');
select json from fproducemvt();

/* form 2
fsubmitquote(_type,_own,_qua_requ,_qtt_requ,_qua_prov,_qtt_prov) 
flow limited by ωu,ωo and qtto */

/* limited by ωu,ωo and qtto */
/* one cycle */
select * from fsubmitquote(1,'d','|q2',30,'|q1',10);
select json from fproducemvt();
/* 3 cycles */
select * from fsubmitquote(1,'d','|q2',10,'|q1',10);
select json from fproducemvt();
/* only limited by ωo and qtto */
select * from fsubmitquote(1,'d','|q2',5,'|q1',10);
select json from fproducemvt();

/* form 3
fsubmitquote(_type,_own,_qua_requ,_qtt_requ,_qua_prov,_qtt_prov,qtt) 
flow limited by ωu,ωo and qttu,qtto */

select * from fsubmitquote(1,'d','|q2',30,'|q1',10,20);
select json from fproducemvt();
/* limited by this ωu,qttu */
select * from fsubmitquote(1,'d','|q2',30,'|q1',10,5);
select json from fproducemvt();
/* limited by this ωo,qtto */
select * from fsubmitquote(1,'d','|q2',10,'|q1',10,100);
select json from fproducemvt();

/* barter */
select * from fsubmitbarter(1,'d',NULL,'|q2',10,'|q1',10,100,'1 hour'::interval);
select json from fproducemvt();

select id,grp,xid,own_src,own_dst,qtt,nat from tmvt order by id desc limit 6; 
select id,qtt from vorder; /* qtt=100-41 */
select * from frmbarter('d',32);
select json from fproducemvt();
select count(*) from vorder;
/* order book empty */

