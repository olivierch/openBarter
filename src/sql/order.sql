set schema 't';

drop extension if exists flow cascade;
create extension flow;

INSERT INTO tconst (name,value) VALUES 
-- The following can be changed
('VERIFY',1), -- if 1, verifies accounting each time it is changed
('REMOVE_CYCLES',0); -- 1, remove unexpected cycles 0 -- stop on unexpected cycles

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
CREATE OR REPLACE FUNCTION 
	finsertorder(_owner text,_qualityprovided text,_qttprovided int8,_qttrequired int8,_qualityrequired text,_debugPhase int) 
	RETURNS TABLE(_uuid text,_cnt int) AS $$
	
DECLARE
	_user text;
	_np	int8;
	_nr	int8;
	_wid	int8;
	_pivot torder%rowtype;
	_q	text[];
	_time_begin timestamp;
	_uid	int8;
BEGIN
	_uid := fconnect(true);
	_time_begin := clock_timestamp();
	
	-- order is rejected if the depository is not the user
	_q := fexplodequality(_qualityprovided);
	IF (_q[1] != current_user) THEN
		RAISE NOTICE 'depository % of quality is not the user %',_q[1],current_user;
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
	
	_pivot.own := _wid;
	_pivot.id  := 0;
	_pivot.qtt := _qttprovided;
	_pivot.np  := _np;
	_pivot.nr  := _nr;
	_pivot.qtt_prov := _qttprovided;
	_pivot.qtt_requ := _qttrequired;
	
	FOR _uuid,_cnt IN SELECT * FROM finsert_order_int(_pivot,_debugPhase) LOOP
		RETURN NEXT;
	END LOOP;
	
	perform fspendquota(_time_begin);
		
	IF(fgetconst('VERIFY') = 1) THEN
		perform fverify();
	END IF;
	
	RETURN;
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE INFO 'ABORTED';
	RETURN;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION finsertorder(text,text,int8,int8,text,int) TO market;


CREATE OR REPLACE FUNCTION fgetuuid(_id int8) RETURNS text AS $$ 
	select current_date::text || '-' || lpad($1::text,8,'0'); $$
LANGUAGE SQL;

--------------------------------------------------------------------------------
-- finsert_order_int

--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION 
	finsert_order_int(_pivot torder,_debugPhase int) RETURNS TABLE(_uuid text,_cnt int) AS $$
DECLARE
	_lidpivots	int8[];
	_xpivots	int8[];
	_idpivot	int8;
	_cnt		int;
	_cntl		int := 0;
	_uuid		text;
BEGIN
	------------------------------------------------------------------------
	_pivot.qtt := _pivot.qtt_prov;

	-- _uuid := CAST(flow_uuid() AS text);
	INSERT INTO torder (uuid,qtt,nr,np,qtt_prov,qtt_requ,own,created,updated) 
		VALUES ('',_pivot.qtt,_pivot.nr,_pivot.np,_pivot.qtt_prov,_pivot.qtt_requ,_pivot.own,statement_timestamp(),NULL)
		RETURNING id INTO _idpivot;
	_uuid := fgetuuid(_idpivot);
	UPDATE torder SET uuid = _uuid WHERE id=_idpivot;
		-- _idpivot makes cycles
		
	_lidpivots := ARRAY[_idpivot];
	
	WHILE array_upper(_lidpivots,1)!=0 LOOP
	-- loop performed for at least one time, for all pivots found
		_cntl := _cntl + 1;
		_idpivot := _lidpivots[1];
		
		IF(_cntl > 1) THEN
			RAISE WARNING 'ftraversal(%) unexpected cycle correction for %', _idpivot,_lidpivots;
			SELECT uuid INTO _uuid FROM torder WHERE id = idpivot; 
		END IF;
		
		SELECT * INTO _lidpivots,_cnt FROM ftraversal(_idpivot,_debugPhase); -- find and execute contracts
		RETURN NEXT; --_cnt := _cnt + _cntd;
		
		-- adds new unexpected pivots found to the list to be processed
		-- it is a union of _lidpivots and _xpivots
		SELECT _lidpivots || array_agg(xpivot) INTO _lidpivots FROM (
				SELECT _xpivots[i] as xpivot FROM generate_subscripts(_xpivots,1) g(i) 
			) AS x
			WHERE NOT (xpivot=any(_lidpivots));
		
		_lidpivots := _lidpivots[2:array_length(_lidpivots,1)];  -- pop _idpivot
	END LOOP;
	
 	RETURN;
