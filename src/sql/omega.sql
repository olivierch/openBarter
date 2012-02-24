set schema 't';

--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION 
	fget_quality(_quality_name text) 
	RETURNS int8 AS $$
DECLARE 
	_id int8;
BEGIN
	SELECT id INTO _id FROM tquality WHERE name = _quality_name;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'The qulity "%" is undefined',_quality_name USING ERRCODE='YU001';
	END IF;
	RETURN _id;
END;
$$ LANGUAGE PLPGSQL;
	
--------------------------------------------------------------------------------
-- fgetomega
--------------------------------------------------------------------------------
-- PUBLIC
/* usage: 
	nb_draft int = fgetomega(_qualityprovided text,_qualityrequired text)
		
	action:
		read omegas.
		if _qualityprovided or _qualityrequired do not exist, the function exists
	
	returns list of
		_qtt_prov,_qtt_requ

*/
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION 
	fgetomega(_qualityprovided text,_qualityrequired text) 
	RETURNS TABLE(_qtt_prov int8,_qtt_requ int8 ) AS $$
	
DECLARE
	_np	int8;
	_nr	int8;
	_pivot torder%rowtype;
	_time_begin timestamp;
	_uid	int8;
BEGIN
	_uid := fconnect(true);
	_time_begin := clock_timestamp();
	
	-- qualities are red
	_np := fget_quality(_qualityprovided); 
	_nr := fget_quality(_qualityrequired);
	
	_pivot.own := 0;
	_pivot.id  := 0;
	_pivot.qtt := 1;
	_pivot.np  := _np;
	_pivot.nr  := _nr;
	_pivot.qtt_prov := 1;
	_pivot.qtt_requ := 1;
	
	FOR _qtt_prov,_qtt_requ IN SELECT * FROM fgetomega_int(_np,_nr,-1) LOOP
		RETURN NEXT;
	END LOOP;
	
	perform fspendquota(_time_begin);
	
	RETURN;
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE INFO 'ABORTED';
	RETURN;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fgetomega(text,text) TO market;

CREATE OR REPLACE FUNCTION fgetomega_int(_np int8,_nr int8,_debugPhase int) RETURNS TABLE(_qtt_prov int8,_qtt_requ int8) AS $$
DECLARE 
	_obCMAXCYCLE 	int := fgetconst('obCMAXCYCLE');
	_maxDepth 	int;
	_cnt 		int;
	_flow 		flow;
	_i 		int;
	_MAX_REFUSED 	int := fgetconst('MAX_REFUSED');
	_flowrs 	int8[];
	_nbcommit	int;
