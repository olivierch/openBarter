-- Trilateral exchange between owners with distinct users
---------------------------------------------------------
--variables
--USER:admin
select  * from market.tvar where name != 'OC_CURRENT_OPENED' order by name;
      name     value
+---------+---------
 INSTALLED         1
OC_CURRENT_PHASE       102
STACK_EXECUTED         0
 STACK_TOP         0
---------------------------------------------------------
--USER:test_clienta
--SELECT * FROM fsubmitorder(type,owner,qua_requ,qtt_requ,qua_prov,qtt_prov);
SELECT * FROM market.fsubmitorder('limit','wa','a',  5,'b',10);
        id     error
+---------+---------
         1      (0,)
--USER:test_clientb
SELECT * FROM market.fsubmitorder('limit','wb','b', 20,'c',40);
        id     error
+---------+---------
         2      (0,)
SELECT * FROM market.fsubmitorder('limit','wc','c', 10,'a',20);
        id     error
+---------+---------
         3      (0,)
--Trilateral exchange expected

--------------------------------------------------------------------------------
table: torder
        id       oid       own  qtt_requ  qua_requ       typ  qtt_prov  qua_prov       qtt    own_id       usr
+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------
         1         1        wa         5         a     limit        10         b         0         1test_clienta
         2         2        wb        20         b     limit        40         c        30         2test_clientb
         3         3        wc        10         c     limit        20         a        10         3test_clientb

--------------------------------------------------------------------------------
table: tmsg
--------------------------------------------------------------------------------
	1:Primitive id:1 from test_clienta: OK

	2:Primitive id:2 from test_clientb: OK

	3:Cycle id:1 Exchange id:3 for wb @test_clientb:
            	3:mvt_from wb @test_clientb : 10 'c' -> wc @test_clientb
            	2:mvt_to   wb @test_clientb : 10 'b' <- wa @test_clienta 
            	stock id:2 remaining after exchange: 30 'c' 

	4:Cycle id:1 Exchange id:1 for wc @test_clientb:
            	1:mvt_from wc @test_clientb : 10 'a' -> wa @test_clienta
            	3:mvt_to   wc @test_clientb : 10 'c' <- wb @test_clientb 
            	stock id:3 remaining after exchange: 10 'a' 

	5:Cycle id:1 Exchange id:2 for wa @test_clienta:
            	2:mvt_from wa @test_clienta : 10 'b' -> wb @test_clientb
            	1:mvt_to   wa @test_clienta : 10 'a' <- wc @test_clientb 
            	stock id:1 remaining after exchange: 0 'b' 

	6:Primitive id:3 from test_clientb: OK

