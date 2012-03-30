-- set schema 't';


-------------------------------------------------------------------------------
-- 
CREATE function fremoveorder(_uuid text) RETURNS vorder AS $$
DECLARE
	_qtt		int8;
	_o 		torder%rowtype;
	_vo		vorder%rowtype;
	_qlt		tquality%rowtype;
BEGIN
	_vo.id = NULL;
	SELECT o.* INTO _o FROM torder o,tquality q,tuser u WHERE o.np=q.id AND q.idd=u.id AND u.name=session_user AND uuid = _uuid;
	IF NOT FOUND THEN
		RAISE WARNING 'the order % belonging to % was not found',_uuid,session_user;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	UPDATE tquality SET qtt = qtt - _o.qtt WHERE id = _o.np RETURNING qtt INTO _qlt;	
	IF(_qlt.qtt <0) THEN
		RAISE WARNING 'the quality % underflows',_qlt.name;
		RAISE EXCEPTION USING ERRCODE='YA002';
	END IF;
	
	SELECT * INTO _vo FROM vorder WHERE id = _o.id;	
	WITH a AS (DELETE FROM torder o WHERE o.id=_o.id RETURNING *) 
	INSERT INTO torderremoved SELECT id,uuid,own,nr,qtt_requ,np,qtt_prov,qtt,created,updated FROM a;
	
	RETURN _vo;
	
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE INFO 'ABORTED';
	RETURN _vo; 
END;		
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fremoveorder(text) TO market;

--------------------------------------------------------------------------------
-- finsert_order
--------------------------------------------------------------------------------
-- PUBLIC
/* usage: 
	nb_draft int = finsertorder(_owner text,_qualityprovided text,qttprovided int8,_qttrequired int8,_qualityrequired text)
		
	action:
		inserts the order.
		if _owner,_qualityprovided or _qualityrequired do not exist, they are created
	
	returns nb_draft:
		the number of draft inserted.
		or error returned by ob_finsert_order_int

*/
--------------------------------------------------------------------------------
-- torder id,uuid,yorder,created,updated
-- yorder: qtt,nr,np,qtt_prov,qtt_requ,own
CREATE FUNCTION 
	finsertorder(_owner text,_qualityprovided text,_qttprovided int8,_qttrequired int8,_qualityrequired text)
	RETURNS TABLE ( _yuuid text, _ydim int, _ygrp int) AS $$
	
DECLARE
	_user text;
	_np	int;
	_nr	int;
	_wid	int;
	_pivot torder%rowtype;
	_q	text[];
	_time_begin timestamp;
	_uid	int;
BEGIN
	_uid := fconnect(true);
	_time_begin := clock_timestamp();
	
	-- order is rejected if the depository is not the user
	_q := fexplodequality(_qualityprovided);
	IF (_q[1] != session_user) THEN
		RAISE NOTICE 'depository % of quality is not the user %',_q[1],session_user;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	-- quantities should be >0
	IF(_qttprovided<=0 OR _qttrequired<=0) THEN
		RAISE NOTICE 'quantities incorrect: %<=0 or %<=0', _qttprovided,_qttrequired;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	-- qualities are inserted if necessary (depository should exist)
	_np := fupdate_quality(_qualityprovided,_qttprovided); 
	_nr := fupdate_quality(_qualityrequired,0);
	
	-- if the owner does not exist, it is inserted
	_wid := fowner(_owner);
	
	_pivot.id  := 0;
	_pivot.own := _wid;
	
	_pivot.nr  := _nr;
	_pivot.qtt_requ := _qttrequired;
	
	_pivot.np  := _np;
	_pivot.qtt_prov := _qttprovided;
	_pivot.qtt := _qttprovided;
	
	FOR _yuuid,_ydim,_ygrp IN SELECT _zuuid,_zdim,_zgrp  FROM finsert_order_int(_pivot,TRUE) LOOP
		RETURN NEXT;
	END LOOP;
	
	perform fspendquota(_time_begin);
	
	RETURN;
	
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE INFO 'ABORTED';
	RETURN; 

END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION finsertorder(text,text,int8,int8,text) TO market;

CREATE VIEW vorderinsert AS
	SELECT id,yorder_get(id,own,nr,qtt_requ,np,qtt_prov,qtt) as ord,np,nr
	FROM torder ORDER BY id ASC;
	
--------------------------------------------------------------------------------
-- finsert_order_int

--------------------------------------------------------------------------------
CREATE FUNCTION 
	finsert_order_int(_pivot torder,_insert bool) RETURNS TABLE (_zuuid text, _zdim int, _zgrp int,_zqtt_prov int8,_zqtt_requ int8) AS $$
DECLARE

	_idpivot 	int;
	_patmax		yflow;
	_cnt 		int;
	_o		torder%rowtype;
	_res	        int8[];
