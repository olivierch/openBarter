set schema 't';
create  extension if not exists intarray;

/* list of cycles <= _obCMAXCYCLE with order as int */
CREATE OR REPLACE FUNCTION fgetxconnected() RETURNS SETOF int[] AS $$
DECLARE 
	_obCMAXCYCLE int := fgetconst('obCMAXCYCLE');
	_MAX_REFUSED int := fgetconst('MAX_REFUSED');
BEGIN
	RETURN QUERY
		WITH RECURSIVE search_forward(id,np,pat,depthf,b,refused) AS (
			-- all valid orders
			SELECT b.id, b.np,array[]::int[],0,false,b.refused
				FROM torder b
				WHERE 	b.qtt > 0  AND flow_maxdimrefused(b.refused,_MAX_REFUSED)
			UNION 
			SELECT 	Yf.id, 
				Yf.np,X.pat || Yf.id::int, -- chemin
				X.depthf + 1, -- taille du chemin
				Yf.id = ANY(X.pat),Yf.refused
				FROM  search_forward X, torder Yf
				WHERE 	 X.np = Yf.nr AND NOT (Yf.id = ANY(X.refused))-- X->Y
					AND Yf.qtt > 0 AND flow_maxdimrefused(Yf.refused,_MAX_REFUSED)
					AND X.depthf < _obCMAXCYCLE
		)
		SELECT pat 
		FROM search_forward WHERE depthf <= _obCMAXCYCLE AND b=true;
	RETURN;
END;
$$ LANGUAGE PLPGSQL;

/* list of cycles <= _obCMAXCYCLE */
CREATE OR REPLACE FUNCTION fgetconnected(_offset int8) RETURNS SETOF int8[] AS $$
DECLARE 
	_obCMAXCYCLE int := fgetconst('obCMAXCYCLE');
	_MAX_REFUSED int := fgetconst('MAX_REFUSED');
	_cnt int8;
BEGIN
	SELECT max(id) into _cnt FROM torder;
	IF(FOUND) THEN
		IF (_offset > _cnt) THEN
			RAISE INFO 'offfset is more than max(torder.id)';
			RETURN;
		END IF;
	ELSE
		RAISE INFO 'torder is empty';
		RETURN;
	END IF;
	RETURN QUERY
		WITH RECURSIVE search_forward(id,np,pat,depthf,b,refused) AS (
			-- all valid orders
			SELECT b.id, b.np,array[]::int8[],0,false,b.refused
				FROM torder b
				WHERE 	b.qtt > 0  
					AND flow_maxdimrefused(b.refused,_MAX_REFUSED) 
					AND (_offset = 0 OR (
						b.id >= _offset AND b.id < _offset+30))
			UNION 
			SELECT 	Yf.id, 
				Yf.np,X.pat || Yf.id::int8, -- chemin
				X.depthf + 1, -- taille du chemin
				Yf.id = ANY(X.pat),Yf.refused
				FROM  search_forward X, torder Yf
				WHERE 	 X.np = Yf.nr AND NOT (Yf.id = ANY(X.refused))-- X->Y
					AND Yf.qtt > 0 AND flow_maxdimrefused(Yf.refused,_MAX_REFUSED)
					AND X.depthf < _obCMAXCYCLE
		)
		SELECT pat 
		FROM search_forward WHERE depthf <= _obCMAXCYCLE AND b=true;
	RETURN;
END;
$$ LANGUAGE PLPGSQL;

/* lists all orders of fgetconnected */
CREATE OR REPLACE FUNCTION fgetlstcon() RETURNS SETOF int8 AS $$
BEGIN
	RAISE INFO 'union of cycles';
	RETURN QUERY select x from(
		select m[id] x from (
			select m,generate_subscripts(m,1) as id from fgetconnected(0) c(m)
			) a
		) b group by x order by x desc;
END;
$$ LANGUAGE PLPGSQL;

/* list of path that do not contain array */ 
CREATE OR REPLACE FUNCTION fgetconl(_lid int8[]) RETURNS SETOF int8[] AS $$
BEGIN
	RAISE INFO 'list of path than do not contain %',_lid;
	RETURN QUERY SELECT pat FROM fgetconnected(0) a(pat) where NOT _lid <@ pat;
