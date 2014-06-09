-- Trilateral exchange between owners with distinct users
---------------------------------------------------------
--variables
--USER:admin
select  * from market.tvar where name != 'OC_CURRENT_OPENED' order by name; 
---------------------------------------------------------
--USER:test_clienta
--SELECT * FROM fsubmitorder(type,owner,qua_requ,qtt_requ,qua_prov,qtt_prov);
SELECT * FROM market.fsubmitorder('limit','wa','a',  5,'b',10);
--USER:test_clientb
SELECT * FROM market.fsubmitorder('limit','wb','b', 20,'c',40);

SELECT * FROM market.fsubmitorder('limit','wc','c', 10,'a',20);
--Trilateral exchange expected