BEGIN
	
	DROP TABLE IF EXISTS _tmp;
	CREATE TEMP TABLE _tmp ON COMMIT DROP AS (
		WITH RECURSIVE search_backward(id,nr,qtt_prov,qtt_requ,refused,
						own,qtt,np,
						-- pat,loop,
						depthb) AS (
			SELECT b.id, b.nr,b.qtt_prov,b.qtt_requ,b.refused,
				b.own,b.qtt,b.np,
				-- ARRAY[_idPivot],false,
				-- 1
				2
				FROM torder b
				WHERE 	-- b.id = _idPivot 
					b.np = _nr
					AND b.qtt > 0 AND flow_maxdimrefused(b.refused,_MAX_REFUSED)			
			UNION 
			SELECT X.id, X.nr,X.qtt_prov,X.qtt_requ,X.refused,
				X.own,X.qtt,X.np,
				-- X.id || Y.pat,X.id=ANY(Y.pat),
				Y.depthb + 1 -- depthb in [2,_obCMAXCYCLE] 
				FROM torder X, search_backward Y
				WHERE	-- X.id != _idPivot
					X.nr != _nr	
					AND X.qtt > 0 AND flow_maxdimrefused(X.refused,_MAX_REFUSED)
					AND X.np = Y.nr AND NOT (Y.id = ANY(X.refused)) -- X->Y
					 -- Y.refused with too many elements
					AND Y.depthb < _obCMAXCYCLE 
					
		)
		SELECT id,max(nr) as nr,max(qtt_prov)as qtt_prov,max(qtt_requ) as qtt_requ,max(own) as own,max(qtt) as qtt,max(np) as np,
			NULL::flow as flow,0 as cntgraph,max(depthb) as depthb,0 as depthf,max(refused) as refused, --bool_or(loop) as loop,
			ARRAY[]::int8[] as Zrefused
		FROM search_backward group by id
	);
	-- depthb in [2,_obCMAXCYCLE]
	IF ( _debugPhase = 0 ) THEN
		RETURN;
	END IF;
	
	-- stops when graph empty
	SELECT count(*) INTO _cnt FROM _tmp;
	IF(_cnt = 0) THEN -- <= 1) THEN
		RETURN;
	END IF; 

	INSERT INTO _tmp (id,nr,qtt_prov,qtt_requ,own,qtt,np,flow,cntgraph,depthb,depthf,refused,Zrefused) VALUES
		(0,_nr,1,1,0,1,_np,NULL::flow,0,1,0,array[]::int8[],array[]::int8[]); 

	LOOP -- repeate as long as a draft is found
		
		UPDATE _tmp SET depthf =0,Zrefused= ARRAY[]::int8[]; -- TODO le mettre à la fin de la LOOP
		
		-- RAISE NOTICE '_maxDepth=% _np=% _idPivot=%',_maxDepth,_np,_idpivot;
		WITH RECURSIVE search_forward(id,nr,np,qtt,refused,depthx) AS (
			SELECT src.id,src.nr,src.np,src.qtt,src.refused,1
				FROM _tmp src 
				WHERE 	--src.id = _idPivot 
					src.id = 0
					-- AND src.qtt > 0 AND flow_maxdimrefused(src.refused,_MAX_REFUSED)
			UNION
			SELECT Y.id,Y.nr,Y.np,Y.qtt,Y.refused,X.depthx + 1
				FROM search_forward X, _tmp Y
				WHERE   --Y.id != _idPivot 
					Y.id != 0
					AND Y.qtt > 0 AND flow_maxdimrefused(Y.refused,_MAX_REFUSED)
					AND X.depthx < _obCMAXCYCLE
					AND X.np = Y.nr AND NOT(Y.id=ANY(X.refused)) -- X->Y
					
		) 
		UPDATE _tmp t 
			SET flow = CASE WHEN sf.depthx = 2 --2  -- source
				THEN flow_init(t.id,t.nr,t.qtt_prov,t.qtt_requ,t.own,t.qtt,t.np) 
				ELSE '[]'::flow END,
			depthf = sf.depthx,
			Zrefused = t.refused
		FROM (SELECT min(depthx) as depthx,id FROM search_forward group by id ) sf WHERE t.id = sf.id ;
		
		IF ( _debugPhase = 1 ) THEN
			RETURN;
		END IF;
		
		-- delete node not seen
		DELETE FROM _tmp WHERE depthf = 0;
		
		SELECT count(*) INTO _cnt FROM _tmp; 
		 		
		if(_cnt = 0) THEN -- then graph _cntgraph is empty or pivot not seen
			RETURN;
		END IF;	
		RAISE INFO 'taille de _tmp %',_cnt;			
