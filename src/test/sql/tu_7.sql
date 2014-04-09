-- Competition between bilateral and multilateral exchange 1/2
---------------------------------------------------------
--variables
--USER:admin
select  * from market.tvar where name != 'OC_CURRENT_OPENED' order by name; 
---------------------------------------------------------
--SELECT * FROM fsubmitorder(type,owner,qua_requ,qtt_requ,qua_prov,qtt_prov);

--USER:test_clientb
SELECT * FROM market.fsubmitorder('limit','wb','b', 80,'a',40);
SELECT * FROM market.fsubmitorder('limit','wc','b', 20,'d',40);
SELECT * FROM market.fsubmitorder('limit','wd','d', 20,'a',40);
--USER:test_clienta
SELECT * FROM market.fsubmitorder('limit','wa','a',  40,'b',80);
-- omega better for the trilateral exchange
-- it wins, the rest is used with a bilateral exchange

