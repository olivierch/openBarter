-- set schema 't';

CREATE VIEW vorderverif AS
	SELECT id,uuid,own,nr,qtt_requ,np,qtt_prov,qtt FROM torder
	UNION
	SELECT id,uuid,own,nr,qtt_requ,np,qtt_prov,qtt FROM torderremoved;
CREATE VIEW vmvtverif AS
	SELECT id,nb,oruuid,grp,own_src,own_dst,qtt,nat FROM tmvt
	UNION
	SELECT id,nb,oruuid,grp,own_src,own_dst,qtt,nat FROM tmvtremoved;

CREATE FUNCTION fgetstats(_extra bool) RETURNS TABLE(_name text,cnt int8) AS $$
DECLARE 
	_i 		int;
	_cnt 		int;
BEGIN
/*	_name := 'with MAXCYCLE=' || fgetconst('obCMAXCYCLE') || ';MAXORDERFETCH=' || fgetconst('MAXORDERFETCH');
	cnt :=0;
	RETURN NEXT;
*/	
	_name := 'number of qualities';
	select count(*) INTO cnt FROM tquality;
	RETURN NEXT;
	
	_name := 'number of owners';
	select count(*) INTO cnt FROM towner;
	RETURN NEXT;
		
	_name := 'number of orders';
	select count(*) INTO cnt FROM vorderverif;
	RETURN NEXT;
	
	_name := 'number of movements';
	select count(*) INTO cnt FROM vmvtverif;
	RETURN NEXT;

	_name := 'number of orders removed';
	select count(*) INTO cnt FROM torderremoved;
	RETURN NEXT;
	
	_name := 'number of movements removed';
	select count(*) INTO cnt FROM tmvtremoved;	
	RETURN NEXT;
	
	_name := 'total number of agreements';
	select count(distinct grp) INTO cnt FROM vmvtverif;	
	RETURN NEXT;
/*
	-- too long
	IF(_extra) THEN				
		_name := 'number of connections between orders';
		cnt := fgetcntcon();
		RETURN NEXT;
	END IF;
*/	
	

	IF(_extra) THEN
	
		_name := 'errors on quantities in mvts';
		cnt := fverifmvt();
		RETURN NEXT;
	
		_name := 'errors on agreements in mvts';
		cnt := fverifmvt2();
		RETURN NEXT;

		FOR _name,cnt IN SELECT name,value FROM tconst LOOP
			RETURN NEXT;
		END LOOP;
				
		_cnt := 0;
		FOR _i,cnt IN SELECT * FROM fcntcycles() LOOP
			IF(_i !=1) THEN
				_name := 'agreements with ' || _i || ' partners';
				_cnt := _cnt + cnt;
			RETURN NEXT;
			END IF;
		END LOOP;
		
	END IF;
	
	RETURN;
END;
$$ LANGUAGE PLPGSQL;
GRANT EXECUTE ON FUNCTION fgetstats(bool)  TO admin;

--------------------------------------------------------------------------------
/* number of connections between orders */
CREATE FUNCTION fgetcntcon() RETURNS int AS $$
DECLARE 
	_cntrel int;
BEGIN
	SELECT count(*) INTO _cntrel FROM torder X,torder Y
		WHERE X.np = Y.nr ;
	RETURN _cntrel;
END;
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
/* agreement 
for all owners : select * from fgetagr(1);
for a given owner: select * from fgetagr(1) where _own='1';
*/
CREATE FUNCTION fgetagr(_grp int) RETURNS TABLE(_own text,_natp text,_qtt_prov int8,_qtt_requ int8,_natr text) AS $$
DECLARE 
	_fnat	 text;
	_fqtt	 int8;
	_fown	 text;
	_m	 vmvtverif%rowtype;