BEGIN
	------------------------------------------------------------------------
	_pivot.qtt := _pivot.qtt_prov;
	
	IF(_insert) THEN
		INSERT INTO torder (uuid,qtt,nr,np,qtt_prov,qtt_requ,own,created,updated) 
			VALUES ('',_pivot.qtt,_pivot.nr,_pivot.np,_pivot.qtt_prov,_pivot.qtt_requ,_pivot.own,statement_timestamp(),NULL)
			RETURNING id INTO _idpivot;
		_zuuid := fgetuuid(_idpivot);
		UPDATE torder SET uuid = _zuuid WHERE id=_idpivot RETURNING * INTO _o;
		_cnt := fcreate_tmp(_o.id,yorder_get(_o.id,_o.own,_o.nr,_o.qtt_requ,_o.np,_o.qtt_prov,_o.qtt),_o.np,_o.nr);
	ELSE
		select max(id)+1 INTO _pivot.id FROM torder;
		-- _pivot.id!=0 and from all id inserted => lastignore=false 
		_cnt := fcreate_tmp(_pivot.id,
				yorder_get(_pivot.id,_pivot.own,_pivot.nr,_pivot.qtt_requ,_pivot.np,_pivot.qtt_prov,_pivot.qtt),
				_pivot.np,_pivot.nr);
	END IF;

	IF(_cnt=0) THEN
		RETURN;
	END IF;
	_cnt := 0;
/*	
	DROP TABLE IF EXISTS _tmp_insert;
	CREATE TABLE _tmp_insert AS (SELECT * FROM _tmp);
*/	
	LOOP
		_cnt := _cnt + 1;
		SELECT yflow_max(pat) INTO _patmax FROM _tmp;
		IF (yflow_status(_patmax)!=3) THEN
			EXIT; -- from LOOP
		END IF;

		-- RAISE NOTICE 'get max = %',yflow_show(_patmax);
		-- RETURN;
/*
		IF(_cnt = 1) THEN
			RAISE NOTICE 'get max = %',yflow_show(_patmax);
		END IF;
*/
		IF(_insert) THEN
		----------------------------------------------------------------
			_zgrp := fexecute_flow(_patmax);
			_zdim := yflow_dim(_patmax);
			RETURN NEXT;
		ELSE
			_res := yflow_qtts(_patmax);
			_zqtt_prov := _res[1];
			_zqtt_requ := _res[2];
			_zdim 	:= _res[3];
			-- RAISE NOTICE 'maxflow %' ,yflow_show(_patmax);
			RETURN NEXT;		
		END IF;
		----------------------------------------------------------------
		UPDATE _tmp SET pat = yflow_reduce(pat,_patmax);
	END LOOP;
	
	DROP TABLE _tmp;
 	RETURN;
END; 
$$ LANGUAGE PLPGSQL; 

create table tsave_tmp(
	n	int,
	id 	int,
	ord	yorder,
	nr	int,
	pat	yflow
);
--------------------------------------------------------------------------------
/* common to insertorder() and getquote() */
CREATE FUNCTION fcreate_tmp_mod(_id int,_ord yorder,_np int,_nr int) RETURNS int AS $$
DECLARE 
	_MAXORDERFETCH	 int := fgetconst('MAXORDERFETCH'); 
	_MAXCYCLE 	int := fgetconst('MAXCYCLE');
	_cnt int;
	_idx  int;
BEGIN
	-- DROP TABLE IF EXISTS _tmp;
	-- RAISE INFO 'pivot: id=% ord=%, np=%, nr=%',_id,_ord,_np,_nr;
	CREATE TEMPORARY TABLE _tmp ON COMMIT DROP AS (
		WITH RECURSIVE search_backward(id,ord,pat,np,nr) AS (
			SELECT 	_id,_ord,yflow_get(_ord),_np,_nr
			UNION ALL
			SELECT 	X.id,X.ord,
				yflow_get(X.ord,Y.pat), -- add the order at the begin of the yflow
				X.np,X.nr
				FROM vorderinsert X, search_backward Y
				WHERE  X.np = yorder_nr(Y.ord) -- use of indexe 
					AND yflow_follow(_MAXCYCLE,X.ord,Y.pat) 
					-- X->Y === X.qtt>0 and X.np=Y[0].nr
					-- Y.pat does not contain X.ord 
					-- len(X.ord+Y.path) <= _MAXCYCLE	
					-- Y[!=-1]|->X === Y[i].np != X.nr with i!= -1
		)
		SELECT id,ord,nr,pat 
		FROM search_backward  --draft
	);

	SELECT COUNT(*) INTO _cnt FROM _tmp;
		
	SELECT max(n) INTO _idx FROM tsave_tmp;
	IF(_idx IS NULL) THEN _idx := 0; END IF;
	WITH a AS (SELECT * FROM _tmp) 
	INSERT INTO tsave_tmp SELECT _idx+1 as n,a.id,a.ord,a.nr,a.pat FROM a;
	
	DELETE FROM _tmp WHERE yflow_status(pat)!=3;
	
	RETURN _cnt;
