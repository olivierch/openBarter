-------------------------------------------------------------------------------
-- table of values in the market
-------------------------------------------------------------------------------
create table tvalue (
    name text UNIQUE not NULL,
    qtts	int8 DEFAULT 0 not NULL,
    PRIMARY KEY (name),
    UNIQUE(name),
    CHECK(	
    	char_length(name)>0 AND
    	qtts >=0
    )
);

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
CREATE FUNCTION faddvalue(_name text,_qtt int8) RETURNS int AS $$
DECLARE
	_qtts int8;
BEGIN
	INSERT INTO tvalue (name,qtts) VALUES (_name,_qtt);
	RETURN 1;
EXCEPTION WHEN unique_violation THEN
	UPDATE tvalue SET qtts = qtts + _qtt WHERE name=_name;
	RETURN 0; 
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
CREATE FUNCTION fverifqtts() RETURNS int AS $$
DECLARE
	_v tvalue%rowtype;
	_cnterr int := 0;
	_qo int8;
	_qv int8;
BEGIN
	FOR _v IN SELECT * FROM tvalue LOOP
		SELECT sum((ord).qtt) INTO _qo FROM torder WHERE (ord).qua_prov=_v.name;
		SELECT sum(qtt) INTO _qv FROM tmvt WHERE nat=_v.name;
		IF(_v.qtts != (_qo+_qv)) THEN 
			_cnterr := _cnterr + 1;
		END IF;
	END LOOP;
	RETURN _cnterr;
END;
$$ LANGUAGE PLPGSQL;

/*------------------------------------------------------------------------------
returns  records:
the number of errors found with fverifmvt() and fverifmvt3()
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
	cnt := fverifmvt3();
	RETURN NEXT;
	RETURN;
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
-- GRANT EXECUTE ON FUNCTION  fgeterrs() TO admin;

--------------------------------------------------------------------------------
CREATE VIEW vorderverif AS 
SELECT (o.ord).id as id,
		(o.ord).qtt_requ as qtt_requ,(o.ord).qua_requ as nr,
		(o.ord).qtt_prov as qtt_prov,(o.ord).qua_prov as np,
		(o.ord).qtt as qtt
from torder o ;

/*------------------------------------------------------------------------------
-- verifies that for all orders:
--	order.qtt_prov = sum(mvt.qtt) of movements related to that order
------------------------------------------------------------------------------*/
CREATE FUNCTION fverifmvt() RETURNS int AS $$
DECLARE
	_qtt_prov	 int8;
	_qtt		 int8;
	_id		 int;
	_qtta		 int8;
	_npa		 text;
	_npb		 text;
	_np		 text;
	-- _nb			int;
	_cnterr		 int := 0;
	-- _iserr		 bool;
BEGIN
	FOR _id,_qtta,_npa,_npb,_qtt_prov,_qtt,_np IN 
	SELECT m.xid,sum(m.qtt),max(m.nat),min(m.nat),o.qtt_prov,o.qtt,o.np
	FROM tmvt m INNER JOIN vorderverif o ON  o.id=m.xid 
	WHERE m.nbc!=1 GROUP BY m.xid,o.qtt_prov,o.qtt,o.np LOOP
			IF(	(_qtt_prov != _qtta+_qtt) 
				-- NOT vorderverif.qtt_prov == vorderverif.qtt + sum(mvt.qtt)
				OR (_np != _npa)	
				-- NOT mvt.nat == vorderverif.nat 
				OR (_npa != _npb)
				-- NOT all mvt.nat are the same 
			)	THEN 
				_cnterr := _cnterr +1;
				RAISE NOTICE 'error on id:%',_id;
			END IF;
	END LOOP;
	RETURN _cnterr;
END;
$$ LANGUAGE PLPGSQL;
/*------------------------------------------------------------------------------
-- verifies that for all agreements, movements comply with related orders.
------------------------------------------------------------------------------*/
CREATE FUNCTION fverifmvt3() RETURNS int AS $$
DECLARE
	_cnterr		 int := 0;
	_mvts		 tmvt[];
	_mvt		 tmvt%rowtype;
	_mvtprec	 tmvt%rowtype;
	-- _mvtfirst	 tmvt%rowtype;
	-- _uuiderr	 text;
	_cnt		 int;		-- count mvt in agreement
