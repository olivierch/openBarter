-- 7-exchange with 7 partners
---------------------------------------------------------
--variables
--USER:admin
select  * from market.tvar order by name;
      name     value
+---------+---------
 INSTALLED         1
OC_CURRENT_OPENED         0
OC_CURRENT_PHASE       102
STACK_EXECUTED         0
 STACK_TOP         0
---------------------------------------------------------
--SELECT * FROM fsubmitorder(type,owner,qua_requ,qtt_requ,qua_prov,qtt_prov);
--USER:test_clienta
SELECT * FROM market.fsubmitorder('limit','wa','a',  5,'b',10);
        id     error
+---------+---------
         1      (0,)
--USER:test_clientb
SELECT * FROM market.fsubmitorder('limit','wb','b', 20,'c',40);
        id     error
+---------+---------
         2      (0,)
SELECT * FROM market.fsubmitorder('limit','wc','c', 20,'d',40);
        id     error
+---------+---------
         3      (0,)
SELECT * FROM market.fsubmitorder('limit','wd','d', 20,'e',40);
        id     error
+---------+---------
         4      (0,)
SELECT * FROM market.fsubmitorder('limit','we','e', 20,'f',40);
        id     error
+---------+---------
         5      (0,)
SELECT * FROM market.fsubmitorder('limit','wf','f', 20,'g',40);
        id     error
+---------+---------
         6      (0,)
SELECT * FROM market.fsubmitorder('limit','wg','g', 20,'a',40);
        id     error
+---------+---------
         7      (0,)

--------------------------------------------------------------------------------
table: torder
        id       oid       own  qtt_requ  qua_requ       typ  qtt_prov  qua_prov       qtt    own_id       usr
+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------+---------
         1         1        wa         5         a     limit        10         b         0         1test_clienta
         2         2        wb        20         b     limit        40         c        30         2test_clientb
         3         3        wc        20         c     limit        40         d        30         3test_clientb
         4         4        wd        20         d     limit        40         e        30         4test_clientb
         5         5        we        20         e     limit        40         f        30         5test_clientb
         6         6        wf        20         f     limit        40         g        30         6test_clientb
         7         7        wg        20         g     limit        40         a        30         7test_clientb

--------------------------------------------------------------------------------
table: tmsg
--------------------------------------------------------------------------------
	1:Primitive id:1 from test_clienta: OK

	2:Primitive id:2 from test_clientb: OK

	3:Primitive id:3 from test_clientb: OK

	4:Primitive id:4 from test_clientb: OK

	5:Primitive id:5 from test_clientb: OK

	6:Primitive id:6 from test_clientb: OK

	7:Cycle id:1 Exchange id:7 for wf @test_clientb:
            	7:mvt_from wf @test_clientb : 10 'g' -> wg @test_clientb
            	6:mvt_to   wf @test_clientb : 10 'f' <- we @test_clientb 
            	stock id:6 remaining after exchange: 30 'g' 

	8:Cycle id:1 Exchange id:1 for wg @test_clientb:
            	1:mvt_from wg @test_clientb : 10 'a' -> wa @test_clienta
            	7:mvt_to   wg @test_clientb : 10 'g' <- wf @test_clientb 
            	stock id:7 remaining after exchange: 30 'a' 

	9:Cycle id:1 Exchange id:2 for wa @test_clienta:
            	2:mvt_from wa @test_clienta : 10 'b' -> wb @test_clientb
            	1:mvt_to   wa @test_clienta : 10 'a' <- wg @test_clientb 
            	stock id:1 remaining after exchange: 0 'b' 

	10:Cycle id:1 Exchange id:3 for wb @test_clientb:
            	3:mvt_from wb @test_clientb : 10 'c' -> wc @test_clientb
            	2:mvt_to   wb @test_clientb : 10 'b' <- wa @test_clienta 
            	stock id:2 remaining after exchange: 30 'c' 

	11:Cycle id:1 Exchange id:4 for wc @test_clientb:
            	4:mvt_from wc @test_clientb : 10 'd' -> wd @test_clientb
            	3:mvt_to   wc @test_clientb : 10 'c' <- wb @test_clientb 
            	stock id:3 remaining after exchange: 30 'd' 

	12:Cycle id:1 Exchange id:5 for wd @test_clientb:
            	5:mvt_from wd @test_clientb : 10 'e' -> we @test_clientb
            	4:mvt_to   wd @test_clientb : 10 'd' <- wc @test_clientb 
            	stock id:4 remaining after exchange: 30 'e' 

	13:Cycle id:1 Exchange id:6 for we @test_clientb:
            	6:mvt_from we @test_clientb : 10 'f' -> wf @test_clientb
            	5:mvt_to   we @test_clientb : 10 'e' <- wd @test_clientb 
            	stock id:5 remaining after exchange: 30 'f' 

	14:Primitive id:7 from test_clientb: OK

