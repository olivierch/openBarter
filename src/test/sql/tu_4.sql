-- Trilateral exchange between owners with two owners
---------------------------------------------------------
--variables
--USER:admin
select  * from market.tvar where name != 'OC_CURRENT_OPENED' order by name; 
-- The profit is shared equally between wa and wb
---------------------------------------------------------
--SELECT * FROM fsubmitorder(type,owner,qua_requ,qtt_requ,qua_prov,qtt_prov);
--USER:test_clienta

SELECT * FROM market.fsubmitorder('limit','wa','a',  5,'b',20);
--USER:test_clientb
SELECT * FROM market.fsubmitorder('limit','wb','b', 20,'c',40);

SELECT * FROM market.fsubmitorder('limit','wb','c', 10,'a',20);
--Trilateral exchange expected