END;
$$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION fgetconll() RETURNS int8[] AS $$
DECLARE
	_res int[];
	_iter record;
	_cnt int :=0;
BEGIN
	RAISE INFO 'intersection all cycles (int8->int!!)';
	FOR _iter IN SELECT pat FROM fgetconnected(0) a(pat) LOOP
		_cnt := _cnt + 1;
		if(_cnt = 1) THEN 
			_res := _iter.pat::int[];
		ELSE
			_res := _res & _iter.pat::int[];
		END IF; 
	END LOOP;
	RETURN _res;
	-- RETURN QUERY SELECT o.id FROM torder o,fgetconnected() c(pat) WHERE o.id=ANY(c.pat) GROUP BY o.id; 
END;
$$ LANGUAGE PLPGSQL;

/* list of Y such as (_id,Y) are connected in torder */
CREATE OR REPLACE FUNCTION fgetcono(_id int8) RETURNS SETOF text AS $$
DECLARE 
	_MAX_REFUSED int := fgetconst('MAX_REFUSED');
	_np int8;
BEGIN
	SELECT np INTO _np FROM torder WHERE id=_id;
	RAISE INFO 'list of connexions from torder[%]-%>',_id,_np;
	RETURN QUERY SELECT Y.id || '-' || Y.np || '>' FROM torder X,torder Y
		WHERE X.id = _id AND X.np = Y.nr  AND NOT (Y.id = ANY(X.refused))
		AND X.qtt > 0 AND flow_maxdimrefused(X.refused,_MAX_REFUSED)
		AND Y.qtt > 0 AND flow_maxdimrefused(Y.refused,_MAX_REFUSED)
		GROUP BY Y.id ORDER BY Y.id;
END;
$$ LANGUAGE PLPGSQL;

/* list of Y such as (_id,Y) are connected in _tmp */
CREATE OR REPLACE FUNCTION fgetconm(_id int8) RETURNS SETOF text AS $$
DECLARE 
 	_MAX_REFUSED int := fgetconst('MAX_REFUSED');
 	_np int8;
BEGIN
	SELECT np INTO _np FROM _tmp WHERE id=_id;
	RAISE INFO 'list of connexions from _tmp[%]-%>',_id,_np;
	RETURN QUERY SELECT Y.id || '-' || Y.np || '>' FROM _tmp X,_tmp Y
		WHERE X.id = _id AND X.np = Y.nr  AND NOT (Y.id = ANY(X.refused))
		AND X.qtt > 0 AND flow_maxdimrefused(X.refused,_MAX_REFUSED)
		AND Y.qtt > 0 AND flow_maxdimrefused(Y.refused,_MAX_REFUSED)
		GROUP BY Y.id ORDER BY Y.id;
END;
$$ LANGUAGE PLPGSQL;

/* executes ftraversal from a pivot already inserted */
CREATE OR REPLACE FUNCTION fttr(_idpivot int8,_phase int) RETURNS int AS $$
DECLARE
 	_cntd int;
 	_lidpivots int8[];
BEGIN
	SELECT count(*) INTO _cntd FROM torder WHERE id=_idpivot;
	IF _cntd=0 THEN
		RAISE EXCEPTION 'idpivot % is not found, command fttr failed' , _idpivot;
		RETURN 0;
	END IF;
	SELECT * INTO _lidpivots,_cntd FROM ftraversal(_idpivot,_phase);
	RAISE NOTICE 'ftraversal(%,%) returned _lidpivots=%,_cntd=%',_idpivot,_phase,_lidpivots,_cntd;
	RETURN _cntd;
END;
$$ LANGUAGE PLPGSQL;

-- for each cycle length, gives the number in tmvt
CREATE OR REPLACE FUNCTION fcntcycles() RETURNS TABLE(nbCycle int8,cnt int8) AS $$ 
	select a.cxt as nbCycle ,count(*) as cnt from (
		select count(*) as cxt from tmvt group by grp
	) a group by a.cxt order by a.cxt desc $$