BEGIN
		_qtt_requ := NULL;
		FOR _m IN SELECT * FROM vmvtverif WHERE grp=_grp ORDER BY id ASC LOOP
			IF(_qtt_requ IS NULL) THEN
				_qtt_requ := _m.qtt;
				SELECT name INTO _natr FROM tquality WHERE _m.nat=id;
				SELECT name INTO _fown FROM towner WHERE _m.own_src=id;
				_fqtt := _m.qtt;
				_fnat := _natr;
			ELSE
				SELECT name INTO _natp FROM tquality WHERE _m.nat=id;
				SELECT name INTO _own FROM towner WHERE _m.own_src=id;
				_qtt_prov := _m.qtt;
				
				RETURN NEXT;
				_qtt_requ := _qtt_prov;
				_natr := _natp;
			END IF;
		END LOOP;
		IF(_qtt_requ IS NOT NULL) THEN
			_own := _fown;
			_natp := _fnat;
			_qtt_prov := _fqtt;
			--_qtt_requ := _qtt_requ;
			--_natr :=  _natr;
			RETURN NEXT;
		END IF;
	RETURN;
END;
$$ LANGUAGE PLPGSQL;


--------------------------------------------------------------------------------
-- for each cycle length, gives the number in tmvt
CREATE FUNCTION fcntcycles() RETURNS TABLE(nbCycle int,cnt int) AS $$ 
	select a.cxt as nbCycle ,count(*)::int as cnt from (
		select count(*)::int as cxt from vmvtverif group by grp
	) a group by a.cxt order by a.cxt asc $$
LANGUAGE SQL;

--------------------------------------------------------------------------------

	
--------------------------------------------------------------------------------
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
	_cnt		 int;
	_nb		 int;
BEGIN
	
	FOR _qtt_prov,_qtt,_uuid,_np IN SELECT qtt_prov,qtt,uuid,np FROM vorderverif LOOP
		
		SELECT sum(qtt),max(nat),min(nat),count(*),max(nb) INTO _qtta,_npa,_npb,_cnt,_nb 
			FROM vmvtverif WHERE oruuid=_uuid GROUP BY oruuid;
		IF(FOUND AND (_cnt=_nb)) THEN 
			IF((_qtt_prov != _qtta+_qtt) OR (_np != _npa) OR (_npa != _npb)) THEN 
				_cnterr := _cnterr +1;
				-- raise INFO 'uuid:%, nb:%',_uuid,_nb;
			END IF;
		END IF;
	END LOOP;

	RETURN _cnterr;
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
/* count error in movements when compared to orders  */
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
	FOR _mvt IN SELECT * FROM vmvtverif ORDER BY grp,id ASC  LOOP
		IF(_mvt.grp != _mvtprec.grp) THEN -- first mvt of agreement
			--> finish last agreement
			IF NOT (_mvtprec.grp IS NULL OR _mvtfirst.grp IS NULL) THEN
				_cnterr := _cnterr + fverifmvt2_int(_mvtprec,_mvtfirst);
				_cnt := _cnt +1;
				
				if(_cnt != _mvtprec.nb) THEN
					_cnterr := _cnterr +1;
					RAISE INFO 'wrong number of movements for agreement %',_mvtprec.oruuid;
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
			RAISE INFO 'wrong number of movements for agreement %',_mvtprec.oruuid;
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

--------------------------------------------------------------------------------
CREATE FUNCTION fverifmvt2_int(_mvtprec tmvt,_mvt tmvt) RETURNS int AS $$
DECLARE
	_o		vorderverif%rowtype;
BEGIN
	SELECT uuid,np,nr,qtt_prov,qtt_requ INTO _o.uuid,_o.np,_o.nr,_o.qtt_prov,_o.qtt_requ FROM vorderverif WHERE uuid = _mvt.oruuid;
	IF (NOT FOUND) THEN
		RAISE INFO 'order not found for vorderverif %',_mvt.oruuid;
		RETURN 1;
	END IF;

	IF(_o.np != _mvt.nat OR _o.nr != _mvtprec.nat) THEN
		RAISE INFO 'mvt.nat != np or mvtprec.nat!=nr';
		RETURN 1;
	END IF;
	
	-- _o.qtt_prov/_o.qtt_requ < _mvt.qtt/_mvtprec.qtt
	IF((_o.qtt_prov * _mvtprec.qtt) < (_mvt.qtt * _o.qtt_requ)) THEN
		RAISE INFO 'order %->%, with  mvt %->%',_o.qtt_requ,_o.qtt_prov,_mvtprec.qtt,_mvt.qtt;
		RAISE INFO 'orderid %, with  mvtid %->%',_o.id,_mvtprec.id,_mvt.id;
		RETURN 1;
	END IF;


	RETURN 0;
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
/* gives the flow representation of a group of movements */
CREATE FUNCTION fgetflow(_grp int8) RETURNS text AS $$
DECLARE
	_o	torder%rowtype;
	_res	text;
	_begin	bool;
