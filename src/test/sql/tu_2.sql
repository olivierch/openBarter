-- Bilateral exchange between owners with distinct users (best+limit)
---------------------------------------------------------
--variables
--USER:admin
select  * from market.tvar where name != 'OC_CURRENT_OPENED' order by name; 
---------------------------------------------------------
--USER:test_clienta
--SELECT * FROM fsubmitorder(type,owner,qua_requ,qtt_requ,qua_prov,qtt_prov);
SELECT * FROM market.fsubmitorder('best','wa','a', 10,'b',5);
--USER:test_clientb
SELECT * FROM market.fsubmitorder('best','wb','b', 20,'a',10);
--Bilateral exchange expected
SELECT * FROM market.fsubmitorder('limit','wa','a', 10,'b',5);
--USER:test_clientb
SELECT * FROM market.fsubmitorder('best','wb','b', 20,'a',10);
--No exchange expected
