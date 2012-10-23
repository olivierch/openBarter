/*------------------------------------------------------------------------------
STAT
------------------------------------------------------------------------------*/
	
/*------------------------------------------------------------------------------
fgetstats() 
	returns stats but not errors
------------------------------------------------------------------------------*/
CREATE FUNCTION fgetstats(_details bool) RETURNS TABLE(_name text,cnt int8) AS $$
DECLARE 
	_i 		int;
	_cnt 		int;
BEGIN

	_name := 'number of qualities';
	select count(*) INTO cnt FROM tquality;
	RETURN NEXT;
	
	_name := 'number of owners';
	select count(*) INTO cnt FROM towner;
	RETURN NEXT;
	
	_name := 'number of quotes';
	select count(*) INTO cnt FROM tquote;
	RETURN NEXT;
			
	_name := 'number of orders';
	select count(*) INTO cnt FROM vorderverif;
	RETURN NEXT;
	
	_name := 'number of movements';
	select count(*) INTO cnt FROM vmvtverif;
	RETURN NEXT;
	
	_name := 'number of quotes removed';
	select count(*) INTO cnt FROM tquoteremoved;
	RETURN NEXT;

	_name := 'number of orders removed';
	select count(*) INTO cnt FROM torderremoved;
	RETURN NEXT;
	
	_name := 'number of movements removed';
	select count(*) INTO cnt FROM tmvtremoved;	
	RETURN NEXT;
	
	_name := 'number of agreements';
	select count(distinct grp) INTO cnt FROM vmvtverif where nb!=1;	
	RETURN NEXT;	
	
	_name := 'number of orders rejected';
	select count(distinct grp) INTO cnt FROM vmvtverif where nb=1;	
	RETURN NEXT;	
	
	FOR _i,cnt IN select nb,count(distinct grp) FROM vmvtverif where nb!=1 GROUP BY nb LOOP
		_name := 'agreements with ' || _i || ' partners';
		RETURN NEXT;
	END LOOP;

	RETURN;
END;
$$ LANGUAGE PLPGSQL  SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fgetstats(bool) TO admin;

/*------------------------------------------------------------------------------
returns 3 records:
the number of errors found with fbalance(),fverifmvt() and fverifmvt2()
------------------------------------------------------------------------------*/
CREATE FUNCTION fgeterrs() RETURNS TABLE(_name text,cnt int8) AS $$
DECLARE 
	_i 		int;
	_cnt 		int;
BEGIN		
	_name := 'errors on quantities in mvts';
	cnt := fverifmvt();
	RETURN NEXT;

	_name := 'errors on agreements in mvts';
	cnt := fverifmvt2();
	RETURN NEXT;
	RETURN;
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fgeterrs() TO admin;

/*------------------------------------------------------------------------------
-- verifies that for all orders:
--	order.qtt_prov = sum(mvt.qtt) of movements related to that order
------------------------------------------------------------------------------*/
CREATE FUNCTION fverifmvt() RETURNS int AS $$
DECLARE
	_qtt_prov	 int8;
	_qtt		 int8;
	_uuid		 text;
	_qtta		 int8;
	_npa		 int;
	_npb		 int;
	_np		 int;
	_cnterr		 int := 0;
	_iserr		 bool;
BEGIN
	
	FOR _qtt_prov,_qtt,_uuid,_np IN SELECT qtt_prov,qtt,uuid,np FROM vorderverif LOOP
	
		_iserr := false;
	
		SELECT sum(qtt),max(nat),min(nat) INTO _qtta,_npa,_npb 
			FROM vmvtverif WHERE oruuid=_uuid GROUP BY oruuid;
			
		IF(	FOUND ) THEN 
			IF(	(_qtt_prov != _qtta+_qtt) 
				-- NOT vorderverif.qtt_prov == vorderverif.qtt + sum(mvt.qtt)
				OR (_np != _npa)	
				-- NOT mvt.nat == vorderverif.nat 
				OR (_npa != _npb)
				-- NOT all mvt.nat are the same 
			)	THEN 
				_iserr := true;
				
			END IF;	
		END IF;
		
		IF(_iserr) THEN
			_cnterr := _cnterr +1;
			RAISE NOTICE 'error on uuid:%',_uuid;
		END IF;
	END LOOP;

	RETURN _cnterr;
END;
$$ LANGUAGE PLPGSQL;

/*------------------------------------------------------------------------------
-- verifies that for all agreements, movements comply with related orders.
------------------------------------------------------------------------------*/
CREATE FUNCTION fverifmvt2() RETURNS int AS $$
DECLARE
	_cnterr		 int := 0;
	_cnterrtot	 int := 0;
	_mvt		 tmvt%rowtype;
	_mvtprec	 tmvt%rowtype;
	_mvtfirst	 tmvt%rowtype;
	_uuiderr	 text;
	_cnt		 int;		-- count mvt in agreement