/*
		when pivot is reached, the path is a loop (refused or draft) and omegas are adjusted such as their product becomes 1.
*/	
		FOR _cnt IN 2 .. _obCMAXCYCLE LOOP
			UPDATE _tmp Y 
			SET 
			flow = flow_catt(X.flow,Y.id,Y.nr,Y.qtt_prov,Y.qtt_requ,Y.own,Y.qtt,Y.np,Y.refused)
			FROM _tmp X WHERE X.id != 0 -- _idPivot -- arcs pivot->sources are not considered
				AND Y.qtt > 0 AND flow_maxdimrefused(Y.refused,_MAX_REFUSED)
				AND flow_omegaz(X.flow,Y.flow,Y.id,Y.nr,Y.qtt_prov,Y.qtt_requ,Y.own,Y.qtt,Y.np,X.refused,Y.refused);
		END LOOP;
				
		-- flow of pivot
		SELECT flow INTO _flow FROM _tmp WHERE id = 0; 
		IF(NOT FOUND) THEN
			RAISE EXCEPTION 'The _tmp[_idPivot=0] should be found' USING ERRCODE='YA003';
		END IF;
		IF ( _debugPhase = 2 ) THEN
			RETURN;
		END IF;
		
		IF(NOT flow_isloop(_flow)) THEN
			RETURN;
		END IF;
		
		-- IF( flow_refused(_flow) < 0 ) THEN 
		SELECT * INTO _qtt_prov,_qtt_requ FROM fdecrease_tmp(_flow,_debugPhase);
		RETURN NEXT;
		
		IF (_debugPhase > 2) THEN
			-- RAISE NOTICE 'stop on phase=% ',_debugPhase;
			RETURN;
		END IF;
			
	END LOOP;
END; 
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
-- fexecute_flow
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fdecrease_tmp(_flw flow,_debugPhase int,OUT _qtt_prov int8, OUT _qtt_requ int8) AS $$
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
	
	RAISE INFO 'The flow %',_flw;
	
	_first_mvt := NULL;
	_exhausted := false;
	
	_i := _nbcommit;	
	FOR _next_i IN 1 .. _nbcommit LOOP
		_oid	:= _commits[_i][1];
		-- _commits[_next_i] follows _commits[_i]
		_w_src	:= _commits[_i][5];
		_w_dst	:= _commits[_next_i][5];
		_flowr	:= _commits[_i][8];
		
		IF(_next_i = _nbcommit) THEN
			_qtt_prov := _commits[_next_i][8];
			_qtt_requ := _flowr;
		END IF;
/*		
		UPDATE torder set qtt = qtt - _flowr ,updated = statement_timestamp()
			WHERE id = _oid AND _flowr <= qtt RETURNING uuid INTO _uuid;
		IF(NOT FOUND) THEN
			RAISE EXCEPTION 'the flow is not in sync with the databasetorder[%].qtt does not exist or < %',_oid,_flowr 
				USING ERRCODE='YU001';
		END IF;	
				
		INSERT INTO tmvt (uuid,grp,own_src,own_dst,qtt,nat,created) 
			VALUES(_uuid,_first_mvt,_w_src,_w_dst,_flowr,_commits[_i][7],statement_timestamp())
			RETURNING id INTO _mvt_id;
*/					
		IF(_first_mvt IS NULL) THEN
			_first_mvt := _mvt_id;
		END IF;
		
		_i := _next_i;
		-----------------------------------------------------
		-- values used by this flow are substracted from _tmp
		SELECT count(*) INTO _cnt FROM _tmp WHERE id = _oid;
		IF(_cnt >1) THEN
			RAISE EXCEPTION 'error with %',_commits 
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
/*
	UPDATE tmvt SET grp = _first_mvt WHERE id = _first_mvt  AND (grp IS NULL);	
	IF(NOT FOUND) THEN
		RAISE EXCEPTION 'the movement % does not exist',_first_mvt 
			USING ERRCODE='YA003';
	END IF;
*/	
	IF(NOT _exhausted) THEN
		--  some order should be exhausted 
		RAISE EXCEPTION 'the cycle should exhaust some order' 
			USING ERRCODE='YA003';
	END IF;
	
	IF _debugPhase>0 THEN
		RAISE NOTICE 'agreement % inserted with % mvts',_first_mvt,_nbcommit;
	END IF;
	
	RETURN;
END;
$$ LANGUAGE PLPGSQL;