END; 
$$ LANGUAGE PLPGSQL; 
/* if _debugPhase = -1, never stop
if _debugPhase = 0 stop after backward traversal
else if _debugPhase = _cntgraph stops after forward traversal */
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ftraversal(_idPivot int8,_debugPhase int,OUT _lidpivots int8[],OUT _cntd int) AS $$
DECLARE 
	_obCMAXCYCLE int := fgetconst('obCMAXCYCLE');
	_maxDepth int;
	_cnt int;
	_flow flow;
	_i int;
	_pivotReached bool;
	_loopFound bool;
	_MAX_REFUSED int := fgetconst('MAX_REFUSED');
BEGIN
	_lidpivots := ARRAY[]::int8[];
	_cntd := 0;
	-- RAISE INFO 'ftraversal called for pivot=%',_idPivot;
	
	DROP TABLE IF EXISTS _tmp;
	CREATE TEMP TABLE _tmp ON COMMIT DROP AS (
		WITH RECURSIVE search_backward(id,nr,qtt_prov,qtt_requ,refused,
						own,qtt,np,
						pat,loop,
						depthb) AS (
			SELECT b.id, b.nr,b.qtt_prov,b.qtt_requ,b.refused,
				b.own,b.qtt,b.np,
				ARRAY[_idPivot],false,
				1
				FROM torder b
				WHERE 	b.id = _idPivot 
					AND b.qtt > 0 AND flow_maxdimrefused(b.refused,_MAX_REFUSED)	
					-- AND flow_orderaccepted(b,_MAX_REFUSED)		
			UNION 
			SELECT X.id, X.nr,X.qtt_prov,X.qtt_requ,X.refused,
				X.own,X.qtt,X.np,
				X.id || Y.pat,X.id=ANY(Y.pat),
				Y.depthb + 1 -- depthb in [1,_obCMAXCYCLE] 
				FROM torder X, search_backward Y
				WHERE	X.id != _idPivot
					-- AND flow_orderaccepted(X,_MAX_REFUSED)	
					AND X.qtt > 0 AND flow_maxdimrefused(X.refused,_MAX_REFUSED)
					AND X.np = Y.nr AND NOT (Y.id = ANY(X.refused)) -- X->Y
					 -- Y.refused with too many elements
					AND Y.depthb < _obCMAXCYCLE 
					
		)
		-- SELECT id,nr,qtt_prov,qtt_requ,own,qtt,np,NULL::flow as flow,0 as cntgraph,depthb,0 as depthf,refused
		SELECT id,max(nr) as nr,max(qtt_prov)as qtt_prov,max(qtt_requ) as qtt_requ,max(own) as own,max(qtt) as qtt,max(np) as np,
			NULL::flow as flow,0 as cntgraph,max(depthb) as depthb,0 as depthf,max(refused) as refused,bool_or(loop) as loop,
			ARRAY[]::int8[] as Zrefused
		FROM search_backward group by id
	);
	-- depthb in [1,_obCMAXCYCLE]
	IF ( _debugPhase = 0 ) THEN
		-- RAISE NOTICE 'ftraversal(%) stopped before fexecute_flow(flow) with flow=%',_idPivot,_flow;
		RETURN;
	END IF;
	
	-- stops when graph empty
	SELECT count(*),bool_or(loop) INTO _cnt,_loopFound FROM _tmp;
	IF(_cnt <= 1) THEN
		RETURN;
	END IF; 
	
	IF (_loopFound) THEN 
		-- unexpected cycles are found
		
		SELECT array_agg(id) INTO _lidpivots 
		FROM _tmp WHERE loop;
		RAISE WARNING 'unexpected cycles found for orders % ',_lidpivots;
		
		IF (fgetconst('REMOVE_CYCLES') = 1 ) THEN
			-- _lidpivots is the set of unexpected pivots
			DELETE FROM _tmp WHERE loop;
		ELSE
			RAISE EXCEPTION 'unexpected cycles found for orders %',_lidpivots USING ERRCODE='YA003';
		END IF;	
	END IF;

	-- CREATE INDEX _tmp_idx ON _tmp(cntgraph,nr);
	_cntd := 0;

	LOOP -- repeate as long as a draft is found
		
		UPDATE _tmp SET depthf =0,Zrefused= ARRAY[]::int8[]; -- TODO le mettre à la fin de la LOOP
		
		-- RAISE NOTICE '_maxDepth=% _np=% _idPivot=%',_maxDepth,_np,_idpivot;
		WITH RECURSIVE search_forward(id,nr,np,qtt,refused,depthx) AS (
			SELECT src.id,src.nr,src.np,src.qtt,src.refused,1
				FROM _tmp src 
				WHERE 	src.id = _idPivot 
					AND src.qtt > 0 AND flow_maxdimrefused(src.refused,_MAX_REFUSED)
			UNION
			SELECT Y.id,Y.nr,Y.np,Y.qtt,Y.refused,X.depthx + 1
				FROM search_forward X, _tmp Y
				WHERE   Y.id != _idPivot 
					AND Y.qtt > 0 AND flow_maxdimrefused(Y.refused,_MAX_REFUSED)
					-- AND Y.cntgraph = _cntgraph-1
					AND X.depthx < _obCMAXCYCLE
					AND X.np = Y.nr AND NOT(Y.id=ANY(X.refused)) -- X->Y
					
		) 
		UPDATE _tmp t 
			SET flow = CASE WHEN sf.depthx = 2  -- source
				THEN flow_init(t.id,t.nr,t.qtt_prov,t.qtt_requ,t.own,t.qtt,t.np) 
				ELSE '[]'::flow END,
			depthf = sf.depthx,
			Zrefused = t.refused
		FROM (SELECT min(depthx) as depthx,id FROM search_forward group by id ) sf WHERE t.id = sf.id ;
		
		IF ( _debugPhase = 1 ) THEN
			-- RAISE NOTICE 'ftraversal(%) stopped before fexecute_flow(flow) with flow=%',_idPivot,_flow;
			RETURN;
		END IF;
		
		-- delete node not seen
		DELETE FROM _tmp WHERE depthf = 0;
		
		SELECT count(*),bool_or(id=_idpivot) INTO _cnt,_pivotReached FROM _tmp; 
		 
		RAISE NOTICE '_cnt=%,_pivotReached=%',_cnt,_pivotReached;		
		if((_cnt = 0) OR (NOT _pivotReached)) THEN -- then graph _cntgraph is empty or pivot not seen
			RETURN;
		END IF;				
