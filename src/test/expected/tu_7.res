-- Competition between bilateral and multilateral exchange 1/2
---------------------------------------------------------
--variables
--USER:admin
select  * from market.tvar order by name;
      name     value
+---------+---------
OC_CURRENT_OPENED         0
OC_CURRENT_PHASE       102
STACK_EXECUTED         0
 STACK_TOP         0
---------------------------------------------------------
--SELECT * FROM fsubmitorder(type,owner,qua_requ,qtt_requ,qua_prov,qtt_prov);
--USER:test_clientb
SELECT * FROM market.fsubmitorder('limit','wb','b', 80,'a',40);
        id     error
+---------+---------
         1      (0,)
SELECT * FROM market.fsubmitorder('limit','wc','b', 20,'d',40);
        id     error
+---------+---------
         2      (0,)
SELECT * FROM market.fsubmitorder('limit','wd','d', 20,'a',40);
        id     error
+---------+---------
         3      (0,)
--USER:test_clienta
SELECT * FROM market.fsubmitorder('limit','wa','a',  40,'b',80);
        id     error
+---------+---------
         4      (0,)
-- omega better for the trilateral exchange
-- it wins, the rest is used with a bilateral exchange

--------------------------------------------------------------------------------
table: torder
        id       oid       own  qtt_requ  qua_requ       typ  qtt_prov  qua_prov       qtt    own_id       usr
+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------
         1         1        wb        80         b     limit        40         a        20         1test_clientb
         2         2        wc        20         b     limit        40         d         0         2test_clientb
         3         3        wd        20         d     limit        40         a         0         3test_clientb
         4         4        wa        40         a     limit        80         b         0         4test_clienta

--------------------------------------------------------------------------------
table: tmsg
--------------------------------------------------------------------------------
	1:Primitive id:1 from test_clientb: OK

	2:Primitive id:2 from test_clientb: OK

	3:Primitive id:3 from test_clientb: OK

	4:Cycle id:1 Exchange id:3 for wd @test_clientb:
            	3:mvt_from wd @test_clientb : 40 'a' -> wa @test_clienta
            	2:mvt_to   wd @test_clientb : 40 'd' <- wc @test_clientb 
            	stock id:3 remaining after exchange: 0 'a' 

	5:Cycle id:1 Exchange id:1 for wa @test_clienta:
            	1:mvt_from wa @test_clienta : 40 'b' -> wc @test_clientb
            	3:mvt_to   wa @test_clienta : 40 'a' <- wd @test_clientb 
            	stock id:4 remaining after exchange: 40 'b' 

	6:Cycle id:1 Exchange id:2 for wc @test_clientb:
            	2:mvt_from wc @test_clientb : 40 'd' -> wd @test_clientb
            	1:mvt_to   wc @test_clientb : 40 'b' <- wa @test_clienta 
            	stock id:2 remaining after exchange: 0 'd' 

	7:Cycle id:4 Exchange id:5 for wb @test_clientb:
            	5:mvt_from wb @test_clientb : 20 'a' -> wa @test_clienta
            	4:mvt_to   wb @test_clientb : 40 'b' <- wa @test_clienta 
            	stock id:1 remaining after exchange: 20 'a' 

	8:Cycle id:4 Exchange id:4 for wa @test_clienta:
            	4:mvt_from wa @test_clienta : 40 'b' -> wb @test_clientb
            	5:mvt_to   wa @test_clienta : 20 'a' <- wb @test_clientb 
            	stock id:4 remaining after exchange: 0 'b' 

	9:Primitive id:4 from test_clienta: OK

