-- Trilateral exchange between owners with two owners
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
-- The profit is shared equally between wa and wb
---------------------------------------------------------
--SELECT * FROM fsubmitorder(type,owner,qua_requ,qtt_requ,qua_prov,qtt_prov);
--USER:test_clienta
SELECT * FROM market.fsubmitorder('limit','wa','a',  5,'b',20);
        id     error
+---------+---------
         1      (0,)
--USER:test_clientb
SELECT * FROM market.fsubmitorder('limit','wb','b', 20,'c',40);
        id     error
+---------+---------
         2      (0,)
SELECT * FROM market.fsubmitorder('limit','wb','c', 10,'a',20);
        id     error
+---------+---------
         3      (0,)
--Trilateral exchange expected

--------------------------------------------------------------------------------
table: torder
        id       oid       own  qtt_requ  qua_requ       typ  qtt_prov  qua_prov       qtt    own_id       usr
+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------
         1         1        wa         5         a     limit        20         b         0         1test_clienta
         2         2        wb        20         b     limit        40         c        20         2test_clientb
         3         3        wb        10         c     limit        20         a         0         2test_clientb

--------------------------------------------------------------------------------
table: tmsg
--------------------------------------------------------------------------------
	1:Primitive id:1 from test_clienta: OK

	2:Primitive id:2 from test_clientb: OK

	3:Cycle id:1 Exchange id:3 for wb @test_clientb:
            	3:mvt_from wb @test_clientb : 20 'c' -> wb @test_clientb
            	2:mvt_to   wb @test_clientb : 20 'b' <- wa @test_clienta 
            	stock id:2 remaining after exchange: 20 'c' 

	4:Cycle id:1 Exchange id:1 for wb @test_clientb:
            	1:mvt_from wb @test_clientb : 20 'a' -> wa @test_clienta
            	3:mvt_to   wb @test_clientb : 20 'c' <- wb @test_clientb 
            	stock id:3 remaining after exchange: 0 'a' 

	5:Cycle id:1 Exchange id:2 for wa @test_clienta:
            	2:mvt_from wa @test_clienta : 20 'b' -> wb @test_clientb
            	1:mvt_to   wa @test_clienta : 20 'a' <- wb @test_clientb 
            	stock id:1 remaining after exchange: 0 'b' 

	6:Primitive id:3 from test_clientb: OK