/*
		when pivot is reached, the path is a loop (refused or draft) and omegas are adjusted such as their product becomes 1.
*/	
		FOR _cnt IN 2 .. _obCMAXCYCLE LOOP
			UPDATE _tmp Y 
			SET 
			flow = flow_catt(X.flow,Y.id,Y.nr,Y.qtt_prov,Y.qtt_requ,Y.own,Y.qtt,Y.np,Y.refused)
			FROM _tmp X WHERE X.id != _idPivot -- arcs pivot->sources are not considered
				AND Y.qtt > 0 AND flow_maxdimrefused(Y.refused,_MAX_REFUSED)
				AND flow_omegaz(X.flow,Y.flow,Y.id,Y.nr,Y.qtt_prov,Y.qtt_requ,Y.own,Y.qtt,Y.np,X.refused,Y.refused);
		END LOOP;
				
		-- flow of pivot
		SELECT flow INTO _flow FROM _tmp WHERE id = _idPivot; 
		IF(NOT FOUND) THEN
			RAISE EXCEPTION 'The _tmp[_idPivot=%] should be found',_idPivot USING ERRCODE='YA003';
		END IF;
		IF ( _debugPhase = 2 ) THEN
			-- RAISE NOTICE 'ftraversal(%) stopped before fexecute_flow(flow) with flow=%',_idPivot,_flow;
			RETURN;
		END IF;
		-- RAISE NOTICE 'flow:%',_flow;
		IF(flow_isloop(_flow)) THEN 
			-- RAISE NOTICE 'fexecute_flow(flow) with flow=%',_flow;
			_cntd := _cntd + fexecute_flow(_flow,_debugPhase);
		ELSE 
			RETURN;
		END IF;
		
		IF (_debugPhase>2) THEN
			-- RAISE NOTICE 'stop on phase=% with _cntd=%',_debugPhase,_cntd;
			RETURN;
		END IF;
			
	END LOOP;