LANGUAGE SQL;


-- for each refused length, gives the number in torder
CREATE OR REPLACE FUNCTION fcntrefused() RETURNS TABLE(nbCycle int,cnt int8) AS $$ 
	select a.rl as nbCycle ,count(*) as cnt from (
		select array_length(refused,1) as rl  from torder 
	) a group by a.rl order by a.rl desc $$
LANGUAGE SQL;

/* number of connections between orders */
CREATE OR REPLACE FUNCTION fgetcntcon() RETURNS int AS $$
DECLARE 
	_MAX_REFUSED int := fgetconst('MAX_REFUSED');
	_cntrel int;
BEGIN
	SELECT count(*) INTO _cntrel FROM torder X,torder Y
		WHERE X.np = Y.nr  AND NOT (Y.id = ANY(X.refused))
		AND X.qtt > 0 AND flow_maxdimrefused(X.refused,_MAX_REFUSED)
		AND Y.qtt > 0 AND flow_maxdimrefused(Y.refused,_MAX_REFUSED);
	RETURN _cntrel;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION fgetstats() RETURNS TABLE(name text,cnt int8) AS $$
DECLARE 
	_MAX_REFUSED int := fgetconst('MAX_REFUSED');
	_i int;
	_cnt int;
BEGIN
	
	name := 'number of qualities';
	select count(*) INTO cnt FROM tquality;
	RETURN NEXT;
	
	name := 'number of owners';
	select count(*) INTO cnt FROM towner;
	RETURN NEXT;
		
	name := 'number of valid orders';
	select count(*) INTO cnt FROM torder WHERE qtt > 0 AND flow_maxdimrefused(refused,_MAX_REFUSED);
	RETURN NEXT;
	
	name := 'number of empty orders';
	select count(*) INTO cnt FROM torderempty;
	RETURN NEXT;
				
	name := 'number of connections between valid orders';
	cnt := fgetcntcon();
	RETURN NEXT;
	
	name := 'number of movements';
	select count(*) INTO cnt FROM tmvt;
	RETURN NEXT;
	
	_cnt := 0;
	FOR _i,cnt IN SELECT * FROM fcntcycles() LOOP
		name := 'cycles with ' || _i || ' partners';
		_cnt := _cnt + cnt;
		RETURN NEXT;
	END LOOP;

	name := 'total number of agreements';
	cnt := _cnt;
	RETURN NEXT;
	
	name := 'total number of relation refused';
	select sum(array_length(refused,1)) INTO cnt FROM torder;
	RETURN NEXT;
	-- select sum(nbcycle*cnt)/sum(cnt) from fcntcycles();
	RETURN;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION fverifmvt() RETURNS int8 AS $$
DECLARE
	_qtt_prov	int8;
	_qtt		int8;
	_uuid		int8;
	_qtta		int8;
	_npa		int8;
	_npb		int8;
	_np		int8;
	_cnterr		int8 := 0;
BEGIN
	FOR _qtt_prov,_qtt,_uuid,_np IN SELECT qtt_prov,qtt,uuid,np FROM torder LOOP
		SELECT sum(qtt),max(nat),mint(nat) INTO _qtta,_npa,_npb FROM tmvt WHERE oruuid=_uuid GROUP BY oruuid;
		IF(FOUND) THEN 
			IF((_qtt_prov != _qtta+_qtt) OR (_np != _npa) OR (_npa != _npb)) THEN 
				_cnterr := _cnterr +1;
			END IF;
		END IF;
	END LOOP;

	RETURN _cnterr;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION fverifmvt2() RETURNS int8 AS $$
DECLARE
	_cnterr		int8 := 0;
	_mvt		tmvt%rowtype;
	_mvtprec	tmvt%rowtype;
	_mvtfirst	tmvt%rowtype;
	_idm		int8;