BEGIN
		
	_mvtprec.grp := NULL;_mvtfirst.grp := NULL;
	_uuiderr := NULL;
	FOR _mvt IN SELECT id,uuid,nb,oruuid,grp,own_src,own_dst,qtt,nat FROM vmvtverif ORDER BY grp,uuid ASC  LOOP
		IF(_mvt.grp != _mvtprec.grp) THEN -- first mvt of agreement
			--> finish last agreement
			IF NOT (_mvtprec.grp IS NULL OR _mvtfirst.grp IS NULL) THEN
				_cnterr := _cnterr + fverifmvt2_int(_mvtprec,_mvtfirst);
				_cnt := _cnt +1;
				
				if(_cnt != _mvtprec.nb) THEN
					_cnterr := _cnterr +1;
					RAISE NOTICE 'wrong number of movements for agreement %',_mvtprec.oruuid;
				END IF;
				-- errors found
				if(_cnterr != 0) THEN
					_cnterrtot := _cnterr + _cnterrtot;
					IF(_uuiderr IS NULL) THEN
						_uuiderr := _mvtprec.oruuid;
					END IF;
				END IF;
			END IF;
			--< A
			_mvtfirst := _mvt;
			_cnt := 0;
			_cnterr := 0;
		ELSE
			_cnterr := _cnterr + fverifmvt2_int(_mvtprec,_mvt);
			_cnt := _cnt +1;
		END IF;
		_mvtprec := _mvt;
	END LOOP;
	--> finish last agreement
	IF NOT (_mvtprec.grp IS NULL OR _mvtfirst.grp IS NULL) THEN
		_cnterr := _cnterr + fverifmvt2_int(_mvtprec,_mvtfirst);
		_cnt := _cnt +1;
		
		if(_cnt != _mvtprec.nb) THEN
			_cnterr := _cnterr +1;
			RAISE NOTICE 'wrong number of movements for agreement %',_mvtprec.oruuid;
		END IF;
		-- errors found
		if(_cnterr != 0) THEN
			_cnterrtot := _cnterr + _cnterrtot;
			IF(_uuiderr IS NULL) THEN
				_uuiderr := _mvtprec.oruuid;
			END IF;
		END IF;
	END IF;
	--< A
	IF(_cnterrtot != 0) THEN
		RAISE NOTICE 'mvt.oruuid= % is the first agreement where an error is found',_uuiderr;
		RETURN _cnterrtot;
	ELSE
		RETURN 0;
	END IF;
END;
$$ LANGUAGE PLPGSQL;

/*------------------------------------------------------------------------------
_mvtprec and _mvt are successive movements of an agreement
------------------------------------------------------------------------------*/
CREATE FUNCTION fverifmvt2_int(_mvtprec tmvt,_mvt tmvt) RETURNS int AS $$
DECLARE
	_o		vorderverif%rowtype;
BEGIN
	SELECT uuid,np,nr,qtt_prov,qtt_requ INTO _o.uuid,_o.np,_o.nr,_o.qtt_prov,_o.qtt_requ FROM vorderverif WHERE uuid = _mvt.oruuid;
	IF (NOT FOUND) THEN
		RAISE NOTICE 'order not found for vorderverif %',_mvt.oruuid;
		RETURN 1;
	END IF;

	IF(_o.np != _mvt.nat OR _o.nr != _mvtprec.nat) THEN
		RAISE NOTICE 'mvt.nat != np or mvtprec.nat!=nr';
		RETURN 1;
	END IF;
	
	-- NOT(_o.qtt_prov/_o.qtt_requ >= _mvt.qtt/_mvtprec.qtt)
	IF(((_o.qtt_prov::float8) / (_o.qtt_requ::float8)) < ((_mvt.qtt::float8)/(_mvtprec.qtt::float8))) THEN
		RAISE NOTICE 'order %->%, with  mvt %->%',_o.qtt_requ,_o.qtt_prov,_mvtprec.qtt,_mvt.qtt;
		RAISE NOTICE '% < 1; should be >=1',(((_o.qtt_prov::float8) / (_o.qtt_requ::float8)) / ((_mvt.qtt::float8)/(_mvtprec.qtt::float8)));
		RAISE NOTICE 'order.uuid %, with  mvtid %->%',_o.uuid,_mvtprec.id,_mvt.id;
		RETURN 1;
	END IF;


	RETURN 0;
END;
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
-- number of partners for the 100 last movements
-- select nb,count(distinct grp) from (select * from vmvtverif order by id desc limit 100) a group by nb;

-- performances

-- list - cnt of agreement created at date increasing
CREATE VIEW vgrp (id,cnt,created) AS SELECT max(id),count(distinct grp) as cnt,max(created) as created from tmvt group by created order by created;

-- same list with delays 
CREATE VIEW vgrp_delay (id,cnt,delay) AS select id,cnt,created-(lag(created) over(order by created)) as delay from vgrp;

-- list of ten groups
-- nbtransactions number of transactions
-- nbcycles 	number of cycles
-- delaymin		min duration of transaction
-- delaymax		max duration of transaction
-- avg			average duration of cycles

-- for 1000 last transactions
CREATE VIEW vperf1000(nbtransactions,nbgrp,delaymin,delaymax,avg) AS select count(*),sum(cnt) as grps,min(delay),max(delay),sum(delay)/sum(cnt) from (select cnt,delay,ntile(10) over(order by delay desc) as n from (select * from vgrp_delay order by id desc limit 1000) as t2) as t group by n order by min desc;

-- distribution of cycles by number of partners for 1000 last cycles
CREATE VIEW vnbgrp1000(nb,cnt) AS SELECT nb,count(*) as cnt from (SELECT max(id) as gid,grp,max(nb) as nb from tmvt group by grp order by gid desc limit 1000) as t group by nb order by nb asc;