END; 
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
-- fexecute_flow
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fexecute_flow(_flw flow,_debugPhase int) RETURNS int AS $$
DECLARE
	_commits	int8[][];
	_i		int;
	_next_i		int;
	_nbcommit	int;
	_oid		int8;
	_w_src		int8;
	_w_dst		int8;
	_flowr		int8;
	_first_mvt	int8;
	_exhausted	bool;
	_backloopref	bool;
	_worst		int;
	_oid1		int8;
	_oid2		int8;
	_mvt_id		int8;
	_qtt		int8;
	_MAX_REFUSED int := fgetconst('MAX_REFUSED');
	_refused	int8[];
	_cnt 		int;
	_todel		bool;
	_uuid		text;
BEGIN
	_commits := flow_to_matrix(_flw);
	
	-- RAISE NOTICE '_commits=%',_commits;
	_nbcommit := flow_dim(_flw); -- array_upper(_commits,1); 
	IF(_nbcommit < 2) THEN
		RAISE WARNING 'nbcommit % < 2',_nbcommit;
		RAISE EXCEPTION USING ERRCODE='YA003';
	END IF;
	
	_worst := flow_refused(_flw);
	IF( _worst >= 0 ) THEN -- occurs when the flow is not draft
/* 		refused and some omega > qtt_p/qtt_r
		-- or when no solution was found
		-- _worst in [0,_nbcommit[, 
		--	 _oid1 = _commits[worst-1][1],
		--	 _oid2 = _commits[worst][1] */	
		-- -1%_nbcommit gives -1, but (-1+_nbcommit)%_nbcommit gives _nbcommit-1 		
				
		_oid1 := _commits[((_worst-1+_nbcommit)%_nbcommit)			+1][1];	
		_oid2 := _commits[  _worst						+1][1];		
		
		UPDATE torder SET refused = refused || _oid2 WHERE id = _oid1 AND NOT(ARRAY[_oid2] <@ refused) 
			RETURNING refused,NOT flow_maxdimrefused(refused,_MAX_REFUSED) INTO _refused,_todel;
		-- we accept that _oid2 is found in torder[_oid1].refused 
		IF( FOUND AND _todel) THEN
			-- perform fdeleteorder(_oid1);
			_i := fcheckorder(_oid1);
		END IF;
		
		UPDATE _tmp   SET refused = refused || _oid2 WHERE id = _oid1 AND NOT(ARRAY[_oid2] <@ refused);
		-- but not in _tmp
		IF (NOT FOUND) THEN
			SELECT refused INTO _refused FROM _tmp WHERE id = _oid1;
			IF(FOUND) THEN
				RAISE EXCEPTION 
				'the flow is refused and the relation %->% it contains was refused\n flow:%',_oid1,_oid2,_flw 
				USING ERRCODE='YA003'; 
			ELSE
				RAISE EXCEPTION 
				'the flow contains % but _tmp[%] not found. flow:%',_oid1,_oid1,_flw 
				USING ERRCODE='YA003'; 
			END IF;
		END IF;
		
		IF _debugPhase>0 THEN
			RAISE NOTICE 'relation %->% refused',_oid1,_oid2;
		END IF;
		RETURN 0; 
	END IF;
		
	
	_first_mvt := NULL;
	_exhausted := false;
	
	_i := _nbcommit;	
	FOR _next_i IN 1 .. _nbcommit LOOP
		_oid	:= _commits[_i][1];
		-- _commits[_next_i] follows _commits[_i]
		_w_src	:= _commits[_i][5];
		_w_dst	:= _commits[_next_i][5];
		_flowr	:= _commits[_i][8];
		
		UPDATE torder set qtt = qtt - _flowr ,updated = statement_timestamp()
			WHERE id = _oid AND _flowr <= qtt RETURNING uuid,qtt INTO _uuid,_qtt;
		IF(NOT FOUND) THEN
			RAISE EXCEPTION 'the flow is not in sync with the databasetorder[%].qtt does not exist or < %',_oid,_flowr 
				USING ERRCODE='YU001';
		END IF;
	
				
		INSERT INTO tmvt (orid,oruuid,grp,own_src,own_dst,qtt,nat,created) 
			VALUES(_oid,_uuid,_first_mvt,_w_src,_w_dst,_flowr,_commits[_i][7],statement_timestamp())
			RETURNING id INTO _mvt_id;
					
		IF(_first_mvt IS NULL) THEN
			_first_mvt := _mvt_id;
		END IF;
		
		IF(_qtt=0) THEN
			_i := fcheckorder(_oid);
		END IF;
		
		_i := _next_i;
		-----------------------------------------------------
		-- values used by this flow are substracted from _tmp
		SELECT count(*) INTO _cnt FROM _tmp WHERE id = _oid;
		IF(_cnt >1) THEN
			RAISE EXCEPTION 'the flow contains id while _tmp[id] does not exist %',_commits 
				USING ERRCODE='YA003';
		END IF;

		UPDATE _tmp SET qtt = qtt - _flowr WHERE id = _oid AND qtt >= _flowr RETURNING qtt INTO _qtt;
		IF (NOT FOUND) THEN
			RAISE EXCEPTION 'order[%] was not found or found with insuffisant value',_oid 
				USING ERRCODE='YA003'; 
		END IF;
		------------------------------------------------------
		IF(_qtt=0) THEN 
			_exhausted := true;
		END IF;

	END LOOP;

	UPDATE tmvt SET grp = _first_mvt WHERE id = _first_mvt  AND (grp IS NULL);	
	IF(NOT FOUND) THEN
		RAISE EXCEPTION 'the movement % does not exist',_first_mvt 
			USING ERRCODE='YA003';
	END IF;

	-- empty orders are moved to torderempty
	FOR _oid IN SELECT orid FROM tmvt WHERE grp = _first_mvt GROUP BY orid LOOP
		
	END LOOP;
	
	IF(NOT _exhausted) THEN
		--  some order should be exhausted 
		RAISE EXCEPTION 'the cycle should exhaust some order' 
			USING ERRCODE='YA003';
	END IF;
	
	IF _debugPhase>0 THEN
		RAISE NOTICE 'agreement % inserted with % mvts',_first_mvt,_nbcommit;
	END IF;
	
	RETURN 1;
