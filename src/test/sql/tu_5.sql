-- Trilateral exchange by one owners
---------------------------------------------------------
--variables
--USER:admin
select  * from market.tvar where name != 'OC_CURRENT_OPENED' order by name; 
---------------------------------------------------------
--SELECT * FROM fsubmitorder(type,owner,qua_requ,qtt_requ,qua_prov,qtt_prov);
--USER:test_clienta

SELECT * FROM market.fsubmitorder('limit','wa','a',  5,'b',10);
--USER:test_clientb
SELECT * FROM market.fsubmitorder('limit','wa','b', 20,'c',40);

SELECT * FROM market.fsubmitorder('limit','wa','c', 10,'a',20);
--Trilateral exchange expected
