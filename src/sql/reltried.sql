/*----------------------------------------------------------------------------

Some orders that are frequently included in refused cycles are removed 
from the database with the following algorithm:

1 - When a movement nr->np is created, a counter Q(np,nr)  is incremented
	Q(np,nr) == treltried[np,nr].cnt +=1, 
	done by fupdate_treltried(_commits int8[],_nbcommit int), called by vfexecute_flow()

2- When an order nr->np is created, the counter Q(np,nr) is recorded at position P
	torder[.].start = P = Q(np,nr)
	done by fget_treltried() called by finsert_order_int()
	
3- orders are removed from the market when their torder[.].start is such as P+MAXTRY < Q, with MAXTRY defined in tconst [10]
	This operation 3) is performed each time some movements are created.
	done by finvalidate_treltried() called by fexecquote() and finsertorder()
	
4- treltried must be truncated at market opening
	done by frenumbertables()
	
Ainsi, on permet à chaque offre d'être mis en concurrence MAXTRY fois sans pénaliser les couple (np,nr) plus rares. 
Celà suppose que toutes les solutions soient parcourus, ce qui n'est pas le cas.
	
*/
INSERT INTO tconst (name,value) VALUES 	('MAXTRY',10);
	-- life time of an order for a given couple (np,nr)
--------------------------------------------------------------------------------
-- TRELTRIED
--------------------------------------------------------------------------------
create table treltried (
	np int references tquality(id) NOT NULL, 
	nr int references tquality(id) NOT NULL, 
	cnt bigint DEFAULT 0,
	PRIMARY KEY (np,nr),     
	CHECK(	
    		np!=nr AND 
    		cnt >=0
    	)
);

--------------------------------------------------------------------------------
-- fupdate_treltried(_commits int8[],_nbcommit int)
--      update treltried[np,nr].cnt
--------------------------------------------------------------------------------
CREATE FUNCTION  fupdate_treltried(_commits int8[],_nbcommit int) RETURNS void AS $$
DECLARE 
	_i int;
	_np int;
	_nr int;
	_MAXTRY 	int := fgetconst('MAXTRY');
BEGIN
	IF(_MAXTRY=0) THEN
		RETURN;
	END IF;
	
	FOR _i IN 1 .. _nbcommit LOOP
		_nr	:= _commits[_i][3]::int;
		_np	:= _commits[_i][5]::int;
		LOOP
			UPDATE treltried SET cnt = cnt + 1 WHERE np=_np AND nr=_nr;
			IF FOUND THEN
				EXIT;
			ELSE
				BEGIN
					INSERT INTO treltried (np,nr,cnt) VALUES (_np,_nr,1);
				EXCEPTION WHEN check_violation THEN
					-- 
				END;
			END IF;
		END LOOP;
	END LOOP;

	RETURN;
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
-- fget_treltried(_np int,_nr int)
-- sets torder[.].start
--------------------------------------------------------------------------------
CREATE FUNCTION  fget_treltried(_np int,_nr int) RETURNS int8 AS $$
DECLARE 
	_cnt int8;
	_MAXTRY 	int := fgetconst('MAXTRY');
BEGIN
	IF(_MAXTRY=0) THEN
		RETURN 0;
	END IF;
	SELECT cnt into _cnt FROM treltried WHERE np=_np AND nr=_nr;
	IF NOT FOUND THEN
		_cnt := 0;
	END IF;

	RETURN _cnt;
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
-- finvalidate_treltried()
--------------------------------------------------------------------------------
CREATE FUNCTION  finvalidate_treltried() RETURNS void AS $$
DECLARE 
	_o 	torder%rowtype;
	_MAXTRY int := fgetconst('MAXTRY');
	_res	int;
	_mvt_id	int;
BEGIN
	IF(_MAXTRY=0) THEN
		RETURN;
	END IF;
	
	FOR _o IN SELECT o.* FROM torder o,treltried r 
		WHERE o.np=r.np AND o.nr=r.nr AND o.start IS NOT NULL AND o.start + _MAXTRY < r.cnt LOOP
		
		INSERT INTO tmvt (nb,oruuid,grp,own_src,own_dst,qtt,nat,created) 
			VALUES(1,_o.uuid,NULL,_o.own,_o.own,_o.qtt,_o.np,statement_timestamp()) 
			RETURNING id INTO _mvt_id;
			
		-- the order order.qtt != 0
		perform fremoveorder_int(_o.id);			
	END LOOP;
	RETURN;
END;
$$ LANGUAGE PLPGSQL;

