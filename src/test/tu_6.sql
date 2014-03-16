-- 7-exchange with 7 partners
---------------------------------------------------------
--variables
--USER:admin
select  * from market.tvar order by name; 
---------------------------------------------------------
--SELECT * FROM fsubmitorder(type,owner,qua_requ,qtt_requ,qua_prov,qtt_prov);
--USER:test_clienta

SELECT * FROM market.fsubmitorder('limit','wa','a',  5,'b',10);
--USER:test_clientb
SELECT * FROM market.fsubmitorder('limit','wb','b', 20,'c',40);
SELECT * FROM market.fsubmitorder('limit','wc','c', 20,'d',40);
SELECT * FROM market.fsubmitorder('limit','wd','d', 20,'e',40);
SELECT * FROM market.fsubmitorder('limit','we','e', 20,'f',40);
SELECT * FROM market.fsubmitorder('limit','wf','f', 20,'g',40);
SELECT * FROM market.fsubmitorder('limit','wg','g', 20,'a',40);