BEGIN
		
	_mvtprec.grp := NULL;
	_cnterr := 0;
	FOR _mvt IN SELECT * FROM tmvt WHERE nbc!=1 ORDER BY grp,id ASC  LOOP
		IF(_mvt.grp = _mvtprec.grp) THEN
			_mvts := array_append(_mvts,_mvt);
		ELSE
			IF NOT (_mvtprec.grp IS NULL) THEN
				_cnterr := fverifmvt3_int(_mvts) + _cnterr;
			END IF;
			_mvts := array_append(ARRAY[]::tmvt[],_mvt);
		END IF;
		_mvtprec.grp := _mvt.grp;
	END LOOP;
	IF NOT (_mvtprec.grp IS NULL) THEN
		_cnterr := fverifmvt3_int(_mvts) + _cnterr;
	END IF;
	RETURN _cnterr;
END;
$$ LANGUAGE PLPGSQL;

/*------------------------------------------------------------------------------
_mvtprec and _mvt are successive movements of an agreement
------------------------------------------------------------------------------*/
CREATE or replace FUNCTION fverifmvt3_int(_mvts tmvt[]) RETURNS int AS $$
DECLARE
	_mvtprec	 tmvt%rowtype;
	_mvtfirst    tmvt%rowtype;
	_mvt		 tmvt%rowtype;
	_cnterr		 int;
	_nbc			 int;
BEGIN
	_nbc := array_length(_mvts,1);
	_mvtprec.id := NULL;
	_cnterr := 0;
	FOREACH _mvt IN ARRAY _mvts LOOP
		IF ( _nbc != _mvt.nbc ) THEN
			RAISE NOTICE 'mvt.nbc incorrect for movement %',_mvt.id;
			_cnterr := _cnterr + 1 ;
		END IF;
		IF (_mvtprec.id IS NULL) THEN
			_mvtfirst := _mvt;
		ELSE
			_cnterr := fverifmvt2_int(_mvtprec,_mvt) + _cnterr;
		END IF;
		_mvtprec.id := _mvt.grp;
	END LOOP;
	IF NOT (_mvtprec.grp IS NULL) THEN
		_cnterr := fverifmvt2_int(_mvt,_mvtfirst) + _cnterr;
	END IF;
	RETURN _cnterr;
END;
$$ LANGUAGE PLPGSQL;

/*------------------------------------------------------------------------------
_mvtprec and _mvt are successive movements of an agreement
------------------------------------------------------------------------------*/
CREATE or replace FUNCTION fverifmvt2_int(_mvtprec tmvt,_mvt tmvt) RETURNS int AS $$
DECLARE
	_o vorderverif%rowtype;
BEGIN
	SELECT id,np,nr,qtt_prov,qtt_requ INTO _o.id,_o.np,_o.nr,_o.qtt_prov,_o.qtt_requ FROM vorderverif WHERE id = _mvt.xid;
	IF (NOT FOUND) THEN
		--RAISE NOTICE 'order not found for vorderverif %',_mvt.id;
		RETURN 0;
	END IF;

	IF(_o.np != _mvt.nat OR _o.nr != _mvtprec.nat) THEN
		RAISE NOTICE 'mvt.nat != np or mvtprec.nat!=nr';
		RETURN 1;
	END IF;
	
	-- NOT(_o.qtt_prov/_o.qtt_requ >= _mvt.qtt/_mvtprec.qtt)
	IF(((_o.qtt_prov::float8) / (_o.qtt_requ::float8)) < ((_mvt.qtt::float8)/(_mvtprec.qtt::float8))) THEN
		RAISE NOTICE 'order %->%, with  mvt %->%',_o.qtt_requ,_o.qtt_prov,_mvtprec.qtt,_mvt.qtt;
		RAISE NOTICE '% < 1; should be >=1',(((_o.qtt_prov::float8) / (_o.qtt_requ::float8)) / ((_mvt.qtt::float8)/(_mvtprec.qtt::float8)));
		RAISE NOTICE 'order.id %, with  mvtid %->%',_o.id,_mvtprec.id,_mvt.id;
		RETURN 1;
	END IF;


	RETURN 0;
END;
$$ LANGUAGE PLPGSQL;

