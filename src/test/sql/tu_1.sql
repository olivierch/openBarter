-- Bilateral exchange between owners with distinct users (limit)
---------------------------------------------------------
--variables
--USER:admin
select  * from market.tvar order by name; 
---------------------------------------------------------
--USER:test_clienta
--SELECT * FROM fsubmitorder(type,owner,qua_requ,qtt_requ,qua_prov,qtt_prov);
SELECT * FROM market.fsubmitorder('limit','wa','a', 5,'b',10);
--USER:test_clientb
SELECT * FROM market.fsubmitorder('limit','wb','b', 10,'a',20);
--Bilateral exchange expected