END;
$$ LANGUAGE PLPGSQL;

CREATE FUNCTION fcreate_tmp(_id int,_ord yorder,_np int,_nr int) RETURNS int AS $$
DECLARE 
	_MAXORDERFETCH	 int := fgetconst('MAXORDERFETCH'); 
	_MAXCYCLE 	int := fgetconst('MAXCYCLE');
	_cnt int;
BEGIN
	-- DROP TABLE IF EXISTS _tmp;
	-- RAISE INFO 'pivot: id=% ord=%, np=%, nr=%',_id,_ord,_np,_nr;
	CREATE TEMPORARY TABLE _tmp ON COMMIT DROP AS (
		WITH RECURSIVE search_backward(id,ord,pat,np,nr) AS (
			SELECT 	_id,_ord,yflow_get(_ord),_np,_nr
			UNION ALL
			SELECT 	X.id,X.ord,
				yflow_get(X.ord,Y.pat), -- add the order at the begin of the yflow
				X.np,X.nr
				FROM vorderinsert X, search_backward Y
				WHERE  X.np = yorder_nr(Y.ord) -- use of indexe 
					AND yflow_follow(_MAXCYCLE,X.ord,Y.pat) 
					-- X->Y === X.qtt>0 and X.np=Y[0].nr
					-- Y.pat does not contain X.ord 
					-- len(X.ord+Y.path) <= _MAXCYCLE	
					-- Y[!=-1]|->X === Y[i].np != X.nr with i!= -1
				 
		)
		SELECT id,ord,nr,pat 
		FROM search_backward where yflow_status(pat)=3 LIMIT _MAXORDERFETCH --draft
	);
	SELECT COUNT(*) INTO _cnt FROM _tmp;
	
	RETURN _cnt;
END;
$$ LANGUAGE PLPGSQL;


--------------------------------------------------------------------------------
-- fexecute_flow
--------------------------------------------------------------------------------

CREATE FUNCTION fexecute_flow(_flw yflow) RETURNS int AS $$
DECLARE
	_commits	int[][];
	_i		int;
	_next_i		int;
	_nbcommit	int;
	
	_oid		int;
	_w_src		int;
	_w_dst		int;
	_flowr		int8;
	_first_mvt	int;
	_exhausted	bool;
	_mvt_id		int;
	_qtt		int8;
	_cnt 		int;
	_uuid		text;
BEGIN

	_commits := yflow_to_matrix(_flw);
	-- indices in _commits
	-- 1  2   3  4        5  6        7   8
	-- id,own,nr,qtt_requ,np,qtt_prov,qtt,flowr
	
	_nbcommit := yflow_dim(_flw);
	_first_mvt := NULL;
	_exhausted := false;
	
	_i := _nbcommit;	
	FOR _next_i IN 1 .. _nbcommit LOOP
		-- _commits[_next_i] follows _commits[_i]
		_oid	:= _commits[_i][1]::int;
		_w_src	:= _commits[_i][2]::int;
		_w_dst	:= _commits[_next_i][2]::int;
		_flowr	:= _commits[_i][8];
		
		UPDATE torder set qtt = qtt - _flowr ,updated = statement_timestamp()
			WHERE id = _oid AND _flowr <= qtt RETURNING uuid,qtt INTO _uuid,_qtt;
		IF(NOT FOUND) THEN
			RAISE WARNING 'the flow is not in sync with the databasetorder[%].qtt does not exist or < %',_oid,_flowr ;
			RAISE EXCEPTION USING ERRCODE='YU001';
		END IF;
			
		INSERT INTO tmvt (nb,oruuid,grp,own_src,own_dst,qtt,nat,created) 
			VALUES(_nbcommit,_uuid,_first_mvt,_w_src,_w_dst,_flowr,_commits[_i][5]::int,statement_timestamp())
			RETURNING id INTO _mvt_id;
					
		IF(_first_mvt IS NULL) THEN
			_first_mvt := _mvt_id;
		END IF;
		
		IF(_qtt=0) THEN
			-- order is moved to orderremoved
			WITH a AS (DELETE FROM torder WHERE id=_oid RETURNING *) 
			INSERT INTO torderremoved SELECT id,uuid,own,nr,qtt_requ,np,qtt_prov,qtt,created,updated FROM a;
			_exhausted := true;
		END IF;

		_i := _next_i;
		------------------------------------------------------
	END LOOP;

	UPDATE tmvt SET grp = _first_mvt WHERE id = _first_mvt  AND (grp IS NULL);	
	IF(NOT FOUND) THEN
		RAISE EXCEPTION 'the movement % does not exist',_first_mvt 
			USING ERRCODE='YA003';
	END IF;
	
	IF(NOT _exhausted) THEN
		--  some order should be exhausted 
		RAISE EXCEPTION 'the cycle should exhaust some order' 
			USING ERRCODE='YA003';
	END IF;
	
	RETURN _first_mvt;
END;
$$ LANGUAGE PLPGSQL;