BEGIN
	_mvtprec.grp := NULL;
	_idm := NULL;
	FOR _mvt IN SELECT * FROM tmvt WHERE grp=1 ORDER BY grp,id ASC  LOOP
		IF(_mvt.grp = _mvtprec.grp) THEN
			_cnterr := _cnterr + fverifmvt2_int(_mvtprec,_mvt);
		ELSE
			IF NOT (_mvtprec.grp IS NULL) THEN
				_cnterr := _cnterr + fverifmvt2_int(_mvtprec,_mvtfirst);
			END IF;
			_mvtfirst := _mvt;
		END IF;
		_mvtprec := _mvt;
		if((_idm IS NULL OR _idm > _mvt.id) and _cnterr!=0 ) THEN
			_idm := _mvt.id;
		END IF;
	END LOOP;
	IF NOT(_mvtprec.grp IS NULL) THEN
		_cnterr := _cnterr + fverifmvt2_int(_mvtprec,_mvtfirst);
	END IF;
	RAISE NOTICE 'mvt.id min %',_idm;
	RETURN _cnterr;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION fverifmvt2_int(_mvtprec tmvt,_mvt tmvt) RETURNS int8 AS $$
DECLARE
	_o		torder%rowtype;
BEGIN
	SELECT * INTO _o FROM torder WHERE id = _mvt.orid;
	IF (NOT FOUND) THEN
		RAISE INFO 'order not found for mvt %',_mvt;
		RETURN 1;
	END IF;
	
	IF(_o.id != _mvt.orid ) THEN
		RAISE EXCEPTION 'error';
	END IF;

	IF(_o.np != _mvt.nat OR _o.nr != _mvtprec.nat) THEN
		RAISE INFO 'nat != np';
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

/* gives the flow representation of a group of movements */
CREATE OR REPLACE FUNCTION fgetflow(_grp int8) RETURNS text AS $$
DECLARE
	_o	torder%rowtype;
	_res	text;
BEGIN
	_res := '[f';
	FOR _o IN SELECT o.* FROM torder o,tmvt m WHERE m.grp=_grp AND m.orid=o.id ORDER BY m.id ASC LOOP
		-- 'flow ''[r,(id,nr,qtt_prov,qtt_requ,own,qtt,np), ...]''';
		_res :=   _res || ',(' || _o.id || ',' || _o.nr  || ',' || _o.qtt_prov || ',' || _o.qtt_requ  || ',' || _o.own  || ',' || _o.qtt_prov || ',' || _o.np || ')';
	END LOOP; 
	_res := _res || ']';
	RAISE NOTICE 'flow_proj(flow,8)=%',flow_proj(_res::flow,8);
	RAISE NOTICE 'flow_to_matrix(flow)=%',flow_to_matrix(_res::flow);
	RETURN _res;
END;
$$ LANGUAGE PLPGSQL;


/* usage:
_t timestamp := current_timestamp;
action to measure
perform frec('action_name',_t);
then execute getdelays.py
 */
CREATE OR REPLACE FUNCTION frectime(_name text,_start timestamp) RETURNS VOID AS $$
DECLARE
	_x	int8;
	_dn	text;
BEGIN
	_dn := 'perf_lay_' || _name;
	_x := extract(millisecond from (current_timestamp - _start)); 
	UPDATE tconst SET value = value + _x WHERE name = _dn;
	IF(NOT FOUND) THEN
		INSERT INTO tconst (name,value) VALUES (_dn,_x);
	END IF;
	_dn := 'perf_cnt_' || _name;
	UPDATE tconst SET value = value + 1 WHERE name = _dn;
	IF(NOT FOUND) THEN
		INSERT INTO tconst (name,value) VALUES (_dn,1);
	END IF;
	RETURN;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION fcorrect() RETURNS VOID AS $$
DECLARE
	_uuid	text;
	_id 	int8;
BEGIN
	FOR _id IN SELECT id from torder LOOP
		_uuid := fgetuuid(_id);
		-- RAISE INFO 'uuid:%',_uuid;
		UPDATE torder SET uuid=_uuid WHERE id=_id;
		UPDATE tmvt SET oruuid=_uuid WHERE orid=_id;
	END LOOP;
	RETURN;
END;
$$ LANGUAGE PLPGSQL;