BEGIN
	_res := '[';
	_begin := true;
	FOR _o IN SELECT o.* FROM torder o,tmvt m WHERE m.grp=_grp AND m.oruuid=o.uuid ORDER BY m.id ASC LOOP
		IF(NOT _begin) THEN
			_res := _res || ',';
		END IF;
		_begin := false;
		_res :=   _res || '(' || _o.id || ',' || _o.own  || ',' || _o.nr || ',' || _o.qtt_requ || ',' || _o.np || ',' || _o.qtt_requ  || ',' || _o.np || ')';
	END LOOP; 
	_res := _res || ']';
	RAISE NOTICE 'flow_to_matrix(flow)=%',yflow_to_matrix(_res::yflow);
	RETURN _res;
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
/* usage:
_t timestamp := current_timestamp;
action to measure
perform frec('action_name',_t);
then execute getdelays.py
 */
CREATE FUNCTION frectime(_name text,_start timestamp) RETURNS VOID AS $$
DECLARE
	_x	int8;
	_dn	text;
BEGIN
	_dn := 'perf_delay_' || _name;
	_x := extract(microsecond from (current_timestamp - _start)); 
	UPDATE tconst SET value = value + _x WHERE name = _dn;
	IF(NOT FOUND) THEN
		INSERT INTO tconst (name,value) VALUES (_dn,_x);
	END IF;
	_dn := 'perf_count_' || _name;
	UPDATE tconst SET value = value + 1 WHERE name = _dn;
	IF(NOT FOUND) THEN
		INSERT INTO tconst (name,value) VALUES (_dn,1);
	END IF;
	RETURN;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION fomega(pat yflow) RETURNS float8 AS $$
DECLARE
	_f float8[];
BEGIN
	_f := yflow_qtts(pat)::float8[];
	-- qtt_prov/qtt_requ
	RETURN (_f[1])/(_f[2]);
END;
$$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION fnpnr(pat yflow) RETURNS int8[] AS $$
DECLARE
	_vi int8[];
	_dim int;
BEGIN
	_vi := yflow_to_matrix(pat);
	_dim := yflow_dim(pat);
	-- qlt_prov,qlt_requ
	RETURN array[_vi[_dim][5],_vi[1][3]];
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION fpopulate(nbq int,nbo int) RETURNS int AS $$
DECLARE
	_f float8[];
	_i int;
	_range float :=1000;
BEGIN
	with t as (select i from generate_series(1,nbq) g(i))
	insert into tquality select t.i,'q' || t.i::text,1,session_user,0 from t;
	select setval('tquality_id_seq',nbq+1,false) INTO _i;

	with t as (select i from generate_series(1,nbo) g(i))
	insert into towner select t.i,t.i::text from t;
	select setval('towner_id_seq',nbo+1,false) INTO _i;

	with t as(select i from generate_series(1,nbo) g(i))
	INSERT INTO torder select --(id,uuid,own,nr,qtt_requ,np,qtt_prov,qtt,created,updated) 
		t.i as id,t.i::text as uuid,t.i as own,round(random()*(nbq-1))::int+1 as nr,(round(random()*_range)::int+1)*100 as qtt_requ,
		round(random()*(nbq-1))::int+1 as np,(round(random()*_range)::int+1)*100 as qtt_prov,1 as qtt,
		statement_timestamp() as created,NULL as updated from t;
	select setval('torder_id_seq',nbo+1,false) INTO _i;

	update torder set np=np-1 where np=nr and np>2; -- all must be different
	update torder set np=2 where np=nr and np=1;
	update torder set qtt=qtt_prov;

	WITH t as (select np, sum(qtt) as qtt from torder group by np)
	update tquality set qtt = t.qtt from t where id=t.np ;
	RETURN 1;
END;
$$ LANGUAGE PLPGSQL;


