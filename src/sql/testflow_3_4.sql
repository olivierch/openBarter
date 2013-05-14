/*  cycle of BEST */
\set ECHO all
set search_path to market;
select count(*) from torder;
/* order book empty */

/* one cycle with BEST orders, the cycle exists even if OMEGA < 1 */
select * from fsubmitbarter(2,'a',NULL,'q1',20,'q2',10,'1 hour'::interval);
select * from fproducemvt();

/*  form 0
fsubmitprequote(_own,_qua_requ,_qua_prov)*/
select * from fsubmitprequote('b','q2','q1');
select json from fproducemvt();

/* 
ωu,qttu values defined by owner
ωo,qtto defines by others 
*/

/* form 1 
fsubmitquote(_own,_qua_requ,_qua_prov)
flow limited by best price and qtto */
select * from fsubmitquote(2,'b','q2','q1');
select json from fproducemvt();

/* form 2
fsubmitquote(_type,_own,_qua_requ,_qtt_requ,_qua_prov,_qtt_prov) 
flow limited by ωu,ωo and qtto */
select * from fsubmitquote(2,'b','q2',20,'q1',10);
select json from fproducemvt();

/* form 3
fsubmitquote(_type,_own,_qua_requ,_qtt_requ,_qua_prov,_qtt_prov,qtt) 
flow limited by ωu,ωo and qttu,qtto */
select * from fsubmitquote(2,'d','q2',20,'q1',10,20);
select json from fproducemvt();

/* barter */
select * from fsubmitbarter(2,'d',NULL,'q2',20,'q1',10,10,'1 hour'::interval);
select json from fproducemvt();

select id,grp,xid,own_src,own_dst,qtt,nat from tmvt order by id desc limit 2; 
select count(*) from vorder;
/* order book empty */