END;
$$ LANGUAGE PLPGSQL;

/* if the order is not valid, it is moved into orderempty */ 
CREATE OR REPLACE FUNCTION fcheckorder(_oid int8) RETURNS int AS $$
DECLARE
	_o 		torder%rowtype;
	_MAX_REFUSED 	int := fgetconst('MAX_REFUSED');
	_first_mvt	int8 := NULL;
BEGIN
	SELECT 		o.* INTO 	_o 
		FROM torder o WHERE
		 	o.id=_oid AND (o.qtt=0 OR NOT flow_maxdimrefused(o.refused,_MAX_REFUSED));
	IF FOUND THEN
		-- RAISE WARNING 'order to del: %',_o;
		-- uuid,owner,qua_requ,qtt_requ,qua_prov,qtt_prov,qtt,created,updated

		INSERT INTO torderempty (uuid,qtt,nr,np,qtt_prov,qtt_requ,own,refused,created,updated) 
		VALUES (_o.uuid,_o.qtt,_o.nr,_o.np,_o.qtt_prov,_o.qtt_requ,_o.own,_o.refused,_o.created,_o.updated);
		IF(_o.qtt != 0) THEN
			INSERT INTO tmvt (orid,oruuid,own_src,own_dst,qtt,nat,created) -- grp undefined
				VALUES(_o.id,_o.uuid,_o.own,_o.own,_q.qtt,_o.np,statement_timestamp())
				RETURNING id INTO _first_mvt;
			UPDATE tmvt SET grp = _first_mvt WHERE _id = first_mvt;
		END IF;
		DELETE FROM torder WHERE id=_oid;

		RETURN 1;
	END IF;
	RETURN 0;
END;
$$ LANGUAGE PLPGSQL;

