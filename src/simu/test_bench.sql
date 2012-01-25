--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- Name: t; Type: SCHEMA; Schema: -; Owner: olivier
--

CREATE SCHEMA t;


ALTER SCHEMA t OWNER TO olivier;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: flow; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS flow WITH SCHEMA t;


--
-- Name: EXTENSION flow; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION flow IS 'data type for cycle of bids';


SET search_path = t, pg_catalog;

--
-- Name: dquantity; Type: DOMAIN; Schema: t; Owner: olivier
--

CREATE DOMAIN dquantity AS bigint
	CONSTRAINT dquantity_check CHECK ((VALUE > 0));


ALTER DOMAIN t.dquantity OWNER TO olivier;

--
-- Name: fackmvt(bigint); Type: FUNCTION; Schema: t; Owner: olivier
--

CREATE FUNCTION fackmvt(_mid bigint) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
	_mvt 	tmvt%rowtype;
	_q	tquality%rowtype;
	_uid	int8;
	_cnt 	int;
BEGIN
	_uid := fconnect(false);
	DELETE FROM tmvt USING tquality 
		WHERE tmvt.id=_mid AND tmvt.nat=tquality.id AND tquality.did=_uid 
		RETURNING * INTO _mvt;
		
	IF(FOUND) THEN
		UPDATE tquality SET qtt = qtt - _mvt.qtt WHERE id=_mvt.nat
			RETURNING * INTO _q;
		IF(NOT FOUND) THEN
			RAISE WARNING 'quality[%] of the movement not found',_mvt.nat;
			RAISE EXCEPTION USING ERRCODE='YA003';
		ELSE
			IF (_q.qtt<0 ) THEN 
				RAISE WARNING 'Quality % underflows',_quality_name;
				RAISE EXCEPTION USING ERRCODE='YA001';
			END IF;
		END IF;
		-- TODO supprimer les ordres associés s'ils sont vides et qu'ils ne sont pas associés à d'autres mvts
		SELECT count(*) INTO _cnt FROM tmvt WHERE orid=_mvt.orid;
		IF(_cnt=0) THEN
			DELETE FROM torder o USING tmvt m 
				WHERE o.id=_mvt.orid;
		END IF;
		
		IF(fgetconst('VERIFY') = 1) THEN
			perform fverify();
		END IF;
		
		RAISE INFO 'movement removed';
		RETURN true;
	ELSE
		RAISE NOTICE 'the quality of the movement is not yours';
		RAISE EXCEPTION USING ERRCODE='YU001';
		RETURN false;
	END IF;
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE NOTICE 'ABORTED';
	RETURN 0;
END;		
$$;


ALTER FUNCTION t.fackmvt(_mid bigint) OWNER TO olivier;

--
-- Name: fadmin(); Type: FUNCTION; Schema: t; Owner: olivier
--

CREATE FUNCTION fadmin() RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
	_b	bool;
	_phase	int;
	_market tmarket%rowtype;
BEGIN
	SELECT * INTO _market FROM tmarket ORDER BY ID DESC LIMIT 1;
	IF(_market.ph1 is NULL) THEN
		_phase := 1;
	ELSE 
		IF(_market.ph2 is NULL) THEN
			_phase := 2;
		ELSE
			_phase := 0;
		END IF;
	END IF;

	IF (_phase = 0) THEN -- was closed, opening
		GRANT market TO client;
		INSERT INTO tmarket (ph0) VALUES (statement_timestamp());
		RAISE NOTICE '[1] The market is now OPENED';
		RETURN true;
	END IF;
	IF (_phase = 1) THEN -- was opened, ending
		REVOKE market FROM client;
		UPDATE tmarket SET ph1=statement_timestamp() WHERE ph1 IS NULL;		
		RAISE NOTICE '[2] The market is now CLOSING';
		RETURN true;
	END IF;
	IF (_phase = 2) THEN -- was ended, closing
		-- REVOKE market FROM client;
		UPDATE tmarket SET ph2=statement_timestamp() WHERE ph2 IS NULL;
		RAISE NOTICE 'The closing starts ...';
		_b := fclose_market();
		RAISE NOTICE '[0] The market is now CLOSED';
		RETURN _b;
	END IF;
END;
$$;


ALTER FUNCTION t.fadmin() OWNER TO olivier;

--
-- Name: fclose_market(); Type: FUNCTION; Schema: t; Owner: olivier
--

CREATE FUNCTION fclose_market() RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
	_backup int;
	_suf text;
	_sql text;
	_cnt int;
	_nbb 	int;
	_pivot torder%rowtype;
	_cnn	int8;
BEGIN
	
	_nbb := fgetconst('NB_BACKUP');
	-- rotation of backups
	SELECT max(id) INTO _cnt FROM tmarket;
	UPDATE tmarket SET backup= ((_cnt-2) % _nbb) +1 WHERE id=_cnt RETURNING backup INTO _backup;
	_suf := CAST(_backup AS text);
	
	EXECUTE 'DROP TABLE IF EXISTS torder_back_' || _suf;
	EXECUTE 'DROP TABLE IF EXISTS tmvt_back_' || _suf;
	EXECUTE 'CREATE TABLE torder_back_' || _suf || ' AS SELECT * FROM torder';
	EXECUTE 'CREATE TABLE tmvt_back_' || _suf || ' AS SELECT * FROM tmvt';
	
	RAISE NOTICE 'TMVT and TORDER saved into backups *_BACK_% among %',_backup,_nbb;
	
	TRUNCATE tmvt,trefused,torder;
	UPDATE tquality set qtt=0 ;
	
	-- reinsertion of orders
/*
	_sql := 'FOR _pivot IN SELECT * FROM torder_back_' || _suf || ' WHERE qtt != 0 ORDER BY created ASC LOOP 
			_cnt := finsert_order_int(_pivot,true);
		END LOOP';
	EXECUTE _sql;
*/
	-- RETURN false;
 
	EXECUTE 'SELECT finsert_order_int(row(id,qtt,nr,np,qtt_prov,qtt_requ,own,created,updated)::torder ,true) 
	FROM torder_back_' || _suf || ' 
	 WHERE qtt != 0 ORDER BY created ASC';
	
	-- diagnostic
	perform fverify();	
	SELECT count(*) INTO _cnn FROM tmvt;
	UPDATE tmarket SET diag=_cnn WHERE id=_cnt;
	IF(_cnn != 0) THEN
		RAISE NOTICE 'Abnormal termination of market closing';
		RAISE NOTICE '0 != % movement where found when orders where re-inserted',_cnn;
		
		RETURN false;
	ELSE
		RAISE NOTICE 'Normal termination of closing.';
		RETURN true;
	END IF;
	
END;
$$;


ALTER FUNCTION t.fclose_market() OWNER TO olivier;

--
-- Name: fconnect(boolean); Type: FUNCTION; Schema: t; Owner: olivier
--

CREATE FUNCTION fconnect(verifyquota boolean) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
	_user tuser%rowtype;
BEGIN
	UPDATE tuser SET last_in=clock_timestamp() WHERE name=current_user RETURNING * INTO _user;
	IF NOT FOUND THEN
		RAISE NOTICE 'user "%" does not exist',current_user;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	IF (verifyquota AND NOT(_user.quota = 0 OR _user.spent<=_user.quota)) THEN
		RAISE NOTICE 'quota reached for user "%" ',current_user;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;

	RETURN _user.id;
END;		
$$;


ALTER FUNCTION t.fconnect(verifyquota boolean) OWNER TO olivier;

--
-- Name: fcreate_tmp(bigint); Type: FUNCTION; Schema: t; Owner: olivier
--

CREATE FUNCTION fcreate_tmp(_nr bigint) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE 
	_obCMAXCYCLE int := fgetconst('obCMAXCYCLE');
	_maxDepth int;
BEGIN
	-- select relname,oid from pg_class where pg_table_is_visible(oid) and relname='_tmp';
	DROP TABLE IF EXISTS _tmp;
	CREATE TEMP TABLE _tmp ON COMMIT DROP AS (
		WITH RECURSIVE search_backward(id,nr,qtt_prov,qtt_requ,
						own,qtt,np,
						depth) AS (
			SELECT b.id, b.nr,b.qtt_prov,b.qtt_requ,
				b.own,b.qtt,b.np,
				2
				FROM torder b
				WHERE 	b.np = _nr -- v->pivot
					AND b.qtt > 0 
					AND (b.own IS NOT NULL) -- excludes the pivot
			UNION 
			SELECT Xb.id, Xb.nr,Xb.qtt_prov,Xb.qtt_requ,
				Xb.own,Xb.qtt,Xb.np,
				Y.depth + 1
				FROM torder Xb, search_backward Y
				WHERE 	Xb.np = Y.nr -- X->Y
					AND Xb.qtt > 0 
					AND (Xb.own IS NOT NULL) -- excludes the pivot
					AND Y.depth < _obCMAXCYCLE
					AND NOT EXISTS (
						SELECT * FROM trefused WHERE Xb.id=x and Y.id=y)
		)
		SELECT id,nr,qtt_prov,qtt_requ,own,qtt,np,NULL::flow as flow,0 as valid,depth 
		FROM search_backward
	);
	SELECT max(depth) INTO _maxDepth FROM _tmp;
	RETURN _maxDepth;
END;
$$;


ALTER FUNCTION t.fcreate_tmp(_nr bigint) OWNER TO olivier;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: torder; Type: TABLE; Schema: t; Owner: olivier; Tablespace: 
--

CREATE TABLE torder (
    id bigint NOT NULL,
    qtt bigint NOT NULL,
    nr bigint NOT NULL,
    np bigint NOT NULL,
    qtt_prov dquantity NOT NULL,
    qtt_requ dquantity NOT NULL,
    own bigint,
    created timestamp without time zone NOT NULL,
    updated timestamp without time zone,
    CONSTRAINT torder_qtt_check CHECK ((qtt >= 0))
);


ALTER TABLE t.torder OWNER TO olivier;

--
-- Name: TABLE torder; Type: COMMENT; Schema: t; Owner: olivier
--

COMMENT ON TABLE torder IS 'description of orders';


--
-- Name: COLUMN torder.qtt; Type: COMMENT; Schema: t; Owner: olivier
--

COMMENT ON COLUMN torder.qtt IS 'current quantity remaining';


--
-- Name: COLUMN torder.nr; Type: COMMENT; Schema: t; Owner: olivier
--

COMMENT ON COLUMN torder.nr IS 'quality required';


--
-- Name: COLUMN torder.np; Type: COMMENT; Schema: t; Owner: olivier
--

COMMENT ON COLUMN torder.np IS 'quality provided';


--
-- Name: COLUMN torder.qtt_prov; Type: COMMENT; Schema: t; Owner: olivier
--

COMMENT ON COLUMN torder.qtt_prov IS 'quantity offered';


--
-- Name: COLUMN torder.qtt_requ; Type: COMMENT; Schema: t; Owner: olivier
--

COMMENT ON COLUMN torder.qtt_requ IS 'used to express omega=qtt_prov/qtt_req';


--
-- Name: COLUMN torder.own; Type: COMMENT; Schema: t; Owner: olivier
--

COMMENT ON COLUMN torder.own IS 'owner of the value provided';


--
-- Name: fdroporder(bigint); Type: FUNCTION; Schema: t; Owner: olivier
--

CREATE FUNCTION fdroporder(_oid bigint) RETURNS torder
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
	_o torder%rowtype;
	_qp tquality%rowtype;
BEGIN
	DELETE FROM torder o USING tquality q 
	WHERE o.id=_oid AND o.np=q.id AND q.depository=current_user 
	RETURNING o.* INTO _o;
	IF(FOUND) THEN
		-- delete by cascade trefused
		
		UPDATE tquality SET qtt = qtt - _o.qtt 
			WHERE id = _o.np RETURNING * INTO _qp;
		IF(NOT FOUND) THEN
			RAISE WARNING 'The quality of the order % is not present',_oid;
			RAISE EXCEPTION USING ERRCODE='YA003';
		END IF;
		IF (_qp.qtt<0 ) THEN 
			RAISE WARNING 'Quality % underflows',_quality_name;
			RAISE EXCEPTION USING ERRCODE='YA001';
		END IF;
		
		IF(fgetconst('VERIFY') = 1) THEN
			perform fverify();
		END IF;
		RAISE INFO 'order % dropped',_oid;
		RETURN _o;
	ELSE
		RAISE NOTICE 'this order % is not yours or does not exist',_oid;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE NOTICE 'ABORTED';
	RETURN NULL;
END;
$$;


ALTER FUNCTION t.fdroporder(_oid bigint) OWNER TO olivier;

--
-- Name: fexplodequality(text); Type: FUNCTION; Schema: t; Owner: olivier
--

CREATE FUNCTION fexplodequality(_quality_name text) RETURNS text[]
    LANGUAGE plpgsql
    AS $$
DECLARE
	_e int;
	_q text[];
BEGIN
	_e =position('/' in _quality_name);
	IF(_e < 2) THEN 
		RAISE NOTICE 'Quality name "%" incorrect',_quality_name;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	_q[1] = substring(_quality_name for _e-1);
	_q[2] = substring(_quality_name from _e+1);
	if(char_length(_q[2])<1) THEN
		RAISE NOTICE 'Quality name "%" incorrect',_quality_name;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	RETURN _q;
END;
$$;


ALTER FUNCTION t.fexplodequality(_quality_name text) OWNER TO olivier;

--
-- Name: fget_drafts(torder); Type: FUNCTION; Schema: t; Owner: olivier
--

CREATE FUNCTION fget_drafts(_pivot torder) RETURNS SETOF flow
    LANGUAGE plpgsql
    AS $$
DECLARE 
	_maxDepth int;
BEGIN
	_maxDepth := fcreate_tmp(_pivot.nr);
	
	IF (_maxDepth is NULL or _maxDepth = 0) THEN
		RETURN;
	END IF;
	-- insert the pivot
	INSERT INTO _tmp (id, nr, qtt_prov, qtt_requ,own, qtt, np, flow,valid,depth) VALUES
			 (0 ,
			 _pivot.nr,
			 _pivot.qtt_prov,
			 _pivot.qtt_requ,
			 _pivot.own,
			 _pivot.qtt,
			 _pivot.np,
			 NULL::flow,    0,    1);
	-- own!=0 indicates that the flow should consider the quantity of the pivot
	
	RETURN QUERY SELECT fget_flows FROM fget_flows(_pivot.np,_maxDepth);
/*	FOR _flow IN SELECT fget_flows FROM fget_flows(_pivot.np,_maxDepth) LOOP
		RETURN NEXT;
	END LOOP;*/
	RETURN;
END; 
$$;


ALTER FUNCTION t.fget_drafts(_pivot torder) OWNER TO olivier;

--
-- Name: fget_flows(bigint, integer); Type: FUNCTION; Schema: t; Owner: olivier
--

CREATE FUNCTION fget_flows(_np bigint, _maxdepth integer) RETURNS SETOF flow
    LANGUAGE plpgsql
    AS $$
DECLARE 
	_cnt int;
	_cntgraph int :=0; 
	_flow flow;
	_idPivot int8 := 0;
BEGIN
	-- CREATE INDEX _tmp_idx ON _tmp(valid,nr);
	LOOP -- repeate as long as a draft is found
		_cntgraph := _cntgraph+1;
/*******************************************************************************
the graph is traversed forward to be reduced
*******************************************************************************/
		-- RAISE NOTICE '_maxDepth=% _np=% _idPivot=% _cntgraph=%',_maxDepth,_np,_idpivot,_cntgraph;
		WITH RECURSIVE search_forward(id,nr,np,qtt,depth) AS (
			SELECT src.id,src.nr,src.np,src.qtt,1
				FROM _tmp src
				WHERE src.id = _idPivot AND src.valid = _cntgraph-1 -- sources
					AND src.qtt != 0 
					
			UNION
			SELECT Y.id,Y.nr,Y.np,Y.qtt,X.depth + 1
				FROM search_forward X, _tmp Y
				WHERE X.np = Y.nr AND Y.valid = _cntgraph-1 -- X->Y, use of index
					AND Y.qtt != 0 
					AND Y.id != _idPivot  -- includes pivot
					AND X.depth < _maxDepth
		) 
	
		UPDATE _tmp t 
		SET flow = CASE WHEN _np = t.nr -- source
				THEN flow_init(t.id,t.nr,t.qtt_prov,t.qtt_requ,t.own,t.qtt,t.np) 
				ELSE NULL::flow END,
			valid = _cntgraph
		FROM search_forward sf WHERE t.id = sf.id;
		
		-- nodes that cannot be reached are deleted
		DELETE FROM _tmp WHERE valid != _cntgraph;
		
/*******************************************************************************
bellman_ford

At the beginning, all sources S are such as S.flow=[S,]
for t in [1,_obCMAXCYCLE]:
	for all arcs[X,Y] of the graph:
		if X.flow empty continue
		flow = X.flow followed by Y
		if flow better than X.flow, then Y.flow <- flow
		
		
When it is not empty, a node T contains a path [S,..,T] where S is a source 
At the end, Each node.flow not empty is the best flow from a source S to this node
with at most t traits. 
The pivot contains the best flow from a source to pivot [S,..,pivot] at most _obCMAXCYCLE long

the algorithm is usually repeated for all node, but here only
_obCMAXCYCLE times. 

*******************************************************************************/	
/* il reste à prendre en compte _lastIgnore représenté pas sid==0*/

		FOR _cnt IN 2 .. _maxDepth LOOP
			UPDATE _tmp Y 
			SET flow = flow_cat(X.flow,Y.id,Y.nr,Y.qtt_prov,Y.qtt_requ,Y.own,Y.qtt,Y.np) 
			-- Y.flow = flow_cat(Y.flow,X.flow,Y.id,Y.nr,Y.qtt_prov,Y.qtt_requ,Y.own,Y.qtt,Y.np)
			-- Z<-X.flow+Y.bid
			FROM _tmp X WHERE 
				X.np  = Y.nr  
				AND X.id != _idPivot -- arcs pivot->sources are not considered
				AND  X.flow IS NOT NULL 
				AND ( Y.flow IS NULL 
					OR flow_omegay(Y.flow,X.flow,Y.qtt_prov,Y.qtt_requ)
				);
				-- flow_omegay(Y.flow,X.flow,Y.qtt_prov,Y.qtt_requ)
				--      omega(Y.flow) < omega(X.flow)*Y.qtt_prov/Y.qtt_requ

		END LOOP;

		-- flow of pivot
		SELECT flow INTO _flow FROM _tmp WHERE id = _idPivot; 
		
		EXIT WHEN _flow IS NULL OR flow_dim(_flow) = 0;
		
		RETURN NEXT _flow; -- new row returned
		
		-- values used by this flow are substracted from _tmp
		DECLARE
			_id	int8;
			_dim	int;
			_flowrs	int8[];
			_ids	int8[];
			_owns	int8[];
			_qtt	int8;
			_lastIgnore bool := false;
		BEGIN
			_flowrs := flow_proj(_flow,8);
			_ids	:= flow_proj(_flow,1);
			_owns	:= flow_proj(_flow,5); 
			_dim    := flow_dim(_flow); 
			
			FOR _cnt IN 1 .. _dim LOOP
				_id   := _ids[_cnt]; 
				-- RAISE NOTICE 'flowrs[%]=% ',_cnt,_flowr;
				IF (_id = 0 AND _owns[_cnt] = 0) THEN
					_lastIgnore := true; -- it's a price read, the pivot is not decreased
				ELSE 
					UPDATE _tmp SET qtt = qtt - _flowrs[_cnt] WHERE id = _id and qtt >= _flowrs[_cnt];
					IF (NOT FOUND) THEN
						RAISE WARNING 'order[%] was not found or found with negative value',_id;
						RAISE EXCEPTION USING ERRCODE='YA003'; 
					END IF;
				END IF;
			END LOOP;
			
			IF(fgetconst('EXHAUST') = 1) THEN
				SELECT count(*) INTO _cnt FROM _tmp WHERE 
					id = ANY (_ids) 
					AND qtt=0 
					AND (NOT _lastIgnore OR (_lastIgnore AND id!=0));
				IF(_cnt <1) THEN
					-- when _lastIgnore, some order other than the pivot should be exhausted
					-- otherwise, some order including the pivot should be exhausted 
					RAISE WARNING 'the cycle should exhaust some order';
					RAISE EXCEPTION USING ERRCODE='YA003';
				END IF;
			END IF;
		END;
		
	END LOOP;

END; 
$$;


ALTER FUNCTION t.fget_flows(_np bigint, _maxdepth integer) OWNER TO olivier;

--
-- Name: fget_omegas(text, text); Type: FUNCTION; Schema: t; Owner: olivier
--

CREATE FUNCTION fget_omegas(_qr text, _qp text) RETURNS TABLE(_num bigint, _qtt_r bigint, _qua_r text, _qtt_p bigint, _qua_p text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE 
	_sidPivot int8 := 0;
	_maxDepth int;
	_flow	flow;
	_commit	__flow_to_commits;
	_time_begin timestamp;
	_np	int8;
	_nr	int8;
BEGIN
	_time_begin := clock_timestamp();
	SELECT id INTO _nr FROM tquality WHERE name=_qr;
	IF(NOT FOUND) THEN RAISE NOTICE 'Quality % unknown',_qr; RAISE EXCEPTION USING ERRCODE='YU001';END IF;
	SELECT id INTO _np FROM tquality WHERE name=_qp;
	IF(NOT FOUND) THEN RAISE NOTICE 'Quality % unknown',_qp; RAISE EXCEPTION USING ERRCODE='YU001';END IF;
	
	_maxDepth := 
	fcreate_tmp(_nr);
	
	IF (_maxDepth is NULL or _maxDepth = 0) THEN
		RAISE INFO 'No results';
		RETURN;
	END IF;
	-- insert the pivot
	INSERT INTO _tmp (id, nr,qtt_prov,qtt_requ,own,qtt,np, flow,     valid,depth) VALUES
			 (0 ,_nr,1,       1,       0,  1,  _np,NULL::flow,0,1);
	_num := 0;
	FOR _flow IN SELECT fget_flows FROM fget_flows(_np,_maxDepth) LOOP
		FOR _qtt_r,_qua_r,_qtt_r,_qua_r IN SELECT c.qtt_r,qr.name,c.qtt_p,qp.name 
			FROM flow_to_commits(_flow) c
			INNER JOIN tquality qp ON (c.np=qp.id)
			INNER JOIN tquality qr ON (c.nr=qr.id) LOOP
			_num := _num+1;
			--_commit.num := _num;
			RETURN NEXT; -- _commit;
		END LOOP;	
	END LOOP;
	-- id == 0 is the pivot
	-- own==0 indicates that the flow should ignore the quantity of the pivot
	
	perform fspendquota(_time_begin);
	RETURN;
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE NOTICE 'ABORTED';
	RETURN;	 
END; 
$$;


ALTER FUNCTION t.fget_omegas(_qr text, _qp text) OWNER TO olivier;

--
-- Name: fgetconst(text); Type: FUNCTION; Schema: t; Owner: olivier
--

CREATE FUNCTION fgetconst(_name text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
	_ret text;
BEGIN
	SELECT value INTO _ret FROM tconst WHERE name=_name;
	IF(NOT FOUND) THEN
		RAISE 'the const % should be found',_name;
		RAISE EXCEPTION USING ERRCODE='YA003';
	END IF;
	RETURN _ret;
END; 
$$;


ALTER FUNCTION t.fgetconst(_name text) OWNER TO olivier;

--
-- Name: finsert_order_int(torder, boolean); Type: FUNCTION; Schema: t; Owner: olivier
--

CREATE FUNCTION finsert_order_int(_pivot torder, _restoretime boolean) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
	_commits	int8[][];
	_i	int;
	_next_i	int;
	_nbcommit	int;
	_first_mvt	int8; 
	_mvt_id	int8;
	_cnt	int := 0;
	_worst	int;
	_oid	int8;
	_oid1	int8;
	_oid2	int8;
	_flowr	int8;
	_flw	flow;
	_w_src	int8;
	_w_dst	int8;
	_created	timestamp;
	_updated	timestamp;

BEGIN
	------------------------------------------------------------------------
	
	IF(_restoretime) THEN
		_created := _pivot.created;
		_updated := _pivot.updated;
		UPDATE tquality SET qtt = qtt + _pivot.qtt WHERE id = _pivot.np;
	ELSE
		_created := statement_timestamp();
		_updated := NULL;
		_pivot.qtt := _pivot.qtt_prov;
	END IF;

	-- take a _pivot.id
	-- this record is ignored by fget_drafts due to the condition (own IS NOT NULL)	
	INSERT INTO torder (qtt,nr,np,qtt_prov,qtt_requ,own,created,updated) 
		VALUES (_pivot.qtt,_pivot.nr,_pivot.np,_pivot.qtt_prov,_pivot.qtt_requ,NULL,_created,_updated)
		RETURNING id INTO _pivot.id;
	
	-- graph traversal
	FOR _flw IN SELECT * FROM fget_drafts(_pivot) LOOP
		_commits := flow_to_matrix(_flw);
		
		-- RAISE NOTICE '_commits=%',_commits;
		_nbcommit := flow_dim(_flw); -- array_upper(_commits,1); 
		IF(_nbcommit < 2) THEN
			RAISE WARNING 'nbcommit % < 2',_nbcommit;
			RAISE EXCEPTION USING ERRCODE='YA003';
		END IF;
		
		_commits[_nbcommit][1] = _pivot.id;
		-- RAISE NOTICE '_commits=%',_commits;
		_worst := flow_refused(_flw);
		IF( _worst >= 0 ) THEN
			-- occurs when some omega > qtt_p/qtt_r 
			-- or when no solution was found
			
			-- _worst in [0,_nbcommit[
			_oid1 := _commits[((_worst-1+_nbcommit)%_nbcommit)+1][1];	
			-- -1%_nbcommit gives -1, but (-1+_nbcommit)%_nbcommit gives _nbcommit-1 		
			_oid2 := _commits[_worst+1][1];
			-- RAISE NOTICE '_worst=%, _oid1=%, _oid2=%',_worst,_oid1,_oid2;
			BEGIN
				IF(_restoretime) THEN
					INSERT INTO trefused (x,y,created) VALUES (_oid1,_oid2,_pivot.created); -- _pivot.id,_created);
				ELSE 
					INSERT INTO trefused (x,y,created) VALUES (_oid1,_oid2,statement_timestamp());
				END IF;
			EXCEPTION WHEN unique_violation THEN
				-- do noting
			END;
			-- INSERT INTO trefused (x,y,created) VALUES (_oid1,_oid2,_created); -- _pivot.id,_created);
		ELSE	-- the draft is accepted	
			_i := _nbcommit;
			_first_mvt := NULL;
			FOR _next_i IN 1 .. _nbcommit LOOP
				-- _commits[_next_i] follows _commits[_i]
				_oid	   := _commits[_i][1];
				
				_w_src :=_commits[_i][5];
				_w_dst :=_commits[_next_i][5];
				_flowr := _commits[_i][6];
				
				IF NOT ((fgetconst('INSERT_DUMMY_MVT') = 0) AND (_w_src = _w_dst)) THEN
/*				
				IF(_restoretime) THEN
					UPDATE torder set qtt = qtt - _flowr ,updated =_pivot.created
						WHERE id = _oid AND _flowr <= qtt ;
				ELSE 
					UPDATE torder set qtt = qtt - _flowr ,updated =statement_timestamp()
						WHERE id = _oid AND _flowr <= qtt ;
				END IF; */
					IF(_restoretime) THEN
						UPDATE torder set qtt = qtt - _flowr ,updated =_pivot.created
							WHERE id = _oid AND _flowr <= qtt ;
						IF(NOT FOUND) THEN
							RAISE NOTICE 'the flow is not in sync with the database';
							RAISE INFO 'torder[%].qtt does not exist or < %',_orid,_flowr;
							RAISE EXCEPTION USING ERRCODE='YU001';
						END IF;				

						INSERT INTO tmvt (orid,grp,own_src,own_dst,qtt,nat,created) 
							VALUES(_oid,_first_mvt,_w_src,_w_dst,_flowr,_commits[_i][7],_pivot.created)
							RETURNING id INTO _mvt_id;
							
					ELSE --same thing with statement_timestamp() instead of _pivot.created
						UPDATE torder set qtt = qtt - _flowr ,updated = statement_timestamp()
							WHERE id = _oid AND _flowr <= qtt ;
						IF(NOT FOUND) THEN
							RAISE NOTICE 'the flow is not in sync with the database';
							RAISE INFO 'torder[%].qtt does not exist or < %',_oid,_flowr;
							RAISE EXCEPTION USING ERRCODE='YU001';
						END IF;				

						INSERT INTO tmvt (orid,grp,own_src,own_dst,qtt,nat,created) 
							VALUES(_oid,_first_mvt,_w_src,_w_dst,_flowr,_commits[_i][7],statement_timestamp())
							RETURNING id INTO _mvt_id;
							
					END IF;	
					IF(_first_mvt IS NULL) THEN
						_first_mvt := _mvt_id;
					END IF;
				END IF;
				
				---------------------------------------------------------
				_i := _next_i;
			END LOOP;
		
			UPDATE tmvt SET grp = _first_mvt WHERE id = _first_mvt;	
	 		_cnt := _cnt +1;
 		END IF;
 	END LOOP;
 	
 	UPDATE torder SET own = _pivot.own WHERE id=_pivot.id;
 	RETURN _cnt;
END; 
$$;


ALTER FUNCTION t.finsert_order_int(_pivot torder, _restoretime boolean) OWNER TO olivier;

--
-- Name: finsertorder(text, text, bigint, bigint, text); Type: FUNCTION; Schema: t; Owner: olivier
--

CREATE FUNCTION finsertorder(_owner text, _qualityprovided text, _qttprovided bigint, _qttrequired bigint, _qualityrequired text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
	
DECLARE
	_cnt int;
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
	
	-- the owner should exist, is inserted if not
	_wid := fowner(_owner);
	
	_pivot.own := _wid;
	_pivot.id  := 0;
	_pivot.qtt := _qttprovided;
	_pivot.np  := _np;
	_pivot.nr  := _nr;
	_pivot.qtt_prov := _qttprovided;
	_pivot.qtt_requ := _qttrequired;
	
	_cnt := finsert_order_int(_pivot,false);
	
	perform fspendquota(_time_begin);
		
	IF(fgetconst('VERIFY') = 1) THEN
		perform fverify();
	END IF;
	
	RETURN _cnt;
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE NOTICE 'ABORTED';
	RETURN 0;
END; 
$$;


ALTER FUNCTION t.finsertorder(_owner text, _qualityprovided text, _qttprovided bigint, _qttrequired bigint, _qualityrequired text) OWNER TO olivier;

--
-- Name: fowner(text); Type: FUNCTION; Schema: t; Owner: olivier
--

CREATE FUNCTION fowner(_name text) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
	_wid int8;
BEGIN
	LOOP
		SELECT id INTO _wid FROM towner WHERE name=_name;
		IF found THEN
			return _wid;
		ELSE
			IF (fgetconst('INSERT_OWN_UNKNOWN')!=1) THEN
				RAISE NOTICE 'The owner % is unknown',_name;
				RAISE EXCEPTION USING ERRCODE='YU001';
			END IF;
		END IF;
		BEGIN
			INSERT INTO towner (name) VALUES (_name) RETURNING id INTO _wid;
			RAISE INFO 'owner % created',_name;
			return _wid;
		EXCEPTION WHEN unique_violation THEN
			--
		END;
	END LOOP;
END;
$$;


ALTER FUNCTION t.fowner(_name text) OWNER TO olivier;

--
-- Name: fspendquota(timestamp without time zone); Type: FUNCTION; Schema: t; Owner: olivier
--

CREATE FUNCTION fspendquota(_time_begin timestamp without time zone) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
	_millisec int8;
BEGIN
	_millisec := CAST(EXTRACT(milliseconds FROM (clock_timestamp() - _time_begin)) AS INT8);
	UPDATE tuser SET spent = spent+_millisec WHERE name=current_user;
	IF NOT FOUND THEN
		RAISE NOTICE 'user "%" does not exist',current_user;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	RETURN true;
END;		
$$;


ALTER FUNCTION t.fspendquota(_time_begin timestamp without time zone) OWNER TO olivier;

--
-- Name: ftime_updated(); Type: FUNCTION; Schema: t; Owner: olivier
--

CREATE FUNCTION ftime_updated() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
	IF (TG_OP = 'INSERT') THEN
		NEW.created := statement_timestamp();
	ELSE 
		NEW.updated := statement_timestamp();
	END IF;
	RETURN NEW;
END;
$$;


ALTER FUNCTION t.ftime_updated() OWNER TO olivier;

--
-- Name: FUNCTION ftime_updated(); Type: COMMENT; Schema: t; Owner: olivier
--

COMMENT ON FUNCTION ftime_updated() IS 'trigger updating fields created and updated';


--
-- Name: fupdate_quality(text, bigint); Type: FUNCTION; Schema: t; Owner: olivier
--

CREATE FUNCTION fupdate_quality(_quality_name text, _qtt bigint) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE 
	_qp tquality%rowtype;
	_q text[];
	_idd int8;
	_id int8;
	_qtta int8;
BEGIN
	LOOP
		-- RAISE NOTICE 'fupdate_quality(%,%)',_quality_name,_qtt;
		UPDATE tquality SET id=id,qtt = qtt + _qtt 
			WHERE name = _quality_name RETURNING id,qtt INTO _id,_qtta;

		IF FOUND THEN
			IF (((_qtt >0) AND (_qtta < _qtt)) OR (_qtta<0) ) THEN 
				RAISE WARNING 'Quality "%" owerflows',_quality_name;
				RAISE EXCEPTION USING ERRCODE='YA001';
			END IF;
		
			RETURN _id;
		END IF;
		
		BEGIN
			_q := fexplodequality(_quality_name);
		
			
			SELECT id INTO _idd FROM tuser WHERE name=_q[1];
			IF(NOT FOUND) THEN -- user should exists
				RAISE NOTICE 'The depository "%" is undefined',_q[1] ;
				RAISE EXCEPTION USING ERRCODE='YU001';
			END IF;
		
			INSERT INTO tquality (name,idd,depository,qtt) VALUES (_quality_name,_idd,_q[1],_qtt)
				RETURNING * INTO _qp;
			RETURN _qp.id;
			
		EXCEPTION WHEN unique_violation THEN
			--
		END;
	END LOOP;
END;
$$;


ALTER FUNCTION t.fupdate_quality(_quality_name text, _qtt bigint) OWNER TO olivier;

--
-- Name: fuser(text, bigint); Type: FUNCTION; Schema: t; Owner: olivier
--

CREATE FUNCTION fuser(_she text, _quota bigint) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
	LOOP
		UPDATE tuser SET quota = _quota WHERE name = _she;
		IF FOUND THEN
			RAISE INFO 'user "%" updated',_she;
			RETURN;
		END IF;
			
		BEGIN
			EXECUTE 'CREATE ROLE ' || _she || ' WITH LOGIN CONNECTION LIMIT 1 IN ROLE client';
			INSERT INTO tuser (name,quota,last_in) VALUES (_she,_quota,NULL);
			RAISE INFO 'tuser and role % are created',_she;
			RETURN;
			
		EXCEPTION 
			WHEN duplicate_object THEN
				RAISE NOTICE 'ERROR the role already "%" exists while the tuser does not.',_she;
				RAISE NOTICE 'You should add the tuser.name=% first.',_she;
				RAISE EXCEPTION USING ERRCODE='YU001';
				RETURN; 
			WHEN unique_violation THEN
				RAISE NOTICE 'ERROR the role "%" does nt exists while the tuser exists.',_she;
				RAISE NOTICE 'You should delete the tuser.name=% first.',_she;
				RAISE EXCEPTION USING ERRCODE='YU001';
				RETURN; 
		END;
	END LOOP;
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE NOTICE 'ABORTED';
END;
$$;


ALTER FUNCTION t.fuser(_she text, _quota bigint) OWNER TO olivier;

--
-- Name: fverify(); Type: FUNCTION; Schema: t; Owner: olivier
--

CREATE FUNCTION fverify() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	_name	text;
	_delta	int8;
	_nberrs	int := 0;
BEGIN
	FOR _name,_delta IN SELECT name,delta FROM vstat WHERE delta!=0 LOOP
		RAISE WARNING 'quality % is in error:delta=%',_name,_delta;
		_nberrs := _nberrs +1;
	END LOOP;
	IF(_nberrs != 0) THEN
		RAISE EXCEPTION USING ERRCODE='YA001'; 		
	END IF;
	RETURN;
/* 
TODO
1°) vérifier que le nom d'un client ne contient pas /
2°) lorsqu'un accord est refuse quand l'un des prix est trop fort,
mettre le refus sur la relation dont le prix est le plus élevé relativement au prix fixé

********************************************************************************
CH18 log_min_message,client_min_message defines which level are reported to client/log
by default 
log_min_message=
client_min_message=

BEGIN
	bloc
	RAISE EXCEPTION USING ERRCODE='YA001';
EXCEPTION WHEN SQLSTATE 'YA001' THEN
	RAISE NOTICE 'voila le PB';
END;
rollback the bloc and notice the problem to the client only
*/

END;
$$;


ALTER FUNCTION t.fverify() OWNER TO olivier;

--
-- Name: tconst; Type: TABLE; Schema: t; Owner: olivier; Tablespace: 
--

CREATE TABLE tconst (
    name text NOT NULL,
    value integer
);


ALTER TABLE t.tconst OWNER TO olivier;

--
-- Name: tmarket; Type: TABLE; Schema: t; Owner: olivier; Tablespace: 
--

CREATE TABLE tmarket (
    id integer NOT NULL,
    ph0 timestamp without time zone NOT NULL,
    ph1 timestamp without time zone,
    ph2 timestamp without time zone,
    backup integer,
    diag integer
);


ALTER TABLE t.tmarket OWNER TO olivier;

--
-- Name: tmarket_id_seq; Type: SEQUENCE; Schema: t; Owner: olivier
--

CREATE SEQUENCE tmarket_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE t.tmarket_id_seq OWNER TO olivier;

--
-- Name: tmarket_id_seq; Type: SEQUENCE OWNED BY; Schema: t; Owner: olivier
--

ALTER SEQUENCE tmarket_id_seq OWNED BY tmarket.id;


--
-- Name: tmarket_id_seq; Type: SEQUENCE SET; Schema: t; Owner: olivier
--

SELECT pg_catalog.setval('tmarket_id_seq', 2, true);


--
-- Name: tmvt; Type: TABLE; Schema: t; Owner: olivier; Tablespace: 
--

CREATE TABLE tmvt (
    id bigint NOT NULL,
    orid bigint,
    grp bigint,
    own_src bigint NOT NULL,
    own_dst bigint NOT NULL,
    qtt dquantity NOT NULL,
    nat bigint NOT NULL,
    created timestamp without time zone NOT NULL
);


ALTER TABLE t.tmvt OWNER TO olivier;

--
-- Name: TABLE tmvt; Type: COMMENT; Schema: t; Owner: olivier
--

COMMENT ON TABLE tmvt IS 'records a change of ownership';


--
-- Name: COLUMN tmvt.orid; Type: COMMENT; Schema: t; Owner: olivier
--

COMMENT ON COLUMN tmvt.orid IS 'order creating this movement';


--
-- Name: COLUMN tmvt.grp; Type: COMMENT; Schema: t; Owner: olivier
--

COMMENT ON COLUMN tmvt.grp IS 'refers to an exchange cycle that created this movement';


--
-- Name: COLUMN tmvt.own_src; Type: COMMENT; Schema: t; Owner: olivier
--

COMMENT ON COLUMN tmvt.own_src IS 'old owner';


--
-- Name: COLUMN tmvt.own_dst; Type: COMMENT; Schema: t; Owner: olivier
--

COMMENT ON COLUMN tmvt.own_dst IS 'new owner';


--
-- Name: COLUMN tmvt.qtt; Type: COMMENT; Schema: t; Owner: olivier
--

COMMENT ON COLUMN tmvt.qtt IS 'quantity of the value';


--
-- Name: COLUMN tmvt.nat; Type: COMMENT; Schema: t; Owner: olivier
--

COMMENT ON COLUMN tmvt.nat IS 'quality of the value';


--
-- Name: tmvt_id_seq; Type: SEQUENCE; Schema: t; Owner: olivier
--

CREATE SEQUENCE tmvt_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE t.tmvt_id_seq OWNER TO olivier;

--
-- Name: tmvt_id_seq; Type: SEQUENCE OWNED BY; Schema: t; Owner: olivier
--

ALTER SEQUENCE tmvt_id_seq OWNED BY tmvt.id;


--
-- Name: tmvt_id_seq; Type: SEQUENCE SET; Schema: t; Owner: olivier
--

SELECT pg_catalog.setval('tmvt_id_seq', 4323, true);


--
-- Name: torder_id_seq; Type: SEQUENCE; Schema: t; Owner: olivier
--

CREATE SEQUENCE torder_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE t.torder_id_seq OWNER TO olivier;

--
-- Name: torder_id_seq; Type: SEQUENCE OWNED BY; Schema: t; Owner: olivier
--

ALTER SEQUENCE torder_id_seq OWNED BY torder.id;


--
-- Name: torder_id_seq; Type: SEQUENCE SET; Schema: t; Owner: olivier
--

SELECT pg_catalog.setval('torder_id_seq', 3406, true);


--
-- Name: towner; Type: TABLE; Schema: t; Owner: olivier; Tablespace: 
--

CREATE TABLE towner (
    id bigint NOT NULL,
    name text NOT NULL,
    created timestamp without time zone,
    updated timestamp without time zone,
    CONSTRAINT towner_name_check CHECK ((char_length(name) > 0))
);


ALTER TABLE t.towner OWNER TO olivier;

--
-- Name: TABLE towner; Type: COMMENT; Schema: t; Owner: olivier
--

COMMENT ON TABLE towner IS 'description of owners of values';


--
-- Name: towner_id_seq; Type: SEQUENCE; Schema: t; Owner: olivier
--

CREATE SEQUENCE towner_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE t.towner_id_seq OWNER TO olivier;

--
-- Name: towner_id_seq; Type: SEQUENCE OWNED BY; Schema: t; Owner: olivier
--

ALTER SEQUENCE towner_id_seq OWNED BY towner.id;


--
-- Name: towner_id_seq; Type: SEQUENCE SET; Schema: t; Owner: olivier
--

SELECT pg_catalog.setval('towner_id_seq', 20, true);


--
-- Name: tquality; Type: TABLE; Schema: t; Owner: olivier; Tablespace: 
--

CREATE TABLE tquality (
    id bigint NOT NULL,
    name text NOT NULL,
    idd bigint NOT NULL,
    depository text NOT NULL,
    qtt bigint DEFAULT 0,
    created timestamp without time zone,
    updated timestamp without time zone,
    CONSTRAINT tquality_check CHECK ((((char_length(name) > 0) AND (char_length(depository) > 0)) AND (qtt >= 0)))
);


ALTER TABLE t.tquality OWNER TO olivier;

--
-- Name: TABLE tquality; Type: COMMENT; Schema: t; Owner: olivier
--

COMMENT ON TABLE tquality IS 'description of qualities';


--
-- Name: COLUMN tquality.name; Type: COMMENT; Schema: t; Owner: olivier
--

COMMENT ON COLUMN tquality.name IS 'name of depository/name of quality ';


--
-- Name: COLUMN tquality.qtt; Type: COMMENT; Schema: t; Owner: olivier
--

COMMENT ON COLUMN tquality.qtt IS 'total quantity delegated';


--
-- Name: tquality_id_seq; Type: SEQUENCE; Schema: t; Owner: olivier
--

CREATE SEQUENCE tquality_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE t.tquality_id_seq OWNER TO olivier;

--
-- Name: tquality_id_seq; Type: SEQUENCE OWNED BY; Schema: t; Owner: olivier
--

ALTER SEQUENCE tquality_id_seq OWNED BY tquality.id;


--
-- Name: tquality_id_seq; Type: SEQUENCE SET; Schema: t; Owner: olivier
--

SELECT pg_catalog.setval('tquality_id_seq', 20, true);


--
-- Name: trefused; Type: TABLE; Schema: t; Owner: olivier; Tablespace: 
--

CREATE TABLE trefused (
    x bigint NOT NULL,
    y bigint NOT NULL,
    created timestamp without time zone
);


ALTER TABLE t.trefused OWNER TO olivier;

--
-- Name: TABLE trefused; Type: COMMENT; Schema: t; Owner: olivier
--

COMMENT ON TABLE trefused IS 'list of relations refused';


--
-- Name: tuser; Type: TABLE; Schema: t; Owner: olivier; Tablespace: 
--

CREATE TABLE tuser (
    id bigint NOT NULL,
    name text NOT NULL,
    spent bigint DEFAULT 0 NOT NULL,
    quota bigint DEFAULT 0 NOT NULL,
    last_in timestamp without time zone,
    created timestamp without time zone,
    updated timestamp without time zone,
    CONSTRAINT tuser_check CHECK ((((char_length(name) > 0) AND (spent >= 0)) AND (quota >= 0)))
);


ALTER TABLE t.tuser OWNER TO olivier;

--
-- Name: TABLE tuser; Type: COMMENT; Schema: t; Owner: olivier
--

COMMENT ON TABLE tuser IS 'users that have been connected';


--
-- Name: tuser_id_seq; Type: SEQUENCE; Schema: t; Owner: olivier
--

CREATE SEQUENCE tuser_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE t.tuser_id_seq OWNER TO olivier;

--
-- Name: tuser_id_seq; Type: SEQUENCE OWNED BY; Schema: t; Owner: olivier
--

ALTER SEQUENCE tuser_id_seq OWNED BY tuser.id;


--
-- Name: tuser_id_seq; Type: SEQUENCE SET; Schema: t; Owner: olivier
--

SELECT pg_catalog.setval('tuser_id_seq', 1, true);


--
-- Name: vmarket; Type: VIEW; Schema: t; Owner: olivier
--

CREATE VIEW vmarket AS
    SELECT CASE WHEN (tmarket.ph1 IS NULL) THEN 'OPENED'::text ELSE CASE WHEN (tmarket.ph2 IS NULL) THEN 'CLOSING'::text ELSE 'CLOSED'::text END END AS state, tmarket.ph0, tmarket.ph1, tmarket.ph2, tmarket.backup, CASE WHEN (tmarket.diag = 0) THEN 'OK'::text ELSE (tmarket.diag || ' ERRORS'::text) END AS diagnostic FROM tmarket ORDER BY tmarket.id DESC LIMIT 1;


ALTER TABLE t.vmarket OWNER TO olivier;

--
-- Name: vmvt; Type: VIEW; Schema: t; Owner: olivier
--

CREATE VIEW vmvt AS
    SELECT m.id, m.orid, m.grp, w_src.name AS provider, q.name AS nat, m.qtt, w_dst.name AS receiver, m.created FROM (((tmvt m JOIN towner w_src ON ((m.own_src = w_src.id))) JOIN towner w_dst ON ((m.own_dst = w_dst.id))) JOIN tquality q ON ((m.nat = q.id)));


ALTER TABLE t.vmvt OWNER TO olivier;

--
-- Name: vorder; Type: VIEW; Schema: t; Owner: olivier
--

CREATE VIEW vorder AS
    SELECT n.id, w.name AS owner, qr.name AS qua_requ, n.qtt_requ, qp.name AS qua_prov, n.qtt_prov, n.qtt, n.created, n.updated, ((n.qtt_prov)::double precision / (n.qtt_requ)::double precision) AS omega FROM (((torder n JOIN tquality qr ON ((n.nr = qr.id))) JOIN tquality qp ON ((n.np = qp.id))) JOIN towner w ON ((n.own = w.id)));


ALTER TABLE t.vorder OWNER TO olivier;

--
-- Name: tquality_pkey; Type: CONSTRAINT; Schema: t; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY tquality
    ADD CONSTRAINT tquality_pkey PRIMARY KEY (id);


--
-- Name: vstat; Type: VIEW; Schema: t; Owner: olivier
--

CREATE VIEW vstat AS
    SELECT q.name, (sum(d.qtt) - (q.qtt)::numeric) AS delta, q.qtt AS qtt_quality, sum(d.qtt) AS qtt_detail FROM ((SELECT torder.np AS nat, torder.qtt FROM torder UNION ALL SELECT tmvt.nat, tmvt.qtt FROM tmvt) d JOIN tquality q ON ((d.nat = q.id))) GROUP BY q.id ORDER BY q.name;


ALTER TABLE t.vstat OWNER TO olivier;

--
-- Name: id; Type: DEFAULT; Schema: t; Owner: olivier
--

ALTER TABLE tmarket ALTER COLUMN id SET DEFAULT nextval('tmarket_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: t; Owner: olivier
--

ALTER TABLE tmvt ALTER COLUMN id SET DEFAULT nextval('tmvt_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: t; Owner: olivier
--

ALTER TABLE torder ALTER COLUMN id SET DEFAULT nextval('torder_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: t; Owner: olivier
--

ALTER TABLE towner ALTER COLUMN id SET DEFAULT nextval('towner_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: t; Owner: olivier
--

ALTER TABLE tquality ALTER COLUMN id SET DEFAULT nextval('tquality_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: t; Owner: olivier
--

ALTER TABLE tuser ALTER COLUMN id SET DEFAULT nextval('tuser_id_seq'::regclass);


--
-- Data for Name: tconst; Type: TABLE DATA; Schema: t; Owner: olivier
--

COPY tconst (name, value) FROM stdin;
obCMAXCYCLE	8
NB_BACKUP	7
VERSION	2
EXHAUST	1
VERIFY	1
INSERT_OWN_UNKNOWN	1
INSERT_DUMMY_MVT	1
\.


--
-- Data for Name: tmarket; Type: TABLE DATA; Schema: t; Owner: olivier
--

COPY tmarket (id, ph0, ph1, ph2, backup, diag) FROM stdin;
1	2012-01-13 20:24:34.108253	2012-01-13 20:24:34.108253	2012-01-13 20:24:34.108253	\N	\N
2	2012-01-13 20:24:43.633425	\N	\N	\N	\N
\.


--
-- Data for Name: tmvt; Type: TABLE DATA; Schema: t; Owner: olivier
--

COPY tmvt (id, orid, grp, own_src, own_dst, qtt, nat, created) FROM stdin;
2	2	1	2	5	7838	3	2012-01-13 20:24:50.203247
3	5	1	5	8	7299	9	2012-01-13 20:24:50.203247
4	8	1	8	11	7198	7	2012-01-13 20:24:50.203247
5	16	1	11	6	7577	8	2012-01-13 20:24:50.203247
1	23	1	6	2	6977	4	2012-01-13 20:24:50.203247
7	9	6	8	8	4936	11	2012-01-13 20:24:50.303702
8	27	6	8	11	4257	1	2012-01-13 20:24:50.303702
6	31	6	11	8	6763	12	2012-01-13 20:24:50.303702
10	25	9	15	12	3702	17	2012-01-13 20:24:50.359669
11	28	9	12	7	3503	2	2012-01-13 20:24:50.359669
12	7	9	7	16	8654	7	2012-01-13 20:24:50.359669
13	33	9	16	8	5087	14	2012-01-13 20:24:50.359669
9	35	9	8	15	2809	10	2012-01-13 20:24:50.359669
18	39	17	16	6	4145	13	2012-01-13 20:24:50.762973
19	29	17	6	19	9883	14	2012-01-13 20:24:50.762973
17	64	17	19	16	2610	18	2012-01-13 20:24:50.762973
21	51	20	3	9	9099	13	2012-01-13 20:24:50.863504
22	17	20	9	3	9231	14	2012-01-13 20:24:50.863504
23	67	20	3	4	2159	19	2012-01-13 20:24:50.863504
24	56	20	4	17	4781	17	2012-01-13 20:24:50.863504
25	66	20	17	5	1190	11	2012-01-13 20:24:50.863504
20	70	20	5	3	4985	9	2012-01-13 20:24:50.863504
27	14	26	2	14	5963	4	2012-01-13 20:24:50.896772
28	24	26	14	3	6806	6	2012-01-13 20:24:50.896772
29	3	26	3	1	5047	5	2012-01-13 20:24:50.896772
26	72	26	1	2	355	1	2012-01-13 20:24:50.896772
31	11	30	1	5	4480	12	2012-01-13 20:24:50.997171
32	59	30	5	16	4791	18	2012-01-13 20:24:50.997171
33	32	30	16	11	4424	3	2012-01-13 20:24:50.997171
34	65	30	11	8	8636	8	2012-01-13 20:24:50.997171
35	50	30	8	18	407	4	2012-01-13 20:24:50.997171
30	78	30	18	1	9058	2	2012-01-13 20:24:50.997171
37	71	36	12	6	2188	10	2012-01-13 20:24:51.041973
38	6	36	6	14	4342	8	2012-01-13 20:24:51.041973
36	81	36	14	12	2545	15	2012-01-13 20:24:51.041973
40	54	39	20	8	7185	6	2012-01-13 20:24:51.119994
39	86	39	8	20	4709	17	2012-01-13 20:24:51.119994
42	34	41	4	19	5607	13	2012-01-13 20:24:51.141962
43	61	41	19	19	6389	20	2012-01-13 20:24:51.141962
44	47	41	19	12	1002	14	2012-01-13 20:24:51.141962
41	87	41	12	4	1053	12	2012-01-13 20:24:51.141962
46	1	45	1	14	7580	1	2012-01-13 20:24:51.220091
47	49	45	14	14	6508	15	2012-01-13 20:24:51.220091
48	41	45	14	9	4873	5	2012-01-13 20:24:51.220091
45	91	45	9	1	6811	2	2012-01-13 20:24:51.220091
50	69	49	2	20	6800	3	2012-01-13 20:24:51.275731
49	93	49	20	2	754	8	2012-01-13 20:24:51.275731
52	57	51	14	13	709	12	2012-01-13 20:24:51.331199
53	53	51	13	9	5872	19	2012-01-13 20:24:51.331199
54	80	51	9	11	7981	17	2012-01-13 20:24:51.331199
55	74	51	11	3	8689	11	2012-01-13 20:24:51.331199
56	94	51	3	2	9448	4	2012-01-13 20:24:51.331199
51	96	51	2	14	3054	18	2012-01-13 20:24:51.331199
58	43	57	1	12	1881	6	2012-01-13 20:24:51.353578
59	89	57	12	11	3379	9	2012-01-13 20:24:51.353578
60	95	57	11	3	8194	5	2012-01-13 20:24:51.353578
57	97	57	3	1	9358	20	2012-01-13 20:24:51.353578
62	58	61	11	8	9087	7	2012-01-13 20:24:51.420321
61	100	61	8	11	3479	10	2012-01-13 20:24:51.420321
64	75	63	8	15	8440	19	2012-01-13 20:24:51.542908
65	37	63	15	4	4145	17	2012-01-13 20:24:51.542908
63	108	63	4	8	4198	16	2012-01-13 20:24:51.542908
69	84	68	2	4	4919	13	2012-01-13 20:24:51.720595
70	36	68	4	7	3593	6	2012-01-13 20:24:51.720595
68	116	68	7	2	2037	9	2012-01-13 20:24:51.720595
75	92	74	10	10	7822	5	2012-01-13 20:24:51.967165
76	118	74	10	15	7063	9	2012-01-13 20:24:51.967165
74	128	74	15	10	4727	3	2012-01-13 20:24:51.967165
78	103	77	12	12	8592	16	2012-01-13 20:24:51.98996
79	21	77	12	5	8451	13	2012-01-13 20:24:51.98996
77	129	77	5	12	6521	12	2012-01-13 20:24:51.98996
88	85	87	10	2	9868	6	2012-01-13 20:24:52.200952
89	124	87	2	9	2897	4	2012-01-13 20:24:52.200952
90	120	87	9	17	406	2	2012-01-13 20:24:52.200952
91	76	87	17	20	9686	8	2012-01-13 20:24:52.200952
92	90	87	20	3	1272	5	2012-01-13 20:24:52.200952
93	107	87	3	3	8044	11	2012-01-13 20:24:52.200952
87	138	87	3	10	5866	14	2012-01-13 20:24:52.200952
97	152	96	6	3	815	5	2012-01-13 20:24:52.490468
96	153	96	3	6	4407	18	2012-01-13 20:24:52.490468
99	133	98	19	15	8732	13	2012-01-13 20:24:53.065426
100	111	98	15	4	9490	18	2012-01-13 20:24:53.065426
101	156	98	4	20	5411	1	2012-01-13 20:24:53.065426
98	158	98	20	19	990	11	2012-01-13 20:24:53.065426
103	114	102	2	11	3988	18	2012-01-13 20:24:53.131904
104	62	102	11	13	79	2	2012-01-13 20:24:53.131904
105	45	102	13	17	7174	7	2012-01-13 20:24:53.131904
102	161	102	17	2	7035	11	2012-01-13 20:24:53.131904
470	430	469	14	16	1117	14	2012-01-13 20:25:56.00765
139	180	138	3	7	4090	17	2012-01-13 20:24:56.411329
140	190	138	7	17	7214	3	2012-01-13 20:24:56.411329
141	145	138	17	8	9707	8	2012-01-13 20:24:56.411329
138	198	138	8	3	1408	16	2012-01-13 20:24:56.411329
143	140	142	12	10	6126	2	2012-01-13 20:24:57.097913
144	55	142	10	3	9820	14	2012-01-13 20:24:57.097913
145	99	142	3	10	9623	20	2012-01-13 20:24:57.097913
146	183	142	10	5	7877	19	2012-01-13 20:24:57.097913
147	123	142	5	18	5302	8	2012-01-13 20:24:57.097913
142	209	142	18	12	2492	1	2012-01-13 20:24:57.097913
155	119	154	13	5	7620	10	2012-01-13 20:24:58.59111
156	112	154	5	2	2040	3	2012-01-13 20:24:58.59111
154	221	154	2	13	3061	16	2012-01-13 20:24:58.59111
166	199	165	3	16	4805	7	2012-01-13 20:24:59.132682
165	227	165	16	3	6416	5	2012-01-13 20:24:59.132682
168	215	167	12	3	3893	17	2012-01-13 20:24:59.276597
169	102	167	3	6	1232	14	2012-01-13 20:24:59.276597
170	160	167	6	11	6452	13	2012-01-13 20:24:59.276597
171	109	167	11	10	733	4	2012-01-13 20:24:59.276597
167	229	167	10	12	3337	3	2012-01-13 20:24:59.276597
173	220	172	19	8	7648	9	2012-01-13 20:24:59.62002
174	131	172	8	5	5269	15	2012-01-13 20:24:59.62002
175	38	172	5	18	2395	14	2012-01-13 20:24:59.62002
176	235	172	18	14	3579	20	2012-01-13 20:24:59.62002
177	230	172	14	3	8206	7	2012-01-13 20:24:59.62002
172	236	172	3	19	3298	4	2012-01-13 20:24:59.62002
179	206	178	3	4	5633	8	2012-01-13 20:24:59.62002
180	4	178	4	3	9098	7	2012-01-13 20:24:59.62002
178	236	178	3	3	2791	4	2012-01-13 20:24:59.62002
185	60	184	18	15	8944	6	2012-01-13 20:25:00.835601
186	238	184	15	12	1234	19	2012-01-13 20:25:00.835601
184	243	184	12	18	2871	14	2012-01-13 20:25:00.835601
188	232	187	19	16	8615	12	2012-01-13 20:25:01.190261
189	223	187	16	9	7442	8	2012-01-13 20:25:01.190261
187	248	187	9	19	1380	17	2012-01-13 20:25:01.190261
191	228	190	11	19	6484	11	2012-01-13 20:25:01.523812
190	254	190	19	11	4316	3	2012-01-13 20:25:01.523812
200	122	199	3	7	5955	5	2012-01-13 20:25:02.33059
199	257	199	7	3	2371	12	2012-01-13 20:25:02.33059
202	222	201	12	3	7641	7	2012-01-13 20:25:02.408217
203	236	201	3	7	1476	4	2012-01-13 20:25:02.408217
204	188	201	7	4	3926	8	2012-01-13 20:25:02.408217
205	203	201	4	19	4288	13	2012-01-13 20:25:02.408217
201	258	201	19	12	1067	17	2012-01-13 20:25:02.408217
207	173	206	18	14	6579	9	2012-01-13 20:25:02.795296
208	253	206	14	18	5334	18	2012-01-13 20:25:02.795296
206	260	206	18	18	6042	12	2012-01-13 20:25:02.795296
210	141	209	9	14	3531	6	2012-01-13 20:25:02.916909
211	244	209	14	16	1469	8	2012-01-13 20:25:02.916909
209	261	209	16	9	9961	2	2012-01-13 20:25:02.916909
213	13	212	1	7	5403	6	2012-01-13 20:25:03.060773
214	170	212	7	10	3140	1	2012-01-13 20:25:03.060773
212	263	212	10	1	9574	4	2012-01-13 20:25:03.060773
216	137	215	15	20	8069	11	2012-01-13 20:25:03.24902
215	267	215	20	15	5450	19	2012-01-13 20:25:03.24902
221	155	220	9	3	9345	18	2012-01-13 20:25:03.9904
222	210	220	3	17	780	13	2012-01-13 20:25:03.9904
220	274	220	17	9	1541	4	2012-01-13 20:25:03.9904
228	42	227	7	15	3121	7	2012-01-13 20:25:04.211024
227	277	227	15	7	7934	15	2012-01-13 20:25:04.211024
239	30	238	1	2	9137	9	2012-01-13 20:25:06.35563
240	266	238	2	10	3984	13	2012-01-13 20:25:06.35563
241	135	238	10	6	4218	18	2012-01-13 20:25:06.35563
242	110	238	6	1	4222	20	2012-01-13 20:25:06.35563
243	73	238	1	7	5830	7	2012-01-13 20:25:06.35563
244	279	238	7	11	7758	4	2012-01-13 20:25:06.35563
238	287	238	11	1	591	10	2012-01-13 20:25:06.35563
261	247	260	10	13	2382	15	2012-01-13 20:25:08.378123
260	295	260	13	10	9359	3	2012-01-13 20:25:08.378123
274	113	273	20	19	2770	9	2012-01-13 20:25:13.006728
275	189	273	19	19	7730	1	2012-01-13 20:25:13.006728
276	178	273	19	15	7474	18	2012-01-13 20:25:13.006728
277	296	273	15	11	3844	5	2012-01-13 20:25:13.006728
278	294	273	11	13	5737	14	2012-01-13 20:25:13.006728
273	305	273	13	20	3269	5	2012-01-13 20:25:13.006728
280	280	279	11	1	8564	19	2012-01-13 20:25:14.874942
281	285	279	1	18	4903	3	2012-01-13 20:25:14.874942
282	151	279	18	18	475	10	2012-01-13 20:25:14.874942
283	269	279	18	1	7165	16	2012-01-13 20:25:14.874942
284	250	279	1	14	5101	5	2012-01-13 20:25:14.874942
285	125	279	14	13	4109	18	2012-01-13 20:25:14.874942
279	309	279	13	11	9284	7	2012-01-13 20:25:14.874942
290	167	289	15	13	5911	8	2012-01-13 20:25:16.575229
289	314	289	13	15	5081	16	2012-01-13 20:25:16.575229
292	181	291	9	13	5140	16	2012-01-13 20:25:16.763656
293	22	291	13	2	7946	7	2012-01-13 20:25:16.763656
291	316	291	2	9	3773	12	2012-01-13 20:25:16.763656
301	312	300	11	3	9452	1	2012-01-13 20:25:18.111764
302	212	300	3	11	9280	8	2012-01-13 20:25:18.111764
300	321	300	11	11	3000	9	2012-01-13 20:25:18.111764
304	297	303	14	7	4710	14	2012-01-13 20:25:18.932951
305	323	303	7	12	6778	19	2012-01-13 20:25:18.932951
306	307	303	12	14	9350	13	2012-01-13 20:25:18.932951
303	325	303	14	14	7240	8	2012-01-13 20:25:18.932951
313	30	312	1	20	48	9	2012-01-13 20:25:19.716155
314	205	312	20	3	8448	19	2012-01-13 20:25:19.716155
315	186	312	3	9	364	1	2012-01-13 20:25:19.716155
316	246	312	9	17	6785	11	2012-01-13 20:25:19.716155
317	303	312	17	20	919	15	2012-01-13 20:25:19.716155
312	330	312	20	1	4256	10	2012-01-13 20:25:19.716155
319	79	318	1	5	4823	14	2012-01-13 20:25:20.060013
318	331	318	5	1	6855	4	2012-01-13 20:25:20.060013
326	169	325	13	12	6528	3	2012-01-13 20:25:22.015997
325	343	325	12	13	5636	10	2012-01-13 20:25:22.015997
337	192	336	4	18	6862	2	2012-01-13 20:25:23.285944
338	52	336	18	8	9028	14	2012-01-13 20:25:23.285944
336	346	336	8	4	2720	12	2012-01-13 20:25:23.285944
344	217	343	7	15	5217	4	2012-01-13 20:25:25.088845
345	310	343	15	15	7654	1	2012-01-13 20:25:25.088845
343	353	343	15	7	1060	12	2012-01-13 20:25:25.088845
353	335	352	13	18	8539	15	2012-01-13 20:25:28.313145
354	159	352	18	19	6597	2	2012-01-13 20:25:28.313145
352	358	352	19	13	5128	18	2012-01-13 20:25:28.313145
356	231	355	2	13	3524	7	2012-01-13 20:25:30.236067
357	360	355	13	1	4370	17	2012-01-13 20:25:30.236067
358	168	355	1	3	5265	3	2012-01-13 20:25:30.236067
359	20	355	3	13	7934	6	2012-01-13 20:25:30.236067
360	162	355	13	2	5182	11	2012-01-13 20:25:30.236067
355	365	355	2	2	1229	2	2012-01-13 20:25:30.236067
380	298	379	2	15	3593	5	2012-01-13 20:25:34.446105
381	121	379	15	15	1021	1	2012-01-13 20:25:34.446105
382	353	379	15	19	5028	12	2012-01-13 20:25:34.446105
383	193	379	19	9	9719	4	2012-01-13 20:25:34.446105
384	340	379	9	16	5127	1	2012-01-13 20:25:34.446105
379	373	379	16	2	1681	10	2012-01-13 20:25:34.446105
396	380	395	9	1	5113	18	2012-01-13 20:25:37.395187
395	384	395	1	9	1997	3	2012-01-13 20:25:37.395187
398	101	397	11	1	8935	11	2012-01-13 20:25:37.882085
399	375	397	1	12	624	2	2012-01-13 20:25:37.882085
397	386	397	12	11	3808	9	2012-01-13 20:25:37.882085
408	239	407	17	19	137	4	2012-01-13 20:25:40.876417
409	142	407	19	4	9548	8	2012-01-13 20:25:40.876417
407	392	407	4	17	7940	15	2012-01-13 20:25:40.876417
411	336	410	13	1	42	16	2012-01-13 20:25:41.674824
412	328	410	1	14	5559	17	2012-01-13 20:25:41.674824
413	376	410	14	9	4932	20	2012-01-13 20:25:41.674824
414	283	410	9	8	5650	8	2012-01-13 20:25:41.674824
410	394	410	8	13	9908	6	2012-01-13 20:25:41.674824
416	355	415	1	15	9837	9	2012-01-13 20:25:41.916649
415	396	415	15	1	3548	5	2012-01-13 20:25:41.916649
427	362	426	14	1	9793	13	2012-01-13 20:25:44.866441
428	377	426	1	3	818	10	2012-01-13 20:25:44.866441
429	19	426	3	3	5797	9	2012-01-13 20:25:44.866441
430	398	426	3	5	1969	19	2012-01-13 20:25:44.866441
426	404	426	5	14	8959	7	2012-01-13 20:25:44.866441
442	381	441	20	5	7614	6	2012-01-13 20:25:47.352319
443	82	441	5	20	4081	20	2012-01-13 20:25:47.352319
441	409	441	20	20	6353	2	2012-01-13 20:25:47.352319
445	406	444	10	19	9238	9	2012-01-13 20:25:48.039169
446	194	444	19	2	9246	13	2012-01-13 20:25:48.039169
447	390	444	2	19	4563	20	2012-01-13 20:25:48.039169
444	411	444	19	10	8860	7	2012-01-13 20:25:48.039169
449	143	448	7	14	7042	1	2012-01-13 20:25:48.236938
450	202	448	14	7	7967	5	2012-01-13 20:25:48.236938
451	240	448	7	12	805	15	2012-01-13 20:25:48.236938
452	399	448	12	18	5057	8	2012-01-13 20:25:48.236938
453	200	448	18	15	1877	18	2012-01-13 20:25:48.236938
448	412	448	15	7	5793	17	2012-01-13 20:25:48.236938
455	400	454	3	18	542	17	2012-01-13 20:25:51.342967
456	339	454	18	16	7674	10	2012-01-13 20:25:51.342967
457	77	454	16	14	6786	5	2012-01-13 20:25:51.342967
458	204	454	14	5	5546	19	2012-01-13 20:25:51.342967
459	342	454	5	4	8242	20	2012-01-13 20:25:51.342967
454	417	454	4	3	4032	6	2012-01-13 20:25:51.342967
471	425	469	16	11	6643	4	2012-01-13 20:25:56.00765
461	308	460	8	18	8966	20	2012-01-13 20:25:52.633901
462	420	460	18	4	3234	4	2012-01-13 20:25:52.633901
463	18	460	4	13	8117	15	2012-01-13 20:25:52.633901
464	268	460	13	14	5254	14	2012-01-13 20:25:52.633901
460	424	460	14	8	1482	19	2012-01-13 20:25:52.633901
472	287	469	11	11	94	10	2012-01-13 20:25:56.00765
473	356	469	11	4	7299	13	2012-01-13 20:25:56.00765
469	435	469	4	14	3686	8	2012-01-13 20:25:56.00765
1231	1006	1230	16	7	5210	10	2012-01-13 20:38:56.888641
1232	680	1230	7	1	6586	4	2012-01-13 20:38:56.888641
477	264	476	12	13	2912	9	2012-01-13 20:25:57.618307
478	148	476	13	14	5246	11	2012-01-13 20:25:57.618307
476	438	476	14	12	340	1	2012-01-13 20:25:57.618307
485	374	484	9	17	7951	13	2012-01-13 20:26:02.713767
486	426	484	17	11	7269	7	2012-01-13 20:26:02.713767
484	452	484	11	9	5636	5	2012-01-13 20:26:02.713767
488	421	487	15	13	2539	3	2012-01-13 20:26:03.156406
489	245	487	13	17	8789	8	2012-01-13 20:26:03.156406
490	446	487	17	20	4198	9	2012-01-13 20:26:03.156406
491	324	487	20	9	8019	15	2012-01-13 20:26:03.156406
487	454	487	9	15	9423	2	2012-01-13 20:26:03.156406
500	432	499	12	6	2362	13	2012-01-13 20:26:06.20487
501	456	499	6	18	2284	12	2012-01-13 20:26:06.20487
502	44	499	18	6	9869	9	2012-01-13 20:26:06.20487
499	459	499	6	12	8152	15	2012-01-13 20:26:06.20487
514	438	513	14	13	3575	1	2012-01-13 20:26:10.923234
515	416	513	13	18	9556	4	2012-01-13 20:26:10.923234
513	473	513	18	14	1680	11	2012-01-13 20:26:10.923234
517	445	516	12	9	1636	20	2012-01-13 20:26:11.133413
518	447	516	9	19	3854	16	2012-01-13 20:26:11.133413
519	391	516	19	2	4589	11	2012-01-13 20:26:11.133413
516	474	516	2	12	8876	2	2012-01-13 20:26:11.133413
529	379	528	18	2	8926	11	2012-01-13 20:26:13.475158
528	479	528	2	18	5180	17	2012-01-13 20:26:13.475158
531	449	530	9	6	8528	11	2012-01-13 20:26:15.156
530	482	530	6	9	4964	9	2012-01-13 20:26:15.156
539	241	538	9	18	2623	20	2012-01-13 20:26:17.010159
540	414	538	18	11	4067	10	2012-01-13 20:26:17.010159
541	356	538	11	19	895	13	2012-01-13 20:26:17.010159
542	466	538	19	19	9085	15	2012-01-13 20:26:17.010159
543	106	538	19	5	1026	19	2012-01-13 20:26:17.010159
538	485	538	5	9	7247	7	2012-01-13 20:26:17.010159
545	435	544	4	14	5101	8	2012-01-13 20:26:17.630109
546	388	544	14	4	5097	2	2012-01-13 20:26:17.630109
547	341	544	4	19	8385	14	2012-01-13 20:26:17.630109
544	486	544	19	4	5215	13	2012-01-13 20:26:17.630109
549	402	548	3	19	6192	12	2012-01-13 20:26:18.203941
550	448	548	19	1	7630	4	2012-01-13 20:26:18.203941
548	488	548	1	3	4893	16	2012-01-13 20:26:18.203941
552	415	551	1	4	8784	8	2012-01-13 20:26:18.403152
551	489	551	4	1	2116	16	2012-01-13 20:26:18.403152
554	252	553	2	11	9137	11	2012-01-13 20:26:19.6324
553	491	553	11	2	3667	16	2012-01-13 20:26:19.6324
556	418	555	20	13	702	1	2012-01-13 20:26:20.237003
557	187	555	13	19	3559	18	2012-01-13 20:26:20.237003
558	436	555	19	4	5998	19	2012-01-13 20:26:20.237003
555	493	555	4	20	5859	5	2012-01-13 20:26:20.237003
560	319	559	2	12	2533	11	2012-01-13 20:26:22.801177
559	500	559	12	2	3905	1	2012-01-13 20:26:22.801177
562	440	561	13	20	3378	12	2012-01-13 20:26:25.706154
563	134	561	20	7	2880	3	2012-01-13 20:26:25.706154
561	509	561	7	13	773	16	2012-01-13 20:26:25.706154
565	315	564	6	7	8933	3	2012-01-13 20:26:26.060325
566	509	564	7	20	3936	16	2012-01-13 20:26:26.060325
567	441	564	20	19	5504	13	2012-01-13 20:26:26.060325
564	510	564	19	6	1720	12	2012-01-13 20:26:26.060325
569	302	568	12	14	6757	3	2012-01-13 20:26:26.358181
570	490	568	14	15	9370	1	2012-01-13 20:26:26.358181
571	506	568	15	5	6434	5	2012-01-13 20:26:26.358181
572	262	568	5	9	6287	6	2012-01-13 20:26:26.358181
568	511	568	9	12	1093	12	2012-01-13 20:26:26.358181
580	419	579	1	19	5074	16	2012-01-13 20:26:28.854551
581	495	579	19	8	6502	17	2012-01-13 20:26:28.854551
582	218	579	8	11	1908	2	2012-01-13 20:26:28.854551
579	517	579	11	1	8410	12	2012-01-13 20:26:28.854551
584	68	583	14	18	1514	10	2012-01-13 20:26:29.165014
585	450	583	18	16	9956	20	2012-01-13 20:26:29.165014
583	518	583	16	14	6778	16	2012-01-13 20:26:29.165014
587	461	586	6	3	2072	17	2012-01-13 20:26:30.214922
588	427	586	3	6	4668	5	2012-01-13 20:26:30.214922
586	521	586	6	6	7248	16	2012-01-13 20:26:30.214922
1233	1039	1230	1	13	4384	15	2012-01-13 20:38:56.888641
1234	843	1230	13	13	8738	19	2012-01-13 20:38:56.888641
1044	760	1043	14	19	3029	5	2012-01-13 20:32:14.875653
1045	775	1043	19	12	3302	17	2012-01-13 20:32:14.875653
883	762	882	9	10	2946	17	2012-01-13 20:29:00.146913
595	523	594	1	9	6841	19	2012-01-13 20:26:34.073468
594	529	594	9	1	7179	1	2012-01-13 20:26:34.073468
597	179	596	14	9	7357	3	2012-01-13 20:26:34.44755
596	530	596	9	14	9001	17	2012-01-13 20:26:34.44755
669	502	668	5	8	8748	18	2012-01-13 20:26:58.292162
599	165	598	14	11	765	5	2012-01-13 20:26:35.806866
600	234	598	11	19	3113	20	2012-01-13 20:26:35.806866
598	534	598	19	14	4409	4	2012-01-13 20:26:35.806866
668	590	668	8	5	9373	2	2012-01-13 20:26:58.292162
602	175	601	12	20	246	11	2012-01-13 20:26:35.927924
603	501	601	20	20	5926	15	2012-01-13 20:26:35.927924
604	350	601	20	16	677	2	2012-01-13 20:26:35.927924
605	515	601	16	19	4529	8	2012-01-13 20:26:35.927924
601	535	601	19	12	3687	9	2012-01-13 20:26:35.927924
607	434	606	18	12	5260	19	2012-01-13 20:26:37.022044
608	496	606	12	8	7670	6	2012-01-13 20:26:37.022044
606	539	606	8	18	3462	14	2012-01-13 20:26:37.022044
610	352	609	16	15	7074	9	2012-01-13 20:26:37.243184
611	472	609	15	16	878	16	2012-01-13 20:26:37.243184
612	284	609	16	12	3346	3	2012-01-13 20:26:37.243184
613	533	609	12	12	5518	18	2012-01-13 20:26:37.243184
614	505	609	12	15	9033	14	2012-01-13 20:26:37.243184
615	526	609	15	20	4632	4	2012-01-13 20:26:37.243184
609	540	609	20	16	7714	10	2012-01-13 20:26:37.243184
617	532	616	18	2	8186	7	2012-01-13 20:26:37.630144
616	542	616	2	18	9687	10	2012-01-13 20:26:37.630144
619	216	618	1	9	1269	12	2012-01-13 20:26:38.801274
620	299	618	9	3	4798	18	2012-01-13 20:26:38.801274
618	544	618	3	1	6464	17	2012-01-13 20:26:38.801274
627	497	626	20	8	8213	20	2012-01-13 20:26:41.662659
626	554	626	8	20	9258	1	2012-01-13 20:26:41.662659
636	443	635	11	2	4968	14	2012-01-13 20:26:43.717375
637	545	635	2	20	659	12	2012-01-13 20:26:43.717375
638	389	635	20	2	5064	3	2012-01-13 20:26:43.717375
639	536	635	2	1	2790	17	2012-01-13 20:26:43.717375
635	560	635	1	11	5115	2	2012-01-13 20:26:43.717375
641	363	640	17	13	1401	5	2012-01-13 20:26:44.835147
640	563	640	13	17	6935	18	2012-01-13 20:26:44.835147
643	513	642	13	3	7612	18	2012-01-13 20:26:49.274485
644	558	642	3	20	4329	13	2012-01-13 20:26:49.274485
645	407	642	20	1	1125	7	2012-01-13 20:26:49.274485
642	567	642	1	13	8723	9	2012-01-13 20:26:49.274485
647	550	646	6	17	1168	1	2012-01-13 20:26:50.801543
648	548	646	17	12	9876	18	2012-01-13 20:26:50.801543
649	553	646	12	9	5482	15	2012-01-13 20:26:50.801543
650	561	646	9	6	2482	10	2012-01-13 20:26:50.801543
651	566	646	6	5	4896	16	2012-01-13 20:26:50.801543
646	568	646	5	6	9854	5	2012-01-13 20:26:50.801543
696	569	695	4	20	1896	9	2012-01-13 20:27:07.506667
697	519	695	20	9	4524	14	2012-01-13 20:27:07.506667
698	584	695	9	17	1882	18	2012-01-13 20:27:07.506667
695	605	695	17	4	4751	11	2012-01-13 20:27:07.506667
700	351	699	16	8	4853	5	2012-01-13 20:27:10.799209
701	595	699	8	11	3558	20	2012-01-13 20:27:10.799209
699	610	699	11	16	5863	12	2012-01-13 20:27:10.799209
703	574	702	17	10	2268	8	2012-01-13 20:27:11.959818
704	26	702	10	14	1239	7	2012-01-13 20:27:11.959818
705	580	702	14	7	4497	12	2012-01-13 20:27:11.959818
706	480	702	7	3	6043	1	2012-01-13 20:27:11.959818
707	587	702	3	15	7489	19	2012-01-13 20:27:11.959818
702	612	702	15	17	7589	15	2012-01-13 20:27:11.959818
709	537	708	18	11	7393	6	2012-01-13 20:27:13.073847
708	616	708	11	18	1131	7	2012-01-13 20:27:13.073847
711	494	710	12	5	6789	13	2012-01-13 20:27:13.725915
710	618	710	5	12	8260	2	2012-01-13 20:27:13.725915
713	487	712	8	16	4409	9	2012-01-13 20:27:17.940949
712	626	712	16	8	6375	2	2012-01-13 20:27:17.940949
715	594	714	18	2	7035	19	2012-01-13 20:27:19.896675
716	359	714	2	15	804	10	2012-01-13 20:27:19.896675
717	444	714	15	18	4068	17	2012-01-13 20:27:19.896675
714	632	714	18	18	8062	4	2012-01-13 20:27:19.896675
719	535	718	19	6	2910	9	2012-01-13 20:27:20.084462
718	633	718	6	19	8712	8	2012-01-13 20:27:20.084462
721	213	720	9	9	7735	20	2012-01-13 20:27:21.490118
722	538	720	9	15	7697	13	2012-01-13 20:27:21.490118
720	636	720	15	9	4188	17	2012-01-13 20:27:21.490118
724	552	723	11	17	6509	11	2012-01-13 20:27:27.940756
725	630	723	17	16	8702	5	2012-01-13 20:27:27.940756
726	637	723	16	9	8860	18	2012-01-13 20:27:27.940756
723	646	723	9	11	6614	8	2012-01-13 20:27:27.940756
731	648	731	11	19	7465	8	2012-01-13 20:27:28.645509
732	644	731	19	10	4774	19	2012-01-13 20:27:28.645509
733	645	731	10	11	8694	7	2012-01-13 20:27:28.645509
734	557	731	11	11	654	16	2012-01-13 20:27:28.645509
884	431	882	10	17	2693	8	2012-01-13 20:29:00.146913
736	455	735	10	5	2955	4	2012-01-13 20:27:29.739991
735	650	735	5	10	8910	11	2012-01-13 20:27:29.739991
882	779	882	17	9	3710	19	2012-01-13 20:29:00.146913
738	562	737	14	17	3242	2	2012-01-13 20:27:30.115446
739	464	737	17	3	1888	1	2012-01-13 20:27:30.115446
737	652	737	3	14	9405	8	2012-01-13 20:27:30.115446
1046	251	1043	12	10	7784	14	2012-01-13 20:32:14.875653
741	291	740	17	20	9313	15	2012-01-13 20:27:30.834758
740	654	740	20	17	3964	12	2012-01-13 20:27:30.834758
743	586	742	12	4	2147	8	2012-01-13 20:27:33.739715
742	660	742	4	12	2833	17	2012-01-13 20:27:33.739715
745	658	744	12	7	8565	10	2012-01-13 20:27:34.159468
746	337	744	7	2	3802	20	2012-01-13 20:27:34.159468
747	651	744	2	19	2870	7	2012-01-13 20:27:34.159468
748	657	744	19	6	5604	17	2012-01-13 20:27:34.159468
749	470	744	6	11	7099	19	2012-01-13 20:27:34.159468
750	547	744	11	1	9432	6	2012-01-13 20:27:34.159468
744	661	744	1	12	1319	12	2012-01-13 20:27:34.159468
752	642	751	17	12	2141	3	2012-01-13 20:27:38.059732
753	613	751	12	10	6395	4	2012-01-13 20:27:38.059732
751	668	751	10	17	7935	1	2012-01-13 20:27:38.059732
755	528	754	4	14	5132	15	2012-01-13 20:27:39.695103
754	671	754	14	4	5961	13	2012-01-13 20:27:39.695103
889	765	888	7	4	2501	3	2012-01-13 20:29:07.571793
757	433	756	17	4	8473	19	2012-01-13 20:27:43.649414
756	679	756	4	17	5367	17	2012-01-13 20:27:43.649414
890	753	888	4	1	9450	18	2012-01-13 20:29:07.571793
759	503	758	19	12	7109	9	2012-01-13 20:27:45.097072
760	541	758	12	8	6353	19	2012-01-13 20:27:45.097072
761	663	758	8	8	8514	7	2012-01-13 20:27:45.097072
758	683	758	8	19	4127	10	2012-01-13 20:27:45.097072
888	788	888	1	7	9960	9	2012-01-13 20:29:07.571793
763	628	762	10	6	5485	12	2012-01-13 20:27:46.002311
764	608	762	6	15	3219	7	2012-01-13 20:27:46.002311
765	674	762	15	15	3018	10	2012-01-13 20:27:46.002311
766	514	762	15	2	8491	4	2012-01-13 20:27:46.002311
762	686	762	2	10	4651	19	2012-01-13 20:27:46.002311
768	83	767	6	14	2871	20	2012-01-13 20:27:46.877185
767	687	767	14	6	6479	17	2012-01-13 20:27:46.877185
775	689	774	9	5	3946	19	2012-01-13 20:27:51.5387
776	672	774	5	2	9546	1	2012-01-13 20:27:51.5387
777	641	774	2	20	3354	15	2012-01-13 20:27:51.5387
778	634	774	20	10	6753	13	2012-01-13 20:27:51.5387
779	585	774	10	16	4289	7	2012-01-13 20:27:51.5387
774	694	774	16	9	4151	14	2012-01-13 20:27:51.5387
790	354	789	19	20	3486	15	2012-01-13 20:27:55.496838
791	619	789	20	20	6267	18	2012-01-13 20:27:55.496838
789	701	789	20	19	3665	11	2012-01-13 20:27:55.496838
812	703	811	10	12	6662	1	2012-01-13 20:28:14.357487
813	700	811	12	3	5283	2	2012-01-13 20:28:14.357487
811	720	811	3	10	5354	14	2012-01-13 20:28:14.357487
834	468	833	20	10	1777	18	2012-01-13 20:28:23.998824
835	678	833	10	6	6056	15	2012-01-13 20:28:23.998824
836	625	833	6	1	2369	9	2012-01-13 20:28:23.998824
837	715	833	1	2	3116	17	2012-01-13 20:28:23.998824
838	207	833	2	5	6142	11	2012-01-13 20:28:23.998824
833	729	833	5	20	4437	12	2012-01-13 20:28:23.998824
840	706	839	14	1	2515	10	2012-01-13 20:28:25.346904
841	708	839	1	12	2010	20	2012-01-13 20:28:25.346904
842	546	839	12	15	1560	3	2012-01-13 20:28:25.346904
843	581	839	15	15	7714	14	2012-01-13 20:28:25.346904
839	730	839	15	14	3621	8	2012-01-13 20:28:25.346904
845	726	844	4	12	7107	4	2012-01-13 20:28:26.052669
846	702	844	12	8	7796	5	2012-01-13 20:28:26.052669
844	731	844	8	4	9649	12	2012-01-13 20:28:26.052669
848	664	847	2	2	7569	15	2012-01-13 20:28:28.625285
849	669	847	2	12	5192	17	2012-01-13 20:28:28.625285
847	736	847	12	2	3816	8	2012-01-13 20:28:28.625285
851	655	850	1	20	9262	12	2012-01-13 20:28:29.102554
850	738	850	20	1	6679	3	2012-01-13 20:28:29.102554
856	732	855	8	6	8547	17	2012-01-13 20:28:31.22551
855	741	855	6	8	2130	16	2012-01-13 20:28:31.22551
858	690	857	17	16	6301	8	2012-01-13 20:28:33.124813
859	745	857	16	4	7575	4	2012-01-13 20:28:33.124813
857	746	857	4	17	6625	7	2012-01-13 20:28:33.124813
861	685	860	1	7	5970	17	2012-01-13 20:28:39.498005
862	740	860	7	18	9259	7	2012-01-13 20:28:39.498005
863	659	860	18	14	8447	5	2012-01-13 20:28:39.498005
864	709	860	14	12	4222	19	2012-01-13 20:28:39.498005
860	756	860	12	1	6850	11	2012-01-13 20:28:39.498005
1047	892	1043	10	17	2316	11	2012-01-13 20:32:14.875653
876	704	875	4	14	9957	14	2012-01-13 20:28:53.473678
875	772	875	14	4	4336	19	2012-01-13 20:28:53.473678
1043	906	1043	17	14	8886	6	2012-01-13 20:32:14.875653
1235	920	1230	13	19	5148	11	2012-01-13 20:38:56.888641
1049	900	1048	2	6	8780	13	2012-01-13 20:32:15.633568
1048	907	1048	6	2	6653	20	2012-01-13 20:32:15.633568
1051	460	1050	9	5	8665	13	2012-01-13 20:32:17.799991
1052	463	1050	5	7	8813	6	2012-01-13 20:32:17.799991
1050	909	1050	7	9	5554	17	2012-01-13 20:32:17.799991
1054	769	1053	2	13	7075	14	2012-01-13 20:32:20.586325
900	649	899	16	18	6461	20	2012-01-13 20:29:17.457189
901	481	899	18	1	6643	15	2012-01-13 20:29:17.457189
899	798	899	1	16	3888	3	2012-01-13 20:29:17.457189
1053	911	1053	13	2	7705	17	2012-01-13 20:32:20.586325
1056	525	1055	6	18	3099	14	2012-01-13 20:32:28.105693
1057	673	1055	18	20	2811	8	2012-01-13 20:32:28.105693
1055	917	1055	20	6	2642	1	2012-01-13 20:32:28.105693
1067	662	1066	7	20	4447	8	2012-01-13 20:32:47.487982
1066	929	1066	20	7	9177	18	2012-01-13 20:32:47.487982
1069	707	1068	8	4	5336	18	2012-01-13 20:32:48.262847
1070	639	1068	4	20	2949	12	2012-01-13 20:32:48.262847
1068	930	1068	20	8	2799	16	2012-01-13 20:32:48.262847
1072	817	1071	2	10	6947	11	2012-01-13 20:32:49.666772
1073	851	1071	10	13	2426	19	2012-01-13 20:32:49.666772
923	46	922	11	1	1190	15	2012-01-13 20:29:32.514609
924	798	922	1	1	4803	3	2012-01-13 20:29:32.514609
925	785	922	1	6	4141	19	2012-01-13 20:29:32.514609
922	806	922	6	11	5949	1	2012-01-13 20:29:32.514609
1071	931	1071	13	2	4242	20	2012-01-13 20:32:49.666772
1089	749	1088	18	6	8094	10	2012-01-13 20:33:11.614546
1090	821	1088	6	15	7533	15	2012-01-13 20:33:11.614546
1088	940	1088	15	18	2075	12	2012-01-13 20:33:11.614546
951	317	950	13	16	2485	8	2012-01-13 20:29:56.304211
952	750	950	16	15	5573	9	2012-01-13 20:29:56.304211
953	764	950	15	6	8648	12	2012-01-13 20:29:56.304211
950	823	950	6	13	4323	17	2012-01-13 20:29:56.304211
955	804	954	9	10	1038	19	2012-01-13 20:30:03.562297
956	791	954	10	10	8304	6	2012-01-13 20:30:03.562297
954	828	954	10	9	2954	11	2012-01-13 20:30:03.562297
1101	949	1100	20	2	5984	17	2012-01-13 20:33:35.404908
1102	572	1100	2	18	2702	8	2012-01-13 20:33:35.404908
1100	953	1100	18	20	9510	9	2012-01-13 20:33:35.404908
962	752	961	7	2	2366	2	2012-01-13 20:30:10.169024
961	834	961	2	7	7312	5	2012-01-13 20:30:10.169024
1104	761	1103	11	1	8181	7	2012-01-13 20:33:41.142879
1105	847	1103	1	16	3321	2	2012-01-13 20:33:41.142879
1103	956	1103	16	11	4621	19	2012-01-13 20:33:41.142879
1107	854	1106	12	4	8082	1	2012-01-13 20:33:52.032934
1108	859	1106	4	7	7509	6	2012-01-13 20:33:52.032934
1109	948	1106	7	8	656	11	2012-01-13 20:33:52.032934
1106	961	1106	8	12	2170	14	2012-01-13 20:33:52.032934
970	757	969	19	1	4665	20	2012-01-13 20:30:17.169907
971	607	969	1	6	7620	19	2012-01-13 20:30:17.169907
972	806	969	6	5	4031	1	2012-01-13 20:30:17.169907
973	754	969	5	8	7586	6	2012-01-13 20:30:17.169907
969	837	969	8	19	3391	9	2012-01-13 20:30:17.169907
981	818	980	3	20	7550	11	2012-01-13 20:30:36.136266
982	793	980	20	7	3137	2	2012-01-13 20:30:36.136266
983	768	980	7	8	3385	17	2012-01-13 20:30:36.136266
984	249	980	8	9	3900	10	2012-01-13 20:30:36.136266
980	853	980	9	3	5853	9	2012-01-13 20:30:36.136266
995	711	994	4	12	9402	2	2012-01-13 20:30:52.18646
996	507	994	12	3	4239	4	2012-01-13 20:30:52.18646
997	781	994	3	20	5056	12	2012-01-13 20:30:52.18646
998	825	994	20	19	650	16	2012-01-13 20:30:52.18646
999	747	994	19	11	9630	3	2012-01-13 20:30:52.18646
994	863	994	11	4	8635	9	2012-01-13 20:30:52.18646
1127	819	1126	19	15	2154	18	2012-01-13 20:34:11.542635
1126	969	1126	15	19	925	15	2012-01-13 20:34:11.542635
1138	924	1137	18	11	2470	20	2012-01-13 20:35:02.492161
1139	623	1137	11	9	2958	8	2012-01-13 20:35:02.492161
1140	796	1137	9	12	6092	1	2012-01-13 20:35:02.492161
1141	971	1137	12	2	4194	11	2012-01-13 20:35:02.492161
1142	676	1137	2	17	769	2	2012-01-13 20:35:02.492161
1137	983	1137	17	18	8272	17	2012-01-13 20:35:02.492161
1144	875	1143	14	6	8236	19	2012-01-13 20:35:20.484393
1145	805	1143	6	20	3472	4	2012-01-13 20:35:20.484393
1146	933	1143	20	2	586	3	2012-01-13 20:35:20.484393
1143	987	1143	2	14	5493	12	2012-01-13 20:35:20.484393
1025	849	1024	5	14	8627	1	2012-01-13 20:31:41.625862
1026	884	1024	14	12	7194	4	2012-01-13 20:31:41.625862
1027	682	1024	12	11	6556	5	2012-01-13 20:31:41.625862
1024	889	1024	11	5	2150	14	2012-01-13 20:31:41.625862
1230	1057	1230	19	16	3111	20	2012-01-13 20:38:56.888641
1492	1226	1491	11	17	8274	7	2012-01-13 20:52:57.690051
1237	1045	1236	14	11	2222	3	2012-01-13 20:38:59.655468
1238	622	1236	11	1	5164	10	2012-01-13 20:38:59.655468
1236	1059	1236	1	14	6084	7	2012-01-13 20:38:59.655468
1152	492	1151	8	4	8609	4	2012-01-13 20:36:07.425789
1153	890	1151	4	18	9892	5	2012-01-13 20:36:07.425789
1151	1002	1151	18	8	5032	3	2012-01-13 20:36:07.425789
1493	845	1491	17	19	3905	13	2012-01-13 20:52:57.690051
1155	696	1154	20	14	4101	4	2012-01-13 20:36:08.483665
1154	1003	1154	14	20	4107	18	2012-01-13 20:36:08.483665
1240	983	1239	17	15	1204	17	2012-01-13 20:39:06.462861
1157	881	1156	6	13	9739	2	2012-01-13 20:36:10.518385
1156	1004	1156	13	6	9773	12	2012-01-13 20:36:10.518385
1241	174	1239	15	20	5396	19	2012-01-13 20:39:06.462861
1242	1040	1239	20	8	5485	7	2012-01-13 20:39:06.462861
1239	1062	1239	8	17	8765	2	2012-01-13 20:39:06.462861
1163	846	1162	8	9	3068	9	2012-01-13 20:36:20.488591
1162	1009	1162	9	8	6368	4	2012-01-13 20:36:20.488591
1169	990	1168	17	5	2938	10	2012-01-13 20:36:24.078219
1170	861	1168	5	15	5261	7	2012-01-13 20:36:24.078219
1168	1011	1168	15	17	3359	8	2012-01-13 20:36:24.078219
1264	1054	1263	7	10	6988	1	2012-01-13 20:40:31.163048
1265	1063	1263	10	8	9851	7	2012-01-13 20:40:31.163048
1266	1062	1263	8	9	104	2	2012-01-13 20:40:31.163048
1267	908	1263	9	2	5844	9	2012-01-13 20:40:31.163048
1268	1078	1263	2	4	2405	4	2012-01-13 20:40:31.163048
1263	1079	1263	4	7	261	12	2012-01-13 20:40:31.163048
1195	869	1194	1	18	1855	17	2012-01-13 20:37:30.007919
1196	924	1194	18	8	684	20	2012-01-13 20:37:30.007919
1197	980	1194	8	13	4945	18	2012-01-13 20:37:30.007919
1194	1032	1194	13	1	6894	14	2012-01-13 20:37:30.007919
1199	693	1198	6	6	7574	12	2012-01-13 20:37:33.21281
1200	945	1198	6	13	9310	9	2012-01-13 20:37:33.21281
1201	972	1198	13	2	9318	11	2012-01-13 20:37:33.21281
1202	947	1198	2	12	6357	6	2012-01-13 20:37:33.21281
1198	1033	1198	12	6	176	16	2012-01-13 20:37:33.21281
1277	1067	1276	15	4	2978	4	2012-01-13 20:41:10.561041
1278	1079	1276	4	17	3600	12	2012-01-13 20:41:10.561041
1279	904	1276	17	15	3667	20	2012-01-13 20:41:10.561041
1280	1061	1276	15	3	8289	19	2012-01-13 20:41:10.561041
1276	1091	1276	3	15	6809	11	2012-01-13 20:41:10.561041
1211	905	1210	20	7	9812	18	2012-01-13 20:37:43.668614
1212	1019	1210	7	19	5661	12	2012-01-13 20:37:43.668614
1213	979	1210	19	11	4374	15	2012-01-13 20:37:43.668614
1214	681	1210	11	19	3728	5	2012-01-13 20:37:43.668614
1215	926	1210	19	19	914	20	2012-01-13 20:37:43.668614
1210	1037	1210	19	20	3159	16	2012-01-13 20:37:43.668614
1217	705	1216	5	11	2412	19	2012-01-13 20:37:46.719685
1218	139	1216	11	1	1868	6	2012-01-13 20:37:46.719685
1216	1038	1216	1	5	5979	14	2012-01-13 20:37:46.719685
1284	1053	1283	2	13	8211	19	2012-01-13 20:41:19.75684
1285	993	1283	13	19	6138	14	2012-01-13 20:41:19.75684
1283	1094	1283	19	2	3483	9	2012-01-13 20:41:19.75684
1223	166	1222	17	1	2135	7	2012-01-13 20:38:03.535164
1222	1044	1222	1	17	7066	5	2012-01-13 20:38:03.535164
1295	293	1294	13	7	4957	2	2012-01-13 20:41:35.363549
1294	1102	1294	7	13	8445	12	2012-01-13 20:41:35.363549
1297	774	1296	8	13	8583	8	2012-01-13 20:41:39.101424
1298	925	1296	13	15	8274	13	2012-01-13 20:41:39.101424
1299	615	1296	15	11	893	9	2012-01-13 20:41:39.101424
1296	1104	1296	11	8	3633	16	2012-01-13 20:41:39.101424
1301	1060	1300	18	20	7283	15	2012-01-13 20:42:13.137706
1302	1012	1300	20	11	4856	4	2012-01-13 20:42:13.137706
1303	1096	1300	11	7	4817	18	2012-01-13 20:42:13.137706
1304	1046	1300	7	7	8647	19	2012-01-13 20:42:13.137706
1300	1111	1300	7	18	5264	17	2012-01-13 20:42:13.137706
1306	790	1305	7	14	4252	18	2012-01-13 20:42:15.550722
1307	1071	1305	14	16	6461	8	2012-01-13 20:42:15.550722
1308	1088	1305	16	18	5394	7	2012-01-13 20:42:15.550722
1309	677	1305	18	12	9852	5	2012-01-13 20:42:15.550722
1305	1112	1305	12	7	3406	12	2012-01-13 20:42:15.550722
1311	1092	1310	14	1	3061	12	2012-01-13 20:42:27.995759
1310	1116	1310	1	14	2421	16	2012-01-13 20:42:27.995759
1317	1114	1316	20	11	5767	4	2012-01-13 20:42:42.53978
1318	1115	1316	11	2	7469	19	2012-01-13 20:42:42.53978
1319	783	1316	2	20	975	15	2012-01-13 20:42:42.53978
1316	1121	1316	20	20	6556	5	2012-01-13 20:42:42.53978
1326	265	1325	18	9	3469	6	2012-01-13 20:42:58.259355
1327	1120	1325	9	5	3023	15	2012-01-13 20:42:58.259355
1325	1125	1325	5	18	9463	19	2012-01-13 20:42:58.259355
1329	1023	1328	5	20	7599	20	2012-01-13 20:43:01.506493
1328	1126	1328	20	5	8827	16	2012-01-13 20:43:01.506493
1331	1124	1330	18	19	8441	1	2012-01-13 20:43:20.039131
1330	1130	1330	19	18	5566	15	2012-01-13 20:43:20.039131
1494	1190	1491	19	18	4443	4	2012-01-13 20:52:57.690051
1495	1209	1491	18	16	1793	16	2012-01-13 20:52:57.690051
1496	602	1491	16	18	5632	14	2012-01-13 20:52:57.690051
1491	1268	1491	18	11	1968	15	2012-01-13 20:52:57.690051
1337	1074	1336	11	1	6961	8	2012-01-13 20:43:38.836748
1338	1070	1336	1	10	8268	14	2012-01-13 20:43:38.836748
1336	1135	1336	10	11	3363	18	2012-01-13 20:43:38.836748
1719	1414	1718	20	6	7132	11	2012-01-13 21:10:45.557193
1498	1199	1497	2	17	5611	8	2012-01-13 20:53:15.918252
1497	1273	1497	17	2	8235	12	2012-01-13 20:53:15.918252
1500	1169	1499	12	13	5527	2	2012-01-13 20:53:18.636647
1499	1274	1499	13	12	7470	1	2012-01-13 20:53:18.636647
1344	1129	1343	1	17	2378	3	2012-01-13 20:43:52.710831
1343	1139	1343	17	1	7367	18	2012-01-13 20:43:52.710831
1501	1275	1501	5	1	5209	1	2012-01-13 20:53:21.410818
1351	1121	1350	20	20	1784	5	2012-01-13 20:44:37.789033
1352	1114	1350	20	18	3416	4	2012-01-13 20:44:37.789033
1353	311	1350	18	15	8271	6	2012-01-13 20:44:37.789033
1354	1077	1350	15	18	4741	11	2012-01-13 20:44:37.789033
1350	1148	1350	18	20	6196	15	2012-01-13 20:44:37.789033
1356	983	1355	17	16	260	17	2012-01-13 20:44:45.759799
1357	786	1355	16	13	6589	11	2012-01-13 20:44:45.759799
1355	1150	1355	13	17	5575	2	2012-01-13 20:44:45.759799
1359	565	1358	6	18	7406	9	2012-01-13 20:44:52.022746
1360	877	1358	18	17	5198	20	2012-01-13 20:44:52.022746
1361	1118	1358	17	14	9761	15	2012-01-13 20:44:52.022746
1358	1152	1358	14	6	1111	16	2012-01-13 20:44:52.022746
1363	1140	1362	19	13	4538	2	2012-01-13 20:44:53.281712
1364	698	1362	13	19	3996	13	2012-01-13 20:44:53.281712
1362	1153	1362	19	19	3051	19	2012-01-13 20:44:53.281712
1366	1133	1365	19	9	6668	8	2012-01-13 20:44:56.51087
1365	1155	1365	9	19	8807	10	2012-01-13 20:44:56.51087
1377	955	1376	15	14	8696	4	2012-01-13 20:46:14.194456
1378	1156	1376	14	11	3934	19	2012-01-13 20:46:14.194456
1379	1110	1376	11	3	1506	3	2012-01-13 20:46:14.194456
1380	1075	1376	3	16	5025	1	2012-01-13 20:46:14.194456
1376	1178	1376	16	15	2208	8	2012-01-13 20:46:14.194456
1382	1145	1381	18	11	9753	3	2012-01-13 20:46:15.588877
1383	759	1381	11	12	6703	1	2012-01-13 20:46:15.588877
1381	1179	1381	12	18	1294	16	2012-01-13 20:46:15.588877
1385	936	1384	12	7	9001	7	2012-01-13 20:46:33.667971
1386	1080	1384	7	12	4148	14	2012-01-13 20:46:33.667971
1387	1172	1384	12	11	5151	13	2012-01-13 20:46:33.667971
1384	1182	1384	11	12	2627	18	2012-01-13 20:46:33.667971
1389	966	1388	17	12	8538	3	2012-01-13 20:46:36.30891
1390	471	1388	12	3	5163	18	2012-01-13 20:46:36.30891
1388	1183	1388	3	17	5433	16	2012-01-13 20:46:36.30891
1392	1164	1391	19	8	9630	19	2012-01-13 20:47:04.284597
1393	1141	1391	8	10	8912	17	2012-01-13 20:47:04.284597
1391	1189	1391	10	19	3602	16	2012-01-13 20:47:04.284597
1395	609	1394	10	2	9758	7	2012-01-13 20:47:20.690727
1396	1160	1394	2	1	4182	13	2012-01-13 20:47:20.690727
1394	1193	1394	1	10	4729	3	2012-01-13 20:47:20.690727
1398	667	1397	6	7	4784	10	2012-01-13 20:47:51.138836
1399	1196	1397	7	7	5677	16	2012-01-13 20:47:51.138836
1400	1081	1397	7	18	9966	1	2012-01-13 20:47:51.138836
1397	1201	1397	18	6	3321	9	2012-01-13 20:47:51.138836
1405	976	1404	19	8	6284	10	2012-01-13 20:48:59.53175
1404	1211	1404	8	19	9955	12	2012-01-13 20:48:59.53175
1412	1158	1411	2	8	9023	1	2012-01-13 20:49:09.058898
1413	1163	1411	8	11	7246	15	2012-01-13 20:49:09.058898
1411	1214	1411	11	2	1955	9	2012-01-13 20:49:09.058898
1415	943	1414	20	20	9675	19	2012-01-13 20:49:24.740074
1414	1218	1414	20	20	6188	3	2012-01-13 20:49:24.740074
1429	1198	1428	12	6	9254	5	2012-01-13 20:50:36.996007
1430	824	1428	6	7	2831	11	2012-01-13 20:50:36.996007
1428	1233	1428	7	12	5041	8	2012-01-13 20:50:36.996007
1432	965	1431	13	1	6166	14	2012-01-13 20:50:43.848885
1431	1234	1431	1	13	4536	5	2012-01-13 20:50:43.848885
1434	1048	1433	3	6	7189	15	2012-01-13 20:50:50.264416
1435	1236	1433	6	10	5247	13	2012-01-13 20:50:50.264416
1433	1237	1433	10	3	3717	8	2012-01-13 20:50:50.264416
1452	1204	1451	4	18	5398	1	2012-01-13 20:51:52.197356
1451	1251	1451	18	4	8977	18	2012-01-13 20:51:52.197356
1470	994	1469	17	13	6152	20	2012-01-13 20:52:25.23474
1471	1200	1469	13	16	3921	19	2012-01-13 20:52:25.23474
1472	891	1469	16	8	7816	11	2012-01-13 20:52:25.23474
1469	1260	1469	8	17	5660	10	2012-01-13 20:52:25.23474
1481	1208	1480	2	19	8116	7	2012-01-13 20:52:39.567069
1482	1241	1480	19	7	7519	11	2012-01-13 20:52:39.567069
1483	1181	1480	7	5	596	3	2012-01-13 20:52:39.567069
1484	1224	1480	5	6	7773	12	2012-01-13 20:52:39.567069
1480	1263	1480	6	2	2221	18	2012-01-13 20:52:39.567069
1502	1207	1501	1	14	7352	5	2012-01-13 20:53:21.410818
1503	136	1501	14	13	1293	18	2012-01-13 20:53:21.410818
1504	1247	1501	13	9	5693	17	2012-01-13 20:53:21.410818
1505	795	1501	9	5	6234	11	2012-01-13 20:53:21.410818
1720	1405	1718	6	15	2551	18	2012-01-13 21:10:45.557193
1721	1167	1718	15	16	6578	4	2012-01-13 21:10:45.557193
1722	1416	1718	16	15	9665	5	2012-01-13 21:10:45.557193
1723	1409	1718	15	18	4403	13	2012-01-13 21:10:45.557193
1718	1432	1718	18	20	3404	1	2012-01-13 21:10:45.557193
1510	1136	1509	11	7	6439	2	2012-01-13 20:53:35.389575
1511	865	1509	7	17	8350	15	2012-01-13 20:53:35.389575
1512	916	1509	17	9	480	11	2012-01-13 20:53:35.389575
1509	1279	1509	9	11	5389	20	2012-01-13 20:53:35.389575
1949	1386	1948	2	16	7970	11	2012-01-13 21:32:07.513035
1514	1244	1513	16	13	2091	18	2012-01-13 20:53:45.251018
1515	1205	1513	13	6	4740	17	2012-01-13 20:53:45.251018
1513	1280	1513	6	16	3254	2	2012-01-13 20:53:45.251018
1725	1322	1724	19	20	877	1	2012-01-13 21:10:53.550024
1726	1414	1724	20	9	1699	11	2012-01-13 21:10:53.550024
1724	1433	1724	9	19	6038	7	2012-01-13 21:10:53.550024
1728	1318	1727	9	13	9411	2	2012-01-13 21:11:13.285148
1727	1436	1727	13	9	9041	1	2012-01-13 21:11:13.285148
1526	961	1525	8	20	7127	14	2012-01-13 20:55:05.406206
1525	1295	1525	20	8	5082	11	2012-01-13 20:55:05.406206
1528	271	1527	14	18	3318	8	2012-01-13 20:55:07.32183
1527	1296	1527	18	14	4172	10	2012-01-13 20:55:07.32183
1736	968	1735	1	17	7592	17	2012-01-13 21:12:27.878198
1735	1443	1735	17	1	7739	8	2012-01-13 21:12:27.878198
1738	1428	1737	17	6	5540	11	2012-01-13 21:12:33.013403
1739	1287	1737	6	16	2124	19	2012-01-13 21:12:33.013403
1740	1309	1737	16	13	3179	6	2012-01-13 21:12:33.013403
1535	1299	1534	3	6	8834	5	2012-01-13 20:55:41.952079
1534	1304	1534	6	3	4732	11	2012-01-13 20:55:41.952079
1737	1444	1737	13	17	2021	17	2012-01-13 21:12:33.013403
1542	1184	1541	11	4	5434	1	2012-01-13 20:56:16.576916
1543	1168	1541	4	1	9436	6	2012-01-13 20:56:16.576916
1541	1311	1541	1	11	8256	2	2012-01-13 20:56:16.576916
1746	1366	1745	18	6	5196	19	2012-01-13 21:13:09.417563
1747	1345	1745	6	8	9830	7	2012-01-13 21:13:09.417563
1748	1375	1745	8	12	1826	14	2012-01-13 21:13:09.417563
1745	1451	1745	12	18	7387	5	2012-01-13 21:13:09.417563
1750	1400	1749	9	12	4951	20	2012-01-13 21:13:12.208345
1749	1452	1749	12	9	3936	9	2012-01-13 21:13:12.208345
1557	1302	1556	15	11	9768	4	2012-01-13 20:57:24.425756
1556	1325	1556	11	15	6701	7	2012-01-13 20:57:24.425756
1616	1305	1615	10	12	6254	2	2012-01-13 21:02:40.944727
1615	1363	1615	12	10	8604	19	2012-01-13 21:02:40.944727
1631	1321	1630	17	15	4760	1	2012-01-13 21:03:44.343764
1632	1281	1630	15	9	1022	9	2012-01-13 21:03:44.343764
1633	1285	1630	9	8	3858	18	2012-01-13 21:03:44.343764
1634	1298	1630	8	14	3445	3	2012-01-13 21:03:44.343764
1635	1248	1630	14	4	2607	5	2012-01-13 21:03:44.343764
1630	1373	1630	4	17	3819	17	2012-01-13 21:03:44.343764
1637	1292	1636	5	3	1722	2	2012-01-13 21:03:46.668676
1638	467	1636	3	9	4609	15	2012-01-13 21:03:46.668676
1636	1374	1636	9	5	3447	13	2012-01-13 21:03:46.668676
1646	982	1645	2	12	3414	3	2012-01-13 21:04:08.768688
1647	1314	1645	12	2	3861	10	2012-01-13 21:04:08.768688
1648	1175	1645	2	20	4147	12	2012-01-13 21:04:08.768688
1645	1379	1645	20	2	4484	16	2012-01-13 21:04:08.768688
1650	1334	1649	16	16	2803	20	2012-01-13 21:04:24.855158
1651	1113	1649	16	6	3231	18	2012-01-13 21:04:24.855158
1652	815	1649	6	20	5539	6	2012-01-13 21:04:24.855158
1649	1382	1649	20	16	5439	15	2012-01-13 21:04:24.855158
1677	1300	1676	17	11	3700	12	2012-01-13 21:06:52.130506
1678	712	1676	11	19	8008	1	2012-01-13 21:06:52.130506
1676	1404	1676	19	17	9091	4	2012-01-13 21:06:52.130506
1685	1020	1684	10	4	4803	17	2012-01-13 21:07:07.413716
1684	1407	1684	4	10	9422	7	2012-01-13 21:07:07.413716
1687	970	1686	16	4	9847	6	2012-01-13 21:07:24.80664
1688	1355	1686	4	4	3688	14	2012-01-13 21:07:24.80664
1686	1411	1686	4	16	7337	13	2012-01-13 21:07:24.80664
1700	688	1699	15	11	5978	9	2012-01-13 21:08:36.390255
1701	1365	1699	11	16	8018	7	2012-01-13 21:08:36.390255
1702	1415	1699	16	12	2582	2	2012-01-13 21:08:36.390255
1699	1419	1699	12	15	3271	16	2012-01-13 21:08:36.390255
1704	792	1703	9	12	2279	17	2012-01-13 21:08:46.660514
1705	1408	1703	12	15	752	10	2012-01-13 21:08:46.660514
1706	867	1703	15	1	2773	20	2012-01-13 21:08:46.660514
1703	1421	1703	1	9	4907	8	2012-01-13 21:08:46.660514
1752	1282	1751	8	8	8256	15	2012-01-13 21:13:32.104722
1753	1364	1751	8	8	3876	11	2012-01-13 21:13:32.104722
1754	1427	1751	8	13	5158	4	2012-01-13 21:13:32.104722
1751	1455	1751	13	8	9169	1	2012-01-13 21:13:32.104722
1950	1349	1948	16	2	7195	14	2012-01-13 21:32:07.513035
1948	1592	1948	2	2	3632	4	2012-01-13 21:32:07.513035
2303	1842	2302	5	1	4982	8	2012-01-13 22:19:56.217468
1952	728	1951	6	19	6714	13	2012-01-13 21:32:10.919457
1951	1593	1951	19	6	3421	10	2012-01-13 21:32:10.919457
1960	1450	1959	14	4	5209	8	2012-01-13 21:35:03.592563
1961	1590	1959	4	17	3223	18	2012-01-13 21:35:03.592563
1962	887	1959	17	1	104	16	2012-01-13 21:35:03.592563
1963	154	1959	1	16	394	3	2012-01-13 21:35:03.592563
1964	1453	1959	16	16	5255	9	2012-01-13 21:35:03.592563
1959	1610	1959	16	14	8101	1	2012-01-13 21:35:03.592563
1772	1463	1771	14	14	6506	20	2012-01-13 21:15:30.982275
1771	1468	1771	14	14	3739	7	2012-01-13 21:15:30.982275
1966	782	1965	12	1	961	1	2012-01-13 21:35:16.42628
1967	1301	1965	1	20	3289	14	2012-01-13 21:35:16.42628
1965	1612	1965	20	12	277	19	2012-01-13 21:35:16.42628
1969	898	1968	13	3	2044	9	2012-01-13 21:36:31.044638
1970	1583	1968	3	10	3966	12	2012-01-13 21:36:31.044638
1968	1618	1968	10	13	5679	18	2012-01-13 21:36:31.044638
1977	1609	1976	7	13	8288	4	2012-01-13 21:38:52.267895
1978	1381	1976	13	6	5810	17	2012-01-13 21:38:52.267895
1979	1622	1976	6	5	5066	11	2012-01-13 21:38:52.267895
1980	1323	1976	5	15	6560	2	2012-01-13 21:38:52.267895
1981	1085	1976	15	1	3327	15	2012-01-13 21:38:52.267895
1976	1630	1976	1	7	9286	1	2012-01-13 21:38:52.267895
1983	1128	1982	18	15	5393	15	2012-01-13 21:39:18.691788
1982	1633	1982	15	18	6555	20	2012-01-13 21:39:18.691788
1992	773	1991	17	17	8491	6	2012-01-13 21:39:56.691615
1993	1623	1991	17	16	7694	5	2012-01-13 21:39:56.691615
1994	1445	1991	16	1	1858	1	2012-01-13 21:39:56.691615
1991	1639	1991	1	17	6105	11	2012-01-13 21:39:56.691615
1996	1388	1995	10	18	7803	13	2012-01-13 21:40:09.542595
1997	1595	1995	18	9	3786	15	2012-01-13 21:40:09.542595
1808	1106	1807	14	8	8627	4	2012-01-13 21:17:49.070181
1807	1485	1807	8	14	9625	10	2012-01-13 21:17:49.070181
1810	958	1809	20	14	8136	6	2012-01-13 21:18:19.902239
1809	1489	1809	14	20	7042	9	2012-01-13 21:18:19.902239
1812	478	1811	5	17	7689	6	2012-01-13 21:19:46.022743
1813	1446	1811	17	13	4933	15	2012-01-13 21:19:46.022743
1814	1488	1811	13	3	6548	8	2012-01-13 21:19:46.022743
1811	1498	1811	3	5	103	10	2012-01-13 21:19:46.022743
1816	1219	1815	12	11	9442	7	2012-01-13 21:19:51.641593
1817	1472	1815	11	19	8008	19	2012-01-13 21:19:51.641593
1815	1499	1815	19	12	3488	9	2012-01-13 21:19:51.641593
1819	1393	1818	3	6	7275	12	2012-01-13 21:20:06.732521
1820	1210	1818	6	4	9426	1	2012-01-13 21:20:06.732521
1818	1501	1818	4	3	6295	10	2012-01-13 21:20:06.732521
1840	935	1839	15	18	8678	13	2012-01-13 21:21:15.009896
1841	1432	1839	18	5	1432	1	2012-01-13 21:21:15.009896
1839	1510	1839	5	15	6143	9	2012-01-13 21:21:15.009896
1848	1493	1847	20	10	4168	15	2012-01-13 21:22:29.540362
1849	1516	1847	10	19	1615	20	2012-01-13 21:22:29.540362
1847	1520	1847	19	20	2249	18	2012-01-13 21:22:29.540362
1856	1497	1855	18	1	2997	4	2012-01-13 21:22:46.291382
1857	1492	1855	1	15	4902	8	2012-01-13 21:22:46.291382
1858	1270	1855	15	10	8448	5	2012-01-13 21:22:46.291382
1855	1523	1855	10	18	4972	14	2012-01-13 21:22:46.291382
1867	1253	1866	13	2	3782	7	2012-01-13 21:24:03.978268
1868	1490	1866	2	8	3791	8	2012-01-13 21:24:03.978268
1869	975	1866	8	17	8436	19	2012-01-13 21:24:03.978268
1866	1535	1866	17	13	2240	18	2012-01-13 21:24:03.978268
1879	1297	1878	9	11	4893	20	2012-01-13 21:24:59.692668
1880	1504	1878	11	16	5621	15	2012-01-13 21:24:59.692668
1881	1529	1878	16	13	1137	12	2012-01-13 21:24:59.692668
1882	177	1878	13	17	4353	19	2012-01-13 21:24:59.692668
1883	1535	1878	17	20	2593	18	2012-01-13 21:24:59.692668
1878	1542	1878	20	9	7837	9	2012-01-13 21:24:59.692668
1893	1464	1892	4	13	2081	18	2012-01-13 21:26:55.421217
1894	1253	1892	13	2	4474	7	2012-01-13 21:26:55.421217
1892	1552	1892	2	4	5774	5	2012-01-13 21:26:55.421217
1933	1151	1932	4	7	1297	20	2012-01-13 21:30:07.752403
1934	1562	1932	7	7	7398	2	2012-01-13 21:30:07.752403
1935	1563	1932	7	3	3630	19	2012-01-13 21:30:07.752403
1932	1577	1932	3	4	5591	9	2012-01-13 21:30:07.752403
1946	1380	1945	2	9	8922	14	2012-01-13 21:31:28.278476
1947	1500	1945	9	3	3262	8	2012-01-13 21:31:28.278476
1945	1588	1945	3	2	6900	7	2012-01-13 21:31:28.278476
1998	1582	1995	9	14	5270	2	2012-01-13 21:40:09.542595
1999	1526	1995	14	6	4244	18	2012-01-13 21:40:09.542595
2000	1127	1995	6	19	5289	4	2012-01-13 21:40:09.542595
2001	1620	1995	19	13	4580	2	2012-01-13 21:40:09.542595
1995	1641	1995	13	10	4306	7	2012-01-13 21:40:09.542595
2003	1195	2002	19	13	6982	2	2012-01-13 21:40:19.025745
2004	1641	2002	13	13	5608	7	2012-01-13 21:40:19.025745
2005	833	2002	13	19	2248	17	2012-01-13 21:40:19.025745
2006	770	2002	19	11	2030	4	2012-01-13 21:40:19.025745
2007	1638	2002	11	16	3127	20	2012-01-13 21:40:19.025745
2008	1217	2002	16	5	1661	10	2012-01-13 21:40:19.025745
2009	1608	2002	5	9	392	16	2012-01-13 21:40:19.025745
2002	1643	2002	9	19	2220	3	2012-01-13 21:40:19.025745
2023	1317	2022	16	6	5570	4	2012-01-13 21:42:00.874568
2024	1632	2022	6	3	7272	6	2012-01-13 21:42:00.874568
2022	1653	2022	3	16	759	3	2012-01-13 21:42:00.874568
2026	1230	2025	3	2	3513	10	2012-01-13 21:42:04.6439
2027	1383	2025	2	1	4411	9	2012-01-13 21:42:04.6439
2028	1617	2025	1	17	8328	19	2012-01-13 21:42:04.6439
2029	1471	2025	17	3	2996	15	2012-01-13 21:42:04.6439
2030	1564	2025	3	3	2069	18	2012-01-13 21:42:04.6439
2025	1654	2025	3	3	8432	3	2012-01-13 21:42:04.6439
2032	850	2031	18	15	9839	7	2012-01-13 21:43:25.042452
2031	1661	2031	15	18	7929	12	2012-01-13 21:43:25.042452
2037	1553	2036	14	9	5480	7	2012-01-13 21:43:40.211554
2036	1664	2036	9	14	5108	20	2012-01-13 21:43:40.211554
2039	951	2038	18	5	4336	9	2012-01-13 21:43:43.506304
2040	1640	2038	5	20	7288	20	2012-01-13 21:43:43.506304
2041	1604	2038	20	14	9350	12	2012-01-13 21:43:43.506304
2042	1441	2038	14	20	5558	7	2012-01-13 21:43:43.506304
2038	1665	2038	20	18	3149	3	2012-01-13 21:43:43.506304
2044	1665	2043	20	19	3423	3	2012-01-13 21:44:10.69988
2045	1615	2043	19	19	3691	15	2012-01-13 21:44:10.69988
2043	1668	2043	19	20	6285	7	2012-01-13 21:44:10.69988
2047	1648	2046	5	2	4675	19	2012-01-13 21:44:38.72792
2046	1670	2046	2	5	7922	11	2012-01-13 21:44:38.72792
2052	1659	2051	6	5	7608	17	2012-01-13 21:45:10.249457
2053	1336	2051	5	3	6258	11	2012-01-13 21:45:10.249457
2051	1674	2051	3	6	1831	18	2012-01-13 21:45:10.249457
2059	1550	2058	14	14	9181	6	2012-01-13 21:45:37.741246
2060	1677	2058	14	17	5413	13	2012-01-13 21:45:37.741246
2061	1229	2058	17	1	843	5	2012-01-13 21:45:37.741246
2058	1678	2058	1	14	5255	20	2012-01-13 21:45:37.741246
2066	1513	2065	6	17	8296	12	2012-01-13 21:46:20.945515
2067	1103	2065	17	12	3410	8	2012-01-13 21:46:20.945515
2065	1683	2065	12	6	2884	3	2012-01-13 21:46:20.945515
2072	1681	2071	18	16	9523	1	2012-01-13 21:46:30.949633
2071	1685	2071	16	18	8962	8	2012-01-13 21:46:30.949633
2074	1575	2073	8	18	5364	13	2012-01-13 21:46:41.306923
2073	1686	2073	18	8	7717	8	2012-01-13 21:46:41.306923
2076	710	2075	4	7	8470	1	2012-01-13 21:46:50.559258
2075	1688	2075	7	4	9433	3	2012-01-13 21:46:50.559258
2078	1530	2077	6	2	5445	6	2012-01-13 21:46:53.438864
2079	1519	2077	2	20	1935	11	2012-01-13 21:46:53.438864
2077	1689	2077	20	6	2219	15	2012-01-13 21:46:53.438864
2081	1439	2080	4	8	4459	13	2012-01-13 21:47:03.782747
2080	1690	2080	8	4	1330	18	2012-01-13 21:47:03.782747
2090	1030	2089	11	20	476	11	2012-01-13 21:47:18.541476
2091	1689	2089	20	13	7698	15	2012-01-13 21:47:18.541476
2092	1462	2089	13	8	3850	1	2012-01-13 21:47:18.541476
2093	1518	2089	8	9	2774	4	2012-01-13 21:47:18.541476
2089	1692	2089	9	11	6741	8	2012-01-13 21:47:18.541476
2095	811	2094	17	20	5926	15	2012-01-13 21:48:27.662169
2096	1694	2094	20	15	7092	12	2012-01-13 21:48:27.662169
2097	1186	2094	15	2	9182	7	2012-01-13 21:48:27.662169
2094	1701	2094	2	17	9700	2	2012-01-13 21:48:27.662169
2107	1358	2106	15	16	3318	7	2012-01-13 21:51:28.151919
2106	1714	2106	16	15	9705	12	2012-01-13 21:51:28.151919
2111	105	2110	4	4	9372	6	2012-01-13 21:51:52.482874
2112	1651	2110	4	18	358	10	2012-01-13 21:51:52.482874
2113	1306	2110	18	8	4733	8	2012-01-13 21:51:52.482874
2114	1625	2110	8	1	5245	4	2012-01-13 21:51:52.482874
2115	1700	2110	1	14	2993	11	2012-01-13 21:51:52.482874
2110	1718	2110	14	4	6431	19	2012-01-13 21:51:52.482874
2117	1470	2116	13	12	7310	13	2012-01-13 21:51:59.101665
2118	1348	2116	12	11	3759	5	2012-01-13 21:51:59.101665
2116	1719	2116	11	13	2845	4	2012-01-13 21:51:59.101665
2123	1628	2122	4	1	9563	11	2012-01-13 21:52:28.460667
2124	1657	2122	1	13	8091	14	2012-01-13 21:52:28.460667
2122	1722	2122	13	4	9564	4	2012-01-13 21:52:28.460667
2126	1197	2125	3	5	6877	15	2012-01-13 21:52:52.458585
2125	1725	2125	5	3	2354	3	2012-01-13 21:52:52.458585
2128	991	2127	18	16	9816	1	2012-01-13 21:53:14.128272
2127	1728	2127	16	18	5801	12	2012-01-13 21:53:14.128272
2130	599	2129	14	17	3939	15	2012-01-13 21:53:30.795545
2129	1731	2129	17	14	6486	20	2012-01-13 21:53:30.795545
2304	882	2302	1	10	1886	9	2012-01-13 22:19:56.217468
2305	1788	2302	10	2	9099	15	2012-01-13 22:19:56.217468
2306	1540	2302	2	2	2287	7	2012-01-13 22:19:56.217468
2307	1865	2302	2	12	7688	14	2012-01-13 22:19:56.217468
2302	1901	2302	12	5	6899	2	2012-01-13 22:19:56.217468
2681	985	2680	14	9	4257	20	2012-01-13 23:14:37.785046
2136	1708	2135	12	8	611	1	2012-01-13 21:55:00.474442
2137	1737	2135	8	10	159	2	2012-01-13 21:55:00.474442
2138	1717	2135	10	1	3499	18	2012-01-13 21:55:00.474442
2135	1741	2135	1	12	1450	14	2012-01-13 21:55:00.474442
2682	1989	2680	9	9	5534	5	2012-01-13 23:14:37.785046
2140	1712	2139	10	8	4634	1	2012-01-13 21:55:16.837897
2141	1737	2139	8	13	3631	2	2012-01-13 21:55:16.837897
2142	876	2139	13	8	2512	14	2012-01-13 21:55:16.837897
2139	1742	2139	8	10	5076	7	2012-01-13 21:55:16.837897
2152	1596	2151	17	15	9585	17	2012-01-13 21:58:58.475773
2151	1764	2151	15	17	2722	10	2012-01-13 21:58:58.475773
2154	1090	2153	7	6	8861	15	2012-01-13 21:59:02.328133
2153	1765	2153	6	7	3932	9	2012-01-13 21:59:02.328133
2166	1750	2165	10	11	8813	17	2012-01-13 21:59:47.518105
2167	1465	2165	11	12	6264	13	2012-01-13 21:59:47.518105
2165	1769	2165	12	10	5315	7	2012-01-13 21:59:47.518105
2173	1662	2172	14	18	6801	20	2012-01-13 22:01:06.207045
2174	516	2172	18	18	6546	6	2012-01-13 22:01:06.207045
2172	1777	2172	18	14	6577	9	2012-01-13 22:01:06.207045
2181	1771	2180	3	17	4182	7	2012-01-13 22:02:15.307674
2180	1786	2180	17	3	5821	17	2012-01-13 22:02:15.307674
2183	1100	2182	10	10	6027	14	2012-01-13 22:02:53.881687
2182	1791	2182	10	10	7697	7	2012-01-13 22:02:53.881687
2185	1660	2184	4	9	9559	2	2012-01-13 22:03:13.415977
2186	1780	2184	9	16	7696	6	2012-01-13 22:03:13.415977
2184	1795	2184	16	4	9202	20	2012-01-13 22:03:13.415977
2188	1763	2187	16	2	9874	2	2012-01-13 22:03:25.147371
2189	1760	2187	2	13	4686	5	2012-01-13 22:03:25.147371
2190	1756	2187	13	5	1961	20	2012-01-13 22:03:25.147371
2187	1798	2187	5	16	3180	3	2012-01-13 22:03:25.147371
2192	1805	2191	15	11	1472	10	2012-01-13 22:04:54.623318
2191	1809	2191	11	15	9934	1	2012-01-13 22:04:54.623318
2200	1776	2199	1	2	5971	12	2012-01-13 22:06:40.314259
2201	1753	2199	2	15	7327	7	2012-01-13 22:06:40.314259
2199	1819	2199	15	1	2341	8	2012-01-13 22:06:40.314259
2203	1749	2202	10	4	6990	1	2012-01-13 22:06:48.558781
2202	1821	2202	4	10	6721	11	2012-01-13 22:06:48.558781
2205	1748	2204	6	12	9603	19	2012-01-13 22:06:52.535079
2206	1307	2204	12	18	5024	17	2012-01-13 22:06:52.535079
2204	1822	2204	18	6	4691	11	2012-01-13 22:06:52.535079
2210	1708	2209	12	14	2508	1	2012-01-13 22:07:16.631201
2211	1733	2209	14	15	7668	13	2012-01-13 22:07:16.631201
2209	1826	2209	15	12	4158	14	2012-01-13 22:07:16.631201
2213	1635	2212	7	13	3832	7	2012-01-13 22:07:49.506895
2214	1794	2212	13	13	1824	19	2012-01-13 22:07:49.506895
2212	1829	2212	13	7	9812	13	2012-01-13 22:07:49.506895
2216	1667	2215	15	10	1210	7	2012-01-13 22:08:01.591477
2215	1830	2215	10	15	3779	6	2012-01-13 22:08:01.591477
2233	1385	2232	10	3	6452	13	2012-01-13 22:12:12.312673
2232	1853	2232	3	10	613	16	2012-01-13 22:12:12.312673
2235	583	2234	18	20	6315	5	2012-01-13 22:13:01.909331
2234	1857	2234	20	18	9634	17	2012-01-13 22:13:01.909331
2237	410	2236	8	1	149	16	2012-01-13 22:13:14.54634
2238	1286	2236	1	8	6770	5	2012-01-13 22:13:14.54634
2236	1859	2236	8	8	3805	14	2012-01-13 22:13:14.54634
2248	1161	2247	17	18	5628	15	2012-01-13 22:13:45.532156
2249	1729	2247	18	3	7533	12	2012-01-13 22:13:45.532156
2250	1347	2247	3	6	2960	9	2012-01-13 22:13:45.532156
2251	1841	2247	6	1	8169	5	2012-01-13 22:13:45.532156
2252	1854	2247	1	14	7509	1	2012-01-13 22:13:45.532156
2247	1863	2247	14	17	6223	17	2012-01-13 22:13:45.532156
2290	1818	2289	12	3	6883	10	2012-01-13 22:19:16.816246
2291	1646	2289	3	15	9879	11	2012-01-13 22:19:16.816246
2292	1851	2289	15	5	9151	18	2012-01-13 22:19:16.816246
2289	1895	2289	5	12	9499	12	2012-01-13 22:19:16.816246
2294	1711	2293	3	5	9704	20	2012-01-13 22:19:34.404559
2295	1798	2293	5	5	1067	3	2012-01-13 22:19:34.404559
2293	1897	2293	5	3	5904	9	2012-01-13 22:19:34.404559
2297	1816	2296	19	12	4308	19	2012-01-13 22:19:47.660565
2298	1806	2296	12	3	5446	8	2012-01-13 22:19:47.660565
2299	1498	2296	3	10	3262	10	2012-01-13 22:19:47.660565
2296	1899	2296	10	19	8923	14	2012-01-13 22:19:47.660565
2301	1328	2300	5	3	9851	13	2012-01-13 22:19:51.756245
2300	1900	2300	3	5	8185	12	2012-01-13 22:19:51.756245
2683	2174	2680	9	7	6051	19	2012-01-13 23:14:37.785046
2684	1757	2680	7	11	7315	6	2012-01-13 23:14:37.785046
2311	1843	2310	17	4	1931	11	2012-01-13 22:21:47.996638
2312	1704	2310	4	3	4544	13	2012-01-13 22:21:47.996638
2310	1912	2310	3	17	8916	15	2012-01-13 22:21:47.996638
2680	2200	2680	11	14	1874	12	2012-01-13 23:14:37.785046
2318	1823	2317	12	5	5571	18	2012-01-13 22:23:24.686187
2319	886	2317	5	5	2071	17	2012-01-13 22:23:24.686187
2317	1919	2317	5	12	5569	1	2012-01-13 22:23:24.686187
2333	1745	2332	11	1	7373	4	2012-01-13 22:24:40.554445
2334	1695	2332	1	12	4346	12	2012-01-13 22:24:40.554445
2332	1927	2332	12	11	1462	3	2012-01-13 22:24:40.554445
2336	361	2335	12	1	2693	9	2012-01-13 22:24:45.169604
2337	1864	2335	1	4	9402	8	2012-01-13 22:24:45.169604
2338	1629	2335	4	12	9357	13	2012-01-13 22:24:45.169604
2335	1928	2335	12	12	3555	12	2012-01-13 22:24:45.169604
2345	1915	2344	17	2	9100	7	2012-01-13 22:25:25.203898
2346	1792	2344	2	20	2397	10	2012-01-13 22:25:25.203898
2347	1425	2344	20	4	9259	6	2012-01-13 22:25:25.203898
2344	1933	2344	4	17	4086	19	2012-01-13 22:25:25.203898
2349	981	2348	11	19	7485	6	2012-01-13 22:25:42.877854
2348	1936	2348	19	11	2232	1	2012-01-13 22:25:42.877854
2351	1702	2350	4	15	8931	18	2012-01-13 22:26:18.741314
2350	1941	2350	15	4	1293	5	2012-01-13 22:26:18.741314
2353	543	2352	16	7	6007	14	2012-01-13 22:26:23.357693
2352	1942	2352	7	16	6807	18	2012-01-13 22:26:23.357693
2364	1811	2363	13	18	3847	3	2012-01-13 22:27:57.159744
2365	1907	2363	18	8	6611	9	2012-01-13 22:27:57.159744
2366	1600	2363	8	1	9805	1	2012-01-13 22:27:57.159744
2367	1923	2363	1	4	6788	8	2012-01-13 22:27:57.159744
2368	1222	2363	4	7	4051	2	2012-01-13 22:27:57.159744
2363	1953	2363	7	13	5077	20	2012-01-13 22:27:57.159744
2372	439	2371	19	16	5365	15	2012-01-13 22:30:03.587727
2373	1956	2371	16	7	3357	17	2012-01-13 22:30:03.587727
2374	1892	2371	7	16	5467	4	2012-01-13 22:30:03.587727
2371	1964	2371	16	19	9163	8	2012-01-13 22:30:03.587727
2376	1269	2375	9	10	6235	15	2012-01-13 22:30:38.777487
2375	1967	2375	10	9	7502	12	2012-01-13 22:30:38.777487
2378	1910	2377	18	11	3668	10	2012-01-13 22:31:05.184536
2379	913	2377	11	9	2515	5	2012-01-13 22:31:05.184536
2380	1958	2377	9	1	9547	18	2012-01-13 22:31:05.184536
2381	1741	2377	1	19	3146	14	2012-01-13 22:31:05.184536
2377	1969	2377	19	18	7728	17	2012-01-13 22:31:05.184536
2383	1849	2382	13	4	2845	17	2012-01-13 22:31:10.265584
2384	1838	2382	4	18	3266	18	2012-01-13 22:31:10.265584
2385	1880	2382	18	3	4191	2	2012-01-13 22:31:10.265584
2382	1970	2382	3	13	5807	7	2012-01-13 22:31:10.265584
2387	1827	2386	11	18	8481	11	2012-01-13 22:31:18.750017
2386	1971	2386	18	11	5505	9	2012-01-13 22:31:18.750017
2389	1903	2388	10	14	4259	9	2012-01-13 22:31:23.461962
2390	1534	2388	14	10	7887	10	2012-01-13 22:31:23.461962
2391	1743	2388	10	6	9765	1	2012-01-13 22:31:23.461962
2388	1972	2388	6	10	6131	3	2012-01-13 22:31:23.461962
2393	1086	2392	9	20	6741	14	2012-01-13 22:31:28.243968
2394	1963	2392	20	13	4909	17	2012-01-13 22:31:28.243968
2395	1758	2392	13	15	6510	2	2012-01-13 22:31:28.243968
2392	1973	2392	15	9	4098	20	2012-01-13 22:31:28.243968
2397	1245	2396	20	4	8236	6	2012-01-13 22:31:37.116635
2396	1974	2396	4	20	9128	7	2012-01-13 22:31:37.116635
2405	1487	2404	13	3	2363	20	2012-01-13 22:32:25.521236
2404	1979	2404	3	13	9778	9	2012-01-13 22:32:25.521236
2407	477	2406	4	10	8005	6	2012-01-13 22:32:29.633414
2408	1955	2406	10	10	1176	7	2012-01-13 22:32:29.633414
2406	1980	2406	10	4	7014	17	2012-01-13 22:32:29.633414
2413	1975	2412	5	10	5372	4	2012-01-13 22:33:36.442073
2414	1607	2412	10	11	5372	6	2012-01-13 22:33:36.442073
2415	1987	2412	11	15	3908	10	2012-01-13 22:33:36.442073
2416	1876	2412	15	17	8288	13	2012-01-13 22:33:36.442073
2412	1988	2412	17	5	7493	15	2012-01-13 22:33:36.442073
2418	1966	2417	5	19	3128	2	2012-01-13 22:33:54.172716
2419	1986	2417	19	19	3960	20	2012-01-13 22:33:54.172716
2420	1767	2417	19	17	7377	10	2012-01-13 22:33:54.172716
2421	1949	2417	17	15	8075	17	2012-01-13 22:33:54.172716
2422	564	2417	15	17	2837	14	2012-01-13 22:33:54.172716
2417	1990	2417	17	5	5641	12	2012-01-13 22:33:54.172716
2424	1707	2423	13	2	2264	5	2012-01-13 22:34:49.589864
2425	1870	2423	2	7	7583	8	2012-01-13 22:34:49.589864
2426	1613	2423	7	11	5546	18	2012-01-13 22:34:49.589864
2427	1885	2423	11	16	2947	2	2012-01-13 22:34:49.589864
2423	1996	2423	16	13	4087	17	2012-01-13 22:34:49.589864
2429	1911	2428	20	5	9083	1	2012-01-13 22:35:03.222279
2430	1946	2428	5	16	6843	8	2012-01-13 22:35:03.222279
2431	327	2428	16	3	2134	11	2012-01-13 22:35:03.222279
2432	1937	2428	3	9	8839	5	2012-01-13 22:35:03.222279
2428	1998	2428	9	20	7781	4	2012-01-13 22:35:03.222279
3061	2445	3060	4	18	7501	19	2012-01-14 00:30:48.691713
2686	1959	2685	10	10	2028	8	2012-01-13 23:15:04.637681
2443	2005	2442	12	8	1766	17	2012-01-13 22:37:57.819861
2442	2010	2442	8	12	5506	1	2012-01-13 22:37:57.819861
2445	2014	2444	8	20	8959	2	2012-01-13 22:39:29.112443
2446	653	2444	20	12	3247	13	2012-01-13 22:39:29.112443
2444	2019	2444	12	8	7284	17	2012-01-13 22:39:29.112443
2448	604	2447	6	7	6574	14	2012-01-13 22:40:10.634592
2447	2022	2447	7	6	3030	5	2012-01-13 22:40:10.634592
2463	1977	2462	7	11	1670	9	2012-01-13 22:41:37.895851
2464	1945	2462	11	11	1844	11	2012-01-13 22:41:37.895851
2462	2030	2462	11	7	7274	7	2012-01-13 22:41:37.895851
2471	1814	2470	18	18	7527	19	2012-01-13 22:41:56.671563
2472	2018	2470	18	5	7194	6	2012-01-13 22:41:56.671563
2473	2017	2470	5	17	3646	7	2012-01-13 22:41:56.671563
2474	1997	2470	17	9	6553	18	2012-01-13 22:41:56.671563
2470	2032	2470	9	18	3601	11	2012-01-13 22:41:56.671563
2476	2003	2475	16	11	4154	10	2012-01-13 22:42:07.082431
2477	1341	2475	11	16	6096	5	2012-01-13 22:42:07.082431
2475	2034	2475	16	16	7872	18	2012-01-13 22:42:07.082431
2479	272	2478	18	1	3053	10	2012-01-13 22:42:11.686393
2478	2035	2478	1	18	7599	12	2012-01-13 22:42:11.686393
2488	767	2487	2	6	6606	1	2012-01-13 22:42:53.705007
2487	2040	2487	6	2	6599	20	2012-01-13 22:42:53.705007
2493	1438	2492	9	2	9617	6	2012-01-13 22:43:59.02046
2492	2048	2492	2	9	4082	1	2012-01-13 22:43:59.02046
2495	576	2494	10	19	1993	4	2012-01-13 22:44:23.066717
2496	2041	2494	19	18	8158	15	2012-01-13 22:44:23.066717
2494	2052	2494	18	10	5313	18	2012-01-13 22:44:23.066717
2501	1981	2500	6	1	1297	10	2012-01-13 22:44:53.100864
2500	2055	2500	1	6	8459	13	2012-01-13 22:44:53.100864
2503	1845	2502	14	10	6851	17	2012-01-13 22:45:02.30868
2502	2057	2502	10	14	5393	5	2012-01-13 22:45:02.30868
2505	978	2504	9	7	1775	1	2012-01-13 22:45:54.205153
2504	2064	2504	7	9	4138	18	2012-01-13 22:45:54.205153
2507	1868	2506	15	17	3006	17	2012-01-13 22:45:59.242466
2508	2037	2506	17	1	8077	5	2012-01-13 22:45:59.242466
2506	2065	2506	1	15	7818	7	2012-01-13 22:45:59.242466
2510	939	2509	4	2	8197	5	2012-01-13 22:46:03.673037
2509	2066	2509	2	4	5368	20	2012-01-13 22:46:03.673037
2515	1252	2514	6	7	2344	4	2012-01-13 22:46:26.689257
2514	2070	2514	7	6	9733	2	2012-01-13 22:46:26.689257
2522	638	2521	11	5	6362	15	2012-01-13 22:46:47.32745
2521	2072	2521	5	11	6740	12	2012-01-13 22:46:47.32745
2524	1191	2523	9	15	3291	17	2012-01-13 22:47:06.371562
2525	2021	2523	15	12	3960	9	2012-01-13 22:47:06.371562
2526	1939	2523	12	1	4559	13	2012-01-13 22:47:06.371562
2523	2075	2523	1	9	6099	1	2012-01-13 22:47:06.371562
2528	1109	2527	18	11	7913	13	2012-01-13 22:48:09.108512
2529	2042	2527	11	14	4105	14	2012-01-13 22:48:09.108512
2527	2080	2527	14	18	3919	12	2012-01-13 22:48:09.108512
2531	820	2530	8	9	5223	5	2012-01-13 22:48:41.235372
2530	2083	2530	9	8	2549	10	2012-01-13 22:48:41.235372
2533	2078	2532	5	8	7801	8	2012-01-13 22:48:46.051158
2534	1621	2532	8	9	9267	13	2012-01-13 22:48:46.051158
2535	2060	2532	9	4	5072	18	2012-01-13 22:48:46.051158
2536	1871	2532	4	16	1906	19	2012-01-13 22:48:46.051158
2532	2084	2532	16	5	9583	5	2012-01-13 22:48:46.051158
2548	1494	2547	10	5	6541	8	2012-01-13 22:50:20.889222
2547	2089	2547	5	10	6178	9	2012-01-13 22:50:20.889222
2550	763	2549	5	4	2334	17	2012-01-13 22:51:04.479666
2549	2092	2549	4	5	5753	18	2012-01-13 22:51:04.479666
2552	1050	2551	2	20	6048	17	2012-01-13 22:51:34.768367
2553	2082	2551	20	14	5771	6	2012-01-13 22:51:34.768367
2551	2094	2551	14	2	2542	12	2012-01-13 22:51:34.768367
2571	629	2570	8	9	5302	6	2012-01-13 22:53:21.594722
2570	2103	2570	9	8	4391	2	2012-01-13 22:53:21.594722
2573	2093	2572	6	14	7852	11	2012-01-13 22:53:51.983339
2572	2106	2572	14	6	7332	15	2012-01-13 22:53:51.983339
2584	2091	2583	18	2	4647	5	2012-01-13 22:55:02.050562
2585	2074	2583	2	6	3663	20	2012-01-13 22:55:02.050562
2586	2110	2583	6	3	2530	3	2012-01-13 22:55:02.050562
2587	2013	2583	3	6	6103	1	2012-01-13 22:55:02.050562
2588	1531	2583	6	10	3383	11	2012-01-13 22:55:02.050562
2583	2111	2583	10	18	8335	12	2012-01-13 22:55:02.050562
2594	2090	2593	14	13	8997	20	2012-01-13 22:57:47.99853
2595	946	2593	13	19	7125	6	2012-01-13 22:57:47.99853
2593	2124	2593	19	14	511	15	2012-01-13 22:57:47.99853
2601	2054	2600	20	19	2755	10	2012-01-13 22:58:29.670371
2602	2121	2600	19	16	5287	3	2012-01-13 22:58:29.670371
2603	1699	2600	16	3	5052	14	2012-01-13 22:58:29.670371
2600	2129	2600	3	20	2601	8	2012-01-13 22:58:29.670371
2687	2006	2685	10	6	2925	9	2012-01-13 23:15:04.637681
2688	2163	2685	6	3	9681	1	2012-01-13 23:15:04.637681
2685	2202	2685	3	10	3606	15	2012-01-13 23:15:04.637681
3062	2461	3060	18	13	7478	7	2012-01-14 00:30:48.691713
2690	1888	2689	2	2	5391	19	2012-01-13 23:15:04.637681
2691	1346	2689	2	11	8062	6	2012-01-13 23:15:04.637681
2692	2200	2689	11	14	4922	12	2012-01-13 23:15:04.637681
2611	2028	2610	12	2	7872	11	2012-01-13 23:00:18.37957
2612	1597	2610	2	9	6067	5	2012-01-13 23:00:18.37957
2610	2137	2610	9	12	5962	3	2012-01-13 23:00:18.37957
2693	1889	2689	14	5	6730	18	2012-01-13 23:15:04.637681
2694	2188	2689	5	3	7246	1	2012-01-13 23:15:04.637681
2689	2202	2689	3	2	1268	15	2012-01-13 23:15:04.637681
2701	960	2700	7	8	4797	5	2012-01-13 23:16:57.714412
2702	1917	2700	8	9	4048	8	2012-01-13 23:16:57.714412
2703	2146	2700	9	6	9560	19	2012-01-13 23:16:57.714412
2624	832	2623	9	14	2766	15	2012-01-13 23:01:46.298052
2625	2135	2623	14	11	7432	9	2012-01-13 23:01:46.298052
2626	1831	2623	11	11	7281	7	2012-01-13 23:01:46.298052
2623	2144	2623	11	9	6385	10	2012-01-13 23:01:46.298052
2700	2210	2700	6	7	6177	10	2012-01-13 23:16:57.714412
2628	2062	2627	12	7	5021	2	2012-01-13 23:02:11.380349
2629	1727	2627	7	18	5370	14	2012-01-13 23:02:11.380349
2627	2147	2627	18	12	7101	6	2012-01-13 23:02:11.380349
2705	2098	2704	7	4	5401	4	2012-01-13 23:17:53.58731
2706	2207	2704	4	20	3493	15	2012-01-13 23:17:53.58731
2707	2085	2704	20	5	1150	1	2012-01-13 23:17:53.58731
2704	2214	2704	5	7	3374	17	2012-01-13 23:17:53.58731
2709	2183	2708	3	5	7208	2	2012-01-13 23:18:48.025037
2710	640	2708	5	10	2663	18	2012-01-13 23:18:48.025037
2708	2218	2708	10	3	5666	7	2012-01-13 23:18:48.025037
2712	801	2711	7	13	3972	11	2012-01-13 23:18:53.165934
2711	2219	2711	13	7	9947	7	2012-01-13 23:18:53.165934
2644	1800	2643	1	2	1207	9	2012-01-13 23:07:05.371689
2645	2145	2643	2	14	5405	3	2012-01-13 23:07:05.371689
2646	1448	2643	14	11	5469	14	2012-01-13 23:07:05.371689
2643	2168	2643	11	1	3732	10	2012-01-13 23:07:05.371689
2648	1591	2647	8	10	1476	13	2012-01-13 23:07:11.501389
2649	2016	2647	10	18	5220	6	2012-01-13 23:07:11.501389
2650	2160	2647	18	7	7371	19	2012-01-13 23:07:11.501389
2651	2122	2647	7	13	5262	18	2012-01-13 23:07:11.501389
2647	2169	2647	13	8	4926	14	2012-01-13 23:07:11.501389
2653	1166	2652	2	14	8020	14	2012-01-13 23:07:16.537285
2652	2170	2652	14	2	1502	9	2012-01-13 23:07:16.537285
2724	2119	2723	11	7	9666	17	2012-01-13 23:20:58.114033
2725	2220	2723	7	18	7571	18	2012-01-13 23:20:58.114033
2661	2086	2660	18	6	2090	4	2012-01-13 23:09:34.398047
2662	1515	2660	6	7	4454	6	2012-01-13 23:09:34.398047
2663	1551	2660	7	5	5537	13	2012-01-13 23:09:34.398047
2660	2178	2660	5	18	1578	9	2012-01-13 23:09:34.398047
2723	2226	2723	18	11	3701	9	2012-01-13 23:20:58.114033
2669	2050	2668	19	17	7538	17	2012-01-13 23:10:21.753202
2668	2182	2668	17	19	6636	9	2012-01-13 23:10:21.753202
2671	2165	2670	7	20	8698	19	2012-01-13 23:11:09.084343
2670	2185	2670	20	7	7311	11	2012-01-13 23:11:09.084343
2673	2179	2672	19	5	6295	17	2012-01-13 23:12:12.466297
2674	631	2672	5	7	4944	13	2012-01-13 23:12:12.466297
2675	2184	2672	7	16	8620	18	2012-01-13 23:12:12.466297
2672	2190	2672	16	19	5059	5	2012-01-13 23:12:12.466297
2742	2109	2741	16	7	6966	13	2012-01-13 23:24:21.771666
2741	2241	2741	7	16	8299	20	2012-01-13 23:24:21.771666
2756	2224	2755	20	15	9979	14	2012-01-13 23:26:35.982057
2755	2250	2755	15	20	1517	2	2012-01-13 23:26:35.982057
2767	1951	2766	8	4	678	19	2012-01-13 23:29:19.645779
2768	1858	2766	4	3	755	1	2012-01-13 23:29:19.645779
2769	2202	2766	3	16	1471	15	2012-01-13 23:29:19.645779
2770	2257	2766	16	3	5387	6	2012-01-13 23:29:19.645779
2766	2258	2766	3	8	1557	14	2012-01-13 23:29:19.645779
2819	2227	2818	18	13	6691	7	2012-01-13 23:39:06.445425
2820	1855	2818	13	3	3745	15	2012-01-13 23:39:06.445425
2821	2259	2818	3	2	9500	17	2012-01-13 23:39:06.445425
2822	1458	2818	2	11	934	10	2012-01-13 23:39:06.445425
2818	2293	2818	11	18	1066	6	2012-01-13 23:39:06.445425
2837	2242	2836	18	18	8916	17	2012-01-13 23:46:21.477221
2838	1213	2836	18	10	2318	19	2012-01-13 23:46:21.477221
2839	2235	2836	10	17	4188	4	2012-01-13 23:46:21.477221
2840	1921	2836	17	7	9653	18	2012-01-13 23:46:21.477221
2836	2309	2836	7	18	1540	2	2012-01-13 23:46:21.477221
2842	1679	2841	9	10	7892	2	2012-01-13 23:46:27.748285
2841	2310	2841	10	9	386	16	2012-01-13 23:46:27.748285
2844	1430	2843	7	13	9747	13	2012-01-13 23:46:59.58311
2843	2312	2843	13	7	9471	9	2012-01-13 23:46:59.58311
3063	1122	3060	13	14	2070	15	2012-01-14 00:30:48.691713
3060	2467	3060	14	4	4868	4	2012-01-14 00:30:48.691713
3503	2650	3502	8	5	3271	4	2012-01-14 02:16:45.608146
2848	1671	2847	13	10	2676	2	2012-01-13 23:47:49.769043
2849	2310	2847	10	20	501	16	2012-01-13 23:47:49.769043
2850	2153	2847	20	11	8380	10	2012-01-13 23:47:49.769043
2851	2293	2847	11	4	1293	6	2012-01-13 23:47:49.769043
2852	2073	2847	4	6	4001	7	2012-01-13 23:47:49.769043
2847	2315	2847	6	13	527	11	2012-01-13 23:47:49.769043
3502	2783	3502	5	8	9037	8	2012-01-14 02:16:45.608146
3505	2698	3504	3	4	2031	5	2012-01-14 02:17:01.862906
2857	573	2856	19	19	7227	6	2012-01-13 23:48:32.643527
2858	2260	2856	19	4	4471	4	2012-01-13 23:48:32.643527
2859	2043	2856	4	2	1027	12	2012-01-13 23:48:32.643527
2856	2319	2856	2	19	2513	17	2012-01-13 23:48:32.643527
2861	2225	2860	17	2	9026	11	2012-01-13 23:50:25.468008
2860	2328	2860	2	17	8781	12	2012-01-13 23:50:25.468008
2870	2162	2869	14	14	4085	14	2012-01-13 23:51:17.220713
2871	1930	2869	14	12	1315	7	2012-01-13 23:51:17.220713
2869	2332	2869	12	14	4218	8	2012-01-13 23:51:17.220713
2873	2318	2872	8	6	5675	15	2012-01-13 23:51:30.316819
2874	1802	2872	6	10	2003	4	2012-01-13 23:51:30.316819
2875	2151	2872	10	12	3728	9	2012-01-13 23:51:30.316819
2876	2255	2872	12	8	4715	18	2012-01-13 23:51:30.316819
2872	2333	2872	8	8	3250	12	2012-01-13 23:51:30.316819
2887	2295	2886	16	7	5555	17	2012-01-13 23:57:18.730333
2886	2354	2886	7	16	6663	1	2012-01-13 23:57:18.730333
2895	1931	2894	17	16	1529	6	2012-01-13 23:58:47.083443
2896	2326	2894	16	7	2055	10	2012-01-13 23:58:47.083443
2897	2337	2894	7	16	6639	13	2012-01-13 23:58:47.083443
2898	2112	2894	16	3	2563	2	2012-01-13 23:58:47.083443
2894	2358	2894	3	17	1175	19	2012-01-13 23:58:47.083443
2905	2166	2904	4	13	8882	5	2012-01-14 00:00:22.037065
2904	2364	2904	13	4	5710	10	2012-01-14 00:00:22.037065
2907	2069	2906	12	10	2422	1	2012-01-14 00:00:47.854862
2908	2274	2906	10	17	9743	19	2012-01-14 00:00:47.854862
2909	1580	2906	17	1	4399	7	2012-01-14 00:00:47.854862
2910	2324	2906	1	20	6475	8	2012-01-14 00:00:47.854862
2906	2366	2906	20	12	2814	9	2012-01-14 00:00:47.854862
2912	1005	2911	12	7	4934	6	2012-01-14 00:00:47.854862
2913	1215	2911	7	10	3066	13	2012-01-14 00:00:47.854862
2914	1730	2911	10	8	3152	18	2012-01-14 00:00:47.854862
2915	2350	2911	8	20	4947	8	2012-01-14 00:00:47.854862
2911	2366	2911	20	12	617	9	2012-01-14 00:00:47.854862
2922	1735	2921	17	9	7270	18	2012-01-14 00:03:02.345364
2923	2313	2921	9	11	3739	11	2012-01-14 00:03:02.345364
2924	2345	2921	11	17	4923	12	2012-01-14 00:03:02.345364
2921	2372	2921	17	17	1489	3	2012-01-14 00:03:02.345364
2935	2365	2934	16	16	5428	13	2012-01-14 00:05:08.844092
2936	2280	2934	16	6	2806	15	2012-01-14 00:05:08.844092
2937	1713	2934	6	16	4783	5	2012-01-14 00:05:08.844092
2934	2376	2934	16	16	289	2	2012-01-14 00:05:08.844092
2946	2372	2945	17	13	6061	3	2012-01-14 00:05:48.726932
2947	2342	2945	13	8	9753	19	2012-01-14 00:05:48.726932
2945	2379	2945	8	17	7920	12	2012-01-14 00:05:48.726932
2955	2366	2954	20	2	3724	9	2012-01-14 00:07:28.129819
2956	1221	2954	2	12	8265	6	2012-01-14 00:07:28.129819
2957	2323	2954	12	9	6228	19	2012-01-14 00:07:28.129819
2954	2384	2954	9	20	5778	8	2012-01-14 00:07:28.129819
2963	1454	2962	13	4	5359	6	2012-01-14 00:08:51.424643
2964	2213	2962	4	7	1890	2	2012-01-14 00:08:51.424643
2962	2387	2962	7	13	7782	13	2012-01-14 00:08:51.424643
2966	2362	2965	8	17	7103	1	2012-01-14 00:09:53.257522
2967	2275	2965	17	3	4176	6	2012-01-14 00:09:53.257522
2968	2258	2965	3	1	3399	14	2012-01-14 00:09:53.257522
2965	2390	2965	1	8	2068	5	2012-01-14 00:09:53.257522
2970	2344	2969	4	17	9946	5	2012-01-14 00:10:33.652874
2969	2394	2969	17	4	9085	12	2012-01-14 00:10:33.652874
2983	2292	2982	3	20	6213	5	2012-01-14 00:12:15.102401
2984	1925	2982	20	14	3383	15	2012-01-14 00:12:15.102401
2982	2400	2982	14	3	2716	8	2012-01-14 00:12:15.102401
2986	1599	2985	17	11	7353	6	2012-01-14 00:13:42.192461
2985	2407	2985	11	17	1221	10	2012-01-14 00:13:42.192461
2992	827	2991	16	1	4244	6	2012-01-14 00:14:39.016369
2993	2392	2991	1	19	5897	19	2012-01-14 00:14:39.016369
2991	2411	2991	19	16	4865	20	2012-01-14 00:14:39.016369
3004	2422	3003	9	12	9425	1	2012-01-14 00:21:41.953034
3005	2320	3003	12	20	1839	20	2012-01-14 00:21:41.953034
3006	2405	3003	20	2	3389	15	2012-01-14 00:21:41.953034
3003	2430	3003	2	9	3591	12	2012-01-14 00:21:41.953034
3010	2419	3009	6	14	9716	10	2012-01-14 00:22:34.489271
3009	2434	3009	14	6	7253	9	2012-01-14 00:22:34.489271
3506	2341	3504	4	11	3165	10	2012-01-14 02:17:01.862906
3507	2330	3504	11	9	538	20	2012-01-14 02:17:01.862906
3018	2100	3017	5	14	2326	11	2012-01-14 00:24:03.331502
3019	2325	3017	14	6	8059	15	2012-01-14 00:24:03.331502
3017	2438	3017	6	5	4111	5	2012-01-14 00:24:03.331502
3021	2352	3020	12	19	8989	1	2012-01-14 00:25:10.490133
3020	2442	3020	19	12	2759	17	2012-01-14 00:25:10.490133
3070	2453	3069	10	16	5956	13	2012-01-14 00:32:33.571775
3071	2463	3069	16	19	6213	11	2012-01-14 00:32:33.571775
3069	2473	3069	19	10	6274	8	2012-01-14 00:32:33.571775
3073	1315	3072	2	1	7624	13	2012-01-14 00:33:09.289874
3072	2475	3072	1	2	7542	10	2012-01-14 00:33:09.289874
3028	2215	3027	9	12	8782	2	2012-01-14 00:25:29.78719
3029	697	3027	12	1	8138	6	2012-01-14 00:25:29.78719
3027	2444	3027	1	9	3284	1	2012-01-14 00:25:29.78719
3075	278	3074	7	20	1082	4	2012-01-14 00:33:47.127908
3031	1144	3030	4	10	5524	18	2012-01-14 00:25:50.943987
3030	2446	3030	10	4	8172	12	2012-01-14 00:25:50.943987
3076	2008	3074	20	12	7328	5	2012-01-14 00:33:47.127908
3033	2451	3032	4	5	9619	1	2012-01-14 00:27:32.795919
3034	2171	3032	5	16	3552	11	2012-01-14 00:27:32.795919
3035	2393	3032	16	20	3590	3	2012-01-14 00:27:32.795919
3036	2355	3032	20	14	4846	18	2012-01-14 00:27:32.795919
3032	2452	3032	14	4	7300	19	2012-01-14 00:27:32.795919
3074	2477	3074	12	7	3197	1	2012-01-14 00:33:47.127908
3038	2284	3037	13	15	1664	20	2012-01-14 00:28:06.502198
3039	1810	3037	15	4	2787	13	2012-01-14 00:28:06.502198
3040	2414	3037	4	12	9782	19	2012-01-14 00:28:06.502198
3041	2340	3037	12	5	1206	9	2012-01-14 00:28:06.502198
3042	2439	3037	5	19	8338	8	2012-01-14 00:28:06.502198
3037	2454	3037	19	13	6211	4	2012-01-14 00:28:06.502198
3044	2189	3043	19	14	8325	15	2012-01-14 00:28:51.486492
3045	2448	3043	14	1	8790	20	2012-01-14 00:28:51.486492
3043	2456	3043	1	19	7998	9	2012-01-14 00:28:51.486492
3047	2381	3046	3	16	6908	10	2012-01-14 00:29:04.225053
3048	1335	3046	16	16	8763	13	2012-01-14 00:29:04.225053
3046	2457	3046	16	3	3323	16	2012-01-14 00:29:04.225053
3050	2431	3049	14	18	5417	2	2012-01-14 00:29:12.052234
3051	2368	3049	18	8	2286	10	2012-01-14 00:29:12.052234
3049	2458	3049	8	14	4935	18	2012-01-14 00:29:12.052234
3053	1351	3052	13	9	7484	5	2012-01-14 00:29:36.943006
3052	2460	3052	9	13	6862	15	2012-01-14 00:29:36.943006
3055	2406	3054	15	6	5076	4	2012-01-14 00:30:04.946206
3056	2276	3054	6	4	1696	18	2012-01-14 00:30:04.946206
3054	2462	3054	4	15	4400	8	2012-01-14 00:30:04.946206
3058	2347	3057	14	17	5925	11	2012-01-14 00:30:24.862132
3059	2049	3057	17	14	3586	12	2012-01-14 00:30:24.862132
3057	2464	3057	14	14	9430	20	2012-01-14 00:30:24.862132
3082	1890	3081	6	14	5356	17	2012-01-14 00:34:24.465528
3083	2290	3081	14	20	3685	4	2012-01-14 00:34:24.465528
3081	2480	3081	20	6	8023	5	2012-01-14 00:34:24.465528
3087	2271	3086	19	6	311	5	2012-01-14 00:38:20.397488
3088	2469	3086	6	8	8977	1	2012-01-14 00:38:20.397488
3086	2491	3086	8	19	614	14	2012-01-14 00:38:20.397488
3092	2059	3091	16	7	5422	20	2012-01-14 00:39:38.529843
3093	1256	3091	7	19	953	12	2012-01-14 00:39:38.529843
3094	2465	3091	19	19	3459	1	2012-01-14 00:39:38.529843
3091	2494	3091	19	16	1634	5	2012-01-14 00:39:38.529843
3112	2194	3111	12	12	5558	14	2012-01-14 00:43:35.780828
3111	2508	3111	12	12	1302	5	2012-01-14 00:43:35.780828
3114	1496	3113	20	6	8546	6	2012-01-14 00:44:49.071519
3113	2510	3113	6	20	6817	10	2012-01-14 00:44:49.071519
3128	2277	3127	20	5	4030	5	2012-01-14 00:45:23.928571
3127	2513	3127	5	20	9341	17	2012-01-14 00:45:23.928571
3135	2404	3134	17	3	6699	15	2012-01-14 00:48:14.344588
3136	2518	3134	3	15	4420	12	2012-01-14 00:48:14.344588
3137	1442	3134	15	16	7257	2	2012-01-14 00:48:14.344588
3134	2520	3134	16	17	3496	8	2012-01-14 00:48:14.344588
3152	2494	3151	19	13	4270	5	2012-01-14 00:50:29.584942
3153	2441	3151	13	6	1538	13	2012-01-14 00:50:29.584942
3151	2527	3151	6	19	2614	1	2012-01-14 00:50:29.584942
3161	2521	3160	1	8	6943	8	2012-01-14 00:51:03.396454
3162	2281	3160	8	4	4982	7	2012-01-14 00:51:03.396454
3160	2530	3160	4	1	3873	13	2012-01-14 00:51:03.396454
3164	2488	3163	5	4	9312	7	2012-01-14 00:51:10.409785
3163	2531	3163	4	5	5626	10	2012-01-14 00:51:10.409785
3168	2397	3167	3	3	7455	6	2012-01-14 00:51:40.260294
3169	2359	3167	3	6	9983	14	2012-01-14 00:51:40.260294
3167	2533	3167	6	3	4052	13	2012-01-14 00:51:40.260294
3174	2327	3173	20	19	2502	2	2012-01-14 00:52:28.24555
3175	2436	3173	19	15	9044	7	2012-01-14 00:52:28.24555
3176	2482	3173	15	12	9847	19	2012-01-14 00:52:28.24555
3177	1627	3173	12	14	3475	17	2012-01-14 00:52:28.24555
3173	2537	3173	14	20	7696	6	2012-01-14 00:52:28.24555
3508	2140	3504	9	11	7876	2	2012-01-14 02:17:01.862906
3504	2784	3504	11	3	4164	6	2012-01-14 02:17:01.862906
3969	2845	3968	19	14	4245	10	2012-01-14 04:41:49.482362
3510	2710	3509	11	16	4220	2	2012-01-14 02:17:18.816114
3509	2785	3509	16	11	6012	18	2012-01-14 02:17:18.816114
3968	3135	3968	14	19	9322	9	2012-01-14 04:41:49.482362
3971	1491	3970	8	10	8015	10	2012-01-14 04:42:52.441421
3970	3137	3970	10	8	3669	16	2012-01-14 04:42:52.441421
3211	2476	3210	9	20	7823	15	2012-01-14 00:57:12.4723
3210	2552	3210	20	9	3830	10	2012-01-14 00:57:12.4723
3213	2542	3212	7	6	4889	20	2012-01-14 00:57:26.652284
3214	2489	3212	6	17	9704	18	2012-01-14 00:57:26.652284
3212	2554	3212	17	7	3652	9	2012-01-14 00:57:26.652284
3216	2450	3215	18	18	3277	3	2012-01-14 00:57:33.797198
3217	1824	3215	18	20	359	5	2012-01-14 00:57:33.797198
3215	2555	3215	20	18	2372	12	2012-01-14 00:57:33.797198
3219	2212	3218	11	4	7919	6	2012-01-14 01:01:20.759551
3218	2564	3218	4	11	9374	19	2012-01-14 01:01:20.759551
3225	635	3224	15	2	3829	2	2012-01-14 01:04:54.082806
3224	2570	3224	2	15	5623	9	2012-01-14 01:04:54.082806
3227	2536	3226	4	2	9037	5	2012-01-14 01:05:37.896472
3226	2573	3226	2	4	6706	8	2012-01-14 01:05:37.896472
3245	2545	3244	10	19	5913	14	2012-01-14 01:07:31.623446
3246	2486	3244	19	16	1393	18	2012-01-14 01:07:31.623446
3244	2580	3244	16	10	5050	13	2012-01-14 01:07:31.623446
3258	1514	3257	9	15	6939	15	2012-01-14 01:08:37.826355
3259	2538	3257	15	6	5442	11	2012-01-14 01:08:37.826355
3260	2118	3257	6	5	6236	19	2012-01-14 01:08:37.826355
3257	2583	3257	5	9	4653	10	2012-01-14 01:08:37.826355
3277	2501	3276	17	9	6275	12	2012-01-14 01:11:58.560515
3278	270	3276	9	18	4089	15	2012-01-14 01:11:58.560515
3279	2576	3276	18	19	6038	6	2012-01-14 01:11:58.560515
3276	2592	3276	19	17	6722	18	2012-01-14 01:11:58.560515
3281	1027	3280	13	14	2781	13	2012-01-14 01:13:48.830005
3280	2597	3280	14	13	3112	3	2012-01-14 01:13:48.830005
3283	1572	3282	14	4	5474	6	2012-01-14 01:14:49.41845
3284	2543	3282	4	8	1569	11	2012-01-14 01:14:49.41845
3285	1736	3282	8	17	1216	17	2012-01-14 01:14:49.41845
3282	2601	3282	17	14	2699	5	2012-01-14 01:14:49.41845
3290	2604	3289	5	7	2858	3	2012-01-14 01:16:01.123253
3291	2264	3289	7	12	3473	6	2012-01-14 01:16:01.123253
3289	2606	3289	12	5	7187	12	2012-01-14 01:16:01.123253
3296	2132	3295	13	19	4978	11	2012-01-14 01:20:13.464249
3295	2619	3295	19	13	1743	10	2012-01-14 01:20:13.464249
3316	2594	3315	16	16	6407	15	2012-01-14 01:24:24.177833
3317	2423	3315	16	9	8825	6	2012-01-14 01:24:24.177833
3315	2632	3315	9	16	9622	7	2012-01-14 01:24:24.177833
3323	2596	3322	20	7	7053	8	2012-01-14 01:25:14.985818
3324	2496	3322	7	16	5547	11	2012-01-14 01:25:14.985818
3325	1754	3322	16	10	1884	18	2012-01-14 01:25:14.985818
3322	2635	3322	10	20	3503	13	2012-01-14 01:25:14.985818
3336	2611	3335	15	9	4042	17	2012-01-14 01:31:32.005205
3337	2556	3335	9	8	5737	19	2012-01-14 01:31:32.005205
3335	2653	3335	8	15	1762	3	2012-01-14 01:31:32.005205
3342	2572	3341	6	19	390	11	2012-01-14 01:31:54.88503
3341	2655	3341	19	6	1143	7	2012-01-14 01:31:54.88503
3348	2481	3347	11	11	5707	5	2012-01-14 01:32:44.355986
3347	2657	3347	11	11	7751	2	2012-01-14 01:32:44.355986
3350	2539	3349	11	13	7088	14	2012-01-14 01:33:10.456807
3351	1417	3349	13	17	1166	11	2012-01-14 01:33:10.456807
3352	2391	3349	17	14	7840	2	2012-01-14 01:33:10.456807
3349	2658	3349	14	11	2362	1	2012-01-14 01:33:10.456807
3364	1739	3363	17	12	9062	9	2012-01-14 01:34:56.589519
3365	2634	3363	12	8	9304	10	2012-01-14 01:34:56.589519
3366	2286	3363	8	10	4279	12	2012-01-14 01:34:56.589519
3367	2177	3363	10	9	3333	4	2012-01-14 01:34:56.589519
3368	2636	3363	9	12	6895	14	2012-01-14 01:34:56.589519
3363	2662	3363	12	17	1124	16	2012-01-14 01:34:56.589519
3370	2562	3369	18	12	2785	8	2012-01-14 01:35:05.145677
3369	2663	3369	12	18	6564	9	2012-01-14 01:35:05.145677
3372	2303	3371	11	16	3363	4	2012-01-14 01:36:39.169331
3373	2614	3371	16	1	6953	17	2012-01-14 01:36:39.169331
3371	2665	3371	1	11	4645	10	2012-01-14 01:36:39.169331
3375	841	3374	12	14	2600	2	2012-01-14 01:37:13.30649
3376	2658	3374	14	6	4578	1	2012-01-14 01:37:13.30649
3377	2642	3374	6	3	2783	17	2012-01-14 01:37:13.30649
3378	910	3374	3	2	3520	13	2012-01-14 01:37:13.30649
3379	2120	3374	2	13	6317	19	2012-01-14 01:37:13.30649
3374	2668	3374	13	12	272	3	2012-01-14 01:37:13.30649
3973	2522	3972	7	3	4675	7	2012-01-14 04:43:02.787694
3972	3138	3972	3	7	7940	5	2012-01-14 04:43:02.787694
3392	1740	3391	12	17	5818	4	2012-01-14 01:38:24.804832
3393	2669	3391	17	13	7606	19	2012-01-14 01:38:24.804832
3394	2668	3391	13	11	1448	3	2012-01-14 01:38:24.804832
3395	2432	3391	11	11	1232	1	2012-01-14 01:38:24.804832
3391	2672	3391	11	12	4006	20	2012-01-14 01:38:24.804832
3397	2459	3396	12	18	5150	14	2012-01-14 01:38:57.593469
3396	2674	3396	18	12	2396	8	2012-01-14 01:38:57.593469
3974	3139	3974	20	9	7254	6	2012-01-14 04:43:13.577782
3525	2509	3524	2	17	9645	20	2012-01-14 02:22:16.428414
3524	2800	3524	17	2	7759	3	2012-01-14 02:22:16.428414
3402	2655	3401	19	6	6514	7	2012-01-14 01:41:04.810828
3403	2572	3401	6	8	4659	11	2012-01-14 01:41:04.810828
3404	816	3401	8	15	8995	6	2012-01-14 01:41:04.810828
3401	2679	3401	15	19	4505	11	2012-01-14 01:41:04.810828
3527	2746	3526	14	19	3613	4	2012-01-14 02:22:33.140023
3528	2734	3526	19	20	6852	12	2012-01-14 02:22:33.140023
3529	2769	3526	20	10	5795	15	2012-01-14 02:22:33.140023
3526	2802	3526	10	14	6162	19	2012-01-14 02:22:33.140023
3410	2683	3409	7	11	7017	9	2012-01-14 01:44:20.863363
3411	2334	3409	11	14	1749	4	2012-01-14 01:44:20.863363
3409	2685	3409	14	7	5530	11	2012-01-14 01:44:20.863363
3413	2487	3412	8	8	7586	11	2012-01-14 01:45:59.058076
3412	2686	3412	8	8	4791	4	2012-01-14 01:45:59.058076
3415	2605	3414	6	1	7136	8	2012-01-14 01:46:06.56924
3414	2687	3414	1	6	9012	9	2012-01-14 01:46:06.56924
3534	2609	3533	16	2	8261	14	2012-01-14 02:23:57.858081
3533	2805	3533	1	16	5207	12	2012-01-14 02:23:57.858081
3423	2586	3422	4	2	5269	13	2012-01-14 01:48:14.187474
3422	2696	3422	2	4	8653	5	2012-01-14 01:48:14.187474
3425	2695	3424	20	6	7395	5	2012-01-14 01:50:27.783996
3426	2561	3424	6	11	2290	20	2012-01-14 01:50:27.783996
3427	2631	3424	11	8	3962	17	2012-01-14 01:50:27.783996
3424	2705	3424	8	20	1007	18	2012-01-14 01:50:27.783996
3429	2630	3428	8	15	3248	20	2012-01-14 01:50:43.605486
3430	2558	3428	15	17	8094	5	2012-01-14 01:50:43.605486
3428	2706	3428	17	8	3045	13	2012-01-14 01:50:43.605486
3432	2012	3431	7	12	8031	13	2012-01-14 01:50:50.988089
3431	2707	3431	12	7	9454	12	2012-01-14 01:50:50.988089
3436	2238	3435	8	5	494	9	2012-01-14 01:52:22.572226
3437	2708	3435	5	7	9754	2	2012-01-14 01:52:22.572226
3438	2567	3435	7	13	4179	1	2012-01-14 01:52:22.572226
3435	2713	3435	13	8	5417	15	2012-01-14 01:52:22.572226
3440	2703	3439	2	3	7166	15	2012-01-14 01:52:38.874447
3441	2640	3439	3	5	6261	12	2012-01-14 01:52:38.874447
3442	1327	3439	5	16	8502	11	2012-01-14 01:52:38.874447
3443	2116	3439	16	11	3774	17	2012-01-14 01:52:38.874447
3439	2715	3439	11	2	2852	8	2012-01-14 01:52:38.874447
3445	2593	3444	15	11	7178	12	2012-01-14 01:52:46.781198
3444	2716	3444	11	15	8468	9	2012-01-14 01:52:46.781198
3447	1762	3446	8	17	8287	10	2012-01-14 01:53:50.482523
3446	2718	3446	17	8	8705	16	2012-01-14 01:53:50.482523
3451	2612	3450	12	17	9511	11	2012-01-14 01:55:31.30782
3452	1146	3450	17	1	2102	6	2012-01-14 01:55:31.30782
3450	2723	3450	1	12	9291	5	2012-01-14 01:55:31.30782
3454	1372	3453	12	11	4321	2	2012-01-14 01:55:55.788596
3455	2117	3453	11	5	2577	17	2012-01-14 01:55:55.788596
3453	2725	3453	5	12	7245	12	2012-01-14 01:55:55.788596
3460	1804	3459	13	16	3635	2	2012-01-14 01:58:09.450876
3461	2726	3459	16	14	4108	17	2012-01-14 01:58:09.450876
3459	2730	3459	14	13	8413	12	2012-01-14 01:58:09.450876
3463	2164	3462	19	20	9086	7	2012-01-14 02:02:19.658061
3462	2737	3462	20	19	9068	15	2012-01-14 02:02:19.658061
3465	1985	3464	7	16	2063	4	2012-01-14 02:02:27.621805
3466	2721	3464	16	13	7393	1	2012-01-14 02:02:27.621805
3467	2697	3464	13	14	2932	6	2012-01-14 02:02:27.621805
3468	1774	3464	14	14	1177	17	2012-01-14 02:02:27.621805
3469	2730	3464	14	8	1271	12	2012-01-14 02:02:27.621805
3464	2738	3464	8	7	8038	6	2012-01-14 02:02:27.621805
3475	2113	3474	3	4	4675	17	2012-01-14 02:07:38.201821
3474	2753	3474	4	3	3411	9	2012-01-14 02:07:38.201821
3482	423	3481	2	19	741	6	2012-01-14 02:09:03.523079
3483	2754	3481	19	20	2790	9	2012-01-14 02:09:03.523079
3484	1461	3481	20	12	1931	4	2012-01-14 02:09:03.523079
3485	2702	3481	12	13	9807	10	2012-01-14 02:09:03.523079
3486	2735	3481	13	15	5852	8	2012-01-14 02:09:03.523079
3481	2757	3481	15	2	7398	7	2012-01-14 02:09:03.523079
3488	2515	3487	4	8	723	1	2012-01-14 02:10:02.503046
3487	2761	3487	8	4	7885	6	2012-01-14 02:10:02.503046
3490	2239	3489	9	19	5181	7	2012-01-14 02:10:27.483146
3489	2762	3489	19	9	4146	1	2012-01-14 02:10:27.483146
3495	2749	3494	15	4	5825	3	2012-01-14 02:13:01.988601
3496	1357	3494	4	18	8321	4	2012-01-14 02:13:01.988601
3494	2771	3494	18	15	4318	8	2012-01-14 02:13:01.988601
3535	2789	3533	2	1	5341	19	2012-01-14 02:23:57.858081
3975	2047	3974	9	20	3038	13	2012-01-14 04:43:13.577782
3537	2447	3536	5	10	1065	16	2012-01-14 02:24:46.276028
3538	2244	3536	10	18	4504	10	2012-01-14 02:24:46.276028
3536	2809	3536	18	5	5066	3	2012-01-14 02:24:46.276028
3553	2810	3552	13	8	9287	17	2012-01-14 02:27:55.836105
3554	2079	3552	8	9	2776	15	2012-01-14 02:27:55.836105
3552	2817	3552	9	13	4633	9	2012-01-14 02:27:55.836105
3560	2705	3559	8	5	1102	18	2012-01-14 02:29:52.000585
3559	2822	3559	5	8	965	17	2012-01-14 02:29:52.000585
3562	2701	3561	1	4	4027	20	2012-01-14 02:30:50.737465
3563	2763	3561	4	13	9645	13	2012-01-14 02:30:50.737465
3564	2778	3561	13	8	6164	5	2012-01-14 02:30:50.737465
3561	2826	3561	8	1	1774	17	2012-01-14 02:30:50.737465
3573	1589	3572	3	2	6389	13	2012-01-14 02:32:45.615302
3572	2834	3572	2	3	2849	9	2012-01-14 02:32:45.615302
3575	2498	3574	11	8	8821	5	2012-01-14 02:32:54.606524
3574	2835	3574	8	11	6888	16	2012-01-14 02:32:54.606524
3580	1586	3579	15	11	3086	4	2012-01-14 02:35:58.355015
3579	2844	3579	11	15	6155	20	2012-01-14 02:35:58.355015
3596	2792	3595	9	11	2593	10	2012-01-14 02:43:28.858049
3597	2786	3595	11	3	8895	8	2012-01-14 02:43:28.858049
3598	2806	3595	3	11	4219	17	2012-01-14 02:43:28.858049
3595	2859	3595	11	9	9491	15	2012-01-14 02:43:28.858049
3600	2846	3599	19	14	1533	4	2012-01-14 02:43:38.180341
3601	2819	3599	14	1	2079	3	2012-01-14 02:43:38.180341
3602	1631	3599	1	14	7679	15	2012-01-14 02:43:38.180341
3599	2860	3599	14	19	5348	1	2012-01-14 02:43:38.180341
3604	2700	3603	5	2	1906	3	2012-01-14 02:44:50.183751
3605	2782	3603	2	15	8966	11	2012-01-14 02:44:50.183751
3603	2863	3603	15	5	6421	13	2012-01-14 02:44:50.183751
3607	2799	3606	13	20	2138	7	2012-01-14 02:45:07.014222
3606	2865	3606	20	13	9020	6	2012-01-14 02:45:07.014222
3609	2039	3608	7	17	5981	8	2012-01-14 02:45:34.478226
3610	1626	3608	17	19	3279	2	2012-01-14 02:45:34.478226
3611	2825	3608	19	16	9854	7	2012-01-14 02:45:34.478226
3608	2866	3608	16	7	9982	17	2012-01-14 02:45:34.478226
3613	2483	3612	19	7	8115	14	2012-01-14 02:45:43.095521
3612	2867	3612	7	19	9098	8	2012-01-14 02:45:43.095521
3615	1840	3614	19	3	7360	2	2012-01-14 02:45:51.832818
3616	2788	3614	3	12	6516	6	2012-01-14 02:45:51.832818
3617	2816	3614	12	1	3024	4	2012-01-14 02:45:51.832818
3618	2840	3614	1	18	3426	13	2012-01-14 02:45:51.832818
3614	2868	3614	18	19	4639	15	2012-01-14 02:45:51.832818
3620	2808	3619	11	7	5825	17	2012-01-14 02:48:01.268461
3621	334	3619	7	19	5406	13	2012-01-14 02:48:01.268461
3619	2873	3619	19	11	8476	4	2012-01-14 02:48:01.268461
3623	1789	3622	20	17	1764	4	2012-01-14 02:48:10.373285
3624	2831	3622	17	10	7657	20	2012-01-14 02:48:10.373285
3622	2874	3622	10	20	5015	2	2012-01-14 02:48:10.373285
3654	2838	3653	11	6	9249	12	2012-01-14 02:58:16.85139
3655	1524	3653	6	5	4973	19	2012-01-14 02:58:16.85139
3653	2899	3653	5	11	4489	10	2012-01-14 02:58:16.85139
3657	2880	3656	8	8	6680	20	2012-01-14 02:58:35.546794
3658	2641	3656	8	15	2298	10	2012-01-14 02:58:35.546794
3656	2901	3656	15	8	3793	15	2012-01-14 02:58:35.546794
3660	2717	3659	7	19	9828	1	2012-01-14 02:58:52.667682
3659	2903	3659	19	7	6976	4	2012-01-14 02:58:52.667682
3664	2878	3663	5	18	1900	3	2012-01-14 03:01:46.915235
3665	2891	3663	18	11	1675	20	2012-01-14 03:01:46.915235
3666	623	3663	11	14	534	8	2012-01-14 03:01:46.915235
3667	2618	3663	14	20	5988	12	2012-01-14 03:01:46.915235
3663	2909	3663	20	5	1778	5	2012-01-14 03:01:46.915235
3675	2774	3674	10	2	4322	3	2012-01-14 03:04:19.430709
3676	2356	3674	2	7	5019	12	2012-01-14 03:04:19.430709
3674	2916	3674	7	10	4845	15	2012-01-14 03:04:19.430709
3678	1398	3677	1	19	3079	18	2012-01-14 03:04:37.650457
3679	2843	3677	19	7	3877	11	2012-01-14 03:04:37.650457
3680	2820	3677	7	9	7529	17	2012-01-14 03:04:37.650457
3681	2892	3677	9	10	8503	14	2012-01-14 03:04:37.650457
3677	2918	3677	10	1	9077	1	2012-01-14 03:04:37.650457
3683	778	3682	3	8	3676	12	2012-01-14 03:06:04.54155
3682	2922	3682	8	3	2509	10	2012-01-14 03:06:04.54155
3685	2768	3684	13	13	1342	17	2012-01-14 03:07:42.952808
3686	2904	3684	13	20	1736	12	2012-01-14 03:07:42.952808
3687	2909	3684	20	20	3035	5	2012-01-14 03:07:42.952808
3684	2927	3684	20	13	4179	19	2012-01-14 03:07:42.952808
3692	2722	3691	1	10	4212	5	2012-01-14 03:10:05.333719
3691	2934	3691	10	1	4341	4	2012-01-14 03:10:05.333719
3696	2675	3695	16	13	6908	2	2012-01-14 03:11:41.506812
3695	2938	3695	6	16	8514	20	2012-01-14 03:11:41.506812
3697	2921	3695	13	6	2761	8	2012-01-14 03:11:41.506812
3706	1602	3705	9	7	169	1	2012-01-14 03:14:56.36778
3707	2942	3705	7	12	4666	3	2012-01-14 03:14:56.36778
3708	2455	3705	12	10	9265	5	2012-01-14 03:14:56.36778
3705	2948	3705	10	9	3470	7	2012-01-14 03:14:56.36778
3739	1017	3738	1	7	2241	6	2012-01-14 03:20:39.258811
3740	2929	3738	7	20	9497	13	2012-01-14 03:20:39.258811
3738	2959	3738	20	1	1128	7	2012-01-14 03:20:39.258811
3750	2304	3749	13	7	7252	1	2012-01-14 03:27:50.232295
3751	2942	3749	7	19	787	3	2012-01-14 03:27:50.232295
3752	579	3749	19	12	6430	15	2012-01-14 03:27:50.232295
3749	2972	3749	12	13	5797	16	2012-01-14 03:27:50.232295
3763	2948	3762	10	11	6406	7	2012-01-14 03:32:02.135701
3764	2535	3762	11	12	589	1	2012-01-14 03:32:02.135701
3762	2983	3762	12	10	1900	5	2012-01-14 03:32:02.135701
3766	866	3765	14	4	6288	13	2012-01-14 03:32:31.693567
3765	2984	3765	4	14	5701	4	2012-01-14 03:32:31.693567
3768	2947	3767	1	17	2739	10	2012-01-14 03:32:42.022042
3767	2985	3767	17	1	9296	2	2012-01-14 03:32:42.022042
3770	2912	3769	15	4	9324	5	2012-01-14 03:32:50.757337
3771	2941	3769	4	5	5221	8	2012-01-14 03:32:50.757337
3772	2882	3769	5	20	8922	17	2012-01-14 03:32:50.757337
3773	2694	3769	20	3	2173	4	2012-01-14 03:32:50.757337
3769	2986	3769	3	15	5155	12	2012-01-14 03:32:50.757337
3782	2588	3781	20	15	4064	1	2012-01-14 03:34:12.660664
3783	2748	3781	15	17	7191	19	2012-01-14 03:34:12.660664
3781	2990	3781	17	20	5220	15	2012-01-14 03:34:12.660664
3785	2855	3784	2	7	6004	2	2012-01-14 03:36:59.982949
3786	2977	3784	7	3	3707	18	2012-01-14 03:36:59.982949
3787	2964	3784	3	6	7311	14	2012-01-14 03:36:59.982949
3788	2853	3784	6	6	3986	7	2012-01-14 03:36:59.982949
3784	2997	3784	6	2	2048	11	2012-01-14 03:36:59.982949
3790	2965	3789	18	19	850	8	2012-01-14 03:38:42.977745
3789	3001	3789	19	18	2377	1	2012-01-14 03:38:42.977745
3792	2732	3791	7	19	5958	13	2012-01-14 03:38:52.023956
3791	3002	3791	19	7	4712	9	2012-01-14 03:38:52.023956
3811	2993	3810	10	13	3271	11	2012-01-14 03:43:48.602075
3812	2879	3810	13	12	8989	19	2012-01-14 03:43:48.602075
3813	2988	3810	12	3	5420	15	2012-01-14 03:43:48.602075
3810	3011	3810	3	10	294	20	2012-01-14 03:43:48.602075
3815	1817	3814	9	2	524	10	2012-01-14 03:45:03.508809
3814	3015	3814	2	9	1197	19	2012-01-14 03:45:03.508809
3821	3012	3820	16	20	1319	20	2012-01-14 03:46:29.655564
3820	3019	3820	20	16	2574	18	2012-01-14 03:46:29.655564
3823	3013	3822	13	5	5508	5	2012-01-14 03:51:22.27465
3824	2878	3822	5	17	1409	3	2012-01-14 03:51:22.27465
3825	878	3822	17	1	9322	13	2012-01-14 03:51:22.27465
3826	2830	3822	1	10	4885	8	2012-01-14 03:51:22.27465
3827	2693	3822	10	7	5469	12	2012-01-14 03:51:22.27465
3822	3026	3822	7	13	8085	4	2012-01-14 03:51:22.27465
3834	2506	3833	19	16	2622	19	2012-01-14 03:54:32.641246
3833	3031	3833	16	19	957	13	2012-01-14 03:54:32.641246
3841	1042	3840	3	11	6858	6	2012-01-14 03:56:03.010756
3840	3035	3840	11	3	4685	12	2012-01-14 03:56:03.010756
3854	3044	3853	17	2	7782	6	2012-01-14 04:00:27.06107
3855	2360	3853	2	10	265	16	2012-01-14 04:00:27.06107
3853	3046	3853	10	17	9853	12	2012-01-14 04:00:27.06107
3857	2680	3856	2	1	2639	11	2012-01-14 04:01:11.615246
3858	3004	3856	1	20	9055	19	2012-01-14 04:01:11.615246
3859	126	3856	20	11	2923	6	2012-01-14 04:01:11.615246
3856	3048	3856	11	2	4446	17	2012-01-14 04:01:11.615246
3871	855	3870	10	5	6039	18	2012-01-14 04:02:59.905667
3872	2595	3870	5	3	5549	6	2012-01-14 04:02:59.905667
3870	3052	3870	3	10	8755	12	2012-01-14 04:02:59.905667
3876	2744	3875	17	6	3042	8	2012-01-14 04:14:14.265375
3877	3043	3875	6	9	878	9	2012-01-14 04:14:14.265375
3875	3068	3875	9	17	9007	13	2012-01-14 04:14:14.265375
3883	2930	3882	7	4	7688	1	2012-01-14 04:16:35.123663
3884	3070	3882	4	17	7360	13	2012-01-14 04:16:35.123663
3882	3074	3882	17	7	4576	9	2012-01-14 04:16:35.123663
3908	2960	3907	16	2	8103	2	2012-01-14 04:25:04.656422
3909	3060	3907	2	4	908	7	2012-01-14 04:25:04.656422
3910	3064	3907	4	6	7527	15	2012-01-14 04:25:04.656422
3907	3091	3907	10	16	787	10	2012-01-14 04:25:04.656422
3911	2302	3907	6	10	7088	14	2012-01-14 04:25:04.656422
3913	2950	3912	7	19	6479	10	2012-01-14 04:25:27.086353
3914	2939	3912	19	13	6212	17	2012-01-14 04:25:27.086353
3912	3092	3912	13	7	2314	8	2012-01-14 04:25:27.086353
3991	1482	3990	16	3	771	1	2012-01-14 04:53:41.614745
3924	3078	3923	7	3	6254	13	2012-01-14 04:27:24.466734
3925	442	3923	3	11	4799	6	2012-01-14 04:27:24.466734
3926	3048	3923	11	17	1653	17	2012-01-14 04:27:24.466734
3923	3097	3923	17	7	7991	19	2012-01-14 04:27:24.466734
3990	3162	3990	3	16	2941	13	2012-01-14 04:53:41.614745
3993	2975	3992	3	15	6255	17	2012-01-14 04:54:03.165042
3992	3164	3992	15	3	8590	2	2012-01-14 04:54:03.165042
3932	3055	3931	20	17	3134	15	2012-01-14 04:29:01.778036
3931	3103	3931	17	20	7524	7	2012-01-14 04:29:01.778036
3936	3105	3935	17	16	8434	8	2012-01-14 04:30:23.179745
3937	2766	3935	16	5	6620	11	2012-01-14 04:30:23.179745
3935	3107	3935	5	17	6937	2	2012-01-14 04:30:23.179745
3999	1435	3998	18	6	4511	1	2012-01-14 04:57:16.542017
3939	3010	3938	6	9	8961	8	2012-01-14 04:30:33.976166
3940	3066	3938	9	10	7477	5	2012-01-14 04:30:33.976166
3941	3022	3938	10	7	8616	14	2012-01-14 04:30:33.976166
3938	3108	3938	7	6	3759	9	2012-01-14 04:30:33.976166
4000	3161	3998	6	14	5748	10	2012-01-14 04:57:16.542017
4001	3071	3998	14	7	581	16	2012-01-14 04:57:16.542017
4002	2728	3998	7	7	2851	8	2012-01-14 04:57:16.542017
3998	3168	3998	7	18	3958	9	2012-01-14 04:57:16.542017
3952	3062	3951	13	17	5046	12	2012-01-14 04:35:01.369025
3953	3110	3951	17	2	2280	16	2012-01-14 04:35:01.369025
3954	1752	3951	2	9	2420	3	2012-01-14 04:35:01.369025
3951	3119	3951	9	13	6841	17	2012-01-14 04:35:01.369025
3956	3120	3955	20	8	1618	8	2012-01-14 04:35:51.503508
3957	751	3955	8	2	3102	2	2012-01-14 04:35:51.503508
3958	3061	3955	2	16	4047	4	2012-01-14 04:35:51.503508
3955	3122	3955	16	20	6077	13	2012-01-14 04:35:51.503508
4013	3156	4012	4	5	6503	10	2012-01-14 04:59:47.524657
4014	2812	4012	5	15	1602	4	2012-01-14 04:59:47.524657
4015	2953	4012	15	2	880	3	2012-01-14 04:59:47.524657
4012	3174	4012	2	4	2826	15	2012-01-14 04:59:47.524657
4017	2833	4016	20	8	2381	14	2012-01-14 04:59:57.681641
4016	3175	4016	8	20	4733	2	2012-01-14 04:59:57.681641
4019	2935	4018	11	15	7647	7	2012-01-14 05:01:49.345005
4020	3176	4018	15	18	4318	10	2012-01-14 05:01:49.345005
4021	1875	4018	18	13	4403	15	2012-01-14 05:01:49.345005
4018	3179	4018	13	11	8759	1	2012-01-14 05:01:49.345005
4023	3008	4022	12	16	2594	15	2012-01-14 05:04:33.125138
4024	3099	4022	16	6	7686	6	2012-01-14 05:04:33.125138
4025	3025	4022	6	19	2749	10	2012-01-14 05:04:33.125138
4026	3180	4022	19	2	7374	14	2012-01-14 05:04:33.125138
4022	3184	4022	2	12	56	1	2012-01-14 05:04:33.125138
4033	3184	4032	2	5	898	1	2012-01-14 05:05:43.821117
4034	3054	4032	5	18	6538	4	2012-01-14 05:05:43.821117
4035	3155	4032	18	11	4269	10	2012-01-14 05:05:43.821117
4032	3187	4032	11	2	9185	14	2012-01-14 05:05:43.821117
4037	2781	4036	1	9	3390	10	2012-01-14 05:06:41.265964
4036	3189	4036	9	1	8754	9	2012-01-14 05:06:41.265964
4056	3163	4055	10	16	5359	6	2012-01-14 05:16:02.889403
4055	3205	4055	16	10	6236	12	2012-01-14 05:16:02.889403
4061	2681	4060	5	2	9584	19	2012-01-14 05:18:40.799177
4060	3210	4060	2	5	2610	9	2012-01-14 05:18:40.799177
4076	3194	4075	7	13	6044	18	2012-01-14 05:25:52.084653
4077	2871	4075	13	15	3062	19	2012-01-14 05:25:52.084653
4078	3143	4075	15	15	7243	6	2012-01-14 05:25:52.084653
4075	3222	4075	15	7	2591	10	2012-01-14 05:25:52.084653
4080	3170	4079	6	4	9790	14	2012-01-14 05:26:04.392466
4079	3223	4079	4	6	2990	5	2012-01-14 05:26:04.392466
4084	2363	4083	1	18	3362	8	2012-01-14 05:26:57.58774
4083	3226	4083	18	1	6626	15	2012-01-14 05:26:57.58774
4088	3109	4087	6	18	3807	20	2012-01-14 05:27:51.927097
4089	3072	4087	18	9	1955	3	2012-01-14 05:27:51.927097
4090	3212	4087	9	7	4524	8	2012-01-14 05:27:51.927097
4091	3168	4087	7	7	760	9	2012-01-14 05:27:51.927097
4092	2575	4087	7	6	3918	11	2012-01-14 05:27:51.927097
4087	3228	4087	6	6	2273	19	2012-01-14 05:27:51.927097
4094	3016	4093	10	17	5028	11	2012-01-14 05:28:25.015548
4093	3230	4093	17	10	1982	13	2012-01-14 05:28:25.015548
4115	3134	4114	8	18	9706	6	2012-01-14 05:38:25.805394
4116	3076	4114	18	10	1823	15	2012-01-14 05:38:25.805394
4117	3229	4114	10	15	5505	4	2012-01-14 05:38:25.805394
4118	2849	4114	15	5	7040	11	2012-01-14 05:38:25.805394
4119	2114	4114	5	12	1413	3	2012-01-14 05:38:25.805394
4114	3245	4114	12	8	2575	8	2012-01-14 05:38:25.805394
4121	3039	4120	20	16	3949	17	2012-01-14 05:41:48.832166
4122	3123	4120	16	17	6807	12	2012-01-14 05:41:48.832166
4120	3251	4120	17	20	7953	11	2012-01-14 05:41:48.832166
4124	2322	4123	13	15	7373	5	2012-01-14 05:43:40.588778
4123	3256	4123	15	13	3645	9	2012-01-14 05:43:40.588778
4143	2908	4142	6	3	1652	12	2012-01-14 05:51:12.501509
4144	3267	4142	3	20	5916	4	2012-01-14 05:51:12.501509
4145	2408	4142	20	9	7768	7	2012-01-14 05:51:12.501509
4142	3269	4142	9	6	4392	13	2012-01-14 05:51:12.501509
4156	2105	4155	1	3	3597	8	2012-01-14 05:55:26.162212
4155	3276	4155	3	1	8847	4	2012-01-14 05:55:26.162212
4162	2869	4161	12	12	5324	1	2012-01-14 05:58:13.48236
4163	3272	4161	12	3	7674	10	2012-01-14 05:58:13.48236
4164	3213	4161	3	7	8030	11	2012-01-14 05:58:13.48236
4165	2416	4161	7	10	6230	13	2012-01-14 05:58:13.48236
4161	3283	4161	10	12	6843	12	2012-01-14 05:58:13.48236
4172	3287	4171	3	5	4267	9	2012-01-14 06:03:03.040166
4173	2992	4171	5	8	5593	7	2012-01-14 06:03:03.040166
4174	3268	4171	8	13	3096	20	2012-01-14 06:03:03.040166
4175	2924	4171	13	2	6231	17	2012-01-14 06:03:03.040166
4171	3290	4171	2	3	5322	19	2012-01-14 06:03:03.040166
4177	3209	4176	18	14	7182	18	2012-01-14 06:03:36.802837
4178	3028	4176	14	12	4002	17	2012-01-14 06:03:36.802837
4179	3219	4176	12	9	9311	9	2012-01-14 06:03:36.802837
4176	3292	4176	9	18	5884	1	2012-01-14 06:03:36.802837
4192	2961	4191	3	8	9729	20	2012-01-14 06:13:47.507635
4193	3311	4191	8	5	3274	3	2012-01-14 06:13:47.507635
4194	3114	4191	5	3	5567	18	2012-01-14 06:13:47.507635
4195	3238	4191	3	6	5889	4	2012-01-14 06:13:47.507635
4196	3133	4191	6	6	1459	19	2012-01-14 06:13:47.507635
4191	3312	4191	6	3	7409	16	2012-01-14 06:13:47.507635
4204	1881	4203	7	16	3260	19	2012-01-14 06:16:46.567729
4203	3319	4203	16	7	9242	4	2012-01-14 06:16:46.567729
4206	2796	4205	19	14	2446	11	2012-01-14 06:16:58.844327
4205	3320	4205	14	19	1176	16	2012-01-14 06:16:58.844327
4208	3216	4207	19	5	1412	6	2012-01-14 06:18:25.38871
4209	2752	4207	5	8	878	14	2012-01-14 06:18:25.38871
4207	3322	4207	8	19	346	17	2012-01-14 06:18:25.38871
4222	3310	4221	4	12	2941	1	2012-01-14 06:21:27.088263
4223	3081	4221	12	5	4090	9	2012-01-14 06:21:27.088263
4224	2466	4221	5	19	1355	12	2012-01-14 06:21:27.088263
4225	3185	4221	19	19	2179	14	2012-01-14 06:21:27.088263
4221	3328	4221	19	4	2489	13	2012-01-14 06:21:27.088263
4241	2751	4240	16	13	6483	12	2012-01-14 06:25:07.463064
4242	3300	4240	13	4	4181	8	2012-01-14 06:25:07.463064
4240	3333	4240	4	16	8774	9	2012-01-14 06:25:07.463064
4246	3320	4245	14	3	823	16	2012-01-14 06:27:25.088944
4247	624	4245	3	4	4400	5	2012-01-14 06:27:25.088944
4248	3317	4245	4	9	1700	12	2012-01-14 06:27:25.088944
4245	3337	4245	9	14	8434	11	2012-01-14 06:27:25.088944
4256	3322	4255	8	2	1630	17	2012-01-14 06:35:47.801919
4257	2680	4255	2	10	1927	11	2012-01-14 06:35:47.801919
4255	3345	4255	10	8	4814	14	2012-01-14 06:35:47.801919
4264	1698	4263	19	14	8860	2	2012-01-14 06:40:39.48521
4263	3354	4263	14	19	2678	9	2012-01-14 06:40:39.48521
4266	2343	4265	8	16	8966	13	2012-01-14 06:41:13.966456
4265	3356	4265	16	8	303	16	2012-01-14 06:41:13.966456
4273	3315	4272	1	16	4036	16	2012-01-14 06:42:53.982416
4274	2776	4272	16	3	5815	1	2012-01-14 06:42:53.982416
4275	3342	4272	3	9	4441	15	2012-01-14 06:42:53.982416
4272	3358	4272	9	1	8472	10	2012-01-14 06:42:53.982416
4277	3154	4276	15	19	5385	11	2012-01-14 06:47:11.470168
4278	3305	4276	19	16	2094	17	2012-01-14 06:47:11.470168
4276	3366	4276	16	15	3162	8	2012-01-14 06:47:11.470168
4285	2622	4284	2	3	3559	6	2012-01-14 06:50:45.629742
4284	3371	4284	3	2	3339	2	2012-01-14 06:50:45.629742
4291	2910	4290	10	13	3852	12	2012-01-14 06:51:59.945998
4290	3374	4290	13	10	2921	4	2012-01-14 06:51:59.945998
4301	2885	4300	10	10	8621	20	2012-01-14 06:57:06.303194
4302	3208	4300	10	13	9901	11	2012-01-14 06:57:06.303194
4300	3386	4300	13	10	8820	10	2012-01-14 06:57:06.303194
4304	3372	4303	17	15	6150	5	2012-01-14 06:57:30.743718
4305	3353	4303	15	4	4332	8	2012-01-14 06:57:30.743718
4306	3296	4303	4	17	6193	9	2012-01-14 06:57:30.743718
4303	3388	4303	17	17	6370	13	2012-01-14 06:57:30.743718
4311	3293	4310	10	13	4769	4	2012-01-14 06:59:12.659348
4312	2571	4310	13	5	4208	14	2012-01-14 06:59:12.659348
4310	3391	4310	5	10	511	8	2012-01-14 06:59:12.659348
4314	3132	4313	17	5	4664	2	2012-01-14 07:06:45.484923
4313	3398	4313	5	17	6388	1	2012-01-14 07:06:45.484923
4318	3306	4317	16	14	6607	13	2012-01-14 07:08:27.572635
4319	3321	4317	14	3	6062	17	2012-01-14 07:08:27.572635
4317	3402	4317	3	16	7200	4	2012-01-14 07:08:27.572635
4321	3285	4320	3	3	4164	14	2012-01-14 07:09:17.219283
4322	3403	4320	3	10	2218	3	2012-01-14 07:09:17.219283
4323	3196	4320	10	4	3504	15	2012-01-14 07:09:17.219283
4320	3404	4320	4	3	1993	2	2012-01-14 07:09:17.219283
\.


--
-- Data for Name: torder; Type: TABLE DATA; Schema: t; Owner: olivier
--

COPY torder (id, qtt, nr, np, qtt_prov, qtt_requ, own, created, updated) FROM stdin;
69	0	8	3	6800	8777	2	2012-01-13 20:24:50.841069	2012-01-13 20:24:51.275731
7	0	2	7	8654	2605	7	2012-01-13 20:24:50.002203	2012-01-13 20:24:50.359669
22	0	16	7	7946	3326	13	2012-01-13 20:24:50.191928	2012-01-13 20:25:16.763656
60	0	14	6	8944	9197	18	2012-01-13 20:24:50.685308	2012-01-13 20:25:00.835601
33	0	7	14	5087	3115	16	2012-01-13 20:24:50.337209	2012-01-13 20:24:50.359669
54	0	17	6	7185	3383	20	2012-01-13 20:24:50.618126	2012-01-13 20:24:51.119994
35	0	14	10	2809	2402	8	2012-01-13 20:24:50.359669	2012-01-13 20:24:50.359669
10	1911	10	11	1911	5676	9	2012-01-13 20:24:50.046717	\N
71	0	15	10	2188	3403	12	2012-01-13 20:24:50.88558	2012-01-13 20:24:51.041973
12	1091	2	13	1091	5513	3	2012-01-13 20:24:50.069227	\N
42	0	15	7	3121	4669	7	2012-01-13 20:24:50.449016	2012-01-13 20:25:04.211024
15	1868	3	9	1868	6128	10	2012-01-13 20:24:50.102948	\N
21	0	16	13	8451	2431	12	2012-01-13 20:24:50.180927	2012-01-13 20:24:51.98996
34	0	12	13	5607	125	4	2012-01-13 20:24:50.348577	2012-01-13 20:24:51.141962
44	0	12	9	9869	4019	18	2012-01-13 20:24:50.472399	2012-01-13 20:26:06.20487
200	0	8	18	1877	5489	18	2012-01-13 20:24:56.47799	2012-01-13 20:25:48.236938
19	0	10	9	5797	4506	3	2012-01-13 20:24:50.158571	2012-01-13 20:25:44.866441
76	0	2	8	9686	5050	17	2012-01-13 20:24:50.974801	2012-01-13 20:24:52.200952
30	0	10	9	9185	1695	1	2012-01-13 20:24:50.292706	2012-01-13 20:25:19.716155
2	0	4	3	7838	3034	2	2012-01-13 20:24:49.9351	2012-01-13 20:24:50.203247
5	0	3	9	7299	8989	5	2012-01-13 20:24:49.968886	2012-01-13 20:24:50.203247
8	0	9	7	7198	3989	8	2012-01-13 20:24:50.013403	2012-01-13 20:24:50.203247
16	0	7	8	7577	8768	11	2012-01-13 20:24:50.11391	2012-01-13 20:24:50.203247
23	0	8	4	6977	453	6	2012-01-13 20:24:50.203247	2012-01-13 20:24:50.203247
43	0	20	6	1881	9995	1	2012-01-13 20:24:50.460243	2012-01-13 20:24:51.353578
61	0	13	20	6389	659	19	2012-01-13 20:24:50.707456	2012-01-13 20:24:51.141962
46	0	1	15	1190	6493	11	2012-01-13 20:24:50.493551	2012-01-13 20:29:32.514609
36	0	13	6	3593	9470	4	2012-01-13 20:24:50.382125	2012-01-13 20:24:51.720595
52	0	2	14	9028	6402	18	2012-01-13 20:24:50.59566	2012-01-13 20:25:23.285944
9	0	12	11	4936	8677	8	2012-01-13 20:24:50.035638	2012-01-13 20:24:50.303702
27	0	11	1	4257	1016	8	2012-01-13 20:24:50.259271	2012-01-13 20:24:50.303702
31	0	1	12	6763	8455	11	2012-01-13 20:24:50.303702	2012-01-13 20:24:50.303702
197	3231	10	6	3231	7828	12	2012-01-13 20:24:56.400165	\N
6	0	10	8	4342	6109	6	2012-01-13 20:24:49.991001	2012-01-13 20:24:51.041973
199	0	5	7	4805	9467	3	2012-01-13 20:24:56.466906	2012-01-13 20:24:59.132682
1	0	2	1	7580	4206	1	2012-01-13 20:24:49.90166	2012-01-13 20:24:51.220091
25	0	10	17	3702	9806	15	2012-01-13 20:24:50.236764	2012-01-13 20:24:50.359669
28	0	17	2	3503	1804	12	2012-01-13 20:24:50.270194	2012-01-13 20:24:50.359669
13	0	4	6	5403	9639	1	2012-01-13 20:24:50.080334	2012-01-13 20:25:03.060773
40	468	19	1	468	4454	17	2012-01-13 20:24:50.426647	\N
57	0	18	12	709	4032	14	2012-01-13 20:24:50.651747	2012-01-13 20:24:51.331199
20	0	3	6	7934	824	3	2012-01-13 20:24:50.169788	2012-01-13 20:25:30.236067
58	0	10	7	9087	4741	11	2012-01-13 20:24:50.663187	2012-01-13 20:24:51.420321
68	0	16	10	1514	9887	14	2012-01-13 20:24:50.829901	2012-01-13 20:26:29.165014
49	0	1	15	6508	3471	14	2012-01-13 20:24:50.540105	2012-01-13 20:24:51.220091
48	4530	16	15	4530	7924	4	2012-01-13 20:24:50.516002	\N
53	0	12	19	5872	89	13	2012-01-13 20:24:50.606922	2012-01-13 20:24:51.331199
47	0	20	14	1002	8540	19	2012-01-13 20:24:50.504917	2012-01-13 20:24:51.141962
77	0	10	5	6786	8052	16	2012-01-13 20:24:50.986089	2012-01-13 20:25:51.342967
75	0	16	19	8440	3306	8	2012-01-13 20:24:50.95262	2012-01-13 20:24:51.542908
14	0	1	4	5963	3850	2	2012-01-13 20:24:50.09144	2012-01-13 20:24:50.896772
37	0	19	17	4145	6509	15	2012-01-13 20:24:50.393354	2012-01-13 20:24:51.542908
62	0	18	2	79	3939	11	2012-01-13 20:24:50.718613	2012-01-13 20:24:53.131904
41	0	15	5	4873	5615	14	2012-01-13 20:24:50.437693	2012-01-13 20:24:51.220091
73	0	20	7	5830	7182	1	2012-01-13 20:24:50.919346	2012-01-13 20:25:06.35563
74	0	17	11	8689	395	11	2012-01-13 20:24:50.941463	2012-01-13 20:24:51.331199
38	0	15	14	2395	6374	5	2012-01-13 20:24:50.404306	2012-01-13 20:24:59.62002
24	0	4	6	6806	267	14	2012-01-13 20:24:50.225446	2012-01-13 20:24:50.896772
26	0	8	7	1239	2106	10	2012-01-13 20:24:50.247904	2012-01-13 20:27:11.959818
39	0	18	13	4145	4023	16	2012-01-13 20:24:50.41548	2012-01-13 20:24:50.762973
29	0	13	14	9883	1994	6	2012-01-13 20:24:50.281277	2012-01-13 20:24:50.762973
64	0	14	18	2610	7772	19	2012-01-13 20:24:50.762973	2012-01-13 20:24:50.762973
198	0	8	16	1408	437	8	2012-01-13 20:24:56.411329	2012-01-13 20:24:56.411329
45	0	2	7	7174	24	13	2012-01-13 20:24:50.482421	2012-01-13 20:24:53.131904
3	0	6	5	5047	2819	3	2012-01-13 20:24:49.946362	2012-01-13 20:24:50.896772
51	0	9	13	9099	421	3	2012-01-13 20:24:50.584398	2012-01-13 20:24:50.863504
17	0	13	14	9231	5406	9	2012-01-13 20:24:50.136091	2012-01-13 20:24:50.863504
67	0	14	19	2159	1464	3	2012-01-13 20:24:50.80784	2012-01-13 20:24:50.863504
56	0	19	17	4781	2398	4	2012-01-13 20:24:50.640532	2012-01-13 20:24:50.863504
66	0	17	11	1190	3980	17	2012-01-13 20:24:50.796548	2012-01-13 20:24:50.863504
70	0	11	9	4985	4987	5	2012-01-13 20:24:50.863504	2012-01-13 20:24:50.863504
72	0	5	1	355	1484	1	2012-01-13 20:24:50.896772	2012-01-13 20:24:50.896772
18	0	4	15	8117	8495	4	2012-01-13 20:24:50.147281	2012-01-13 20:25:52.633901
201	1699	16	19	1699	6589	10	2012-01-13 20:24:56.500398	\N
11	0	2	12	4480	805	1	2012-01-13 20:24:50.057975	2012-01-13 20:24:50.997171
59	0	12	18	4791	6996	5	2012-01-13 20:24:50.674017	2012-01-13 20:24:50.997171
55	0	2	14	9820	2896	10	2012-01-13 20:24:50.629439	2012-01-13 20:24:57.097913
32	0	18	3	4424	1749	16	2012-01-13 20:24:50.325892	2012-01-13 20:24:50.997171
65	0	3	8	8636	7021	11	2012-01-13 20:24:50.785576	2012-01-13 20:24:50.997171
50	0	8	4	407	6810	8	2012-01-13 20:24:50.563678	2012-01-13 20:24:50.997171
78	0	4	2	9058	2062	18	2012-01-13 20:24:50.997171	2012-01-13 20:24:50.997171
121	0	5	1	1021	2527	15	2012-01-13 20:24:51.8099	2012-01-13 20:25:34.446105
113	0	5	9	2770	5582	20	2012-01-13 20:24:51.631912	2012-01-13 20:25:13.006728
81	0	8	15	2545	657	14	2012-01-13 20:24:51.041973	2012-01-13 20:24:51.041973
143	0	17	1	7042	2155	7	2012-01-13 20:24:52.301001	2012-01-13 20:25:48.236938
139	0	19	6	1868	570	11	2012-01-13 20:24:52.223193	2012-01-13 20:37:46.719685
92	0	3	5	7822	4446	10	2012-01-13 20:24:51.253587	2012-01-13 20:24:51.967165
145	0	3	8	9707	3966	17	2012-01-13 20:24:52.334523	2012-01-13 20:24:56.411329
86	0	6	17	4709	1514	8	2012-01-13 20:24:51.119994	2012-01-13 20:24:51.119994
114	0	11	18	3988	7677	2	2012-01-13 20:24:51.665529	2012-01-13 20:24:53.131904
87	0	14	12	1053	5492	12	2012-01-13 20:24:51.141962	2012-01-13 20:24:51.141962
88	4904	3	6	4904	8813	20	2012-01-13 20:24:51.175437	\N
137	0	19	11	8069	3896	15	2012-01-13 20:24:52.178584	2012-01-13 20:25:03.24902
102	0	17	14	1232	72	3	2012-01-13 20:24:51.456163	2012-01-13 20:24:59.276597
91	0	5	2	6811	8103	9	2012-01-13 20:24:51.220091	2012-01-13 20:24:51.220091
93	0	3	8	754	447	20	2012-01-13 20:24:51.275731	2012-01-13 20:24:51.275731
151	0	3	10	475	8091	18	2012-01-13 20:24:52.445701	2012-01-13 20:25:14.874942
80	0	19	17	7981	6570	9	2012-01-13 20:24:51.0312	2012-01-13 20:24:51.331199
94	0	11	4	9448	6666	3	2012-01-13 20:24:51.297958	2012-01-13 20:24:51.331199
96	0	4	18	3054	1135	2	2012-01-13 20:24:51.331199	2012-01-13 20:24:51.331199
204	0	5	19	5546	9901	14	2012-01-13 20:24:56.69947	2012-01-13 20:25:51.342967
89	0	6	9	3379	1244	12	2012-01-13 20:24:51.186636	2012-01-13 20:24:51.353578
95	0	9	5	8194	8888	11	2012-01-13 20:24:51.309006	2012-01-13 20:24:51.353578
97	0	5	20	9358	4157	3	2012-01-13 20:24:51.353578	2012-01-13 20:24:51.353578
98	308	17	9	308	4468	18	2012-01-13 20:24:51.387071	\N
119	0	16	10	7620	2801	13	2012-01-13 20:24:51.776601	2012-01-13 20:24:58.59111
118	0	5	9	7063	4715	10	2012-01-13 20:24:51.756474	2012-01-13 20:24:51.967165
100	0	7	10	3479	100	8	2012-01-13 20:24:51.420321	2012-01-13 20:24:51.420321
142	0	4	8	9548	9298	19	2012-01-13 20:24:52.278832	2012-01-13 20:25:40.876417
131	0	9	15	5269	665	8	2012-01-13 20:24:52.03415	2012-01-13 20:24:59.62002
154	0	16	3	394	1804	1	2012-01-13 20:24:52.97711	2012-01-13 21:35:03.592563
104	1302	3	14	1302	9666	19	2012-01-13 20:24:51.486956	\N
1646	0	10	11	9879	9323	3	2012-01-13 21:41:01.322814	2012-01-13 22:19:16.816246
134	0	12	3	2880	1055	20	2012-01-13 20:24:52.112184	2012-01-13 20:26:25.706154
108	0	17	16	4198	463	4	2012-01-13 20:24:51.542908	2012-01-13 20:24:51.542908
122	0	12	5	5955	355	3	2012-01-13 20:24:51.832053	2012-01-13 20:25:02.33059
128	0	9	3	4727	4152	15	2012-01-13 20:24:51.967165	2012-01-13 20:24:51.967165
84	0	9	13	4919	8634	2	2012-01-13 20:24:51.086435	2012-01-13 20:24:51.720595
116	0	6	9	2037	19	7	2012-01-13 20:24:51.720595	2012-01-13 20:24:51.720595
117	2986	2	6	2986	7687	8	2012-01-13 20:24:51.743002	\N
109	0	13	4	733	4203	11	2012-01-13 20:24:51.565298	2012-01-13 20:24:59.276597
82	0	6	20	4081	8101	5	2012-01-13 20:24:51.064248	2012-01-13 20:25:47.352319
101	0	9	11	8935	2080	11	2012-01-13 20:24:51.44242	2012-01-13 20:25:37.882085
203	0	8	13	4288	9909	4	2012-01-13 20:24:56.655908	2012-01-13 20:25:02.408217
112	0	10	3	2040	2934	5	2012-01-13 20:24:51.620782	2012-01-13 20:24:58.59111
205	0	9	19	8448	7501	20	2012-01-13 20:24:56.943951	2012-01-13 20:25:19.716155
155	0	4	18	9345	3196	9	2012-01-13 20:24:52.998596	2012-01-13 20:25:03.9904
103	0	12	16	8592	1870	12	2012-01-13 20:24:51.475768	2012-01-13 20:24:51.98996
129	0	13	12	6521	603	5	2012-01-13 20:24:51.98996	2012-01-13 20:24:51.98996
141	0	2	6	3531	4583	9	2012-01-13 20:24:52.267759	2012-01-13 20:25:02.916909
148	0	9	11	5246	1878	13	2012-01-13 20:24:52.400933	2012-01-13 20:25:57.618307
85	0	14	6	9868	4112	10	2012-01-13 20:24:51.097676	2012-01-13 20:24:52.200952
135	0	13	18	4218	8973	10	2012-01-13 20:24:52.123111	2012-01-13 20:25:06.35563
124	0	6	4	2897	5199	2	2012-01-13 20:24:51.878609	2012-01-13 20:24:52.200952
120	0	4	2	406	2566	9	2012-01-13 20:24:51.787534	2012-01-13 20:24:52.200952
90	0	8	5	1272	9118	20	2012-01-13 20:24:51.209094	2012-01-13 20:24:52.200952
106	0	15	19	1026	5809	19	2012-01-13 20:24:51.509503	2012-01-13 20:26:17.010159
83	0	17	20	2871	8300	6	2012-01-13 20:24:51.075247	2012-01-13 20:27:46.877185
125	0	5	18	4109	6346	14	2012-01-13 20:24:51.900965	2012-01-13 20:25:14.874942
107	0	5	11	8044	3159	3	2012-01-13 20:24:51.531692	2012-01-13 20:24:52.200952
138	0	11	14	5866	498	3	2012-01-13 20:24:52.200952	2012-01-13 20:24:52.200952
136	0	5	18	1293	9104	14	2012-01-13 20:24:52.14557	2012-01-13 20:53:21.410818
110	0	18	20	4222	6370	6	2012-01-13 20:24:51.58754	2012-01-13 20:25:06.35563
144	39	5	16	39	6547	10	2012-01-13 20:24:52.312186	\N
79	0	4	14	4823	7911	1	2012-01-13 20:24:51.019482	2012-01-13 20:25:20.060013
146	1024	12	5	1024	8829	5	2012-01-13 20:24:52.356649	\N
140	0	1	2	6126	7050	12	2012-01-13 20:24:52.245554	2012-01-13 20:24:57.097913
126	0	19	6	2923	3719	20	2012-01-13 20:24:51.922951	2012-01-14 04:01:11.615246
149	3123	12	1	3123	8600	18	2012-01-13 20:24:52.412477	\N
150	446	3	20	446	9342	18	2012-01-13 20:24:52.423408	\N
202	0	1	5	7967	6051	14	2012-01-13 20:24:56.522567	2012-01-13 20:25:48.236938
152	0	18	5	815	988	6	2012-01-13 20:24:52.468013	2012-01-13 20:24:52.490468
153	0	5	18	4407	772	3	2012-01-13 20:24:52.490468	2012-01-13 20:24:52.490468
157	5362	16	11	5362	2610	12	2012-01-13 20:24:53.043057	\N
133	0	11	13	8732	6997	19	2012-01-13 20:24:52.089407	2012-01-13 20:24:53.065426
111	0	13	18	9490	579	15	2012-01-13 20:24:51.598601	2012-01-13 20:24:53.065426
156	0	18	1	5411	2012	4	2012-01-13 20:24:53.021029	2012-01-13 20:24:53.065426
158	0	1	11	990	7329	20	2012-01-13 20:24:53.065426	2012-01-13 20:24:53.065426
231	0	2	7	3524	4516	2	2012-01-13 20:24:59.497789	2012-01-13 20:25:30.236067
175	0	9	11	246	450	12	2012-01-13 20:24:54.404131	2012-01-13 20:26:35.927924
161	0	7	11	7035	6607	17	2012-01-13 20:24:53.131904	2012-01-13 20:24:53.131904
193	0	12	4	9719	2090	19	2012-01-13 20:24:55.758603	2012-01-13 20:25:34.446105
163	1714	12	4	1714	8098	4	2012-01-13 20:24:53.198579	\N
164	253	10	14	253	1299	16	2012-01-13 20:24:53.209828	\N
216	0	17	12	1269	7105	1	2012-01-13 20:24:57.883109	2012-01-13 20:26:38.801274
174	0	17	19	5396	7324	15	2012-01-13 20:24:54.392842	2012-01-13 20:39:06.462861
181	0	12	16	5140	7325	9	2012-01-13 20:24:54.526372	2012-01-13 20:25:16.763656
239	0	15	4	137	4565	17	2012-01-13 20:25:00.128555	2012-01-13 20:25:40.876417
192	0	12	2	6862	2071	4	2012-01-13 20:24:55.747524	2012-01-13 20:25:23.285944
210	0	18	13	780	4482	3	2012-01-13 20:24:57.353194	2012-01-13 20:25:03.9904
227	0	7	5	6416	338	16	2012-01-13 20:24:59.132682	2012-01-13 20:24:59.132682
240	0	5	15	805	518	7	2012-01-13 20:25:00.216932	2012-01-13 20:25:48.236938
1647	2775	16	10	2775	7922	11	2012-01-13 21:41:23.59494	\N
244	0	6	8	1469	1747	14	2012-01-13 20:25:00.935613	2012-01-13 20:25:02.916909
177	0	12	19	4353	3581	13	2012-01-13 20:24:54.448713	2012-01-13 21:24:59.692668
213	0	17	20	7735	6097	9	2012-01-13 20:24:57.694937	2012-01-13 20:27:21.490118
176	625	15	18	625	9721	11	2012-01-13 20:24:54.426401	\N
167	0	16	8	5911	6290	15	2012-01-13 20:24:53.287359	2012-01-13 20:25:16.575229
165	0	4	5	765	7651	14	2012-01-13 20:24:53.232101	2012-01-13 20:26:35.806866
237	307	14	19	307	8025	2	2012-01-13 20:24:59.886139	\N
212	0	1	8	9280	6348	3	2012-01-13 20:24:57.606082	2012-01-13 20:25:18.111764
222	0	17	7	7641	468	12	2012-01-13 20:24:58.635207	2012-01-13 20:25:02.408217
180	0	16	17	4090	3903	3	2012-01-13 20:24:54.493129	2012-01-13 20:24:56.411329
221	0	3	16	3061	599	2	2012-01-13 20:24:58.59111	2012-01-13 20:24:58.59111
190	0	17	3	7214	4038	7	2012-01-13 20:24:55.702836	2012-01-13 20:24:56.411329
166	0	5	7	2135	7326	17	2012-01-13 20:24:53.276281	2012-01-13 20:38:03.535164
185	2525	17	13	2525	8059	12	2012-01-13 20:24:55.323135	\N
169	0	10	3	6528	6609	13	2012-01-13 20:24:53.309988	2012-01-13 20:25:22.015997
218	0	17	2	1908	1109	8	2012-01-13 20:24:57.960501	2012-01-13 20:26:28.854551
173	0	12	9	6579	2602	18	2012-01-13 20:24:54.381424	2012-01-13 20:25:02.795296
186	0	19	1	364	897	3	2012-01-13 20:24:55.356705	2012-01-13 20:25:19.716155
191	343	5	4	343	6808	18	2012-01-13 20:24:55.714208	\N
217	0	12	4	5217	416	7	2012-01-13 20:24:57.938455	2012-01-13 20:25:25.088845
194	0	9	13	9246	5862	19	2012-01-13 20:24:55.769845	2012-01-13 20:25:48.039169
208	9414	3	6	9414	6803	14	2012-01-13 20:24:57.075618	\N
170	0	6	1	3140	8478	7	2012-01-13 20:24:53.343223	2012-01-13 20:25:03.060773
99	0	14	20	9623	7226	3	2012-01-13 20:24:51.398176	2012-01-13 20:24:57.097913
183	0	20	19	7877	6837	10	2012-01-13 20:24:55.03493	2012-01-13 20:24:57.097913
123	0	19	8	5302	2491	5	2012-01-13 20:24:51.84324	2012-01-13 20:24:57.097913
209	0	8	1	2492	8918	18	2012-01-13 20:24:57.097913	2012-01-13 20:24:57.097913
247	0	3	15	2382	2261	10	2012-01-13 20:25:01.112818	2012-01-13 20:25:08.378123
1648	0	11	19	4675	3849	5	2012-01-13 21:41:33.679905	2012-01-13 21:44:38.72792
246	0	1	11	6785	442	9	2012-01-13 20:25:01.046513	2012-01-13 20:25:19.716155
207	0	17	11	6142	8042	2	2012-01-13 20:24:57.064529	2012-01-13 20:28:23.998824
214	2506	5	14	2506	7624	8	2012-01-13 20:24:57.705841	\N
159	0	15	2	6597	7420	18	2012-01-13 20:24:53.098778	2012-01-13 20:25:28.313145
179	0	17	3	7357	6867	14	2012-01-13 20:24:54.482127	2012-01-13 20:26:34.44755
228	0	3	11	6484	4566	11	2012-01-13 20:24:59.254631	2012-01-13 20:25:01.523812
224	828	11	7	828	5598	16	2012-01-13 20:24:58.679359	\N
189	0	9	1	7730	5705	19	2012-01-13 20:24:55.66931	2012-01-13 20:25:13.006728
215	0	3	17	3893	8802	12	2012-01-13 20:24:57.838795	2012-01-13 20:24:59.276597
160	0	14	13	6452	1183	6	2012-01-13 20:24:53.109777	2012-01-13 20:24:59.276597
226	1552	17	4	1552	9002	19	2012-01-13 20:24:59.099196	\N
229	0	4	3	3337	6553	10	2012-01-13 20:24:59.276597	2012-01-13 20:24:59.276597
245	0	3	8	8789	6248	13	2012-01-13 20:25:01.035117	2012-01-13 20:26:03.156406
236	0	7	4	7565	6724	3	2012-01-13 20:24:59.62002	2012-01-13 20:25:02.408217
233	193	18	19	193	8860	18	2012-01-13 20:24:59.5311	\N
241	0	7	20	2623	6480	9	2012-01-13 20:25:00.283555	2012-01-13 20:26:17.010159
220	0	4	9	7648	2751	19	2012-01-13 20:24:58.280882	2012-01-13 20:24:59.62002
235	0	14	20	3579	8352	18	2012-01-13 20:24:59.597547	2012-01-13 20:24:59.62002
230	0	20	7	8206	3434	14	2012-01-13 20:24:59.476369	2012-01-13 20:24:59.62002
206	0	4	8	5633	3610	3	2012-01-13 20:24:56.986864	2012-01-13 20:24:59.62002
4	0	8	7	9098	9828	4	2012-01-13 20:24:49.957579	2012-01-13 20:24:59.62002
178	0	1	18	7474	3827	19	2012-01-13 20:24:54.459755	2012-01-13 20:25:13.006728
187	0	1	18	3559	7355	13	2012-01-13 20:24:55.423533	2012-01-13 20:26:20.237003
234	0	5	20	3113	3896	11	2012-01-13 20:24:59.586462	2012-01-13 20:26:35.806866
238	0	6	19	1234	3508	15	2012-01-13 20:25:00.05132	2012-01-13 20:25:00.835601
243	0	19	14	2871	369	12	2012-01-13 20:25:00.835601	2012-01-13 20:25:00.835601
168	0	17	3	5265	3587	1	2012-01-13 20:24:53.298549	2012-01-13 20:25:30.236067
162	0	6	11	5182	6747	13	2012-01-13 20:24:53.176493	2012-01-13 20:25:30.236067
188	0	4	8	3926	3108	7	2012-01-13 20:24:55.647763	2012-01-13 20:25:02.408217
232	0	17	12	8615	1189	19	2012-01-13 20:24:59.519921	2012-01-13 20:25:01.190261
223	0	12	8	7442	6313	16	2012-01-13 20:24:58.657279	2012-01-13 20:25:01.190261
248	0	8	17	1380	5650	9	2012-01-13 20:25:01.190261	2012-01-13 20:25:01.190261
251	0	17	14	7784	6736	12	2012-01-13 20:25:01.413502	2012-01-13 20:32:14.875653
316	0	7	12	3773	5650	2	2012-01-13 20:25:16.763656	2012-01-13 20:25:16.763656
293	0	12	2	4957	9470	13	2012-01-13 20:25:08.289049	2012-01-13 20:41:35.363549
319	0	1	11	2533	4751	2	2012-01-13 20:25:17.084535	2012-01-13 20:26:22.801177
336	0	6	16	42	9961	13	2012-01-13 20:25:20.690134	2012-01-13 20:25:41.674824
254	0	11	3	4316	4361	19	2012-01-13 20:25:01.523812	2012-01-13 20:25:01.523812
1649	535	9	12	535	8161	1	2012-01-13 21:41:36.988469	\N
327	0	8	11	2134	4414	16	2012-01-13 20:25:19.142275	2012-01-13 22:35:03.222279
291	0	12	15	9313	5596	17	2012-01-13 20:25:08.266448	2012-01-13 20:27:30.834758
257	0	5	12	2371	404	7	2012-01-13 20:25:02.33059	2012-01-13 20:25:02.33059
272	0	12	10	3053	8805	18	2012-01-13 20:25:03.448546	2012-01-13 22:42:11.686393
258	0	13	17	1067	8777	19	2012-01-13 20:25:02.408217	2012-01-13 20:25:02.408217
259	4211	8	14	4211	8703	8	2012-01-13 20:25:02.662852	\N
339	0	17	10	7674	2392	18	2012-01-13 20:25:21.253067	2012-01-13 20:25:51.342967
253	0	9	18	5334	731	14	2012-01-13 20:25:01.479708	2012-01-13 20:25:02.795296
260	0	18	12	6042	1614	18	2012-01-13 20:25:02.795296	2012-01-13 20:25:02.795296
261	0	8	2	9961	2838	16	2012-01-13 20:25:02.916909	2012-01-13 20:25:02.916909
284	0	16	3	3346	5068	16	2012-01-13 20:25:05.980329	2012-01-13 20:26:37.243184
299	0	12	18	4798	2914	9	2012-01-13 20:25:10.567612	2012-01-13 20:26:38.801274
263	0	1	4	9574	1769	10	2012-01-13 20:25:03.060773	2012-01-13 20:25:03.060773
324	0	9	15	8019	9612	20	2012-01-13 20:25:18.578293	2012-01-13 20:26:03.156406
311	0	4	6	8271	6772	18	2012-01-13 20:25:15.747712	2012-01-13 20:44:37.789033
300	1870	16	3	1870	9559	13	2012-01-13 20:25:10.58754	\N
267	0	11	19	5450	5540	20	2012-01-13 20:25:03.24902	2012-01-13 20:25:03.24902
287	0	4	10	685	3933	11	2012-01-13 20:25:06.35563	2012-01-13 20:25:56.00765
334	0	17	13	5406	8922	7	2012-01-13 20:25:20.434675	2012-01-14 02:48:01.268461
278	0	1	4	1082	4527	7	2012-01-13 20:25:04.288951	2012-01-14 00:33:47.127908
270	0	12	15	4089	8633	9	2012-01-13 20:25:03.415182	2012-01-14 01:11:58.560515
249	0	17	10	3900	8016	8	2012-01-13 20:25:01.322821	2012-01-13 20:30:36.136266
286	1596	16	7	1596	8522	14	2012-01-13 20:25:06.211918	\N
274	0	13	4	1541	50	17	2012-01-13 20:25:03.9904	2012-01-13 20:25:03.9904
275	5172	11	6	5172	6969	3	2012-01-13 20:25:04.067807	\N
266	0	9	13	3984	762	2	2012-01-13 20:25:03.215546	2012-01-13 20:25:06.35563
277	0	7	15	7934	105	15	2012-01-13 20:25:04.211024	2012-01-13 20:25:04.211024
269	0	10	16	7165	3352	18	2012-01-13 20:25:03.381918	2012-01-13 20:25:14.874942
279	0	7	4	7758	9228	7	2012-01-13 20:25:04.344413	2012-01-13 20:25:06.35563
264	0	1	9	2912	4313	12	2012-01-13 20:25:03.139226	2012-01-13 20:25:57.618307
250	0	16	5	5101	382	1	2012-01-13 20:25:01.333941	2012-01-13 20:25:14.874942
309	0	18	7	9284	3820	13	2012-01-13 20:25:14.874942	2012-01-13 20:25:14.874942
337	0	10	20	3802	5373	7	2012-01-13 20:25:20.811023	2012-01-13 20:27:34.159468
332	4389	3	7	4389	6633	2	2012-01-13 20:25:20.158746	\N
317	0	17	8	2485	4806	13	2012-01-13 20:25:16.918619	2012-01-13 20:29:56.304211
292	52	12	7	52	2267	11	2012-01-13 20:25:08.277923	\N
265	0	19	6	3469	1322	18	2012-01-13 20:25:03.193668	2012-01-13 20:42:58.259355
335	0	18	15	8539	5855	13	2012-01-13 20:25:20.457236	2012-01-13 20:25:28.313145
295	0	15	3	9359	7424	13	2012-01-13 20:25:08.378123	2012-01-13 20:25:08.378123
271	0	10	8	3318	6952	14	2012-01-13 20:25:03.426161	2012-01-13 20:55:07.32183
322	367	5	7	367	8701	10	2012-01-13 20:25:18.233537	\N
296	0	18	5	3844	1294	15	2012-01-13 20:25:08.948451	2012-01-13 20:25:13.006728
294	0	5	14	5737	2263	11	2012-01-13 20:25:08.30034	2012-01-13 20:25:13.006728
305	0	14	5	3269	1132	13	2012-01-13 20:25:13.006728	2012-01-13 20:25:13.006728
306	437	16	17	437	3827	13	2012-01-13 20:25:14.577425	\N
252	0	16	11	9137	3330	2	2012-01-13 20:25:01.435324	2012-01-13 20:26:19.6324
318	61	18	5	61	4049	18	2012-01-13 20:25:16.962794	\N
280	0	7	19	8564	9209	11	2012-01-13 20:25:04.599367	2012-01-13 20:25:14.874942
285	0	19	3	4903	6450	1	2012-01-13 20:25:06.057094	2012-01-13 20:25:14.874942
315	0	12	3	8933	4698	6	2012-01-13 20:25:16.730533	2012-01-13 20:26:26.060325
314	0	8	16	5081	1204	13	2012-01-13 20:25:16.575229	2012-01-13 20:25:16.575229
302	0	12	3	6757	5023	12	2012-01-13 20:25:12.068173	2012-01-13 20:26:26.358181
262	0	5	6	6287	7662	5	2012-01-13 20:25:03.005888	2012-01-13 20:26:26.358181
312	0	9	1	9452	7149	11	2012-01-13 20:25:15.891305	2012-01-13 20:25:18.111764
321	0	8	9	3000	5179	11	2012-01-13 20:25:18.111764	2012-01-13 20:25:18.111764
308	0	19	20	8966	8462	8	2012-01-13 20:25:14.697089	2012-01-13 20:25:52.633901
297	0	8	14	4710	6562	14	2012-01-13 20:25:09.062947	2012-01-13 20:25:18.932951
323	0	14	19	6778	4115	7	2012-01-13 20:25:18.357631	2012-01-13 20:25:18.932951
307	0	19	13	9350	1994	12	2012-01-13 20:25:14.663842	2012-01-13 20:25:18.932951
325	0	13	8	7240	1833	14	2012-01-13 20:25:18.932951	2012-01-13 20:25:18.932951
326	4341	15	6	4341	6336	16	2012-01-13 20:25:19.04237	\N
331	0	14	4	6855	1633	5	2012-01-13 20:25:20.060013	2012-01-13 20:25:20.060013
303	0	11	15	919	3172	17	2012-01-13 20:25:12.078635	2012-01-13 20:25:19.716155
330	0	15	10	4256	6458	20	2012-01-13 20:25:19.716155	2012-01-13 20:25:19.716155
298	0	10	5	3593	4009	2	2012-01-13 20:25:09.173886	2012-01-13 20:25:34.446105
268	0	15	14	5254	8190	13	2012-01-13 20:25:03.315542	2012-01-13 20:25:52.633901
338	153	12	5	153	4194	7	2012-01-13 20:25:21.187488	\N
310	0	4	1	7654	6158	15	2012-01-13 20:25:15.173774	2012-01-13 20:25:25.088845
402	0	16	12	6192	7145	3	2012-01-13 20:25:43.485398	2012-01-13 20:26:18.203941
419	0	12	16	5074	9383	1	2012-01-13 20:25:51.628678	2012-01-13 20:26:28.854551
343	0	3	10	5636	633	12	2012-01-13 20:25:22.015997	2012-01-13 20:25:22.015997
415	0	16	8	8784	1455	1	2012-01-13 20:25:49.783471	2012-01-13 20:26:18.403152
410	0	14	16	149	7756	8	2012-01-13 20:25:47.806252	2012-01-13 22:13:14.54634
361	0	12	9	2693	8709	12	2012-01-13 20:25:29.364368	2012-01-13 22:24:45.169604
423	0	7	6	741	2194	2	2012-01-13 20:25:52.613167	2012-01-14 02:09:03.523079
346	0	14	12	2720	3843	8	2012-01-13 20:25:23.285944	2012-01-13 20:25:23.285944
347	1896	12	2	1896	8245	1	2012-01-13 20:25:23.441294	\N
363	0	18	5	1401	5972	17	2012-01-13 20:25:29.871271	2012-01-13 20:26:44.835147
349	3441	18	6	3441	9952	5	2012-01-13 20:25:23.969516	\N
352	0	10	9	7074	9956	16	2012-01-13 20:25:24.679348	2012-01-13 20:26:37.243184
359	0	19	10	804	9795	2	2012-01-13 20:25:28.590079	2012-01-13 20:27:19.896675
389	0	12	3	5064	8264	20	2012-01-13 20:25:40.148245	2012-01-13 20:26:43.717375
353	0	1	12	6088	7453	15	2012-01-13 20:25:25.088845	2012-01-13 20:25:34.446105
374	0	5	13	7951	7420	9	2012-01-13 20:25:34.644575	2012-01-13 20:26:02.713767
340	0	4	1	5127	1534	9	2012-01-13 20:25:21.441162	2012-01-13 20:25:34.446105
373	0	1	10	1681	2480	16	2012-01-13 20:25:34.446105	2012-01-13 20:25:34.446105
358	0	2	18	5128	3464	19	2012-01-13 20:25:28.313145	2012-01-13 20:25:28.313145
354	0	11	15	3486	10000	19	2012-01-13 20:25:25.375193	2012-01-13 20:27:55.496838
421	0	2	3	2539	3319	15	2012-01-13 20:25:51.993038	2012-01-13 20:26:03.156406
407	0	13	7	1125	7734	20	2012-01-13 20:25:46.481537	2012-01-13 20:26:49.274485
364	2535	3	7	2535	3128	16	2012-01-13 20:25:30.070189	\N
360	0	7	17	4370	6988	13	2012-01-13 20:25:28.799978	2012-01-13 20:25:30.236067
365	0	11	2	1229	3745	2	2012-01-13 20:25:30.236067	2012-01-13 20:25:30.236067
418	0	5	1	702	103	20	2012-01-13 20:25:51.518088	2012-01-13 20:26:20.237003
368	2466	3	18	2466	2817	6	2012-01-13 20:25:31.539352	\N
369	584	14	15	584	7092	3	2012-01-13 20:25:31.694716	\N
406	0	7	9	9238	7663	10	2012-01-13 20:25:45.71751	2012-01-13 20:25:48.039169
371	273	18	7	273	2327	4	2012-01-13 20:25:32.82132	\N
379	0	17	11	8926	1578	18	2012-01-13 20:25:35.837319	2012-01-13 20:26:13.475158
392	0	8	15	7940	11	4	2012-01-13 20:25:40.876417	2012-01-13 20:25:40.876417
414	0	20	10	4067	8921	18	2012-01-13 20:25:49.473838	2012-01-13 20:26:17.010159
390	0	13	20	4563	6506	2	2012-01-13 20:25:40.323873	2012-01-13 20:25:48.039169
382	1478	10	14	1478	6669	8	2012-01-13 20:25:36.765973	\N
393	1736	7	14	1736	9658	10	2012-01-13 20:25:41.059107	\N
427	0	17	5	4668	3453	3	2012-01-13 20:25:53.62875	2012-01-13 20:26:30.214922
328	0	16	17	5559	1964	1	2012-01-13 20:25:19.263657	2012-01-13 20:25:41.674824
376	0	17	20	4932	1268	14	2012-01-13 20:25:34.843733	2012-01-13 20:25:41.674824
380	0	3	18	5113	671	9	2012-01-13 20:25:36.364394	2012-01-13 20:25:37.395187
384	0	18	3	1997	3970	1	2012-01-13 20:25:37.395187	2012-01-13 20:25:37.395187
385	2960	12	8	2960	8088	7	2012-01-13 20:25:37.716988	\N
283	0	20	8	5650	9163	9	2012-01-13 20:25:05.548304	2012-01-13 20:25:41.674824
375	0	11	2	624	1679	1	2012-01-13 20:25:34.668473	2012-01-13 20:25:37.882085
386	0	2	9	3808	5788	12	2012-01-13 20:25:37.882085	2012-01-13 20:25:37.882085
411	0	20	7	8860	3133	19	2012-01-13 20:25:48.039169	2012-01-13 20:25:48.039169
391	0	16	11	4589	688	19	2012-01-13 20:25:40.544705	2012-01-13 20:26:11.133413
394	0	8	6	9908	165	8	2012-01-13 20:25:41.674824	2012-01-13 20:25:41.674824
395	3105	3	14	3105	8221	1	2012-01-13 20:25:41.828135	\N
399	0	15	8	5057	5869	12	2012-01-13 20:25:42.237515	2012-01-13 20:25:48.236938
355	0	5	9	9837	2769	1	2012-01-13 20:25:25.905984	2012-01-13 20:25:41.916649
396	0	9	5	3548	5821	15	2012-01-13 20:25:41.916649	2012-01-13 20:25:41.916649
397	143	11	14	143	5317	20	2012-01-13 20:25:42.038561	\N
362	0	7	13	9793	485	14	2012-01-13 20:25:29.839372	2012-01-13 20:25:44.866441
377	0	13	10	818	9616	1	2012-01-13 20:25:35.120918	2012-01-13 20:25:44.866441
398	0	9	19	1969	1845	3	2012-01-13 20:25:42.137754	2012-01-13 20:25:44.866441
404	0	19	7	8959	780	5	2012-01-13 20:25:44.866441	2012-01-13 20:25:44.866441
405	2590	18	6	2590	7149	6	2012-01-13 20:25:45.552604	\N
350	0	15	2	677	5706	20	2012-01-13 20:25:24.225984	2012-01-13 20:26:35.927924
351	0	12	5	4853	5203	16	2012-01-13 20:25:24.524966	2012-01-13 20:27:10.799209
412	0	18	17	5793	9863	15	2012-01-13 20:25:48.236938	2012-01-13 20:25:48.236938
381	0	2	6	7614	1345	20	2012-01-13 20:25:36.61131	2012-01-13 20:25:47.352319
409	0	20	2	6353	5091	20	2012-01-13 20:25:47.352319	2012-01-13 20:25:47.352319
413	277	4	14	277	5991	3	2012-01-13 20:25:49.321705	\N
388	0	8	2	5097	8078	14	2012-01-13 20:25:39.682393	2012-01-13 20:26:17.630109
400	0	6	17	542	8975	3	2012-01-13 20:25:42.635867	2012-01-13 20:25:51.342967
342	0	19	20	8242	2639	5	2012-01-13 20:25:21.817145	2012-01-13 20:25:51.342967
417	0	20	6	4032	90	4	2012-01-13 20:25:51.342967	2012-01-13 20:25:51.342967
426	0	13	7	7269	4022	17	2012-01-13 20:25:53.419586	2012-01-13 20:26:02.713767
416	0	1	4	9556	8308	13	2012-01-13 20:25:50.159602	2012-01-13 20:26:10.923234
422	3156	3	18	3156	3837	11	2012-01-13 20:25:52.125733	\N
420	0	20	4	3234	1454	18	2012-01-13 20:25:51.849554	2012-01-13 20:25:52.633901
424	0	14	19	1482	705	14	2012-01-13 20:25:52.633901	2012-01-13 20:25:52.633901
356	0	10	13	8194	3084	11	2012-01-13 20:25:27.864068	2012-01-13 20:26:17.010159
425	0	14	4	6643	5244	16	2012-01-13 20:25:52.811065	2012-01-13 20:25:56.00765
341	0	2	14	8385	2196	4	2012-01-13 20:25:21.651041	2012-01-13 20:26:17.630109
429	1110	2	6	1110	4353	11	2012-01-13 20:25:54.545086	\N
481	0	20	15	6643	7146	18	2012-01-13 20:26:14.704783	2012-01-13 20:29:17.457189
462	411	19	11	411	3188	7	2012-01-13 20:26:07.199813	\N
503	0	10	9	7109	7158	19	2012-01-13 20:26:24.072818	2012-01-13 20:27:45.097072
472	0	9	16	878	5354	15	2012-01-13 20:26:10.724954	2012-01-13 20:26:37.243184
430	0	8	14	1117	403	14	2012-01-13 20:25:54.567685	2012-01-13 20:25:56.00765
498	4679	10	4	4679	7801	4	2012-01-13 20:26:21.955232	\N
492	0	3	4	8609	6836	8	2012-01-13 20:26:19.982601	2012-01-13 20:36:07.425789
495	0	16	17	6502	6281	19	2012-01-13 20:26:20.966066	2012-01-13 20:26:28.854551
477	0	17	6	8005	6401	4	2012-01-13 20:26:13.430682	2012-01-13 22:32:29.633414
450	0	10	20	9956	7904	18	2012-01-13 20:26:01.785059	2012-01-13 20:26:29.165014
490	0	3	1	9370	8391	14	2012-01-13 20:26:18.690097	2012-01-13 20:26:26.358181
502	0	2	18	8748	7653	5	2012-01-13 20:26:23.408801	2012-01-13 20:26:58.292162
455	0	11	4	2955	9088	10	2012-01-13 20:26:04.10921	2012-01-13 20:27:29.739991
479	0	11	17	5180	2121	2	2012-01-13 20:26:13.475158	2012-01-13 20:26:13.475158
470	0	17	19	7099	5411	6	2012-01-13 20:26:09.784958	2012-01-13 20:27:34.159468
461	0	16	17	2072	5775	6	2012-01-13 20:26:07.012761	2012-01-13 20:26:30.214922
439	0	8	15	5365	8659	19	2012-01-13 20:25:57.873501	2012-01-13 22:30:03.587727
494	0	2	13	6789	5812	12	2012-01-13 20:26:20.779675	2012-01-13 20:27:13.725915
507	0	2	4	4239	6113	12	2012-01-13 20:26:25.131563	2012-01-13 20:30:52.18646
452	0	7	5	5636	202	11	2012-01-13 20:26:02.713767	2012-01-13 20:26:02.713767
453	915	16	14	915	5881	18	2012-01-13 20:26:02.957449	\N
446	0	8	9	4198	3142	17	2012-01-13 20:25:59.552865	2012-01-13 20:26:03.156406
454	0	15	2	9423	9223	9	2012-01-13 20:26:03.156406	2012-01-13 20:26:03.156406
464	0	2	1	1888	3499	17	2012-01-13 20:26:07.442738	2012-01-13 20:27:30.115446
491	0	11	16	3667	9268	11	2012-01-13 20:26:19.6324	2012-01-13 20:26:19.6324
457	785	10	9	785	8983	4	2012-01-13 20:26:05.20078	\N
1651	0	6	10	358	1738	4	2012-01-13 21:41:46.472431	2012-01-13 21:51:52.482874
478	0	10	6	7689	2060	5	2012-01-13 20:26:13.452834	2012-01-13 21:19:46.022743
431	0	17	8	2693	4832	10	2012-01-13 20:25:54.711783	2012-01-13 20:29:00.146913
432	0	15	13	2362	6545	12	2012-01-13 20:25:54.92227	2012-01-13 20:26:06.20487
456	0	13	12	2284	4961	6	2012-01-13 20:26:04.649435	2012-01-13 20:26:06.20487
459	0	9	15	8152	2709	6	2012-01-13 20:26:06.20487	2012-01-13 20:26:06.20487
471	0	3	18	5163	5755	12	2012-01-13 20:26:10.205771	2012-01-13 20:46:36.30891
501	0	11	15	5926	1440	20	2012-01-13 20:26:22.977284	2012-01-13 20:26:35.927924
433	0	17	19	8473	7845	17	2012-01-13 20:25:55.209868	2012-01-13 20:27:43.649414
467	0	2	15	4609	4226	3	2012-01-13 20:26:08.515129	2012-01-13 21:03:46.668676
497	0	1	20	8213	6207	20	2012-01-13 20:26:21.772045	2012-01-13 20:26:41.662659
449	0	9	11	8528	4818	9	2012-01-13 20:26:01.301248	2012-01-13 20:26:15.156
438	0	11	1	3915	3687	14	2012-01-13 20:25:57.618307	2012-01-13 20:26:10.923234
473	0	4	11	1680	2016	18	2012-01-13 20:26:10.923234	2012-01-13 20:26:10.923234
482	0	11	9	4964	6127	6	2012-01-13 20:26:15.156	2012-01-13 20:26:15.156
445	0	2	20	1636	5573	12	2012-01-13 20:25:59.265901	2012-01-13 20:26:11.133413
447	0	20	16	3854	8635	9	2012-01-13 20:25:59.696429	2012-01-13 20:26:11.133413
474	0	11	2	8876	5480	2	2012-01-13 20:26:11.133413	2012-01-13 20:26:11.133413
1653	0	6	3	759	3780	3	2012-01-13 21:42:00.874568	2012-01-13 21:42:00.874568
442	0	13	6	4799	6919	3	2012-01-13 20:25:58.691619	2012-01-14 04:27:24.466734
499	1414	12	20	1414	9792	18	2012-01-13 20:26:22.369715	\N
466	0	13	15	9085	953	19	2012-01-13 20:26:08.226983	2012-01-13 20:26:17.010159
485	0	19	7	7247	3595	5	2012-01-13 20:26:17.010159	2012-01-13 20:26:17.010159
436	0	18	19	5998	9762	19	2012-01-13 20:25:56.680877	2012-01-13 20:26:20.237003
435	0	13	8	8787	4837	4	2012-01-13 20:25:56.00765	2012-01-13 20:26:17.630109
486	0	14	13	5215	4239	19	2012-01-13 20:26:17.630109	2012-01-13 20:26:17.630109
444	0	10	17	4068	7309	15	2012-01-13 20:25:58.912178	2012-01-13 20:27:19.896675
493	0	19	5	5859	7028	4	2012-01-13 20:26:20.237003	2012-01-13 20:26:20.237003
448	0	12	4	7630	6150	19	2012-01-13 20:26:01.003013	2012-01-13 20:26:18.203941
488	0	4	16	4893	1554	1	2012-01-13 20:26:18.203941	2012-01-13 20:26:18.203941
489	0	8	16	2116	9418	4	2012-01-13 20:26:18.403152	2012-01-13 20:26:18.403152
487	0	2	9	4409	2878	8	2012-01-13 20:26:17.950008	2012-01-13 20:27:17.940949
434	0	14	19	5260	9979	18	2012-01-13 20:25:55.542392	2012-01-13 20:26:37.022044
505	0	18	14	9033	3063	12	2012-01-13 20:26:24.401936	2012-01-13 20:26:37.243184
443	0	2	14	4968	2103	11	2012-01-13 20:25:58.723773	2012-01-13 20:26:43.717375
504	2983	11	6	2983	4452	3	2012-01-13 20:26:24.369758	\N
500	0	11	1	3905	222	12	2012-01-13 20:26:22.801177	2012-01-13 20:26:22.801177
496	0	19	6	7670	1443	12	2012-01-13 20:26:21.751898	2012-01-13 20:26:37.022044
480	0	12	1	6043	8360	7	2012-01-13 20:26:13.697	2012-01-13 20:27:11.959818
468	0	12	18	1777	685	20	2012-01-13 20:26:08.993884	2012-01-13 20:28:23.998824
460	0	17	13	8665	7918	9	2012-01-13 20:26:06.504313	2012-01-13 20:32:17.799991
463	0	13	6	8813	2315	5	2012-01-13 20:26:07.421107	2012-01-13 20:32:17.799991
508	76	1	14	76	1070	10	2012-01-13 20:26:25.529657	\N
509	0	3	16	4709	5154	7	2012-01-13 20:26:25.706154	2012-01-13 20:26:26.060325
440	0	16	12	3378	6332	13	2012-01-13 20:25:58.083234	2012-01-13 20:26:25.706154
506	0	1	5	6434	520	15	2012-01-13 20:26:24.855913	2012-01-13 20:26:26.358181
441	0	16	13	5504	5366	20	2012-01-13 20:25:58.25983	2012-01-13 20:26:26.060325
510	0	13	12	1720	156	19	2012-01-13 20:26:26.060325	2012-01-13 20:26:26.060325
511	0	6	12	1093	313	9	2012-01-13 20:26:26.358181	2012-01-13 20:26:26.358181
585	0	13	7	4289	9995	10	2012-01-13 20:26:56.180609	2012-01-13 20:27:51.5387
571	320	10	14	320	3321	16	2012-01-13 20:26:51.826654	\N
583	0	17	5	6315	9209	18	2012-01-13 20:26:55.605378	2012-01-13 22:13:01.909331
544	0	18	17	6464	1700	3	2012-01-13 20:26:38.801274	2012-01-13 20:26:38.801274
517	0	2	12	8410	6008	11	2012-01-13 20:26:28.854551	2012-01-13 20:26:28.854551
518	0	20	16	6778	2	16	2012-01-13 20:26:29.165014	2012-01-13 20:26:29.165014
595	0	5	20	3558	3079	8	2012-01-13 20:27:01.739781	2012-01-13 20:27:10.799209
520	5459	16	18	5459	9376	7	2012-01-13 20:26:29.618398	\N
521	0	5	16	7248	3125	6	2012-01-13 20:26:30.214922	2012-01-13 20:26:30.214922
522	1024	11	13	1024	6166	9	2012-01-13 20:26:30.503365	\N
524	1679	17	4	1679	7047	1	2012-01-13 20:26:31.04506	\N
572	0	17	8	2702	7998	2	2012-01-13 20:26:51.958648	2012-01-13 20:33:35.404908
525	0	1	14	3099	6304	6	2012-01-13 20:26:31.321923	2012-01-13 20:32:28.105693
1654	0	18	3	8432	9685	3	2012-01-13 21:42:04.6439	2012-01-13 21:42:04.6439
528	0	13	15	5132	4730	4	2012-01-13 20:26:32.94461	2012-01-13 20:27:39.695103
541	0	9	19	6353	6734	12	2012-01-13 20:26:37.420051	2012-01-13 20:27:45.097072
523	0	1	19	6841	4446	1	2012-01-13 20:26:30.702262	2012-01-13 20:26:34.073468
529	0	19	1	7179	2533	9	2012-01-13 20:26:34.073468	2012-01-13 20:26:34.073468
530	0	3	17	9001	3236	9	2012-01-13 20:26:34.44755	2012-01-13 20:26:34.44755
531	7030	16	17	7030	6757	20	2012-01-13 20:26:34.590877	\N
586	0	17	8	2147	632	12	2012-01-13 20:26:56.481582	2012-01-13 20:27:33.739715
534	0	20	4	4409	120	19	2012-01-13 20:26:35.806866	2012-01-13 20:26:35.806866
565	0	16	9	7406	6928	6	2012-01-13 20:26:45.320227	2012-01-13 20:44:52.022746
515	0	2	8	4529	961	16	2012-01-13 20:26:28.700817	2012-01-13 20:26:35.927924
538	0	20	13	7697	4189	9	2012-01-13 20:26:36.855695	2012-01-13 20:27:21.490118
563	0	5	18	6935	1525	13	2012-01-13 20:26:44.835147	2012-01-13 20:26:44.835147
594	0	4	19	7035	4750	18	2012-01-13 20:27:01.374142	2012-01-13 20:27:19.896675
552	0	8	11	6509	8290	11	2012-01-13 20:26:40.778912	2012-01-13 20:27:27.940756
539	0	6	14	3462	6434	8	2012-01-13 20:26:37.022044	2012-01-13 20:26:37.022044
533	0	3	18	5518	330	12	2012-01-13 20:26:35.364327	2012-01-13 20:26:37.243184
526	0	14	4	4632	5946	15	2012-01-13 20:26:31.97472	2012-01-13 20:26:37.243184
540	0	4	10	7714	2832	20	2012-01-13 20:26:37.243184	2012-01-13 20:26:37.243184
514	0	10	4	8491	4102	15	2012-01-13 20:26:28.227661	2012-01-13 20:27:46.002311
532	0	10	7	8186	1823	18	2012-01-13 20:26:35.227057	2012-01-13 20:26:37.630144
542	0	7	10	9687	7142	2	2012-01-13 20:26:37.630144	2012-01-13 20:26:37.630144
576	0	18	4	1993	5670	10	2012-01-13 20:26:53.074279	2012-01-13 22:44:23.066717
551	324	3	12	324	8199	5	2012-01-13 20:26:40.625146	\N
557	0	7	16	654	7772	11	2012-01-13 20:26:42.171179	2012-01-13 20:27:28.645509
579	0	3	15	6430	7531	19	2012-01-13 20:26:54.179162	2012-01-14 03:27:50.232295
573	0	17	6	7227	9958	19	2012-01-13 20:26:52.312786	2012-01-13 23:48:32.643527
554	0	20	1	9258	3689	8	2012-01-13 20:26:41.662659	2012-01-13 20:26:41.662659
555	432	3	15	432	8750	8	2012-01-13 20:26:41.817609	\N
556	1393	5	4	1393	9476	11	2012-01-13 20:26:42.039073	\N
562	0	8	2	3242	6988	14	2012-01-13 20:26:44.425577	2012-01-13 20:27:30.115446
1655	2184	20	19	2184	4142	20	2012-01-13 21:42:21.960568	\N
516	0	20	6	6546	2375	18	2012-01-13 20:26:28.833104	2012-01-13 22:01:06.207045
537	0	7	6	7393	29	18	2012-01-13 20:26:36.83368	2012-01-13 20:27:13.073847
545	0	14	12	659	2268	2	2012-01-13 20:26:38.978074	2012-01-13 20:26:43.717375
536	0	3	17	2790	788	2	2012-01-13 20:26:36.704061	2012-01-13 20:26:43.717375
560	0	17	2	5115	808	1	2012-01-13 20:26:43.717375	2012-01-13 20:26:43.717375
543	0	18	14	6007	4697	16	2012-01-13 20:26:38.449933	2012-01-13 22:26:23.357693
513	0	9	18	7612	9122	13	2012-01-13 20:26:27.484337	2012-01-13 20:26:49.274485
558	0	18	13	4329	1152	3	2012-01-13 20:26:42.746415	2012-01-13 20:26:49.274485
567	0	7	9	8723	1722	1	2012-01-13 20:26:49.274485	2012-01-13 20:26:49.274485
574	0	15	8	2268	9885	17	2012-01-13 20:26:52.334326	2012-01-13 20:27:11.959818
550	0	5	1	1168	8148	6	2012-01-13 20:26:40.247963	2012-01-13 20:26:50.801543
548	0	1	18	9876	9183	17	2012-01-13 20:26:39.430458	2012-01-13 20:26:50.801543
553	0	18	15	5482	2059	12	2012-01-13 20:26:41.51072	2012-01-13 20:26:50.801543
561	0	15	10	2482	7292	9	2012-01-13 20:26:44.083296	2012-01-13 20:26:50.801543
566	0	10	16	4896	4840	6	2012-01-13 20:26:48.924462	2012-01-13 20:26:50.801543
568	0	16	5	9854	951	5	2012-01-13 20:26:50.801543	2012-01-13 20:26:50.801543
580	0	7	12	4497	6191	14	2012-01-13 20:26:54.788619	2012-01-13 20:27:11.959818
570	7695	10	5	7695	9575	20	2012-01-13 20:26:51.373511	\N
535	0	8	9	6597	7191	19	2012-01-13 20:26:35.927924	2012-01-13 20:27:20.084462
582	7224	8	6	7224	7339	3	2012-01-13 20:26:55.573075	\N
546	0	20	3	1560	8218	12	2012-01-13 20:26:39.165498	2012-01-13 20:28:25.346904
547	0	19	6	9432	320	11	2012-01-13 20:26:39.409052	2012-01-13 20:27:34.159468
581	0	3	14	7714	167	15	2012-01-13 20:26:55.307155	2012-01-13 20:28:25.346904
588	4212	3	18	4212	5385	3	2012-01-13 20:26:57.055778	\N
592	7984	3	17	7984	7125	11	2012-01-13 20:26:59.849931	\N
590	0	18	2	9373	5138	8	2012-01-13 20:26:58.292162	2012-01-13 20:26:58.292162
587	0	1	19	7489	988	3	2012-01-13 20:26:56.746826	2012-01-13 20:27:11.959818
596	1288	18	12	1288	9340	7	2012-01-13 20:27:01.927376	\N
597	1546	3	7	1546	7825	17	2012-01-13 20:27:02.579728	\N
569	0	11	9	1896	1158	4	2012-01-13 20:26:51.141382	2012-01-13 20:27:07.506667
519	0	9	14	4524	1984	20	2012-01-13 20:26:29.319404	2012-01-13 20:27:07.506667
584	0	14	18	1882	7484	9	2012-01-13 20:26:55.971255	2012-01-13 20:27:07.506667
653	0	2	13	3247	4456	20	2012-01-13 20:27:30.502679	2012-01-13 22:39:29.112443
1656	175	8	7	175	7029	20	2012-01-13 21:42:27.609039	\N
619	0	15	18	6267	6468	20	2012-01-13 20:27:14.082147	2012-01-13 20:27:55.496838
599	0	20	15	3939	5352	14	2012-01-13 20:27:04.301701	2012-01-13 21:53:30.795545
604	0	5	14	6574	9963	6	2012-01-13 20:27:06.964137	2012-01-13 22:40:10.634592
638	0	12	15	6362	9312	11	2012-01-13 20:27:22.11801	2012-01-13 22:46:47.32745
623	0	20	8	3492	4995	11	2012-01-13 20:27:16.913832	2012-01-14 03:01:46.915235
629	0	2	6	5302	5285	8	2012-01-13 20:27:19.091516	2012-01-13 22:53:21.594722
605	0	18	11	4751	4047	17	2012-01-13 20:27:07.506667	2012-01-13 20:27:07.506667
606	4864	16	15	4864	6694	4	2012-01-13 20:27:08.126319	\N
673	0	14	8	2811	8089	18	2012-01-13 20:27:40.645094	2012-01-13 20:32:28.105693
640	0	2	18	2663	8701	5	2012-01-13 20:27:23.101123	2012-01-13 23:18:48.025037
672	0	19	1	9546	5628	5	2012-01-13 20:27:39.947963	2012-01-13 20:27:51.5387
667	0	9	10	4784	9044	6	2012-01-13 20:27:37.806981	2012-01-13 20:47:51.138836
610	0	20	12	5863	4448	11	2012-01-13 20:27:10.799209	2012-01-13 20:27:10.799209
611	2724	16	13	2724	3563	5	2012-01-13 20:27:11.350734	\N
636	0	13	17	4188	3922	15	2012-01-13 20:27:21.490118	2012-01-13 20:27:21.490118
612	0	19	15	7589	3097	15	2012-01-13 20:27:11.959818	2012-01-13 20:27:11.959818
655	0	3	12	9262	5892	1	2012-01-13 20:27:31.099204	2012-01-13 20:28:29.102554
614	7130	16	15	7130	8954	13	2012-01-13 20:27:12.610463	\N
677	0	7	5	9852	7163	18	2012-01-13 20:27:42.246088	2012-01-13 20:42:15.550722
616	0	6	7	1131	6322	11	2012-01-13 20:27:13.073847	2012-01-13 20:27:13.073847
617	819	13	11	819	5807	11	2012-01-13 20:27:13.550268	\N
618	0	13	2	8260	9021	5	2012-01-13 20:27:13.725915	2012-01-13 20:27:13.725915
678	0	18	15	6056	6084	10	2012-01-13 20:27:43.153128	2012-01-13 20:28:23.998824
620	1619	2	11	1619	7244	10	2012-01-13 20:27:14.511477	\N
621	3576	9	15	3576	7357	3	2012-01-13 20:27:14.846835	\N
615	0	13	9	893	4639	15	2012-01-13 20:27:12.941679	2012-01-13 20:41:39.101424
681	0	15	5	3728	5454	11	2012-01-13 20:27:44.190343	2012-01-13 20:37:43.668614
664	0	8	15	7569	8637	2	2012-01-13 20:27:35.885473	2012-01-13 20:28:28.625285
626	0	9	2	6375	4812	16	2012-01-13 20:27:17.940949	2012-01-13 20:27:17.940949
627	2960	19	6	2960	6230	4	2012-01-13 20:27:18.339842	\N
641	0	1	15	3354	4036	2	2012-01-13 20:27:23.310665	2012-01-13 20:27:51.5387
635	0	9	2	3829	6495	15	2012-01-13 20:27:20.725934	2012-01-14 01:04:54.082806
657	0	7	17	5604	9439	19	2012-01-13 20:27:31.83916	2012-01-13 20:27:34.159468
624	0	16	5	4400	996	3	2012-01-13 20:27:17.354319	2012-01-14 06:27:25.088944
632	0	17	4	8062	14	18	2012-01-13 20:27:19.896675	2012-01-13 20:27:19.896675
633	0	9	8	8712	550	6	2012-01-13 20:27:20.084462	2012-01-13 20:27:20.084462
625	0	15	9	2369	5473	6	2012-01-13 20:27:17.75135	2012-01-13 20:28:23.998824
643	7398	16	7	7398	8565	2	2012-01-13 20:27:25.756329	\N
652	0	1	8	9405	1303	3	2012-01-13 20:27:30.115446	2012-01-13 20:27:30.115446
630	0	11	5	8702	3175	17	2012-01-13 20:27:19.122869	2012-01-13 20:27:27.940756
637	0	5	18	8860	7380	16	2012-01-13 20:27:21.71967	2012-01-13 20:27:27.940756
646	0	18	8	6614	1214	9	2012-01-13 20:27:27.940756	2012-01-13 20:27:27.940756
661	0	6	12	1319	8187	1	2012-01-13 20:27:34.159468	2012-01-13 20:27:34.159468
654	0	15	12	3964	624	20	2012-01-13 20:27:30.834758	2012-01-13 20:27:30.834758
644	0	8	19	4774	9512	19	2012-01-13 20:27:26.627213	2012-01-13 20:27:28.645509
645	0	19	7	8694	2707	10	2012-01-13 20:27:27.177657	2012-01-13 20:27:28.645509
648	0	16	8	7465	945	11	2012-01-13 20:27:28.645509	2012-01-13 20:27:28.645509
607	0	20	19	7620	6281	1	2012-01-13 20:27:09.200037	2012-01-13 20:30:17.169907
650	0	4	11	8910	2032	5	2012-01-13 20:27:29.739991	2012-01-13 20:27:29.739991
659	0	7	5	8447	6933	18	2012-01-13 20:27:33.220289	2012-01-13 20:28:39.498005
656	2451	12	20	2451	8713	7	2012-01-13 20:27:31.629665	\N
602	0	16	14	5632	810	16	2012-01-13 20:27:05.639036	2012-01-13 20:52:57.690051
649	0	3	20	6461	3663	16	2012-01-13 20:27:29.409865	2012-01-13 20:29:17.457189
660	0	8	17	2833	4045	4	2012-01-13 20:27:33.739715	2012-01-13 20:27:33.739715
670	8458	3	13	8458	8761	2	2012-01-13 20:27:38.822509	\N
658	0	12	10	8565	7347	12	2012-01-13 20:27:32.802319	2012-01-13 20:27:34.159468
651	0	20	7	2870	1404	2	2012-01-13 20:27:29.960862	2012-01-13 20:27:34.159468
639	0	18	12	2949	8867	4	2012-01-13 20:27:22.660397	2012-01-13 20:32:48.262847
628	0	19	12	5485	8333	10	2012-01-13 20:27:18.371529	2012-01-13 20:27:46.002311
662	0	18	8	4447	6091	7	2012-01-13 20:27:34.81147	2012-01-13 20:32:47.487982
665	1387	16	10	1387	4202	12	2012-01-13 20:27:36.458474	\N
666	3596	20	7	3596	5909	3	2012-01-13 20:27:36.98878	\N
642	0	1	3	2141	9093	17	2012-01-13 20:27:23.675529	2012-01-13 20:27:38.059732
613	0	3	4	6395	1698	12	2012-01-13 20:27:12.190184	2012-01-13 20:27:38.059732
668	0	4	1	7935	3763	10	2012-01-13 20:27:38.059732	2012-01-13 20:27:38.059732
671	0	15	13	5961	3956	14	2012-01-13 20:27:39.695103	2012-01-13 20:27:39.695103
669	0	15	17	5192	9705	2	2012-01-13 20:27:38.313007	2012-01-13 20:28:28.625285
676	0	11	2	769	5695	2	2012-01-13 20:27:41.982167	2012-01-13 20:35:02.492161
634	0	15	13	6753	7584	20	2012-01-13 20:27:20.316835	2012-01-13 20:27:51.5387
675	277	8	7	277	9524	9	2012-01-13 20:27:41.451246	\N
680	0	10	4	6586	5210	7	2012-01-13 20:27:43.947982	2012-01-13 20:38:56.888641
609	0	3	7	9758	7049	10	2012-01-13 20:27:09.837167	2012-01-13 20:47:20.690727
622	0	3	10	5164	7971	11	2012-01-13 20:27:15.36623	2012-01-13 20:38:59.655468
679	0	19	17	5367	4937	4	2012-01-13 20:27:43.649414	2012-01-13 20:27:43.649414
663	0	19	7	8514	9520	8	2012-01-13 20:27:35.009743	2012-01-13 20:27:45.097072
760	0	6	5	3029	9248	14	2012-01-13 20:28:41.853385	2012-01-13 20:32:14.875653
683	0	7	10	4127	709	8	2012-01-13 20:27:45.097072	2012-01-13 20:27:45.097072
684	1005	13	14	1005	5641	5	2012-01-13 20:27:45.429352	\N
711	0	9	2	9402	8490	4	2012-01-13 20:28:03.406616	2012-01-13 20:30:52.18646
608	0	12	7	3219	2914	6	2012-01-13 20:27:09.638584	2012-01-13 20:27:46.002311
674	0	7	10	3018	2557	15	2012-01-13 20:27:40.920161	2012-01-13 20:27:46.002311
686	0	4	19	4651	8128	2	2012-01-13 20:27:46.002311	2012-01-13 20:27:46.002311
687	0	20	17	6479	137	14	2012-01-13 20:27:46.877185	2012-01-13 20:27:46.877185
728	0	10	13	6714	4393	6	2012-01-13 20:28:23.126934	2012-01-13 21:32:10.919457
715	0	9	17	3116	1410	1	2012-01-13 20:28:08.343807	2012-01-13 20:28:23.998824
761	0	19	7	8181	8292	11	2012-01-13 20:28:42.281558	2012-01-13 20:33:41.142879
763	0	18	17	2334	8742	5	2012-01-13 20:28:43.806353	2012-01-13 22:51:04.479666
729	0	11	12	4437	3433	5	2012-01-13 20:28:23.998824	2012-01-13 20:28:23.998824
692	2000	17	19	2000	4578	1	2012-01-13 20:27:49.768799	\N
705	0	14	19	2412	8308	5	2012-01-13 20:27:58.159689	2012-01-13 20:37:46.719685
689	0	14	19	3946	8164	9	2012-01-13 20:27:47.738811	2012-01-13 20:27:51.5387
694	0	7	14	4151	553	16	2012-01-13 20:27:51.5387	2012-01-13 20:27:51.5387
693	0	16	12	7574	3300	6	2012-01-13 20:27:50.223249	2012-01-13 20:37:33.21281
751	0	8	2	3102	4626	8	2012-01-13 20:28:37.520949	2012-01-14 04:35:51.503508
759	0	3	1	6703	1741	11	2012-01-13 20:28:40.978078	2012-01-13 20:46:15.588877
1658	1504	4	14	1504	1638	6	2012-01-13 21:42:53.855111	\N
717	1073	10	8	1073	9419	4	2012-01-13 20:28:10.141392	\N
710	0	3	1	8470	7392	4	2012-01-13 20:28:01.197385	2012-01-13 21:46:50.559258
706	0	8	10	2515	1689	14	2012-01-13 20:27:58.47749	2012-01-13 20:28:25.346904
708	0	10	20	2010	3007	1	2012-01-13 20:27:59.550707	2012-01-13 20:28:25.346904
701	0	18	11	3665	445	20	2012-01-13 20:27:55.496838	2012-01-13 20:27:55.496838
732	0	16	17	8547	1189	8	2012-01-13 20:28:26.648126	2012-01-13 20:28:31.22551
730	0	14	8	3621	3585	15	2012-01-13 20:28:25.346904	2012-01-13 20:28:25.346904
762	0	19	17	2946	2645	9	2012-01-13 20:28:43.401434	2012-01-13 20:29:00.146913
698	0	2	13	3996	2243	13	2012-01-13 20:27:53.394368	2012-01-13 20:44:53.281712
741	0	17	16	2130	2322	6	2012-01-13 20:28:31.22551	2012-01-13 20:28:31.22551
749	0	12	10	8094	8411	18	2012-01-13 20:28:35.367121	2012-01-13 20:33:11.614546
1657	0	11	14	8091	9527	1	2012-01-13 21:42:39.540514	2012-01-13 21:52:28.460667
682	0	4	5	6556	8944	12	2012-01-13 20:27:44.522184	2012-01-13 20:31:41.625862
688	0	16	9	5978	7341	15	2012-01-13 20:27:47.09604	2012-01-13 21:08:36.390255
697	0	2	6	8138	9190	12	2012-01-13 20:27:53.35951	2012-01-14 00:25:29.78719
742	5900	3	6	5900	7266	16	2012-01-13 20:28:31.499554	\N
719	2274	9	19	2274	7758	14	2012-01-13 20:28:11.720719	\N
714	627	3	18	627	7658	14	2012-01-13 20:28:07.236178	\N
726	0	12	4	7107	2198	4	2012-01-13 20:28:20.416433	2012-01-13 20:28:26.052669
703	0	14	1	6662	6944	10	2012-01-13 20:27:56.368084	2012-01-13 20:28:14.357487
700	0	1	2	5283	7895	12	2012-01-13 20:27:54.520991	2012-01-13 20:28:14.357487
720	0	2	14	5354	1455	3	2012-01-13 20:28:14.357487	2012-01-13 20:28:14.357487
721	1491	10	15	1491	5982	2	2012-01-13 20:28:14.681883	\N
702	0	4	5	7796	8615	12	2012-01-13 20:27:55.782609	2012-01-13 20:28:26.052669
731	0	5	12	9649	5811	8	2012-01-13 20:28:26.052669	2012-01-13 20:28:26.052669
723	2479	10	15	2479	7348	12	2012-01-13 20:28:16.528111	\N
752	0	5	2	2366	8573	7	2012-01-13 20:28:38.061679	2012-01-13 20:30:10.169024
733	508	19	1	508	9138	1	2012-01-13 20:28:27.266538	\N
734	2425	9	5	2425	5653	17	2012-01-13 20:28:27.553693	\N
727	7449	3	7	7449	9024	18	2012-01-13 20:28:21.214135	\N
743	141	10	6	141	6164	2	2012-01-13 20:28:31.523138	\N
735	6334	3	17	6334	6289	5	2012-01-13 20:28:28.139819	\N
736	0	17	8	3816	1605	12	2012-01-13 20:28:28.625285	2012-01-13 20:28:28.625285
737	1668	20	8	1668	9914	9	2012-01-13 20:28:28.915063	\N
744	2108	9	4	2108	6107	18	2012-01-13 20:28:31.554673	\N
738	0	12	3	6679	8647	20	2012-01-13 20:28:29.102554	2012-01-13 20:28:29.102554
758	523	12	10	523	2510	10	2012-01-13 20:28:40.736222	\N
690	0	7	8	6301	5188	17	2012-01-13 20:27:48.2796	2012-01-13 20:28:33.124813
745	0	8	4	7575	4581	16	2012-01-13 20:28:32.28619	2012-01-13 20:28:33.124813
746	0	4	7	6625	7380	4	2012-01-13 20:28:33.124813	2012-01-13 20:28:33.124813
707	0	16	18	5336	438	8	2012-01-13 20:27:58.786823	2012-01-13 20:32:48.262847
748	3111	15	13	3111	6880	16	2012-01-13 20:28:34.804193	\N
757	0	9	20	4665	4758	19	2012-01-13 20:28:40.216557	2012-01-13 20:30:17.169907
750	0	8	9	5573	5709	16	2012-01-13 20:28:36.883445	2012-01-13 20:29:56.304211
747	0	16	3	9630	5138	19	2012-01-13 20:28:34.021147	2012-01-13 20:30:52.18646
755	912	12	1	912	3850	5	2012-01-13 20:28:39.265011	\N
685	0	11	17	5970	8184	1	2012-01-13 20:27:45.726074	2012-01-13 20:28:39.498005
740	0	17	7	9259	5059	7	2012-01-13 20:28:30.162169	2012-01-13 20:28:39.498005
709	0	5	19	4222	5529	14	2012-01-13 20:27:59.847268	2012-01-13 20:28:39.498005
756	0	19	11	6850	7485	12	2012-01-13 20:28:39.498005	2012-01-13 20:28:39.498005
712	0	12	1	8008	3583	11	2012-01-13 20:28:05.883179	2012-01-13 21:06:52.130506
696	0	18	4	4101	3872	20	2012-01-13 20:27:53.082703	2012-01-13 20:36:08.483665
765	0	9	3	2501	6966	7	2012-01-13 20:28:46.581818	2012-01-13 20:29:07.571793
754	0	1	6	7586	5763	5	2012-01-13 20:28:39.233849	2012-01-13 20:30:17.169907
764	0	9	12	8648	8355	15	2012-01-13 20:28:44.968139	2012-01-13 20:29:56.304211
704	0	19	14	9957	6972	4	2012-01-13 20:27:56.964651	2012-01-13 20:28:53.473678
753	0	3	18	9450	4014	4	2012-01-13 20:28:38.636104	2012-01-13 20:29:07.571793
820	0	10	5	5223	4187	8	2012-01-13 20:29:52.710024	2012-01-13 22:48:41.235372
819	0	15	18	2154	8483	19	2012-01-13 20:29:48.519792	2012-01-13 20:34:11.542635
817	0	20	11	6947	1159	2	2012-01-13 20:29:46.652672	2012-01-13 20:32:49.666772
811	0	2	15	5926	8725	17	2012-01-13 20:29:40.011454	2012-01-13 21:48:27.662169
847	0	7	2	3321	6400	1	2012-01-13 20:30:27.820115	2012-01-13 20:33:41.142879
772	0	14	19	4336	4468	14	2012-01-13 20:28:53.473678	2012-01-13 20:28:53.473678
833	0	7	17	2248	5794	13	2012-01-13 20:30:09.030186	2012-01-13 21:40:19.025745
790	0	12	18	4252	4033	7	2012-01-13 20:29:09.570491	2012-01-13 20:42:15.550722
769	0	17	14	7075	6783	2	2012-01-13 20:28:50.831202	2012-01-13 20:32:20.586325
767	0	20	1	6606	8267	2	2012-01-13 20:28:49.140487	2012-01-13 22:42:53.705007
777	188	11	5	188	2883	2	2012-01-13 20:28:59.229316	\N
855	0	12	18	6039	7868	10	2012-01-13 20:30:40.128519	2012-01-14 04:02:59.905667
1659	0	18	17	7608	8100	6	2012-01-13 21:43:00.48666	2012-01-13 21:45:10.249457
779	0	8	19	3710	648	17	2012-01-13 20:29:00.146913	2012-01-13 20:29:00.146913
1660	0	20	2	9559	7720	4	2012-01-13 21:43:12.84868	2012-01-13 22:03:13.415977
849	0	14	1	8627	4344	5	2012-01-13 20:30:30.071978	2012-01-13 20:31:41.625862
773	0	11	6	8491	7362	17	2012-01-13 20:28:53.969707	2012-01-13 21:39:56.691615
786	0	17	11	6589	5867	16	2012-01-13 20:29:06.240551	2012-01-13 20:44:45.759799
784	810	9	1	810	7967	2	2012-01-13 20:29:03.462888	\N
842	2286	3	8	2286	3939	11	2012-01-13 20:30:20.009241	\N
824	0	5	11	2831	9928	6	2012-01-13 20:29:57.090563	2012-01-13 20:50:36.996007
787	4411	10	4	4411	9690	6	2012-01-13 20:29:07.153245	\N
834	0	2	5	7312	253	2	2012-01-13 20:30:10.169024	2012-01-13 20:30:10.169024
788	0	18	9	9960	2894	1	2012-01-13 20:29:07.571793	2012-01-13 20:29:07.571793
832	0	10	15	2766	3056	9	2012-01-13 20:30:08.47719	2012-01-13 23:01:46.298052
783	0	19	15	975	1498	2	2012-01-13 20:29:02.965959	2012-01-13 20:42:42.53978
835	483	3	6	483	4071	8	2012-01-13 20:30:10.831115	\N
782	0	19	1	961	1655	12	2012-01-13 20:29:02.533545	2012-01-13 21:35:16.42628
794	286	14	1	286	6957	16	2012-01-13 20:29:12.313421	\N
815	0	18	6	5539	2113	6	2012-01-13 20:29:45.136537	2012-01-13 21:04:24.855158
805	0	19	4	3472	8732	6	2012-01-13 20:29:31.442811	2012-01-13 20:35:20.484393
801	0	7	11	3972	9964	7	2012-01-13 20:29:22.272918	2012-01-13 23:18:53.165934
827	0	20	6	4244	2476	16	2012-01-13 20:30:02.77253	2012-01-14 00:14:39.016369
841	0	3	2	2600	2042	12	2012-01-13 20:30:19.490139	2012-01-14 01:37:13.30649
846	0	4	9	3068	5830	8	2012-01-13 20:30:25.90868	2012-01-13 20:36:20.488591
816	0	11	6	8995	9195	8	2012-01-13 20:29:45.645578	2012-01-14 01:41:04.810828
798	0	15	3	8691	9551	1	2012-01-13 20:29:17.457189	2012-01-13 20:29:32.514609
785	0	3	19	4141	2070	1	2012-01-13 20:29:04.041479	2012-01-13 20:29:32.514609
778	0	10	12	3676	7697	3	2012-01-13 20:28:59.694213	2012-01-14 03:06:04.54155
823	0	12	17	4323	1015	6	2012-01-13 20:29:56.304211	2012-01-13 20:29:56.304211
774	0	16	8	8583	7664	8	2012-01-13 20:28:54.798731	2012-01-13 20:41:39.101424
845	0	7	13	3905	7006	17	2012-01-13 20:30:24.636908	2012-01-13 20:52:57.690051
809	566	3	18	566	3415	16	2012-01-13 20:29:36.885657	\N
775	0	5	17	3302	5638	19	2012-01-13 20:28:55.983904	2012-01-13 20:32:14.875653
813	282	10	2	282	8105	15	2012-01-13 20:29:43.236734	\N
826	1380	3	20	1380	7144	6	2012-01-13 20:29:59.874111	\N
792	0	8	17	2279	1258	9	2012-01-13 20:29:10.521904	2012-01-13 21:08:46.660514
821	0	10	15	7533	3630	6	2012-01-13 20:29:53.743274	2012-01-13 20:33:11.614546
796	0	8	1	6092	1331	9	2012-01-13 20:29:14.83361	2012-01-13 20:35:02.492161
804	0	11	19	1038	2703	9	2012-01-13 20:29:29.220352	2012-01-13 20:30:03.562297
791	0	19	6	8304	1219	10	2012-01-13 20:29:10.035135	2012-01-13 20:30:03.562297
828	0	6	11	2954	4492	10	2012-01-13 20:30:03.562297	2012-01-13 20:30:03.562297
844	2564	4	2	2564	8123	7	2012-01-13 20:30:23.953608	\N
830	4040	16	14	4040	4301	1	2012-01-13 20:30:06.101708	\N
831	4902	12	6	4902	7981	16	2012-01-13 20:30:08.006536	\N
806	0	19	1	9980	2524	6	2012-01-13 20:29:32.514609	2012-01-13 20:30:17.169907
837	0	6	9	3391	625	8	2012-01-13 20:30:17.169907	2012-01-13 20:30:17.169907
838	140	7	6	140	6303	18	2012-01-13 20:30:17.855205	\N
839	345	1	18	345	5921	20	2012-01-13 20:30:18.47446	\N
840	1216	3	11	1216	1555	6	2012-01-13 20:30:19.092343	\N
795	0	17	11	6234	9593	9	2012-01-13 20:29:12.852115	2012-01-13 20:53:21.410818
861	0	10	7	5261	3811	5	2012-01-13 20:30:49.368236	2012-01-13 20:36:24.078219
854	0	14	1	8082	8115	12	2012-01-13 20:30:37.287726	2012-01-13 20:33:52.032934
851	0	11	19	2426	9429	10	2012-01-13 20:30:33.622537	2012-01-13 20:32:49.666772
859	0	1	6	7509	4865	4	2012-01-13 20:30:47.551087	2012-01-13 20:33:52.032934
793	0	11	2	3137	8645	20	2012-01-13 20:29:10.985215	2012-01-13 20:30:36.136266
768	0	2	17	3385	3344	7	2012-01-13 20:28:50.402394	2012-01-13 20:30:36.136266
818	0	9	11	7550	1375	3	2012-01-13 20:29:47.491868	2012-01-13 20:30:36.136266
853	0	10	9	5853	4765	9	2012-01-13 20:30:36.136266	2012-01-13 20:30:36.136266
857	142	6	19	142	863	16	2012-01-13 20:30:44.662458	\N
858	1642	16	12	1642	8594	16	2012-01-13 20:30:45.293772	\N
843	0	15	19	8738	9982	13	2012-01-13 20:30:21.934777	2012-01-13 20:38:56.888641
770	0	17	4	2030	7391	19	2012-01-13 20:28:51.705568	2012-01-13 21:40:19.025745
862	385	14	17	385	6539	17	2012-01-13 20:30:51.438333	\N
781	0	4	12	5056	9240	3	2012-01-13 20:29:01.560065	2012-01-13 20:30:52.18646
825	0	12	16	650	3916	20	2012-01-13 20:29:58.825306	2012-01-13 20:30:52.18646
863	0	3	9	8635	262	11	2012-01-13 20:30:52.18646	2012-01-13 20:30:52.18646
864	2590	3	18	2590	3771	14	2012-01-13 20:30:52.649567	\N
867	0	10	20	2773	7375	15	2012-01-13 20:30:59.967325	2012-01-13 21:08:46.660514
878	0	3	13	9322	5758	17	2012-01-13 20:31:22.733796	2012-01-14 03:51:22.27465
958	0	9	6	8136	3381	20	2012-01-13 20:33:45.696673	2012-01-13 21:18:19.902239
921	2853	16	2	2853	8767	11	2012-01-13 20:32:33.297074	\N
945	0	12	9	9310	7037	6	2012-01-13 20:33:19.267611	2012-01-13 20:37:33.21281
870	1734	13	19	1734	7131	2	2012-01-13 20:31:06.202371	\N
951	0	3	9	4336	5496	18	2012-01-13 20:33:30.404425	2012-01-13 21:43:43.506304
872	513	15	4	513	2301	14	2012-01-13 20:31:09.194598	\N
876	0	2	14	2512	3521	13	2012-01-13 20:31:15.416721	2012-01-13 21:55:16.837897
901	6124	3	19	6124	4554	20	2012-01-13 20:32:02.348422	\N
882	0	8	9	1886	6660	1	2012-01-13 20:31:31.247335	2012-01-13 22:19:56.217468
890	0	4	5	9892	5041	4	2012-01-13 20:31:42.431421	2012-01-13 20:36:07.425789
886	0	18	17	2071	2944	5	2012-01-13 20:31:38.640744	2012-01-13 22:23:24.686187
955	0	8	4	8696	5313	15	2012-01-13 20:33:38.366756	2012-01-13 20:46:14.194456
879	997	14	6	997	4557	11	2012-01-13 20:31:24.274948	\N
913	0	10	5	2515	1456	11	2012-01-13 20:32:24.343855	2012-01-13 22:31:05.184536
902	511	9	1	511	2504	20	2012-01-13 20:32:04.103023	\N
939	0	20	5	8197	6695	4	2012-01-13 20:33:09.460777	2012-01-13 22:46:03.673037
869	0	14	17	1855	4591	1	2012-01-13 20:31:05.52758	2012-01-13 20:37:30.007919
946	0	20	6	7125	2896	13	2012-01-13 20:33:23.804093	2012-01-13 22:57:47.99853
883	4445	16	2	4445	7234	1	2012-01-13 20:31:31.949258	\N
910	0	17	13	3520	4373	3	2012-01-13 20:32:18.62888	2012-01-14 01:37:13.30649
925	0	8	13	8274	1121	13	2012-01-13 20:32:42.203439	2012-01-13 20:41:39.101424
866	0	4	13	6288	7120	14	2012-01-13 20:30:56.741562	2012-01-14 03:32:31.693567
898	0	18	9	2044	8216	13	2012-01-13 20:31:55.319929	2012-01-13 21:36:31.044638
888	2688	19	14	2688	4016	9	2012-01-13 20:31:40.111629	\N
884	0	1	4	7194	9274	14	2012-01-13 20:31:34.116746	2012-01-13 20:31:41.625862
889	0	5	14	2150	420	11	2012-01-13 20:31:41.625862	2012-01-13 20:31:41.625862
881	0	12	2	9739	5667	6	2012-01-13 20:31:27.187019	2012-01-13 20:36:10.518385
865	0	2	15	8350	6309	7	2012-01-13 20:30:54.23219	2012-01-13 20:53:35.389575
922	1206	17	19	1206	9652	19	2012-01-13 20:32:36.51549	\N
893	276	15	13	276	6147	12	2012-01-13 20:31:47.831477	\N
920	0	19	11	5148	2990	13	2012-01-13 20:32:32.510957	2012-01-13 20:38:56.888641
892	0	14	11	2316	784	10	2012-01-13 20:31:47.049981	2012-01-13 20:32:14.875653
896	1012	12	15	1012	6590	8	2012-01-13 20:31:53.275624	\N
906	0	11	6	8886	644	17	2012-01-13 20:32:14.875653	2012-01-13 20:32:14.875653
899	1611	20	2	1611	9892	7	2012-01-13 20:31:58.539322	\N
923	311	4	9	311	2720	3	2012-01-13 20:32:38.545742	\N
900	0	20	13	8780	3201	2	2012-01-13 20:32:00.714857	2012-01-13 20:32:15.633568
907	0	13	20	6653	2861	6	2012-01-13 20:32:15.633568	2012-01-13 20:32:15.633568
904	0	12	20	3667	4799	17	2012-01-13 20:32:07.104794	2012-01-13 20:41:10.561041
909	0	6	17	5554	2779	7	2012-01-13 20:32:17.799991	2012-01-13 20:32:17.799991
875	0	12	19	8236	974	14	2012-01-13 20:31:14.021407	2012-01-13 20:35:20.484393
911	0	14	17	7705	6520	13	2012-01-13 20:32:20.586325	2012-01-13 20:32:20.586325
912	1171	6	19	1171	9406	16	2012-01-13 20:32:22.087351	\N
914	2171	9	8	2171	6407	9	2012-01-13 20:32:24.978917	\N
915	4491	20	6	4491	3320	11	2012-01-13 20:32:26.383426	\N
935	0	9	13	8678	3132	15	2012-01-13 20:32:57.794192	2012-01-13 21:21:15.009896
917	0	8	1	2642	97	20	2012-01-13 20:32:28.105693	2012-01-13 20:32:28.105693
918	801	7	6	801	7251	16	2012-01-13 20:32:28.856621	\N
877	0	9	20	5198	8913	18	2012-01-13 20:31:16.741603	2012-01-13 20:44:52.022746
908	0	2	9	5844	7674	9	2012-01-13 20:32:16.317894	2012-01-13 20:40:31.163048
936	0	18	7	9001	7946	12	2012-01-13 20:32:59.166732	2012-01-13 20:46:33.667971
927	2649	10	4	2649	9017	2	2012-01-13 20:32:44.253835	\N
924	0	17	20	3154	7525	18	2012-01-13 20:32:39.382656	2012-01-13 20:37:30.007919
929	0	8	18	9177	540	20	2012-01-13 20:32:47.487982	2012-01-13 20:32:47.487982
930	0	12	16	2799	8975	20	2012-01-13 20:32:48.262847	2012-01-13 20:32:48.262847
931	0	19	20	4242	5340	13	2012-01-13 20:32:49.666772	2012-01-13 20:32:49.666772
887	0	18	16	104	1666	17	2012-01-13 20:31:39.29332	2012-01-13 21:35:03.592563
943	0	3	19	9675	4276	20	2012-01-13 20:33:14.640107	2012-01-13 20:49:24.740074
940	0	15	12	2075	1934	15	2012-01-13 20:33:11.614546	2012-01-13 20:33:11.614546
941	631	2	5	631	8478	15	2012-01-13 20:33:12.507874	\N
938	3734	4	14	3734	3752	9	2012-01-13 20:33:07.822687	\N
942	1529	12	18	1529	3577	8	2012-01-13 20:33:13.347209	\N
891	0	19	11	7816	7845	16	2012-01-13 20:31:44.885904	2012-01-13 20:52:25.23474
905	0	16	18	9812	4634	20	2012-01-13 20:32:11.077612	2012-01-13 20:37:43.668614
916	0	15	11	480	562	17	2012-01-13 20:32:27.299923	2012-01-13 20:53:35.389575
947	0	11	6	6357	5506	2	2012-01-13 20:33:24.92525	2012-01-13 20:37:33.21281
954	1275	12	4	1275	4767	11	2012-01-13 20:33:37.663403	\N
950	97	18	12	97	6173	9	2012-01-13 20:33:28.793106	\N
949	0	9	17	5984	3561	20	2012-01-13 20:33:27.18942	2012-01-13 20:33:35.404908
953	0	8	9	9510	5265	18	2012-01-13 20:33:35.404908	2012-01-13 20:33:35.404908
957	5091	7	14	5091	8809	8	2012-01-13 20:33:41.991818	\N
956	0	2	19	4621	1783	16	2012-01-13 20:33:41.142879	2012-01-13 20:33:41.142879
959	1702	17	13	1702	6719	11	2012-01-13 20:33:47.604974	\N
948	0	6	11	656	761	7	2012-01-13 20:33:26.273867	2012-01-13 20:33:52.032934
1005	0	9	6	4934	1726	12	2012-01-13 20:36:12.284943	2012-01-14 00:00:47.854862
982	0	16	3	3414	6550	2	2012-01-13 20:34:59.124014	2012-01-13 21:04:08.768688
850	0	12	7	9839	8304	18	2012-01-13 20:30:31.488226	2012-01-13 21:43:25.042452
1012	0	15	4	4856	9844	20	2012-01-13 20:36:26.037135	2012-01-13 20:42:13.137706
1661	0	7	12	7929	669	15	2012-01-13 21:43:25.042452	2012-01-13 21:43:25.042452
991	0	12	1	9816	9934	18	2012-01-13 20:35:33.061079	2012-01-13 21:53:14.128272
981	0	1	6	7485	5349	11	2012-01-13 20:34:56.902698	2012-01-13 22:25:42.877854
978	0	18	1	1775	4540	9	2012-01-13 20:34:48.226188	2012-01-13 22:45:54.205153
1050	0	12	17	6048	8408	2	2012-01-13 20:38:22.078382	2012-01-13 22:51:34.768367
961	0	11	14	9297	7364	8	2012-01-13 20:33:52.032934	2012-01-13 20:55:05.406206
1048	0	8	15	7189	5446	3	2012-01-13 20:38:15.751503	2012-01-13 20:50:50.264416
976	0	12	10	6284	8360	19	2012-01-13 20:34:36.58878	2012-01-13 20:48:59.53175
960	0	10	5	4797	4245	7	2012-01-13 20:33:49.161529	2012-01-13 23:16:57.714412
995	291	1	8	291	3493	5	2012-01-13 20:35:46.097699	\N
975	0	8	19	8436	7247	8	2012-01-13 20:34:25.907184	2012-01-13 21:24:03.978268
969	0	18	15	925	127	15	2012-01-13 20:34:11.542635	2012-01-13 20:34:11.542635
968	0	8	17	7592	6716	1	2012-01-13 20:34:08.820608	2012-01-13 21:12:27.878198
996	2754	8	14	2754	6767	7	2012-01-13 20:35:48.084183	\N
1027	0	3	13	2781	1308	13	2012-01-13 20:37:16.777436	2012-01-14 01:13:48.830005
997	6266	2	14	6266	9875	6	2012-01-13 20:35:50.62472	\N
1017	0	7	6	2241	8289	1	2012-01-13 20:36:44.146386	2012-01-14 03:20:39.258811
998	1457	2	15	1457	4751	20	2012-01-13 20:35:56.231516	\N
1042	0	12	6	6858	9228	3	2012-01-13 20:37:54.281146	2012-01-14 03:56:03.010756
965	0	5	14	6166	3697	13	2012-01-13 20:34:02.204564	2012-01-13 20:50:43.848885
977	3237	3	1	3237	9669	10	2012-01-13 20:34:42.758485	\N
1045	0	7	3	2222	4527	14	2012-01-13 20:38:04.632713	2012-01-13 20:38:59.655468
1020	0	7	17	4803	7770	10	2012-01-13 20:36:50.202769	2012-01-13 21:07:07.413716
971	0	1	11	4194	1160	12	2012-01-13 20:34:14.34627	2012-01-13 20:35:02.492161
1054	0	12	1	6988	2060	7	2012-01-13 20:38:42.319464	2012-01-13 20:40:31.163048
984	3544	3	10	3544	8995	12	2012-01-13 20:35:08.382784	\N
986	1948	16	11	1948	5383	20	2012-01-13 20:35:17.383561	\N
999	5339	20	7	5339	6817	20	2012-01-13 20:35:58.867699	\N
933	0	4	3	586	3574	20	2012-01-13 20:32:54.446808	2012-01-13 20:35:20.484393
987	0	3	12	5493	2624	2	2012-01-13 20:35:20.484393	2012-01-13 20:35:20.484393
988	1494	10	4	1494	5884	18	2012-01-13 20:35:27.778489	\N
989	4066	2	6	4066	4822	12	2012-01-13 20:35:28.521742	\N
1023	0	16	20	7599	6756	5	2012-01-13 20:37:02.383573	2012-01-13 20:43:01.506493
1000	448	2	11	448	8981	11	2012-01-13 20:36:03.365007	\N
1001	3897	16	15	3897	3486	15	2012-01-13 20:36:04.187831	\N
1032	0	18	14	6894	748	13	2012-01-13 20:37:30.007919	2012-01-13 20:37:30.007919
1002	0	5	3	5032	5858	18	2012-01-13 20:36:07.425789	2012-01-13 20:36:07.425789
1003	0	4	18	4107	4122	14	2012-01-13 20:36:08.483665	2012-01-13 20:36:08.483665
1004	0	2	12	9773	8602	13	2012-01-13 20:36:10.518385	2012-01-13 20:36:10.518385
966	0	16	3	8538	8084	17	2012-01-13 20:34:03.9644	2012-01-13 20:46:36.30891
1007	19	2	3	19	7587	9	2012-01-13 20:36:16.238954	\N
1014	1185	4	8	1185	8188	14	2012-01-13 20:36:35.133636	\N
1026	3092	4	7	3092	6577	19	2012-01-13 20:37:12.465709	\N
1009	0	9	4	6368	1523	9	2012-01-13 20:36:20.488591	2012-01-13 20:36:20.488591
990	0	8	10	2938	2466	17	2012-01-13 20:35:32.226055	2012-01-13 20:36:24.078219
1011	0	7	8	3359	3497	15	2012-01-13 20:36:24.078219	2012-01-13 20:36:24.078219
1018	136	18	4	136	9231	14	2012-01-13 20:36:46.392118	\N
1053	0	9	19	8211	5733	2	2012-01-13 20:38:34.245897	2012-01-13 20:41:19.75684
970	0	13	6	9847	9351	16	2012-01-13 20:34:12.345734	2012-01-13 21:07:24.80664
1021	1635	9	13	1635	2119	10	2012-01-13 20:36:52.896792	\N
1022	1891	18	19	1891	9043	1	2012-01-13 20:36:53.767863	\N
983	0	2	17	9736	4125	17	2012-01-13 20:35:02.492161	2012-01-13 20:44:45.759799
1024	1042	6	13	1042	5620	14	2012-01-13 20:37:07.168336	\N
1019	0	18	12	5661	7820	7	2012-01-13 20:36:48.203526	2012-01-13 20:37:43.668614
972	0	9	11	9318	2051	13	2012-01-13 20:34:15.162587	2012-01-13 20:37:33.21281
1029	3792	17	6	3792	5892	15	2012-01-13 20:37:24.58154	\N
1031	1933	9	14	1933	5767	11	2012-01-13 20:37:27.974342	\N
979	0	12	15	4374	617	19	2012-01-13 20:34:51.700927	2012-01-13 20:37:43.668614
980	0	20	18	4945	6409	8	2012-01-13 20:34:52.426513	2012-01-13 20:37:30.007919
1033	0	6	16	176	322	12	2012-01-13 20:37:33.21281	2012-01-13 20:37:33.21281
926	0	5	20	914	2559	19	2012-01-13 20:32:43.492864	2012-01-13 20:37:43.668614
1037	0	20	16	3159	6247	19	2012-01-13 20:37:43.668614	2012-01-13 20:37:43.668614
1036	332	11	9	332	3910	4	2012-01-13 20:37:42.562489	\N
1038	0	6	14	5979	1062	1	2012-01-13 20:37:46.719685	2012-01-13 20:37:46.719685
1043	8658	3	2	8658	8158	20	2012-01-13 20:37:59.182626	\N
993	0	19	14	6138	2087	13	2012-01-13 20:35:41.066598	2012-01-13 20:41:19.75684
1044	0	7	5	7066	837	1	2012-01-13 20:38:03.535164	2012-01-13 20:38:03.535164
994	0	10	20	6152	9072	17	2012-01-13 20:35:42.936653	2012-01-13 20:52:25.23474
1047	6096	9	13	6096	9132	20	2012-01-13 20:38:10.027664	\N
1049	2264	17	6	2264	4997	3	2012-01-13 20:38:19.660588	\N
1051	1632	3	10	1632	3253	5	2012-01-13 20:38:25.315701	\N
1046	0	18	19	8647	4243	7	2012-01-13 20:38:05.714585	2012-01-13 20:42:13.137706
1006	0	20	10	5210	4690	16	2012-01-13 20:36:14.473954	2012-01-13 20:38:56.888641
1100	0	7	14	6027	8234	10	2012-01-13 20:41:31.011846	2012-01-13 22:02:53.881687
1056	4683	20	17	4683	9168	8	2012-01-13 20:38:51.0229	\N
1039	0	4	15	4384	4586	1	2012-01-13 20:37:47.858069	2012-01-13 20:38:56.888641
1057	0	11	20	3111	740	19	2012-01-13 20:38:56.888641	2012-01-13 20:38:56.888641
1058	346	12	8	346	8402	16	2012-01-13 20:38:58.030948	\N
1085	0	2	15	3327	3100	15	2012-01-13 20:40:47.187885	2012-01-13 21:38:52.267895
1059	0	10	7	6084	239	1	2012-01-13 20:38:59.655468	2012-01-13 20:38:59.655468
1040	0	19	7	5485	6923	20	2012-01-13 20:37:48.793093	2012-01-13 20:39:06.462861
1064	6124	16	8	6124	7500	8	2012-01-13 20:39:25.202294	\N
1103	0	12	8	3410	6793	17	2012-01-13 20:41:36.514292	2012-01-13 21:46:20.945515
1089	1725	10	8	1725	5841	3	2012-01-13 20:40:54.454078	\N
1662	0	9	20	6801	4059	14	2012-01-13 21:43:28.45012	2012-01-13 22:01:06.207045
1066	780	17	1	780	4766	17	2012-01-13 20:39:34.818277	\N
1107	1950	3	14	1950	4887	14	2012-01-13 20:41:50.953305	\N
1090	0	9	15	8861	8617	7	2012-01-13 20:40:57.264082	2012-01-13 21:59:02.328133
1069	770	9	6	770	1972	6	2012-01-13 20:39:43.996231	\N
1113	0	20	18	3231	3026	16	2012-01-13 20:42:17.889522	2012-01-13 21:04:24.855158
1131	1445	8	6	1445	9950	2	2012-01-13 20:43:21.311663	\N
1086	0	20	14	6741	2567	9	2012-01-13 20:40:48.281006	2012-01-13 22:31:28.243968
1067	0	11	4	2978	8947	15	2012-01-13 20:39:36.876789	2012-01-13 20:41:10.561041
1079	0	4	12	3861	9659	4	2012-01-13 20:40:31.163048	2012-01-13 20:41:10.561041
1109	0	12	13	7913	6212	18	2012-01-13 20:41:56.41026	2012-01-13 22:48:09.108512
1061	0	20	19	8289	1707	15	2012-01-13 20:39:02.395962	2012-01-13 20:41:10.561041
1091	0	19	11	6809	1199	3	2012-01-13 20:41:10.561041	2012-01-13 20:41:10.561041
1145	0	16	3	9753	8669	18	2012-01-13 20:44:16.802937	2012-01-13 20:46:15.588877
1076	597	15	2	597	5423	9	2012-01-13 20:40:25.31538	\N
1144	0	12	18	5524	6880	4	2012-01-13 20:44:14.861252	2012-01-14 00:25:50.943987
1118	0	20	15	9761	4138	17	2012-01-13 20:42:32.818352	2012-01-13 20:44:52.022746
1063	0	1	7	9851	7221	10	2012-01-13 20:39:12.40599	2012-01-13 20:40:31.163048
1062	0	7	2	8869	7704	8	2012-01-13 20:39:06.462861	2012-01-13 20:40:31.163048
1078	0	9	4	2405	2500	2	2012-01-13 20:40:28.941876	2012-01-13 20:40:31.163048
1108	5464	16	8	5464	7028	1	2012-01-13 20:41:52.541257	\N
1141	0	19	17	8912	9315	8	2012-01-13 20:44:02.696127	2012-01-13 20:47:04.284597
1136	0	20	2	6439	3883	11	2012-01-13 20:43:40.188268	2012-01-13 20:53:35.389575
1082	362	11	1	362	1955	18	2012-01-13 20:40:42.234749	\N
1122	0	7	15	2070	6166	13	2012-01-13 20:42:47.99036	2012-01-14 00:30:48.691713
1084	34	15	2	34	2209	14	2012-01-13 20:40:45.926491	\N
1128	0	20	15	5393	6504	18	2012-01-13 20:43:06.265977	2012-01-13 21:39:18.691788
1094	0	14	9	3483	3070	19	2012-01-13 20:41:19.75684	2012-01-13 20:41:19.75684
1095	2110	2	1	2110	6151	2	2012-01-13 20:41:21.028908	\N
1140	0	19	2	4538	5393	19	2012-01-13 20:43:53.838865	2012-01-13 20:44:53.281712
1097	153	7	19	153	2521	10	2012-01-13 20:41:24.231315	\N
1098	9663	16	7	9663	7085	4	2012-01-13 20:41:25.293211	\N
1080	0	7	14	4148	2311	7	2012-01-13 20:40:35.186107	2012-01-13 20:46:33.667971
1060	0	17	15	7283	4042	18	2012-01-13 20:39:00.571137	2012-01-13 20:42:13.137706
1102	0	2	12	8445	1366	7	2012-01-13 20:41:35.363549	2012-01-13 20:41:35.363549
1096	0	4	18	4817	8650	11	2012-01-13 20:41:23.00783	2012-01-13 20:42:13.137706
1104	0	9	16	3633	146	11	2012-01-13 20:41:39.101424	2012-01-13 20:41:39.101424
1105	1271	12	19	1271	9122	4	2012-01-13 20:41:40.380114	\N
1111	0	19	17	5264	4808	7	2012-01-13 20:42:13.137706	2012-01-13 20:42:13.137706
1119	391	13	7	391	8599	11	2012-01-13 20:42:38.958217	\N
1071	0	18	8	6461	7022	14	2012-01-13 20:39:49.304223	2012-01-13 20:42:15.550722
1088	0	8	7	5394	1276	16	2012-01-13 20:40:53.436793	2012-01-13 20:42:15.550722
1112	0	5	12	3406	7765	12	2012-01-13 20:42:15.550722	2012-01-13 20:42:15.550722
1106	0	10	4	8627	7554	14	2012-01-13 20:41:47.314281	2012-01-13 21:17:49.070181
1092	0	16	12	3061	2951	14	2012-01-13 20:41:11.774175	2012-01-13 20:42:27.995759
1116	0	12	16	2421	792	1	2012-01-13 20:42:27.995759	2012-01-13 20:42:27.995759
1127	0	18	4	5289	4835	6	2012-01-13 20:43:03.516232	2012-01-13 21:40:09.542595
1120	0	6	15	3023	7736	9	2012-01-13 20:42:40.109501	2012-01-13 20:42:58.259355
1133	0	10	8	6668	7404	19	2012-01-13 20:43:29.470609	2012-01-13 20:44:56.51087
1115	0	4	19	7469	6863	11	2012-01-13 20:42:23.800884	2012-01-13 20:42:42.53978
1110	0	19	3	1506	8348	11	2012-01-13 20:42:11.814823	2012-01-13 20:46:14.194456
1075	0	3	1	5025	911	3	2012-01-13 20:40:16.34715	2012-01-13 20:46:14.194456
1125	0	15	19	9463	6475	5	2012-01-13 20:42:58.259355	2012-01-13 20:42:58.259355
1126	0	20	16	8827	6469	20	2012-01-13 20:43:01.506493	2012-01-13 20:43:01.506493
1124	0	15	1	8441	6791	18	2012-01-13 20:42:55.117176	2012-01-13 20:43:20.039131
1130	0	1	15	5566	441	19	2012-01-13 20:43:20.039131	2012-01-13 20:43:20.039131
1081	0	16	1	9966	9536	7	2012-01-13 20:40:37.225572	2012-01-13 20:47:51.138836
1134	5849	19	6	5849	9605	8	2012-01-13 20:43:33.021816	\N
1137	2941	19	7	2941	7109	19	2012-01-13 20:43:46.804057	\N
1074	0	18	8	6961	7850	11	2012-01-13 20:40:05.500999	2012-01-13 20:43:38.836748
1070	0	8	14	8268	2742	1	2012-01-13 20:39:45.688367	2012-01-13 20:43:38.836748
1135	0	14	18	3363	5278	10	2012-01-13 20:43:38.836748	2012-01-13 20:43:38.836748
1129	0	18	3	2378	9699	1	2012-01-13 20:43:18.93686	2012-01-13 20:43:52.710831
1139	0	3	18	7367	935	17	2012-01-13 20:43:52.710831	2012-01-13 20:43:52.710831
1143	4256	17	14	4256	7378	4	2012-01-13 20:44:11.432504	\N
1121	0	15	5	8340	6550	20	2012-01-13 20:42:42.53978	2012-01-13 20:44:37.789033
1147	5043	3	7	5043	4332	18	2012-01-13 20:44:24.831285	\N
1114	0	5	4	9183	6400	20	2012-01-13 20:42:19.776569	2012-01-13 20:44:37.789033
1077	0	6	11	4741	6646	15	2012-01-13 20:40:27.628663	2012-01-13 20:44:37.789033
1148	0	11	15	6196	7444	18	2012-01-13 20:44:37.789033	2012-01-13 20:44:37.789033
1149	45	12	13	45	2160	17	2012-01-13 20:44:44.856824	\N
1180	3618	8	6	3618	9389	8	2012-01-13 20:46:17.06861	\N
1150	0	11	2	5575	8876	13	2012-01-13 20:44:45.759799	2012-01-13 20:44:45.759799
1195	0	3	2	6982	4142	19	2012-01-13 20:47:24.906776	2012-01-13 21:40:19.025745
1152	0	15	16	1111	469	14	2012-01-13 20:44:52.022746	2012-01-13 20:44:52.022746
1190	0	13	4	4443	6613	19	2012-01-13 20:47:05.609147	2012-01-13 20:52:57.690051
1153	0	13	19	3051	4412	19	2012-01-13 20:44:53.281712	2012-01-13 20:44:53.281712
1154	124	18	17	124	2333	14	2012-01-13 20:44:55.525434	\N
1155	0	8	10	8807	6028	9	2012-01-13 20:44:56.51087	2012-01-13 20:44:56.51087
1157	101	1	11	101	339	7	2012-01-13 20:45:00.783801	\N
1172	0	14	13	5151	975	12	2012-01-13 20:45:51.510257	2012-01-13 20:46:33.667971
1222	0	8	2	4051	5851	4	2012-01-13 20:49:43.201106	2012-01-13 22:27:57.159744
1162	207	18	11	207	4071	17	2012-01-13 20:45:21.528674	\N
1216	7729	9	2	7729	8989	10	2012-01-13 20:49:12.293669	\N
1161	0	17	15	5628	8804	17	2012-01-13 20:45:16.686948	2012-01-13 22:13:45.532156
1165	422	3	14	422	8684	11	2012-01-13 20:45:32.463402	\N
1213	0	17	19	2318	3139	18	2012-01-13 20:49:05.001505	2012-01-13 23:46:21.477221
1219	0	9	7	9442	5079	12	2012-01-13 20:49:26.286633	2012-01-13 21:19:51.641593
1175	0	10	12	4147	6277	2	2012-01-13 20:46:05.751141	2012-01-13 21:04:08.768688
1207	0	1	5	7352	4285	1	2012-01-13 20:48:10.255538	2012-01-13 20:53:21.410818
1170	808	18	12	808	3110	17	2012-01-13 20:45:48.961166	\N
1171	2047	17	5	2047	8540	8	2012-01-13 20:45:50.176976	\N
1173	3659	12	7	3659	6084	15	2012-01-13 20:45:52.880244	\N
1174	587	10	13	587	6230	9	2012-01-13 20:46:03.031328	\N
1167	0	18	4	6578	4582	15	2012-01-13 20:45:38.825752	2012-01-13 21:10:45.557193
1176	1469	10	1	1469	3396	5	2012-01-13 20:46:06.807361	\N
1186	0	12	7	9182	8813	15	2012-01-13 20:46:42.426124	2012-01-13 21:48:27.662169
1182	0	13	18	2627	4683	11	2012-01-13 20:46:33.667971	2012-01-13 20:46:33.667971
1204	0	18	1	5398	3820	4	2012-01-13 20:48:01.694756	2012-01-13 20:51:52.197356
1183	0	18	16	5433	910	3	2012-01-13 20:46:36.30891	2012-01-13 20:46:36.30891
1156	0	4	19	3934	3155	14	2012-01-13 20:44:58.708678	2012-01-13 20:46:14.194456
1178	0	1	8	2208	1046	16	2012-01-13 20:46:14.194456	2012-01-13 20:46:14.194456
1179	0	1	16	1294	2847	12	2012-01-13 20:46:15.588877	2012-01-13 20:46:15.588877
1210	0	12	1	9426	9227	6	2012-01-13 20:48:19.432717	2012-01-13 21:20:06.732521
1185	1665	15	18	1665	9295	19	2012-01-13 20:46:41.171507	\N
1197	0	3	15	6877	4413	3	2012-01-13 20:47:35.650637	2012-01-13 21:52:52.458585
1187	984	3	18	984	7795	4	2012-01-13 20:46:54.062056	\N
1188	694	19	4	694	8416	11	2012-01-13 20:47:01.848376	\N
1169	0	1	2	5527	5814	12	2012-01-13 20:45:44.953377	2012-01-13 20:53:18.636647
1164	0	16	19	9630	3829	19	2012-01-13 20:45:27.592638	2012-01-13 20:47:04.284597
1189	0	17	16	3602	2659	10	2012-01-13 20:47:04.284597	2012-01-13 20:47:04.284597
1199	0	12	8	5611	3310	2	2012-01-13 20:47:42.777032	2012-01-13 20:53:15.918252
1166	0	9	14	8020	4011	2	2012-01-13 20:45:33.496427	2012-01-13 23:07:16.537285
1192	4436	9	15	4436	8570	8	2012-01-13 20:47:14.395709	\N
1160	0	7	13	4182	2006	2	2012-01-13 20:45:15.569271	2012-01-13 20:47:20.690727
1193	0	13	3	4729	824	1	2012-01-13 20:47:20.690727	2012-01-13 20:47:20.690727
1194	1279	6	18	1279	9847	13	2012-01-13 20:47:22.099998	\N
1664	0	7	20	5108	4112	9	2012-01-13 21:43:40.211554	2012-01-13 21:43:40.211554
1208	0	18	7	8116	3117	2	2012-01-13 20:48:13.007178	2012-01-13 20:52:39.567069
1205	0	18	17	4740	2385	13	2012-01-13 20:48:05.694248	2012-01-13 20:53:45.251018
1196	0	10	16	5677	3092	7	2012-01-13 20:47:34.587192	2012-01-13 20:47:51.138836
1201	0	1	9	3321	374	18	2012-01-13 20:47:51.138836	2012-01-13 20:47:51.138836
1209	0	4	16	1793	4547	18	2012-01-13 20:48:17.924634	2012-01-13 20:52:57.690051
1203	199	4	10	199	6327	18	2012-01-13 20:48:00.267219	\N
1200	0	20	19	3921	969	13	2012-01-13 20:47:47.119805	2012-01-13 20:52:25.23474
1184	0	2	1	5434	7096	11	2012-01-13 20:46:37.577622	2012-01-13 20:56:16.576916
1206	393	12	20	393	8166	4	2012-01-13 20:48:08.080073	\N
1168	0	1	6	9436	5888	4	2012-01-13 20:45:41.836876	2012-01-13 20:56:16.576916
1151	0	9	20	1297	3310	4	2012-01-13 20:44:50.945287	2012-01-13 21:30:07.752403
1158	0	9	1	9023	9237	2	2012-01-13 20:45:01.87607	2012-01-13 20:49:09.058898
1211	0	10	12	9955	5768	8	2012-01-13 20:48:59.53175	2012-01-13 20:48:59.53175
1191	0	1	17	3291	6571	9	2012-01-13 20:47:07.929447	2012-01-13 22:47:06.371562
1163	0	1	15	7246	4915	8	2012-01-13 20:45:22.518075	2012-01-13 20:49:09.058898
1214	0	15	9	1955	948	11	2012-01-13 20:49:09.058898	2012-01-13 20:49:09.058898
1215	0	6	13	3066	5045	7	2012-01-13 20:49:10.482012	2012-01-14 00:00:47.854862
1221	0	9	6	8265	3607	2	2012-01-13 20:49:39.39467	2012-01-14 00:07:28.129819
1146	0	11	6	2102	2271	17	2012-01-13 20:44:23.68905	2012-01-14 01:55:31.30782
1217	0	20	10	1661	3847	16	2012-01-13 20:49:23.568404	2012-01-13 21:40:19.025745
1218	0	19	3	6188	5688	20	2012-01-13 20:49:24.740074	2012-01-13 20:49:24.740074
1223	858	2	4	858	6850	18	2012-01-13 20:49:45.781621	\N
1198	0	8	5	9254	1783	12	2012-01-13 20:47:40.316934	2012-01-13 20:50:36.996007
1181	0	11	3	596	1536	7	2012-01-13 20:46:32.137471	2012-01-13 20:52:39.567069
1224	0	3	12	7773	9091	5	2012-01-13 20:49:48.532262	2012-01-13 20:52:39.567069
1291	708	4	5	708	3459	7	2012-01-13 20:54:37.875321	\N
1317	0	3	4	5570	2222	16	2012-01-13 20:56:39.748176	2012-01-13 21:42:00.874568
1261	1855	7	6	1855	8197	18	2012-01-13 20:52:31.192142	\N
1228	845	13	17	845	6083	2	2012-01-13 20:50:10.122462	\N
1306	0	10	8	4733	5581	18	2012-01-13 20:55:50.043592	2012-01-13 21:51:52.482874
1231	909	10	11	909	8067	16	2012-01-13 20:50:20.655722	\N
1232	1580	16	11	1580	6034	7	2012-01-13 20:50:24.497256	\N
1230	0	3	10	3513	2071	3	2012-01-13 20:50:13.217246	2012-01-13 21:42:04.6439
1233	0	11	8	5041	7114	7	2012-01-13 20:50:36.996007	2012-01-13 20:50:36.996007
1279	0	11	20	5389	5457	9	2012-01-13 20:53:35.389575	2012-01-13 20:53:35.389575
1234	0	14	5	4536	1260	1	2012-01-13 20:50:43.848885	2012-01-13 20:50:43.848885
1235	33	17	4	33	2474	16	2012-01-13 20:50:45.866615	\N
1236	0	15	13	5247	2205	6	2012-01-13 20:50:47.445854	2012-01-13 20:50:50.264416
1237	0	13	8	3717	717	10	2012-01-13 20:50:50.264416	2012-01-13 20:50:50.264416
1238	2326	19	1	2326	6140	6	2012-01-13 20:50:51.753479	\N
1239	2760	11	14	2760	7010	1	2012-01-13 20:50:57.226198	\N
1240	7034	16	6	7034	4132	9	2012-01-13 20:51:00.147979	\N
1244	0	2	18	2091	4608	16	2012-01-13 20:51:23.669786	2012-01-13 20:53:45.251018
1242	3405	9	15	3405	6676	5	2012-01-13 20:51:12.687848	\N
1314	0	3	10	3861	1064	12	2012-01-13 20:56:30.44855	2012-01-13 21:04:08.768688
1252	0	2	4	2344	8006	6	2012-01-13 20:51:53.867901	2012-01-13 22:46:26.689257
1666	688	11	4	688	5478	10	2012-01-13 21:43:50.733116	\N
1280	0	17	2	3254	160	6	2012-01-13 20:53:45.251018	2012-01-13 20:53:45.251018
1241	0	7	11	7519	8234	19	2012-01-13 20:51:08.141328	2012-01-13 20:52:39.567069
1665	0	7	3	6572	8024	20	2012-01-13 21:43:43.506304	2012-01-13 21:44:10.69988
1292	0	13	2	1722	2107	5	2012-01-13 20:54:39.685931	2012-01-13 21:03:46.668676
1249	1375	8	10	1375	7026	11	2012-01-13 20:51:41.409543	\N
1229	0	13	5	843	1311	17	2012-01-13 20:50:11.637793	2012-01-13 21:45:37.741246
1263	0	12	18	2221	834	6	2012-01-13 20:52:39.567069	2012-01-13 20:52:39.567069
1251	0	1	18	8977	827	18	2012-01-13 20:51:52.197356	2012-01-13 20:51:52.197356
1315	0	10	13	7624	7413	2	2012-01-13 20:56:31.942222	2012-01-14 00:33:09.289874
1297	0	9	20	4893	9868	9	2012-01-13 20:55:08.777061	2012-01-13 21:24:59.692668
1254	2267	3	19	2267	6090	8	2012-01-13 20:52:01.549944	\N
1307	0	19	17	5024	9778	12	2012-01-13 20:55:54.37253	2012-01-13 22:06:52.535079
1264	1956	15	17	1956	7024	8	2012-01-13 20:52:42.421042	\N
1286	0	16	5	6770	719	1	2012-01-13 20:54:01.769339	2012-01-13 22:13:14.54634
1265	370	4	14	370	2599	3	2012-01-13 20:52:43.88756	\N
1269	0	12	15	6235	5822	9	2012-01-13 20:52:59.738206	2012-01-13 22:30:38.777487
1245	0	7	6	8236	4824	20	2012-01-13 20:51:26.567667	2012-01-13 22:31:37.116635
1300	0	4	12	3700	8889	17	2012-01-13 20:55:29.072762	2012-01-13 21:06:52.130506
1259	197	18	15	197	601	20	2012-01-13 20:52:23.497431	\N
1260	0	11	10	5660	9963	8	2012-01-13 20:52:25.23474	2012-01-13 20:52:25.23474
1267	1932	3	9	1932	9093	1	2012-01-13 20:52:49.341711	\N
1270	0	8	5	8448	9075	15	2012-01-13 20:53:06.381562	2012-01-13 21:22:46.291382
1226	0	15	7	8274	7016	11	2012-01-13 20:50:04.666399	2012-01-13 20:52:57.690051
1268	0	14	15	1968	441	18	2012-01-13 20:52:57.690051	2012-01-13 20:52:57.690051
1256	0	20	12	953	2051	7	2012-01-13 20:52:12.430979	2012-01-14 00:39:38.529843
1301	0	1	14	3289	1214	1	2012-01-13 20:55:32.259301	2012-01-13 21:35:16.42628
1271	1733	12	15	1733	8483	16	2012-01-13 20:53:11.891289	\N
1272	189	4	12	189	9262	17	2012-01-13 20:53:14.317664	\N
1273	0	8	12	8235	7070	17	2012-01-13 20:53:15.918252	2012-01-13 20:53:15.918252
1283	309	17	15	309	5077	5	2012-01-13 20:53:52.425829	\N
1274	0	2	1	7470	5072	13	2012-01-13 20:53:18.636647	2012-01-13 20:53:18.636647
1247	0	18	17	5693	2111	13	2012-01-13 20:51:35.653322	2012-01-13 20:53:21.410818
1275	0	11	1	5209	2086	5	2012-01-13 20:53:21.410818	2012-01-13 20:53:21.410818
1276	3916	12	14	3916	8570	9	2012-01-13 20:53:24.856834	\N
1277	4046	9	6	4046	8188	17	2012-01-13 20:53:29.815579	\N
1284	2404	3	8	2404	6869	16	2012-01-13 20:53:53.825085	\N
1318	0	1	2	9411	9831	9	2012-01-13 20:56:41.230773	2012-01-13 21:11:13.285148
1282	0	1	15	8256	5391	8	2012-01-13 20:53:48.114062	2012-01-13 21:13:32.104722
1293	7807	10	6	7807	7062	3	2012-01-13 20:54:41.243201	\N
1289	2743	5	19	2743	9421	19	2012-01-13 20:54:20.476537	\N
1290	9013	9	13	9013	9032	11	2012-01-13 20:54:23.353611	\N
1287	0	11	19	2124	1743	6	2012-01-13 20:54:06.490967	2012-01-13 21:12:33.013403
1295	0	14	11	5082	4956	20	2012-01-13 20:55:05.406206	2012-01-13 20:55:05.406206
1296	0	8	10	4172	1757	18	2012-01-13 20:55:07.32183	2012-01-13 20:55:07.32183
1253	0	18	7	8256	4846	13	2012-01-13 20:51:55.458654	2012-01-13 21:26:55.421217
1309	0	19	6	3179	1598	16	2012-01-13 20:56:05.150637	2012-01-13 21:12:33.013403
1305	0	19	2	6254	5536	10	2012-01-13 20:55:43.799402	2012-01-13 21:02:40.944727
1304	0	5	11	4732	3144	6	2012-01-13 20:55:41.952079	2012-01-13 20:55:41.952079
1281	0	1	9	1022	2432	15	2012-01-13 20:53:46.722126	2012-01-13 21:03:44.343764
1299	0	11	5	8834	8907	3	2012-01-13 20:55:21.369286	2012-01-13 20:55:41.952079
1308	3144	18	6	3144	4978	18	2012-01-13 20:56:02.173324	\N
1312	5802	16	18	5802	7897	5	2012-01-13 20:56:18.843839	\N
1311	0	6	2	8256	6231	1	2012-01-13 20:56:16.576916	2012-01-13 20:56:16.576916
1319	213	13	17	213	2765	11	2012-01-13 20:56:48.689595	\N
1302	0	7	4	9768	8595	15	2012-01-13 20:55:35.307921	2012-01-13 20:57:24.425756
1285	0	9	18	3858	2177	9	2012-01-13 20:54:00.316924	2012-01-13 21:03:44.343764
1383	0	10	9	4411	8844	2	2012-01-13 21:04:27.359495	2012-01-13 21:42:04.6439
1385	0	16	13	6452	523	10	2012-01-13 21:04:42.446045	2012-01-13 22:12:12.312673
1366	0	5	19	5196	8214	18	2012-01-13 21:02:59.944385	2012-01-13 21:13:09.417563
1388	0	7	13	7803	9561	10	2012-01-13 21:05:08.277317	2012-01-13 21:40:09.542595
1324	229	18	19	229	3662	14	2012-01-13 20:57:22.8005	\N
1336	0	17	11	6258	9062	5	2012-01-13 20:58:46.567612	2012-01-13 21:45:10.249457
1325	0	4	7	6701	6894	11	2012-01-13 20:57:24.425756	2012-01-13 20:57:24.425756
1326	1456	3	9	1456	9843	6	2012-01-13 20:57:26.502465	\N
1372	0	12	2	4321	5133	12	2012-01-13 21:03:36.411235	2012-01-14 01:55:55.788596
1341	0	10	5	6096	3541	11	2012-01-13 20:59:22.813508	2012-01-13 22:42:07.082431
1358	0	12	7	3318	3501	15	2012-01-13 21:01:59.17243	2012-01-13 21:51:28.151919
1348	0	13	5	3759	6011	12	2012-01-13 21:00:46.045122	2012-01-13 21:51:59.101665
1725	0	15	3	2354	2529	5	2012-01-13 21:52:52.458585	2012-01-13 21:52:52.458585
1398	0	1	18	3079	8787	1	2012-01-13 21:06:19.204479	2012-01-14 03:04:37.650457
1331	3058	8	17	3058	6604	2	2012-01-13 20:58:18.905234	\N
1332	7	11	4	7	617	12	2012-01-13 20:58:25.209879	\N
1351	0	15	5	7484	9752	13	2012-01-13 21:01:08.834666	2012-01-14 00:29:36.943006
1726	1021	9	19	1021	7101	1	2012-01-13 21:52:55.699881	\N
1337	4278	9	14	4278	3975	14	2012-01-13 20:58:53.595699	\N
1338	4419	3	14	4419	6789	14	2012-01-13 20:58:59.980515	\N
1347	0	12	9	2960	8152	3	2012-01-13 21:00:35.915792	2012-01-13 22:13:45.532156
1328	0	12	13	9851	5760	5	2012-01-13 20:57:53.194338	2012-01-13 22:19:51.756245
1346	0	19	6	8062	9884	2	2012-01-13 21:00:10.5163	2012-01-13 23:15:04.637681
1335	0	10	13	8763	7935	16	2012-01-13 20:58:40.509489	2012-01-14 00:29:04.225053
1417	0	14	11	1166	4979	13	2012-01-13 21:08:25.807016	2012-01-14 01:33:10.456807
1327	0	12	11	8502	9398	5	2012-01-13 20:57:42.230976	2012-01-14 01:52:38.874447
1359	1428	3	12	1428	8802	16	2012-01-13 21:02:04.951641	\N
1357	0	3	4	8321	9957	4	2012-01-13 21:01:45.00995	2012-01-14 02:13:01.988601
1344	1946	2	6	1946	3731	4	2012-01-13 20:59:41.069326	\N
1400	0	9	20	4951	9536	9	2012-01-13 21:06:28.999124	2012-01-13 21:13:12.208345
1381	0	4	17	5810	9444	13	2012-01-13 21:04:20.624073	2012-01-13 21:38:52.267895
1350	2086	12	13	2086	6583	17	2012-01-13 21:01:01.572572	\N
1360	1645	8	13	1645	9392	4	2012-01-13 21:02:19.39333	\N
1353	1288	4	17	1288	9987	20	2012-01-13 21:01:22.093041	\N
1413	1580	16	11	1580	3949	20	2012-01-13 21:07:39.994902	\N
1362	2683	17	4	2683	8958	12	2012-01-13 21:02:34.565659	\N
1363	0	2	19	8604	989	12	2012-01-13 21:02:40.944727	2012-01-13 21:02:40.944727
1393	0	10	12	7275	7399	3	2012-01-13 21:05:38.285011	2012-01-13 21:20:06.732521
1408	0	17	10	752	2693	12	2012-01-13 21:07:09.714504	2012-01-13 21:08:46.660514
1364	0	15	11	3876	5781	8	2012-01-13 21:02:43.326757	2012-01-13 21:13:32.104722
1403	3043	11	6	3043	8257	18	2012-01-13 21:06:49.855209	\N
1368	407	6	15	407	7622	9	2012-01-13 21:03:18.139721	\N
1369	18	6	7	18	862	10	2012-01-13 21:03:20.769031	\N
1379	0	12	16	4484	5431	20	2012-01-13 21:04:08.768688	2012-01-13 21:04:08.768688
1371	1795	2	13	1795	7966	12	2012-01-13 21:03:31.636287	\N
1321	0	17	1	4760	9599	17	2012-01-13 20:57:05.305137	2012-01-13 21:03:44.343764
1298	0	18	3	3445	5599	8	2012-01-13 20:55:18.382862	2012-01-13 21:03:44.343764
1248	0	3	5	2607	507	14	2012-01-13 20:51:39.988643	2012-01-13 21:03:44.343764
1373	0	5	17	3819	1094	4	2012-01-13 21:03:44.343764	2012-01-13 21:03:44.343764
1386	0	4	11	7970	6376	2	2012-01-13 21:04:56.474292	2012-01-13 21:32:07.513035
1374	0	15	13	3447	2945	9	2012-01-13 21:03:46.668676	2012-01-13 21:03:46.668676
1380	0	7	14	8922	6111	2	2012-01-13 21:04:16.330926	2012-01-13 21:31:28.278476
1376	3317	12	4	3317	9404	8	2012-01-13 21:03:56.324181	\N
1334	0	15	20	2803	9761	16	2012-01-13 20:58:31.963558	2012-01-13 21:04:24.855158
1382	0	6	15	5439	2464	20	2012-01-13 21:04:24.855158	2012-01-13 21:04:24.855158
1384	1078	17	6	1078	4932	17	2012-01-13 21:04:40.246118	\N
1323	0	11	2	6560	8463	5	2012-01-13 20:57:10.896415	2012-01-13 21:38:52.267895
1389	7324	3	17	7324	6944	20	2012-01-13 21:05:15.143598	\N
1349	0	11	14	7195	8036	16	2012-01-13 21:00:50.423643	2012-01-13 21:32:07.513035
1394	2672	8	7	2672	6537	2	2012-01-13 21:05:41.502368	\N
1396	2967	3	18	2967	3902	14	2012-01-13 21:05:56.453198	\N
1345	0	19	7	9830	9892	6	2012-01-13 20:59:54.059448	2012-01-13 21:13:09.417563
1399	2421	10	11	2421	6121	6	2012-01-13 21:06:21.658182	\N
1401	444	9	6	444	6975	7	2012-01-13 21:06:45.515402	\N
1402	772	9	18	772	2415	13	2012-01-13 21:06:47.635376	\N
1404	0	1	4	9091	7967	19	2012-01-13 21:06:52.130506	2012-01-13 21:06:52.130506
1322	0	7	1	877	1881	19	2012-01-13 20:57:08.948282	2012-01-13 21:10:53.550024
1414	0	1	11	8831	7837	20	2012-01-13 21:07:50.530741	2012-01-13 21:10:53.550024
1407	0	17	7	9422	2190	4	2012-01-13 21:07:07.413716	2012-01-13 21:07:07.413716
1410	2605	12	7	2605	5401	18	2012-01-13 21:07:16.806295	\N
1355	0	6	14	3688	3058	4	2012-01-13 21:01:31.723614	2012-01-13 21:07:24.80664
1411	0	14	13	7337	34	4	2012-01-13 21:07:24.80664	2012-01-13 21:07:24.80664
1375	0	7	14	1826	989	8	2012-01-13 21:03:53.974692	2012-01-13 21:13:09.417563
1405	0	11	18	2551	5472	6	2012-01-13 21:06:59.513048	2012-01-13 21:10:45.557193
1365	0	9	7	8018	2095	11	2012-01-13 21:02:50.919315	2012-01-13 21:08:36.390255
1415	0	7	2	2582	3026	16	2012-01-13 21:08:06.711324	2012-01-13 21:08:36.390255
1416	0	4	5	9665	3346	16	2012-01-13 21:08:14.781015	2012-01-13 21:10:45.557193
1452	0	20	9	3936	1917	12	2012-01-13 21:13:12.208345	2012-01-13 21:13:12.208345
1419	0	2	16	3271	217	12	2012-01-13 21:08:36.390255	2012-01-13 21:08:36.390255
1420	4594	16	2	4594	4204	9	2012-01-13 21:08:38.780123	\N
1421	0	20	8	4907	735	1	2012-01-13 21:08:46.660514	2012-01-13 21:08:46.660514
1422	26	20	12	26	5453	8	2012-01-13 21:08:49.714796	\N
1471	0	19	15	2996	4157	17	2012-01-13 21:15:50.364439	2012-01-13 21:42:04.6439
1445	0	5	1	1858	5500	16	2012-01-13 21:12:35.728182	2012-01-13 21:39:56.691615
1424	294	6	8	294	9582	5	2012-01-13 21:08:56.317756	\N
1487	0	9	20	2363	7813	13	2012-01-13 21:18:06.896204	2012-01-13 22:32:25.521236
1441	0	12	7	5558	5807	14	2012-01-13 21:11:55.449518	2012-01-13 21:43:43.506304
1496	0	10	6	8546	5615	20	2012-01-13 21:19:19.840286	2012-01-14 00:44:49.071519
1454	0	13	6	5359	6520	13	2012-01-13 21:13:27.061812	2012-01-14 00:08:51.424643
1431	5727	20	11	5727	7598	2	2012-01-13 21:10:33.311173	\N
1513	0	3	12	8296	4498	6	2012-01-13 21:21:36.784197	2012-01-13 21:46:20.945515
1409	0	5	13	4403	3747	15	2012-01-13 21:07:12.220949	2012-01-13 21:10:45.557193
1511	153	9	12	153	8428	8	2012-01-13 21:21:27.146481	\N
1427	0	11	4	5158	9301	8	2012-01-13 21:09:23.597136	2012-01-13 21:13:32.104722
1433	0	11	7	6038	55	9	2012-01-13 21:10:53.550024	2012-01-13 21:10:53.550024
1434	893	3	15	893	3967	7	2012-01-13 21:10:55.920095	\N
1455	0	4	1	9169	4969	13	2012-01-13 21:13:32.104722	2012-01-13 21:13:32.104722
1436	0	2	1	9041	8414	13	2012-01-13 21:11:13.285148	2012-01-13 21:11:13.285148
1439	0	18	13	4459	4088	4	2012-01-13 21:11:40.82744	2012-01-13 21:47:03.782747
1456	178	16	7	178	2552	11	2012-01-13 21:13:41.471952	\N
1494	0	9	8	6541	7438	10	2012-01-13 21:18:55.667558	2012-01-13 22:50:20.889222
1462	0	15	1	3850	5902	13	2012-01-13 21:14:31.26067	2012-01-13 21:47:18.541476
1440	1024	15	5	1024	1491	9	2012-01-13 21:11:52.719019	\N
1470	0	4	13	7310	3128	13	2012-01-13 21:15:43.219124	2012-01-13 21:51:59.101665
1514	0	10	15	6939	8529	9	2012-01-13 21:21:45.756693	2012-01-14 01:08:37.826355
1443	0	17	8	7739	6794	17	2012-01-13 21:12:27.878198	2012-01-13 21:12:27.878198
1457	7472	3	11	7472	5769	14	2012-01-13 21:13:50.77289	\N
1428	0	17	11	5540	5534	17	2012-01-13 21:09:26.317586	2012-01-13 21:12:33.013403
1444	0	6	17	2021	2069	13	2012-01-13 21:12:33.013403	2012-01-13 21:12:33.013403
1465	0	17	13	6264	4785	11	2012-01-13 21:14:43.362533	2012-01-13 21:59:47.518105
1450	0	1	8	5209	9143	14	2012-01-13 21:13:01.767973	2012-01-13 21:35:03.592563
1447	1762	1	17	1762	4785	15	2012-01-13 21:12:40.620301	\N
1515	0	4	6	4454	1665	6	2012-01-13 21:21:56.525495	2012-01-13 23:09:34.398047
1498	0	8	10	3365	5910	3	2012-01-13 21:19:46.022743	2012-01-13 22:19:47.660565
1425	0	10	6	9259	3438	20	2012-01-13 21:09:04.485388	2012-01-13 22:25:25.203898
1430	0	9	13	9747	8712	7	2012-01-13 21:09:47.618182	2012-01-13 23:46:59.58311
1451	0	14	5	7387	470	12	2012-01-13 21:13:09.417563	2012-01-13 21:13:09.417563
1438	0	1	6	9617	7719	9	2012-01-13 21:11:20.678762	2012-01-13 22:43:59.02046
1448	0	3	14	5469	1767	14	2012-01-13 21:12:47.449612	2012-01-13 23:07:05.371689
1458	251	17	10	1185	3535	2	2012-01-13 21:14:02.549662	2012-01-13 23:39:06.445425
1435	0	9	1	4511	4953	18	2012-01-13 21:11:06.542459	2012-01-14 04:57:16.542017
1491	0	16	10	8015	4023	8	2012-01-13 21:18:31.114156	2012-01-14 04:42:52.441421
1442	0	12	2	7257	6917	15	2012-01-13 21:12:08.500288	2012-01-14 00:48:14.344588
1500	0	14	8	3262	8330	9	2012-01-13 21:19:54.588101	2012-01-13 21:31:28.278476
1461	0	9	4	1931	3300	20	2012-01-13 21:14:26.727738	2012-01-14 02:09:03.523079
1482	0	13	1	771	2396	16	2012-01-13 21:17:18.532238	2012-01-14 04:53:41.614745
1474	2147	8	19	2147	5858	9	2012-01-13 21:16:19.213135	\N
1463	0	7	20	6506	8547	14	2012-01-13 21:14:35.832982	2012-01-13 21:15:30.982275
1468	0	20	7	3739	2092	14	2012-01-13 21:15:30.982275	2012-01-13 21:15:30.982275
1469	7842	16	2	7842	5038	15	2012-01-13 21:15:32.951367	\N
1476	149	4	2	149	3628	3	2012-01-13 21:16:34.63115	\N
1489	0	6	9	7042	3486	14	2012-01-13 21:18:19.902239	2012-01-13 21:18:19.902239
1478	2160	9	15	2160	6220	9	2012-01-13 21:16:44.659388	\N
1504	0	20	15	5621	3365	11	2012-01-13 21:20:30.61143	2012-01-13 21:24:59.692668
1490	0	7	8	3791	4836	2	2012-01-13 21:18:22.926045	2012-01-13 21:24:03.978268
1497	0	14	4	2997	8004	18	2012-01-13 21:19:36.386889	2012-01-13 21:22:46.291382
1485	0	4	10	9625	9434	8	2012-01-13 21:17:49.070181	2012-01-13 21:17:49.070181
1486	945	10	4	945	8428	6	2012-01-13 21:17:54.37657	\N
1501	0	1	10	6295	240	4	2012-01-13 21:20:06.732521	2012-01-13 21:20:06.732521
1495	1952	16	7	1952	5873	5	2012-01-13 21:19:06.060789	\N
1464	0	5	18	2081	6829	4	2012-01-13 21:14:40.757967	2012-01-13 21:26:55.421217
1446	0	6	15	4933	6886	17	2012-01-13 21:12:38.03592	2012-01-13 21:19:46.022743
1488	0	15	8	6548	7907	13	2012-01-13 21:18:11.759975	2012-01-13 21:19:46.022743
1472	0	7	19	8008	8625	11	2012-01-13 21:15:52.986353	2012-01-13 21:19:51.641593
1499	0	19	9	3488	2474	19	2012-01-13 21:19:51.641593	2012-01-13 21:19:51.641593
1502	2760	2	7	2760	9282	2	2012-01-13 21:20:09.684777	\N
1505	5767	16	5	5767	1751	6	2012-01-13 21:20:35.975244	\N
1453	0	3	9	5255	217	16	2012-01-13 21:13:13.764628	2012-01-13 21:35:03.592563
1509	3248	16	15	3248	5610	6	2012-01-13 21:21:05.280493	\N
1432	0	13	1	4836	6616	18	2012-01-13 21:10:45.557193	2012-01-13 21:21:15.009896
1510	0	1	9	6143	8050	5	2012-01-13 21:21:15.009896	2012-01-13 21:21:15.009896
1512	4191	2	6	4191	6485	2	2012-01-13 21:21:31.669943	\N
1492	0	4	8	4902	2672	1	2012-01-13 21:18:42.118392	2012-01-13 21:22:46.291382
1493	0	18	15	4168	3246	20	2012-01-13 21:18:47.369711	2012-01-13 21:22:29.540362
1564	0	15	18	2069	4992	3	2012-01-13 21:28:36.435802	2012-01-13 21:42:04.6439
1553	0	20	7	5480	5940	14	2012-01-13 21:26:58.488497	2012-01-13 21:43:40.211554
1596	0	10	17	9585	4228	17	2012-01-13 21:32:30.269276	2012-01-13 21:58:58.475773
1518	0	1	4	2774	4301	8	2012-01-13 21:22:13.633412	2012-01-13 21:47:18.541476
1516	0	15	20	1615	9282	10	2012-01-13 21:21:59.367162	2012-01-13 21:22:29.540362
1520	0	20	18	2249	234	19	2012-01-13 21:22:29.540362	2012-01-13 21:22:29.540362
1604	0	20	12	9350	7605	20	2012-01-13 21:34:07.054946	2012-01-13 21:43:43.506304
1580	0	19	7	4399	9209	17	2012-01-13 21:30:35.520062	2012-01-14 00:00:47.854862
1615	0	3	15	3691	1631	19	2012-01-13 21:35:49.076625	2012-01-13 21:44:10.69988
1523	0	5	14	4972	2121	10	2012-01-13 21:22:46.291382	2012-01-13 21:22:46.291382
1602	0	7	1	169	3962	9	2012-01-13 21:33:45.53415	2012-01-14 03:14:56.36778
1525	1555	18	20	1555	8187	17	2012-01-13 21:22:58.550149	\N
1668	0	15	7	6285	9356	19	2012-01-13 21:44:10.69988	2012-01-13 21:44:10.69988
1608	0	10	16	392	3231	5	2012-01-13 21:34:36.893237	2012-01-13 21:40:19.025745
1527	1060	8	4	1060	2774	17	2012-01-13 21:23:11.98777	\N
1528	1893	16	17	1893	1849	7	2012-01-13 21:23:14.822654	\N
1552	0	7	5	5774	2378	2	2012-01-13 21:26:55.421217	2012-01-13 21:26:55.421217
1540	0	15	7	2287	3320	2	2012-01-13 21:24:47.356296	2012-01-13 22:19:56.217468
1597	0	11	5	6067	8319	2	2012-01-13 21:32:42.337126	2012-01-13 23:00:18.37957
1532	2524	11	6	2524	7813	8	2012-01-13 21:23:46.406189	\N
1550	0	20	6	9181	3230	14	2012-01-13 21:26:34.606925	2012-01-13 21:45:37.741246
1575	0	8	13	5364	3731	8	2012-01-13 21:29:52.896254	2012-01-13 21:46:41.306923
1530	0	15	6	5445	3435	6	2012-01-13 21:23:31.478421	2012-01-13 21:46:53.438864
1607	0	4	6	5372	3268	10	2012-01-13 21:34:26.493722	2012-01-13 22:33:36.442073
1554	4093	12	11	4093	9048	12	2012-01-13 21:27:07.506967	\N
1536	795	9	20	795	3500	18	2012-01-13 21:24:10.062027	\N
1537	4166	3	7	4166	3434	9	2012-01-13 21:24:18.791493	\N
1538	1334	17	13	1334	2942	5	2012-01-13 21:24:30.469558	\N
1600	0	9	1	9805	3719	8	2012-01-13 21:33:20.209707	2012-01-13 22:27:57.159744
1534	0	9	10	7887	7273	14	2012-01-13 21:23:58.318177	2012-01-13 22:31:23.461962
1613	0	8	18	5546	7739	7	2012-01-13 21:35:19.718042	2012-01-13 22:34:49.589864
1531	0	1	11	3383	7722	6	2012-01-13 21:23:37.003424	2012-01-13 22:55:02.050562
1573	642	13	6	642	4146	6	2012-01-13 21:29:46.331836	\N
1591	0	14	13	1476	6687	8	2012-01-13 21:31:57.648531	2012-01-13 23:07:11.501389
1529	0	15	12	1137	1580	16	2012-01-13 21:23:28.571077	2012-01-13 21:24:59.692668
1535	0	19	18	4833	2711	17	2012-01-13 21:24:03.978268	2012-01-13 21:24:59.692668
1542	0	18	9	7837	7787	20	2012-01-13 21:24:59.692668	2012-01-13 21:24:59.692668
1543	1230	9	18	1230	8346	17	2012-01-13 21:25:15.674685	\N
1544	81	7	11	81	3089	11	2012-01-13 21:25:20.659	\N
1551	0	6	13	5537	9332	7	2012-01-13 21:26:49.385334	2012-01-13 23:09:34.398047
1574	388	14	4	388	4038	20	2012-01-13 21:29:49.550132	\N
1546	4243	2	6	4243	9983	10	2012-01-13 21:25:47.459331	\N
1547	1787	16	6	1787	8955	8	2012-01-13 21:25:52.622327	\N
1548	7690	20	19	7690	9713	4	2012-01-13 21:26:04.103083	\N
1599	0	10	6	7353	3307	17	2012-01-13 21:33:07.739636	2012-01-14 00:13:42.192461
1557	307	2	10	307	7391	17	2012-01-13 21:27:44.959606	\N
1572	0	5	6	5474	8135	14	2012-01-13 21:29:33.899567	2012-01-14 01:14:49.41845
1589	0	9	13	6389	5768	3	2012-01-13 21:31:33.657643	2012-01-14 02:32:45.615302
1586	0	20	4	3086	5121	15	2012-01-13 21:31:13.231093	2012-01-14 02:35:58.355015
1559	1011	11	20	1011	7985	7	2012-01-13 21:27:56.114947	\N
1524	0	12	19	4973	4939	6	2012-01-13 21:22:49.254775	2012-01-14 02:58:16.85139
1576	37	1	19	37	2830	9	2012-01-13 21:30:04.709232	\N
1588	0	8	7	6900	2896	3	2012-01-13 21:31:28.278476	2012-01-13 21:31:28.278476
1565	4666	3	10	4666	9953	11	2012-01-13 21:28:42.742636	\N
1562	0	20	2	7398	996	7	2012-01-13 21:28:22.446306	2012-01-13 21:30:07.752403
1563	0	2	19	3630	6517	7	2012-01-13 21:28:27.60755	2012-01-13 21:30:07.752403
1569	190	20	11	190	6885	11	2012-01-13 21:29:21.935666	\N
1577	0	19	9	5591	956	3	2012-01-13 21:30:07.752403	2012-01-13 21:30:07.752403
1571	735	20	15	735	5965	20	2012-01-13 21:29:31.146332	\N
1579	975	7	14	975	7880	6	2012-01-13 21:30:29.042944	\N
1581	1341	18	5	1341	7648	11	2012-01-13 21:30:48.093485	\N
1609	0	1	4	8288	8493	7	2012-01-13 21:34:40.376754	2012-01-13 21:38:52.267895
1584	761	15	20	761	5918	18	2012-01-13 21:31:03.338248	\N
1611	13	9	3	13	6294	18	2012-01-13 21:35:13.162962	\N
1587	1512	9	18	1512	1919	5	2012-01-13 21:31:22.274644	\N
1592	0	14	4	3632	630	2	2012-01-13 21:32:07.513035	2012-01-13 21:32:07.513035
1593	0	13	10	3421	4609	19	2012-01-13 21:32:10.919457	2012-01-13 21:32:10.919457
1594	7460	16	7	7460	6223	18	2012-01-13 21:32:14.520605	\N
1601	2205	9	4	2205	7027	13	2012-01-13 21:33:32.556492	\N
1603	3611	16	4	3611	6027	2	2012-01-13 21:33:48.872888	\N
1606	1855	12	20	1855	7973	17	2012-01-13 21:34:23.59684	\N
1595	0	13	15	3786	5581	18	2012-01-13 21:32:26.818391	2012-01-13 21:40:09.542595
1590	0	8	18	3223	1658	4	2012-01-13 21:31:48.869751	2012-01-13 21:35:03.592563
1610	0	9	1	8101	2421	16	2012-01-13 21:35:03.592563	2012-01-13 21:35:03.592563
1612	0	14	19	277	40	20	2012-01-13 21:35:16.42628	2012-01-13 21:35:16.42628
1614	9622	3	13	9622	8329	20	2012-01-13 21:35:25.650581	\N
1583	0	9	12	3966	2544	3	2012-01-13 21:31:00.690483	2012-01-13 21:36:31.044638
1616	4668	3	20	4668	8387	9	2012-01-13 21:36:11.95879	\N
1685	0	1	8	8962	8435	16	2012-01-13 21:46:30.949633	2012-01-13 21:46:30.949633
1645	4646	10	6	4646	6169	9	2012-01-13 21:40:50.211211	\N
1618	0	12	18	5679	1249	10	2012-01-13 21:36:31.044638	2012-01-13 21:36:31.044638
1619	4972	16	20	4972	9384	15	2012-01-13 21:36:34.01324	\N
1699	0	3	14	5052	871	16	2012-01-13 21:48:10.939315	2012-01-13 22:58:29.670371
1696	2808	17	15	2808	7553	13	2012-01-13 21:47:50.819385	\N
1632	0	4	6	7272	2470	6	2012-01-13 21:39:11.906254	2012-01-13 21:42:00.874568
1617	0	9	19	8328	1127	1	2012-01-13 21:36:25.06458	2012-01-13 21:42:04.6439
1640	0	9	20	7288	4195	5	2012-01-13 21:40:00.248955	2012-01-13 21:43:43.506304
1721	5354	3	17	5354	9869	11	2012-01-13 21:52:17.682456	\N
1698	0	9	2	8860	7448	19	2012-01-13 21:48:01.896011	2012-01-14 06:40:39.48521
1631	0	3	15	7679	7195	1	2012-01-13 21:38:55.879925	2012-01-14 02:43:38.180341
1723	829	3	15	829	2835	2	2012-01-13 21:52:31.944363	\N
1702	0	5	18	8931	8263	4	2012-01-13 21:48:31.020647	2012-01-13 22:26:18.741314
1669	938	5	6	938	1455	15	2012-01-13 21:44:35.574484	\N
1622	0	17	11	5066	2301	6	2012-01-13 21:37:21.976382	2012-01-13 21:38:52.267895
1630	0	15	1	9286	1515	1	2012-01-13 21:38:52.267895	2012-01-13 21:38:52.267895
1626	0	8	2	3279	4780	17	2012-01-13 21:37:56.882082	2012-01-14 02:45:34.478226
1686	0	13	8	7717	793	18	2012-01-13 21:46:41.306923	2012-01-13 21:46:41.306923
1633	0	15	20	6555	3855	15	2012-01-13 21:39:18.691788	2012-01-13 21:39:18.691788
1670	0	19	11	7922	6796	2	2012-01-13 21:44:38.72792	2012-01-13 21:44:38.72792
1711	0	9	20	9704	7324	3	2012-01-13 21:50:28.953361	2012-01-13 22:19:34.404559
1636	3194	5	18	3194	9196	3	2012-01-13 21:39:36.540068	\N
1713	0	15	5	4783	6054	6	2012-01-13 21:51:09.23469	2012-01-14 00:05:08.844092
1687	1907	10	6	1907	1280	18	2012-01-13 21:46:44.714425	\N
1673	281	3	6	281	3313	7	2012-01-13 21:44:59.458457	\N
1623	0	6	5	7694	9074	17	2012-01-13 21:37:28.70698	2012-01-13 21:39:56.691615
1639	0	1	11	6105	1046	1	2012-01-13 21:39:56.691615	2012-01-13 21:39:56.691615
1582	0	15	2	5270	8372	9	2012-01-13 21:30:54.128994	2012-01-13 21:40:09.542595
1526	0	2	18	4244	7456	14	2012-01-13 21:23:04.045704	2012-01-13 21:40:09.542595
1620	0	4	2	4580	4940	19	2012-01-13 21:36:44.147037	2012-01-13 21:40:09.542595
1642	1535	20	1	1535	2037	4	2012-01-13 21:40:15.991234	\N
1674	0	11	18	1831	316	3	2012-01-13 21:45:10.249457	2012-01-13 21:45:10.249457
1641	0	2	7	9914	233	13	2012-01-13 21:40:09.542595	2012-01-13 21:40:19.025745
1638	0	4	20	3127	3270	11	2012-01-13 21:39:53.177825	2012-01-13 21:40:19.025745
1643	0	16	3	2220	669	9	2012-01-13 21:40:19.025745	2012-01-13 21:40:19.025745
1675	5405	11	6	5405	7156	1	2012-01-13 21:45:13.586625	\N
1688	0	1	3	9433	3585	7	2012-01-13 21:46:50.559258	2012-01-13 21:46:50.559258
1697	8402	16	9	8402	9727	1	2012-01-13 21:47:54.19488	\N
1519	0	6	11	1935	6942	2	2012-01-13 21:22:26.43383	2012-01-13 21:46:53.438864
1677	0	6	13	5413	5113	14	2012-01-13 21:45:34.225213	2012-01-13 21:45:37.741246
1678	0	5	20	5255	8945	1	2012-01-13 21:45:37.741246	2012-01-13 21:45:37.741246
1671	0	11	2	2676	2523	13	2012-01-13 21:44:45.64593	2012-01-13 23:47:49.769043
1682	673	3	14	673	3126	16	2012-01-13 21:46:18.581431	\N
1683	0	8	3	2884	1020	12	2012-01-13 21:46:20.945515	2012-01-13 21:46:20.945515
1690	0	13	18	1330	716	8	2012-01-13 21:47:03.782747	2012-01-13 21:47:03.782747
1679	0	16	2	7892	1186	9	2012-01-13 21:45:43.827811	2012-01-13 23:46:27.748285
1681	0	8	1	9523	3313	18	2012-01-13 21:46:03.161952	2012-01-13 21:46:30.949633
1719	0	5	4	2845	2576	11	2012-01-13 21:51:59.101665	2012-01-13 21:51:59.101665
1030	0	8	11	476	340	11	2012-01-13 20:37:26.983054	2012-01-13 21:47:18.541476
1689	0	11	15	9917	3280	20	2012-01-13 21:46:53.438864	2012-01-13 21:47:18.541476
1692	0	4	8	6741	7447	9	2012-01-13 21:47:18.541476	2012-01-13 21:47:18.541476
1693	1498	11	17	1498	8687	1	2012-01-13 21:47:28.720642	\N
1705	7495	15	14	7495	7506	3	2012-01-13 21:49:10.43218	\N
1629	0	8	13	9357	6234	4	2012-01-13 21:38:28.639086	2012-01-13 22:24:45.169604
1694	0	15	12	7092	8806	20	2012-01-13 21:47:34.625764	2012-01-13 21:48:27.662169
1701	0	7	2	9700	1281	2	2012-01-13 21:48:27.662169	2012-01-13 21:48:27.662169
1707	0	17	5	2264	3621	13	2012-01-13 21:49:53.862638	2012-01-13 22:34:49.589864
1704	0	11	13	4544	4157	4	2012-01-13 21:49:04.086069	2012-01-13 22:21:47.996638
1695	0	4	12	4346	8573	1	2012-01-13 21:47:40.954385	2012-01-13 22:24:40.554445
1621	0	8	13	9267	6969	8	2012-01-13 21:36:54.992068	2012-01-13 22:48:46.051158
1712	0	7	1	4634	4955	10	2012-01-13 21:50:59.00882	2012-01-13 21:55:16.837897
1709	1237	20	12	1237	7418	2	2012-01-13 21:50:07.852055	\N
1710	2176	17	4	2176	7257	1	2012-01-13 21:50:10.631105	\N
1708	0	14	1	3119	4918	12	2012-01-13 21:50:00.893089	2012-01-13 22:07:16.631201
1627	0	19	17	3475	8876	12	2012-01-13 21:38:06.835004	2012-01-14 00:52:28.24555
1714	0	7	12	9705	630	16	2012-01-13 21:51:28.151919	2012-01-13 21:51:28.151919
1715	4129	16	2	4129	4374	13	2012-01-13 21:51:31.640996	\N
1635	0	13	7	3832	9315	7	2012-01-13 21:39:29.862834	2012-01-13 22:07:49.506895
105	0	19	6	9372	9582	4	2012-01-13 20:24:51.498291	2012-01-13 21:51:52.482874
1625	0	8	4	5245	4901	8	2012-01-13 21:37:47.288883	2012-01-13 21:51:52.482874
1700	0	4	11	2993	1082	1	2012-01-13 21:48:21.1727	2012-01-13 21:51:52.482874
1718	0	11	19	6431	2332	14	2012-01-13 21:51:52.482874	2012-01-13 21:51:52.482874
1628	0	4	11	9563	8765	4	2012-01-13 21:38:13.756296	2012-01-13 21:52:28.460667
1722	0	14	4	9564	4224	13	2012-01-13 21:52:28.460667	2012-01-13 21:52:28.460667
1724	2846	10	6	2846	8061	18	2012-01-13 21:52:44.222415	\N
1800	0	10	9	1207	2844	1	2012-01-13 22:03:43.771618	2012-01-13 23:07:05.371689
1728	0	1	12	5801	4598	16	2012-01-13 21:53:14.128272	2012-01-13 21:53:14.128272
1798	0	20	3	4247	3878	5	2012-01-13 22:03:25.147371	2012-01-13 22:19:34.404559
1735	0	3	18	7270	2870	17	2012-01-13 21:54:08.204054	2012-01-14 00:03:02.345364
1804	1042	12	2	4677	6696	13	2012-01-13 22:04:19.524417	2012-01-14 01:58:09.450876
1731	0	15	20	6486	4720	17	2012-01-13 21:53:30.795545	2012-01-13 21:53:30.795545
1732	493	17	2	493	5443	4	2012-01-13 21:53:44.289552	\N
1794	0	7	19	1824	902	13	2012-01-13 22:03:09.715955	2012-01-13 22:07:49.506895
1810	0	20	13	2787	2223	15	2012-01-13 22:05:05.993656	2012-01-14 00:28:06.502198
1754	0	11	18	1884	3476	16	2012-01-13 21:57:31.741251	2012-01-14 01:25:14.985818
1738	6073	18	6	6073	7869	14	2012-01-13 21:54:32.140968	\N
1740	0	20	4	5818	7981	12	2012-01-13 21:54:50.566914	2012-01-14 01:38:24.804832
1762	0	16	10	8287	3740	8	2012-01-13 21:58:39.370938	2012-01-14 01:53:50.482523
1777	0	6	9	6577	3419	18	2012-01-13 22:01:06.207045	2012-01-13 22:01:06.207045
1717	0	2	18	3499	2831	10	2012-01-13 21:51:46.382012	2012-01-13 21:55:00.474442
1743	0	10	1	9765	8595	10	2012-01-13 21:55:27.368698	2012-01-13 22:31:23.461962
1764	0	17	10	2722	3810	15	2012-01-13 21:58:58.475773	2012-01-13 21:58:58.475773
1737	0	1	2	3790	1959	8	2012-01-13 21:54:28.582879	2012-01-13 21:55:16.837897
1742	0	14	7	5076	5332	8	2012-01-13 21:55:16.837897	2012-01-13 21:55:16.837897
1758	0	17	2	6510	9408	13	2012-01-13 21:58:06.205678	2012-01-13 22:31:28.243968
1744	1178	10	17	1178	8136	10	2012-01-13 21:55:49.718399	\N
1792	0	7	10	2397	4492	2	2012-01-13 22:02:57.701632	2012-01-13 22:25:25.203898
1746	1031	4	11	1031	6151	6	2012-01-13 21:56:07.737805	\N
1733	0	1	13	7668	5697	14	2012-01-13 21:53:51.062178	2012-01-13 22:07:16.631201
1748	0	11	19	9603	6152	6	2012-01-13 21:56:32.897278	2012-01-13 22:06:52.535079
1778	5575	12	18	5575	8765	2	2012-01-13 22:01:10.546664	\N
1751	1098	17	4	1098	7065	11	2012-01-13 21:57:00.227107	\N
1749	0	11	1	6990	7662	10	2012-01-13 21:56:42.857781	2012-01-13 22:06:48.558781
1739	0	16	9	9062	9053	17	2012-01-13 21:54:42.352811	2012-01-14 01:34:56.589519
1755	6542	16	14	6542	6003	1	2012-01-13 21:57:39.027227	\N
1757	0	19	6	7315	8389	7	2012-01-13 21:57:50.443771	2012-01-13 23:14:37.785046
1802	0	15	4	2003	4541	6	2012-01-13 22:04:07.465443	2012-01-13 23:51:30.316819
1767	0	20	10	7377	9291	19	2012-01-13 21:59:17.322442	2012-01-13 22:33:54.172716
1765	0	15	9	3932	2672	6	2012-01-13 21:59:02.328133	2012-01-13 21:59:02.328133
1761	3023	1	6	3023	5829	17	2012-01-13 21:58:28.455531	\N
1779	946	13	15	946	8463	17	2012-01-13 22:01:24.228911	\N
1727	0	2	14	5370	7972	7	2012-01-13 21:53:01.357892	2012-01-13 23:02:11.380349
1781	4500	19	14	4500	7724	18	2012-01-13 22:01:38.644908	\N
1750	0	7	17	8813	6826	10	2012-01-13 21:56:53.150447	2012-01-13 21:59:47.518105
1769	0	13	7	5315	1629	12	2012-01-13 21:59:47.518105	2012-01-13 21:59:47.518105
1770	4801	4	6	4801	7780	8	2012-01-13 21:59:51.221738	\N
1772	1630	5	2	1630	9034	2	2012-01-13 22:00:18.555751	\N
1782	2319	13	15	2319	7591	8	2012-01-13 22:01:46.42016	\N
1789	0	2	4	1764	6425	20	2012-01-13 22:02:41.360277	2012-01-14 02:48:10.373285
1775	1799	9	5	1799	7599	19	2012-01-13 22:00:41.495542	\N
1729	0	15	12	7533	8219	18	2012-01-13 21:53:17.413459	2012-01-13 22:13:45.532156
1790	1448	16	15	1448	6699	4	2012-01-13 22:02:45.042459	\N
1784	1927	20	19	1927	9631	11	2012-01-13 22:01:57.890654	\N
1797	1057	12	2	1057	6156	15	2012-01-13 22:03:21.602107	\N
1791	0	14	7	7697	1573	10	2012-01-13 22:02:53.881687	2012-01-13 22:02:53.881687
1771	0	17	7	4182	6985	3	2012-01-13 22:00:15.003885	2012-01-13 22:02:15.307674
1786	0	7	17	5821	1639	17	2012-01-13 22:02:15.307674	2012-01-13 22:02:15.307674
1787	1872	17	6	1872	5732	10	2012-01-13 22:02:19.153065	\N
1745	0	3	4	7373	2734	11	2012-01-13 21:55:55.838017	2012-01-13 22:24:40.554445
1752	0	16	3	2420	958	2	2012-01-13 21:57:11.429736	2012-01-14 04:35:01.369025
1811	0	20	3	3847	8704	13	2012-01-13 22:05:09.568288	2012-01-13 22:27:57.159744
1793	1884	11	4	1884	6473	8	2012-01-13 22:03:05.819077	\N
1806	0	19	8	5446	8637	12	2012-01-13 22:04:30.971077	2012-01-13 22:19:47.660565
1780	0	2	6	7696	1967	9	2012-01-13 22:01:28.017965	2012-01-13 22:03:13.415977
1795	0	6	20	9202	832	16	2012-01-13 22:03:13.415977	2012-01-13 22:03:13.415977
1796	701	11	14	701	5743	20	2012-01-13 22:03:17.592506	\N
1801	1892	3	6	1892	5323	6	2012-01-13 22:03:47.589372	\N
1763	0	3	2	9874	948	16	2012-01-13 21:58:50.569159	2012-01-13 22:03:25.147371
1760	0	2	5	4686	8009	2	2012-01-13 21:58:21.16923	2012-01-13 22:03:25.147371
1756	0	5	20	1961	7905	13	2012-01-13 21:57:47.100799	2012-01-13 22:03:25.147371
1788	0	9	15	9099	4124	10	2012-01-13 22:02:26.823191	2012-01-13 22:19:56.217468
1799	776	12	4	776	4397	18	2012-01-13 22:03:36.397214	\N
1730	0	13	18	3152	6234	10	2012-01-13 21:53:24.013664	2012-01-14 00:00:47.854862
1803	2467	11	19	2467	6797	13	2012-01-13 22:04:15.694657	\N
1774	0	6	17	1177	5832	14	2012-01-13 22:00:37.627424	2012-01-14 02:02:27.621805
1736	0	11	17	1216	1733	8	2012-01-13 21:54:25.272036	2012-01-14 01:14:49.41845
1741	0	18	14	4596	5783	1	2012-01-13 21:55:00.474442	2012-01-13 22:31:05.184536
1807	1711	16	6	1711	6576	11	2012-01-13 22:04:39.297055	\N
1808	1896	5	19	1896	2678	15	2012-01-13 22:04:48.521655	\N
1805	0	1	10	1472	1823	15	2012-01-13 22:04:26.826771	2012-01-13 22:04:54.623318
1809	0	10	1	9934	4663	11	2012-01-13 22:04:54.623318	2012-01-13 22:04:54.623318
1776	0	8	12	5971	7175	1	2012-01-13 22:00:56.11528	2012-01-13 22:06:40.314259
1753	0	12	7	7327	5599	2	2012-01-13 21:57:22.085192	2012-01-13 22:06:40.314259
1848	3812	12	5	3812	9741	5	2012-01-13 22:11:17.075117	\N
1845	0	5	17	6851	9705	14	2012-01-13 22:10:36.778071	2012-01-13 22:45:02.30868
1815	977	19	12	977	7879	9	2012-01-13 22:05:52.060271	\N
1902	606	4	6	606	6192	9	2012-01-13 22:20:05.523445	\N
1875	0	10	15	4403	6471	18	2012-01-13 22:15:37.183337	2012-01-14 05:01:49.345005
1819	0	7	8	2341	1726	15	2012-01-13 22:06:40.314259	2012-01-13 22:06:40.314259
1820	929	2	11	929	2451	12	2012-01-13 22:06:44.550109	\N
1827	0	9	11	8481	6045	11	2012-01-13 22:07:20.909753	2012-01-13 22:31:18.750017
1821	0	1	11	6721	4120	4	2012-01-13 22:06:48.558781	2012-01-13 22:06:48.558781
1822	0	17	11	4691	1866	18	2012-01-13 22:06:52.535079	2012-01-13 22:06:52.535079
1864	0	9	8	9402	3087	1	2012-01-13 22:13:49.771948	2012-01-13 22:24:45.169604
1840	0	15	2	7360	8998	19	2012-01-13 22:09:45.947554	2012-01-14 02:45:51.832818
1826	0	13	14	4158	3023	15	2012-01-13 22:07:16.631201	2012-01-13 22:07:16.631201
1903	0	3	9	4259	4799	10	2012-01-13 22:20:09.782261	2012-01-13 22:31:23.461962
1828	1056	14	7	1056	7120	8	2012-01-13 22:07:40.512654	\N
1898	9223	16	17	9223	7776	9	2012-01-13 22:19:41.660954	\N
1829	0	19	13	9812	4909	13	2012-01-13 22:07:49.506895	2012-01-13 22:07:49.506895
1667	0	6	7	1210	8126	15	2012-01-13 21:43:54.87305	2012-01-13 22:08:01.591477
1830	0	7	6	3779	552	10	2012-01-13 22:08:01.591477	2012-01-13 22:08:01.591477
1888	0	15	19	5391	4811	2	2012-01-13 22:17:56.512097	2012-01-13 23:15:04.637681
1832	197	5	15	197	1856	20	2012-01-13 22:08:20.943448	\N
1852	427	15	12	427	6564	7	2012-01-13 22:12:07.827345	\N
1835	580	3	5	580	4427	14	2012-01-13 22:08:41.379654	\N
1836	3042	19	1	3042	8725	14	2012-01-13 22:08:51.494408	\N
1837	7251	10	5	7251	7451	6	2012-01-13 22:08:59.799869	\N
1876	0	10	13	8288	3173	15	2012-01-13 22:15:45.546448	2012-01-13 22:33:36.442073
1839	6198	3	2	6198	9109	2	2012-01-13 22:09:29.651406	\N
1817	0	19	10	524	5255	9	2012-01-13 22:06:19.323623	2012-01-14 03:45:03.508809
1907	0	3	9	6611	5012	18	2012-01-13 22:20:51.850677	2012-01-13 22:27:57.159744
1844	23	4	18	23	945	3	2012-01-13 22:10:32.446837	\N
1868	0	7	17	3006	8799	15	2012-01-13 22:14:29.146419	2012-01-13 22:45:59.242466
1853	0	13	16	613	3720	3	2012-01-13 22:12:12.312673	2012-01-13 22:12:12.312673
1847	7623	11	19	7623	8696	8	2012-01-13 22:11:04.253984	\N
1871	0	18	19	1906	5627	4	2012-01-13 22:15:07.979327	2012-01-13 22:48:46.051158
1890	0	5	17	5356	9972	6	2012-01-13 22:18:15.311362	2012-01-14 00:34:24.465528
1856	4236	16	7	4236	6656	11	2012-01-13 22:12:48.414239	\N
1857	0	5	17	9634	6350	20	2012-01-13 22:13:01.909331	2012-01-13 22:13:01.909331
1855	0	7	15	3745	9694	13	2012-01-13 22:12:29.589975	2012-01-13 23:39:06.445425
1869	1808	2	14	1808	3349	15	2012-01-13 22:14:42.730576	\N
1859	0	5	14	3805	687	8	2012-01-13 22:13:14.54634	2012-01-13 22:13:14.54634
1814	0	11	19	7527	6520	18	2012-01-13 22:05:38.644478	2012-01-13 22:41:56.671563
1862	343	13	17	343	8472	15	2012-01-13 22:13:41.176665	\N
1841	0	9	5	8169	1809	6	2012-01-13 22:09:59.031476	2012-01-13 22:13:45.532156
1854	0	5	1	7509	7086	1	2012-01-13 22:12:17.137572	2012-01-13 22:13:45.532156
1863	0	1	17	6223	99	14	2012-01-13 22:13:45.532156	2012-01-13 22:13:45.532156
1892	0	17	4	5467	5926	7	2012-01-13 22:18:33.904903	2012-01-13 22:30:03.587727
1870	0	5	8	7583	7771	2	2012-01-13 22:14:50.845056	2012-01-13 22:34:49.589864
1879	2008	17	19	2008	8868	14	2012-01-13 22:16:27.663261	\N
1831	0	9	7	7281	5645	11	2012-01-13 22:08:05.705961	2012-01-13 23:01:46.298052
1872	6465	3	11	6465	4729	8	2012-01-13 22:15:12.155588	\N
1873	1322	2	8	1322	4067	12	2012-01-13 22:15:29.007046	\N
1874	2543	12	19	2543	5059	14	2012-01-13 22:15:33.196879	\N
1881	0	4	19	3260	8978	7	2012-01-13 22:16:55.858142	2012-01-14 06:16:46.567729
1885	0	18	2	2947	4678	11	2012-01-13 22:17:28.645402	2012-01-13 22:34:49.589864
1889	0	12	18	6730	4377	14	2012-01-13 22:18:06.730674	2012-01-13 23:15:04.637681
1849	0	7	17	2845	3716	13	2012-01-13 22:11:25.333224	2012-01-13 22:31:10.265584
1887	1860	1	14	1860	4885	15	2012-01-13 22:17:48.068448	\N
1883	1739	14	13	1739	8772	7	2012-01-13 22:17:19.838906	\N
1884	1537	11	17	1537	6360	1	2012-01-13 22:17:24.139234	\N
1858	0	19	1	755	1376	4	2012-01-13 22:13:10.254295	2012-01-13 23:29:19.645779
1824	0	3	5	359	206	18	2012-01-13 22:07:04.929955	2012-01-14 00:57:33.797198
1897	0	3	9	5904	5334	5	2012-01-13 22:19:34.404559	2012-01-13 22:19:34.404559
1818	0	12	10	6883	6628	12	2012-01-13 22:06:28.052861	2012-01-13 22:19:16.816246
1851	0	11	18	9151	5859	15	2012-01-13 22:11:44.156894	2012-01-13 22:19:16.816246
1895	0	18	12	9499	2450	5	2012-01-13 22:19:16.816246	2012-01-13 22:19:16.816246
1896	6467	20	5	6467	6980	11	2012-01-13 22:19:21.600848	\N
1900	0	13	12	8185	5319	3	2012-01-13 22:19:51.756245	2012-01-13 22:19:51.756245
1816	0	14	19	4308	8320	19	2012-01-13 22:06:00.839875	2012-01-13 22:19:47.660565
1899	0	10	14	8923	31	10	2012-01-13 22:19:47.660565	2012-01-13 22:19:47.660565
1842	0	2	8	4982	5452	5	2012-01-13 22:10:20.265254	2012-01-13 22:19:56.217468
1865	0	7	14	7688	3037	2	2012-01-13 22:13:57.330754	2012-01-13 22:19:56.217468
1901	0	14	2	6899	5652	12	2012-01-13 22:19:56.217468	2012-01-13 22:19:56.217468
1904	251	19	13	251	5812	11	2012-01-13 22:20:23.826224	\N
1906	1474	12	10	1474	7773	2	2012-01-13 22:20:47.650022	\N
1908	1416	18	19	1416	9989	14	2012-01-13 22:21:09.663689	\N
1843	0	15	11	1931	2071	17	2012-01-13 22:10:28.176726	2012-01-13 22:21:47.996638
1909	3512	16	14	3512	2223	6	2012-01-13 22:21:14.028383	\N
1977	0	7	9	1670	3153	7	2012-01-13 22:32:10.790967	2012-01-13 22:41:37.895851
1912	0	13	15	8916	8618	3	2012-01-13 22:21:47.996638	2012-01-13 22:21:47.996638
1913	9226	16	12	9226	8611	3	2012-01-13 22:22:07.260568	\N
1961	1990	3	12	1990	2530	19	2012-01-13 22:29:07.218783	\N
1941	0	18	5	1293	370	15	2012-01-13 22:26:18.741314	2012-01-13 22:26:18.741314
1916	1754	2	12	1754	5166	13	2012-01-13 22:22:45.123451	\N
1951	1143	14	19	1821	5725	8	2012-01-13 22:27:48.425678	2012-01-13 23:29:19.645779
1918	3487	3	11	3487	9219	13	2012-01-13 22:22:58.198349	\N
1823	0	1	18	5571	5383	12	2012-01-13 22:06:56.853537	2012-01-13 22:23:24.686187
1919	0	17	1	5569	2838	5	2012-01-13 22:23:24.686187	2012-01-13 22:23:24.686187
1920	2661	4	1	2661	8825	11	2012-01-13 22:23:34.098933	\N
1930	0	14	7	1315	4125	14	2012-01-13 22:25:02.495521	2012-01-13 23:51:17.220713
1942	0	14	18	6807	4102	7	2012-01-13 22:26:23.357693	2012-01-13 22:26:23.357693
1962	2829	17	14	2829	8169	18	2012-01-13 22:29:33.041566	\N
1981	0	13	10	1297	8846	6	2012-01-13 22:32:43.324083	2012-01-13 22:44:53.100864
1985	0	6	4	2063	6117	7	2012-01-13 22:33:07.34176	2012-01-14 02:02:27.621805
1926	164	11	7	164	179	18	2012-01-13 22:24:35.926377	\N
1927	0	12	3	1462	1782	12	2012-01-13 22:24:40.554445	2012-01-13 22:24:40.554445
1928	0	13	12	3555	4745	12	2012-01-13 22:24:45.169604	2012-01-13 22:24:45.169604
1929	253	9	11	253	5004	8	2012-01-13 22:24:50.017493	\N
1931	0	19	6	1529	1893	17	2012-01-13 22:25:07.139194	2012-01-13 23:58:47.083443
1925	0	5	15	3383	8786	20	2012-01-13 22:24:26.732737	2012-01-14 00:12:15.102401
1939	0	9	13	4559	3246	12	2012-01-13 22:26:05.9182	2012-01-13 22:47:06.371562
1915	0	19	7	9100	7935	17	2012-01-13 22:22:21.306746	2012-01-13 22:25:25.203898
1933	0	6	19	4086	2879	4	2012-01-13 22:25:25.203898	2012-01-13 22:25:25.203898
1934	427	7	13	427	3743	18	2012-01-13 22:25:30.11006	\N
1935	122	20	17	122	1117	19	2012-01-13 22:25:38.761545	\N
1945	0	9	11	1844	1446	11	2012-01-13 22:26:51.936578	2012-01-13 22:41:37.895851
1936	0	6	1	2232	838	19	2012-01-13 22:25:42.877854	2012-01-13 22:25:42.877854
1989	0	20	5	5534	5834	9	2012-01-13 22:33:41.222729	2012-01-13 23:14:37.785046
1938	1417	9	18	1417	3352	7	2012-01-13 22:26:01.859787	\N
1959	0	15	8	2028	2176	10	2012-01-13 22:28:57.240601	2012-01-13 23:15:04.637681
1940	131	19	4	131	9014	14	2012-01-13 22:26:13.762463	\N
1971	0	11	9	5505	2409	18	2012-01-13 22:31:18.750017	2012-01-13 22:31:18.750017
1948	1837	3	11	1837	4731	5	2012-01-13 22:27:28.360974	\N
1911	0	4	1	9083	8467	20	2012-01-13 22:21:34.421591	2012-01-13 22:35:03.222279
1950	9458	16	7	9458	2805	15	2012-01-13 22:27:39.47426	\N
1921	0	4	18	9653	6319	17	2012-01-13 22:23:38.424399	2012-01-13 23:46:21.477221
1952	389	8	13	389	8383	4	2012-01-13 22:27:53.138021	\N
1956	0	15	17	3357	2333	16	2012-01-13 22:28:14.720685	2012-01-13 22:30:03.587727
1923	0	1	8	6788	6309	1	2012-01-13 22:24:02.481674	2012-01-13 22:27:57.159744
1953	0	2	20	5077	569	7	2012-01-13 22:27:57.159744	2012-01-13 22:27:57.159744
1954	1327	9	17	1327	5877	13	2012-01-13 22:28:01.997482	\N
1964	0	4	8	9163	5048	16	2012-01-13 22:30:03.587727	2012-01-13 22:30:03.587727
1917	0	5	8	4048	4279	8	2012-01-13 22:22:54.001501	2012-01-13 23:16:57.714412
1960	997	17	10	997	8865	1	2012-01-13 22:29:02.072674	\N
1965	3168	17	5	3168	7546	7	2012-01-13 22:30:12.969298	\N
1946	0	1	8	6843	7119	5	2012-01-13 22:26:59.861526	2012-01-13 22:35:03.222279
1972	0	1	3	6131	113	6	2012-01-13 22:31:23.461962	2012-01-13 22:31:23.461962
1967	0	15	12	7502	1519	10	2012-01-13 22:30:38.777487	2012-01-13 22:30:38.777487
1968	3511	9	14	3511	4278	20	2012-01-13 22:30:43.625738	\N
1910	0	17	10	3668	9520	18	2012-01-13 22:21:19.508601	2012-01-13 22:31:05.184536
1958	0	5	18	9547	3600	9	2012-01-13 22:28:43.51161	2012-01-13 22:31:05.184536
1969	0	14	17	7728	16	19	2012-01-13 22:31:05.184536	2012-01-13 22:31:05.184536
1979	0	20	9	9778	50	3	2012-01-13 22:32:25.521236	2012-01-13 22:32:25.521236
1838	0	17	18	3266	3936	4	2012-01-13 22:09:21.090987	2012-01-13 22:31:10.265584
1880	0	18	2	4191	3915	18	2012-01-13 22:16:46.617889	2012-01-13 22:31:10.265584
1970	0	2	7	5807	3833	3	2012-01-13 22:31:10.265584	2012-01-13 22:31:10.265584
1963	0	14	17	4909	7667	20	2012-01-13 22:29:42.550858	2012-01-13 22:31:28.243968
1973	0	2	20	4098	4275	15	2012-01-13 22:31:28.243968	2012-01-13 22:31:28.243968
1974	0	6	7	9128	933	4	2012-01-13 22:31:37.116635	2012-01-13 22:31:37.116635
1976	672	5	20	672	7351	16	2012-01-13 22:32:06.328778	\N
1955	0	6	7	1176	3727	10	2012-01-13 22:28:10.050904	2012-01-13 22:32:29.633414
1984	2016	16	5	2016	2455	6	2012-01-13 22:33:01.308044	\N
1980	0	7	17	7014	2618	10	2012-01-13 22:32:29.633414	2012-01-13 22:32:29.633414
1983	846	20	13	846	5634	12	2012-01-13 22:32:57.450808	\N
1937	0	11	5	8839	8903	3	2012-01-13 22:25:47.595062	2012-01-13 22:35:03.222279
1975	0	15	4	5372	5427	5	2012-01-13 22:31:41.713116	2012-01-13 22:33:36.442073
1987	0	6	10	3908	8700	11	2012-01-13 22:33:26.213005	2012-01-13 22:33:36.442073
1988	0	13	15	7493	231	17	2012-01-13 22:33:36.442073	2012-01-13 22:33:36.442073
1966	0	12	2	3128	2275	5	2012-01-13 22:30:34.279202	2012-01-13 22:33:54.172716
1986	0	2	20	3960	4189	19	2012-01-13 22:33:17.428456	2012-01-13 22:33:54.172716
1949	0	10	17	8075	3814	17	2012-01-13 22:27:35.214597	2012-01-13 22:33:54.172716
564	0	17	14	2837	3530	15	2012-01-13 20:26:45.088549	2012-01-13 22:33:54.172716
1990	0	14	12	5641	5803	17	2012-01-13 22:33:54.172716	2012-01-13 22:33:54.172716
1991	5676	16	17	5676	3017	3	2012-01-13 22:34:03.814577	\N
1992	2656	4	12	2656	5529	8	2012-01-13 22:34:09.442874	\N
1993	2401	10	3	2401	7098	14	2012-01-13 22:34:18.668885	\N
1994	2453	12	11	2453	3419	1	2012-01-13 22:34:27.304391	\N
1995	2006	6	7	2006	5229	15	2012-01-13 22:34:44.781207	\N
1996	0	2	17	4087	280	16	2012-01-13 22:34:49.589864	2012-01-13 22:34:49.589864
2069	0	9	1	2422	2094	12	2012-01-13 22:46:22.669178	2012-01-14 00:00:47.854862
1998	0	5	4	7781	218	9	2012-01-13 22:35:03.222279	2012-01-13 22:35:03.222279
1999	2501	2	7	2501	5542	4	2012-01-13 22:35:07.505076	\N
2000	8840	9	13	8840	8316	2	2012-01-13 22:35:24.10028	\N
2002	1509	18	11	1509	7714	19	2012-01-13 22:36:11.745472	\N
2044	82	2	7	82	5539	17	2012-01-13 22:43:26.900598	\N
2027	489	18	14	489	2626	11	2012-01-13 22:40:59.868689	\N
2073	0	6	7	4001	4832	4	2012-01-13 22:46:52.146761	2012-01-13 23:47:49.769043
2062	0	6	2	5021	6880	12	2012-01-13 22:45:39.211683	2012-01-13 23:02:11.380349
2059	0	5	20	5422	7581	16	2012-01-13 22:45:15.364324	2012-01-14 00:39:38.529843
2009	2885	3	19	2885	9509	4	2012-01-13 22:37:37.5281	\N
2005	0	1	17	1766	824	12	2012-01-13 22:36:44.944887	2012-01-13 22:37:57.819861
2010	0	17	1	5506	4880	8	2012-01-13 22:37:57.819861	2012-01-13 22:37:57.819861
2011	5585	16	17	5585	7704	5	2012-01-13 22:38:07.246349	\N
2079	0	17	15	2776	7113	8	2012-01-13 22:47:58.612884	2012-01-14 02:27:55.836105
2054	0	8	10	2755	8969	20	2012-01-13 22:44:43.120293	2012-01-13 22:58:29.670371
2015	3650	9	2	3650	5787	4	2012-01-13 22:38:46.841491	\N
2050	0	9	17	7538	6992	19	2012-01-13 22:44:08.333219	2012-01-13 23:10:21.753202
2056	1775	4	13	1775	3670	16	2012-01-13 22:44:57.625464	\N
2014	0	17	2	8959	4222	8	2012-01-13 22:38:36.923226	2012-01-13 22:39:29.112443
2019	0	13	17	7284	635	12	2012-01-13 22:39:29.112443	2012-01-13 22:39:29.112443
2020	244	15	13	244	5639	1	2012-01-13 22:39:34.057356	\N
2076	9189	16	15	9189	6622	4	2012-01-13 22:47:11.021716	\N
2030	0	11	7	7274	569	11	2012-01-13 22:41:37.895851	2012-01-13 22:41:37.895851
2022	0	14	5	3030	123	7	2012-01-13 22:40:10.634592	2012-01-13 22:40:10.634592
2024	35	12	7	35	9887	15	2012-01-13 22:40:25.929705	\N
2046	4430	2	13	4430	9293	6	2012-01-13 22:43:40.747641	\N
2018	0	19	6	7194	5829	18	2012-01-13 22:39:19.580923	2012-01-13 22:41:56.671563
2017	0	6	7	3646	5612	5	2012-01-13 22:39:09.383272	2012-01-13 22:41:56.671563
1997	0	7	18	6553	5695	17	2012-01-13 22:34:53.996454	2012-01-13 22:41:56.671563
2032	0	18	11	3601	120	9	2012-01-13 22:41:56.671563	2012-01-13 22:41:56.671563
2033	6691	16	14	6691	4428	7	2012-01-13 22:42:01.425587	\N
2003	0	18	10	4154	9016	16	2012-01-13 22:36:16.200085	2012-01-13 22:42:07.082431
2034	0	5	18	7872	3275	16	2012-01-13 22:42:07.082431	2012-01-13 22:42:07.082431
2035	0	10	12	7599	1712	1	2012-01-13 22:42:11.686393	2012-01-13 22:42:11.686393
2048	0	6	1	4082	3277	2	2012-01-13 22:43:59.02046	2012-01-13 22:43:59.02046
2047	0	6	13	3038	6382	9	2012-01-13 22:43:54.153661	2012-01-14 04:43:13.577782
2008	0	4	5	7328	7327	20	2012-01-13 22:37:12.842542	2012-01-14 00:33:47.127908
2040	0	1	20	6599	2859	6	2012-01-13 22:42:53.705007	2012-01-13 22:42:53.705007
2070	0	4	2	9733	1916	7	2012-01-13 22:46:26.689257	2012-01-13 22:46:26.689257
2078	0	5	8	7801	4870	5	2012-01-13 22:47:49.864614	2012-01-13 22:48:46.051158
2006	0	8	9	2925	5933	10	2012-01-13 22:36:53.863193	2012-01-13 23:15:04.637681
2051	5074	16	11	5074	9327	15	2012-01-13 22:44:17.038849	\N
2057	0	17	5	5393	726	10	2012-01-13 22:45:02.30868	2012-01-13 22:45:02.30868
2041	0	4	15	8158	5627	19	2012-01-13 22:42:58.314363	2012-01-13 22:44:23.066717
2052	0	15	18	5313	895	18	2012-01-13 22:44:23.066717	2012-01-13 22:44:23.066717
2028	0	3	11	7872	3063	12	2012-01-13 22:41:04.434251	2012-01-13 23:00:18.37957
2064	0	1	18	4138	1134	7	2012-01-13 22:45:54.205153	2012-01-13 22:45:54.205153
2055	0	10	13	8459	1106	1	2012-01-13 22:44:53.100864	2012-01-13 22:44:53.100864
2058	2929	10	8	2929	9977	1	2012-01-13 22:45:07.301076	\N
2012	0	12	13	8031	7986	7	2012-01-13 22:38:13.129466	2012-01-14 01:50:50.988089
2074	0	5	20	3663	5683	2	2012-01-13 22:47:01.890135	2012-01-13 22:55:02.050562
2061	2123	17	14	2123	8308	14	2012-01-13 22:45:29.688717	\N
2016	0	13	6	5220	3886	10	2012-01-13 22:38:59.934553	2012-01-13 23:07:11.501389
2063	363	2	1	363	2348	15	2012-01-13 22:45:49.605124	\N
2037	0	17	5	8077	6342	17	2012-01-13 22:42:24.847609	2012-01-13 22:45:59.242466
2065	0	5	7	7818	60	1	2012-01-13 22:45:59.242466	2012-01-13 22:45:59.242466
2068	106	5	2	106	1669	1	2012-01-13 22:46:18.136953	\N
2066	0	5	20	5368	6417	2	2012-01-13 22:46:03.673037	2012-01-13 22:46:03.673037
2049	0	11	12	3586	5711	17	2012-01-13 22:44:03.869952	2012-01-14 00:30:24.862132
2072	0	15	12	6740	905	5	2012-01-13 22:46:47.32745	2012-01-13 22:46:47.32745
2043	0	4	12	1027	1637	4	2012-01-13 22:43:22.08752	2012-01-13 23:48:32.643527
2039	0	17	8	5981	9614	7	2012-01-13 22:42:39.326475	2012-01-14 02:45:34.478226
2021	0	17	9	3960	5809	15	2012-01-13 22:39:43.614899	2012-01-13 22:47:06.371562
2075	0	13	1	6099	1213	1	2012-01-13 22:47:06.371562	2012-01-13 22:47:06.371562
2077	4496	3	11	4496	7758	11	2012-01-13 22:47:17.550886	\N
2013	0	3	1	6103	533	3	2012-01-13 22:38:29.980523	2012-01-13 22:55:02.050562
2060	0	13	18	5072	3869	9	2012-01-13 22:45:19.859021	2012-01-13 22:48:46.051158
2042	0	13	14	4105	4992	11	2012-01-13 22:43:13.111252	2012-01-13 22:48:09.108512
2080	0	14	12	3919	189	14	2012-01-13 22:48:09.108512	2012-01-13 22:48:09.108512
2081	2734	3	10	2734	8957	20	2012-01-13 22:48:14.117703	\N
2166	0	10	5	8882	8914	4	2012-01-13 23:06:22.490174	2012-01-14 00:00:22.037065
2083	0	5	10	2549	1689	9	2012-01-13 22:48:41.235372	2012-01-13 22:48:41.235372
2140	0	20	2	7876	7030	9	2012-01-13 23:01:04.264517	2012-01-14 02:17:01.862906
2084	0	19	5	9583	8672	16	2012-01-13 22:48:46.051158	2012-01-13 22:48:46.051158
2119	0	9	17	9666	9331	11	2012-01-13 22:56:14.582559	2012-01-13 23:20:58.114033
2165	0	11	19	8698	7204	7	2012-01-13 23:06:11.754637	2012-01-13 23:11:09.084343
2105	0	4	8	3597	7861	1	2012-01-13 22:53:37.061034	2012-01-14 05:55:26.162212
2115	221	16	10	221	1589	17	2012-01-13 22:55:38.824412	\N
2089	0	8	9	6178	2513	5	2012-01-13 22:50:20.889222	2012-01-13 22:50:20.889222
2117	0	2	17	2577	4848	11	2012-01-13 22:55:54.984886	2012-01-14 01:55:55.788596
2092	0	17	18	5753	161	4	2012-01-13 22:51:04.479666	2012-01-13 22:51:04.479666
2164	0	15	7	9086	9431	19	2012-01-13 23:06:01.371056	2012-01-14 02:02:19.658061
2082	0	17	6	5771	1829	20	2012-01-13 22:48:31.631734	2012-01-13 22:51:34.768367
2094	0	6	12	2542	4825	14	2012-01-13 22:51:34.768367	2012-01-13 22:51:34.768367
2132	0	10	11	4978	4194	13	2012-01-13 22:58:55.107336	2012-01-14 01:20:13.464249
2109	0	20	13	6966	5320	16	2012-01-13 22:54:39.344883	2012-01-13 23:24:21.771666
2153	0	16	10	8380	2961	20	2012-01-13 23:03:26.329626	2012-01-13 23:47:49.769043
2171	0	1	11	3552	5076	5	2012-01-13 23:07:22.203711	2012-01-14 00:27:32.795919
2101	8	6	17	8	4387	11	2012-01-13 22:53:08.203732	\N
2102	569	10	1	569	9268	18	2012-01-13 22:53:13.460943	\N
2116	0	11	17	3774	7839	16	2012-01-13 22:55:45.165347	2012-01-14 01:52:38.874447
2103	0	6	2	4391	3807	9	2012-01-13 22:53:21.594722	2012-01-13 22:53:21.594722
2104	145	11	18	145	9598	6	2012-01-13 22:53:26.940262	\N
2093	0	15	11	7852	6240	6	2012-01-13 22:51:09.643044	2012-01-13 22:53:51.983339
2106	0	11	15	7332	490	14	2012-01-13 22:53:51.983339	2012-01-13 22:53:51.983339
2118	0	11	19	6236	5863	6	2012-01-13 22:55:59.852773	2012-01-14 01:08:37.826355
2162	0	8	14	4085	1697	14	2012-01-13 23:05:18.840765	2012-01-13 23:51:17.220713
2136	4653	12	2	4653	7364	6	2012-01-13 23:00:04.085378	\N
2091	0	12	5	4647	4793	18	2012-01-13 22:50:50.53451	2012-01-13 22:55:02.050562
2110	0	20	3	2530	7312	6	2012-01-13 22:54:47.811513	2012-01-13 22:55:02.050562
2111	0	11	12	8335	8548	10	2012-01-13 22:55:02.050562	2012-01-13 22:55:02.050562
2148	1173	10	4	1173	5689	8	2012-01-13 23:02:16.431421	\N
2090	0	15	20	8997	7877	14	2012-01-13 22:50:25.71987	2012-01-13 22:57:47.99853
2124	0	6	15	511	166	19	2012-01-13 22:57:47.99853	2012-01-13 22:57:47.99853
2125	481	5	13	481	2228	4	2012-01-13 22:57:53.470697	\N
2126	579	12	7	579	8019	17	2012-01-13 22:57:58.05438	\N
2137	0	5	3	5962	347	9	2012-01-13 23:00:18.37957	2012-01-13 23:00:18.37957
2128	6405	3	7	6405	5664	7	2012-01-13 22:58:13.489358	\N
2121	0	10	3	5287	6579	19	2012-01-13 22:57:07.53215	2012-01-13 22:58:29.670371
2129	0	14	8	2601	983	3	2012-01-13 22:58:29.670371	2012-01-13 22:58:29.670371
2130	2913	4	6	2913	3749	14	2012-01-13 22:58:34.878021	\N
2138	1658	11	4	1658	4847	2	2012-01-13 23:00:23.290027	\N
2177	0	12	4	3333	3846	10	2012-01-13 23:09:22.829591	2012-01-14 01:34:56.589519
2133	447	19	14	447	1205	4	2012-01-13 22:59:09.29923	\N
2139	5184	15	14	5184	9533	12	2012-01-13 23:00:39.189288	\N
2114	0	11	3	1413	5341	5	2012-01-13 22:55:33.914754	2012-01-14 05:38:25.805394
2141	1373	3	11	1373	3663	14	2012-01-13 23:01:22.826355	\N
2149	1708	11	2	1708	2825	9	2012-01-13 23:02:26.120031	\N
2150	1984	8	3	1984	9175	2	2012-01-13 23:02:36.380675	\N
2112	0	13	2	2563	3819	16	2012-01-13 22:55:11.766566	2012-01-13 23:58:47.083443
2135	0	15	9	7432	9323	14	2012-01-13 22:59:30.925089	2012-01-13 23:01:46.298052
2144	0	7	10	6385	366	11	2012-01-13 23:01:46.298052	2012-01-13 23:01:46.298052
2170	0	14	9	1502	980	14	2012-01-13 23:07:16.537285	2012-01-13 23:07:16.537285
2098	0	17	4	5401	8617	7	2012-01-13 22:52:32.361397	2012-01-13 23:17:53.58731
2147	0	14	6	7101	1450	18	2012-01-13 23:02:11.380349	2012-01-13 23:02:11.380349
2146	0	8	19	9560	6637	9	2012-01-13 23:01:56.318292	2012-01-13 23:16:57.714412
2151	0	4	9	3728	9581	10	2012-01-13 23:02:51.502364	2012-01-13 23:51:30.316819
2154	1185	4	2	1185	1047	4	2012-01-13 23:03:39.68284	\N
2157	1980	15	20	1980	4629	7	2012-01-13 23:04:29.021795	\N
2158	5709	2	19	5709	8300	14	2012-01-13 23:04:34.258444	\N
2159	3214	9	5	3214	9271	20	2012-01-13 23:04:49.485074	\N
2161	1680	17	5	1680	9833	8	2012-01-13 23:05:04.267227	\N
2100	0	5	11	2326	3998	5	2012-01-13 22:53:03.605516	2012-01-14 00:24:03.331502
2113	0	9	17	4675	9690	3	2012-01-13 22:55:16.734535	2012-01-14 02:07:38.201821
2174	0	5	19	6051	1738	9	2012-01-13 23:08:29.863735	2012-01-13 23:14:37.785046
2120	0	13	19	6317	8493	2	2012-01-13 22:56:52.150844	2012-01-14 01:37:13.30649
2167	645	7	14	645	3646	8	2012-01-13 23:07:00.15751	\N
2160	0	6	19	7371	6429	18	2012-01-13 23:04:58.723105	2012-01-13 23:07:11.501389
2145	0	9	3	5405	2671	2	2012-01-13 23:01:51.735694	2012-01-13 23:07:05.371689
2168	0	14	10	3732	2023	11	2012-01-13 23:07:05.371689	2012-01-13 23:07:05.371689
2122	0	19	18	5262	5594	7	2012-01-13 22:57:21.622704	2012-01-13 23:07:11.501389
2169	0	18	14	4926	733	13	2012-01-13 23:07:11.501389	2012-01-13 23:07:11.501389
2172	3665	16	14	3665	8120	19	2012-01-13 23:07:37.900413	\N
2173	2021	10	18	2021	9900	11	2012-01-13 23:07:47.97185	\N
2163	0	9	1	9681	6534	6	2012-01-13 23:05:29.177518	2012-01-13 23:15:04.637681
2085	0	15	1	1150	2883	20	2012-01-13 22:49:07.687893	2012-01-13 23:17:53.58731
2086	0	9	4	2090	1304	18	2012-01-13 22:49:21.433782	2012-01-13 23:09:34.398047
2178	0	13	9	1578	3895	5	2012-01-13 23:09:34.398047	2012-01-13 23:09:34.398047
2180	2353	3	17	2353	9884	2	2012-01-13 23:09:51.161808	\N
2210	0	19	10	6177	8396	6	2012-01-13 23:16:57.714412	2012-01-13 23:16:57.714412
2182	0	17	9	6636	7083	17	2012-01-13 23:10:21.753202	2012-01-13 23:10:21.753202
2242	0	2	17	8916	6900	18	2012-01-13 23:24:27.518388	2012-01-13 23:46:21.477221
2211	582	16	17	582	5186	20	2012-01-13 23:17:09.63935	\N
2185	0	19	11	7311	6135	20	2012-01-13 23:11:09.084343	2012-01-13 23:11:09.084343
2186	836	2	19	836	1055	1	2012-01-13 23:11:14.991235	\N
2187	4298	16	13	4298	7521	14	2012-01-13 23:11:20.138478	\N
2271	0	14	5	311	1401	19	2012-01-13 23:32:50.266621	2012-01-14 00:38:20.397488
2264	0	3	6	3473	935	7	2012-01-13 23:30:51.341697	2012-01-14 01:16:01.123253
2179	0	5	17	6295	5940	19	2012-01-13 23:09:46.072787	2012-01-13 23:12:12.466297
631	0	17	13	4944	5197	5	2012-01-13 20:27:19.610568	2012-01-13 23:12:12.466297
2184	0	13	18	8620	6967	7	2012-01-13 23:10:43.683098	2012-01-13 23:12:12.466297
2190	0	18	5	5059	3170	16	2012-01-13 23:12:12.466297	2012-01-13 23:12:12.466297
2191	7770	18	7	7770	9658	14	2012-01-13 23:12:17.824331	\N
2192	1084	10	7	1084	6240	16	2012-01-13 23:12:38.94013	\N
2193	1965	9	11	1965	2050	12	2012-01-13 23:12:59.315714	\N
2212	0	19	6	7919	9991	11	2012-01-13 23:17:16.572697	2012-01-14 01:01:20.759551
2195	4088	19	14	4088	9780	16	2012-01-13 23:13:18.929063	\N
2197	7689	3	11	7689	7138	12	2012-01-13 23:13:46.817856	\N
2198	3470	1	19	3470	6259	5	2012-01-13 23:14:17.044782	\N
2199	1826	10	8	1826	9324	16	2012-01-13 23:14:28.12461	\N
2275	0	1	6	4176	2632	17	2012-01-13 23:34:04.605962	2012-01-14 00:09:53.257522
985	0	12	20	4257	6845	14	2012-01-13 20:35:12.323979	2012-01-13 23:14:37.785046
2201	1293	20	14	1293	8249	17	2012-01-13 23:14:55.351989	\N
2207	0	4	15	3493	1593	4	2012-01-13 23:16:08.501706	2012-01-13 23:17:53.58731
2200	0	6	12	6796	8757	11	2012-01-13 23:14:37.785046	2012-01-13 23:15:04.637681
2188	0	18	1	7246	6226	5	2012-01-13 23:11:30.666849	2012-01-13 23:15:04.637681
2235	0	19	4	4188	5109	10	2012-01-13 23:22:57.08068	2012-01-13 23:46:21.477221
2203	6114	3	19	6114	3821	1	2012-01-13 23:15:21.727778	\N
2204	892	16	2	892	1611	16	2012-01-13 23:15:45.733502	\N
2205	67	7	15	67	6720	2	2012-01-13 23:15:52.625281	\N
2214	0	1	17	3374	879	5	2012-01-13 23:17:53.58731	2012-01-13 23:17:53.58731
2239	0	1	7	5181	6921	9	2012-01-13 23:23:48.003788	2012-01-14 02:10:27.483146
2208	8264	9	6	8264	7745	6	2012-01-13 23:16:14.028528	\N
2209	1526	12	15	1526	7067	2	2012-01-13 23:16:45.392659	\N
2189	0	9	15	8325	6035	19	2012-01-13 23:11:52.169747	2012-01-14 00:28:51.486492
2216	1055	16	1	1055	4625	2	2012-01-13 23:18:26.72595	\N
2217	852	10	12	852	8346	5	2012-01-13 23:18:33.608775	\N
2183	0	7	2	7208	5522	3	2012-01-13 23:10:27.5679	2012-01-13 23:18:48.025037
2218	0	18	7	5666	449	10	2012-01-13 23:18:48.025037	2012-01-13 23:18:48.025037
2219	0	11	7	9947	2613	13	2012-01-13 23:18:53.165934	2012-01-13 23:18:53.165934
2244	0	16	10	4504	1055	10	2012-01-13 23:25:18.037122	2012-01-14 02:24:46.276028
2240	963	4	7	963	4126	13	2012-01-13 23:24:04.584474	\N
2255	0	9	18	4715	1723	12	2012-01-13 23:28:01.755571	2012-01-13 23:51:30.316819
2224	0	2	14	9979	4252	20	2012-01-13 23:20:10.696424	2012-01-13 23:26:35.982057
2220	0	17	18	7571	3155	7	2012-01-13 23:18:58.48931	2012-01-13 23:20:58.114033
2226	0	18	9	3701	5800	18	2012-01-13 23:20:58.114033	2012-01-13 23:20:58.114033
2241	0	13	20	8299	1471	7	2012-01-13 23:24:21.771666	2012-01-13 23:24:21.771666
2231	5397	16	13	5397	4451	18	2012-01-13 23:22:07.97587	\N
2232	7165	4	2	7165	7639	1	2012-01-13 23:22:14.864629	\N
2233	1197	3	16	1197	9056	15	2012-01-13 23:22:31.741921	\N
2260	0	6	4	4471	7004	19	2012-01-13 23:29:48.276224	2012-01-13 23:48:32.643527
2236	2760	3	11	2760	1457	2	2012-01-13 23:23:14.342232	\N
2237	2241	17	11	2241	7333	7	2012-01-13 23:23:19.072162	\N
2225	0	12	11	9026	8853	17	2012-01-13 23:20:25.981421	2012-01-13 23:50:25.468008
2243	3720	1	7	3720	6859	11	2012-01-13 23:24:55.338308	\N
2245	4944	12	7	4944	9216	16	2012-01-13 23:25:26.121234	\N
2246	705	4	5	705	2204	3	2012-01-13 23:25:48.161303	\N
2250	0	14	2	1517	2149	15	2012-01-13 23:26:35.982057	2012-01-13 23:26:35.982057
2251	1071	16	13	1071	9943	10	2012-01-13 23:26:42.127536	\N
2254	1399	5	14	1399	2851	7	2012-01-13 23:27:56.628111	\N
2274	0	1	19	9743	3899	10	2012-01-13 23:33:52.761264	2012-01-14 00:00:47.854862
2253	2316	10	2	2316	4693	16	2012-01-13 23:27:40.591252	\N
2202	0	1	15	6345	2805	3	2012-01-13 23:15:04.637681	2012-01-13 23:29:19.645779
2213	0	6	2	1890	3473	4	2012-01-13 23:17:33.386898	2012-01-14 00:08:51.424643
2257	0	15	6	5387	4076	16	2012-01-13 23:29:08.437975	2012-01-13 23:29:19.645779
2215	0	1	2	8782	9409	9	2012-01-13 23:17:59.090134	2012-01-14 00:25:29.78719
2238	0	15	9	494	5604	8	2012-01-13 23:23:36.598812	2012-01-14 01:52:22.572226
2267	106	5	16	106	2061	3	2012-01-13 23:31:52.537981	\N
2268	2323	3	18	2323	1907	5	2012-01-13 23:31:58.550117	\N
2269	2385	15	12	2385	9295	20	2012-01-13 23:32:14.41579	\N
2194	0	5	14	5558	4592	12	2012-01-13 23:13:04.142989	2012-01-14 00:43:35.780828
2273	1154	15	6	1154	2441	14	2012-01-13 23:33:46.92471	\N
2258	0	6	14	4956	2079	3	2012-01-13 23:29:19.645779	2012-01-14 00:09:53.257522
2347	0	20	11	5925	6295	14	2012-01-13 23:55:55.152637	2012-01-14 00:30:24.862132
2281	0	8	7	4982	8536	8	2012-01-13 23:35:11.322215	2012-01-14 00:51:03.396454
2311	913	12	17	913	8921	1	2012-01-13 23:46:41.663922	\N
2279	220	2	1	220	5008	7	2012-01-13 23:34:59.344644	\N
2342	0	3	19	9753	2809	13	2012-01-13 23:53:50.435348	2012-01-14 00:05:48.726932
2359	0	6	14	9983	7298	3	2012-01-13 23:58:53.869838	2012-01-14 00:51:40.260294
2356	0	3	12	5019	5434	2	2012-01-13 23:57:37.077953	2012-01-14 03:04:19.430709
2312	0	13	9	9471	8534	13	2012-01-13 23:46:59.58311	2012-01-13 23:46:59.58311
2276	0	4	18	1696	3857	6	2012-01-13 23:34:28.47861	2012-01-14 00:30:04.946206
2285	2301	8	5	2301	7728	16	2012-01-13 23:35:56.494305	\N
2303	0	10	4	3363	4622	11	2012-01-13 23:42:16.109411	2012-01-14 01:36:39.169331
2287	220	4	16	220	6367	11	2012-01-13 23:36:30.110553	\N
2288	2000	8	4	2000	8240	11	2012-01-13 23:36:37.29211	\N
2365	0	2	13	5428	6549	16	2012-01-14 00:00:28.54401	2012-01-14 00:05:08.844092
2277	0	17	5	4030	5425	20	2012-01-13 23:34:41.150758	2012-01-14 00:45:23.928571
2291	9167	16	4	9167	7216	2	2012-01-13 23:37:53.91398	\N
2320	0	1	20	1839	2438	12	2012-01-13 23:48:38.290222	2012-01-14 00:21:41.953034
2227	0	6	7	6691	4559	18	2012-01-13 23:21:03.692046	2012-01-13 23:39:06.445425
2259	0	15	17	9500	5670	3	2012-01-13 23:29:31.664011	2012-01-13 23:39:06.445425
2296	7404	16	8	7404	3586	8	2012-01-13 23:40:19.555584	\N
2297	366	13	4	366	1778	11	2012-01-13 23:41:05.641015	\N
2298	1848	4	11	1848	5071	7	2012-01-13 23:41:12.396	\N
2300	52	5	8	52	6731	3	2012-01-13 23:41:38.280353	\N
2301	269	13	17	269	9489	12	2012-01-13 23:41:44.447217	\N
2363	0	15	8	3362	6015	1	2012-01-14 00:00:15.476873	2012-01-14 05:26:57.58774
2334	0	9	4	1749	1639	11	2012-01-13 23:51:49.238531	2012-01-14 01:44:20.863363
2360	0	6	16	265	5058	2	2012-01-13 23:59:20.641846	2012-01-14 04:00:27.06107
2305	165	8	13	165	487	11	2012-01-13 23:44:47.535056	\N
2306	1287	20	5	1287	6036	13	2012-01-13 23:44:53.370481	\N
2308	6291	10	14	6291	8521	4	2012-01-13 23:45:34.962192	\N
2310	0	2	16	887	5844	10	2012-01-13 23:46:27.748285	2012-01-13 23:47:49.769043
2309	0	18	2	1540	1746	7	2012-01-13 23:46:21.477221	2012-01-13 23:46:21.477221
2293	0	10	6	2359	506	11	2012-01-13 23:39:06.445425	2012-01-13 23:47:49.769043
2315	0	7	11	527	179	6	2012-01-13 23:47:49.769043	2012-01-13 23:47:49.769043
2332	0	7	8	4218	3036	12	2012-01-13 23:51:17.220713	2012-01-13 23:51:17.220713
2317	2574	11	12	2574	8432	9	2012-01-13 23:48:08.53411	\N
2292	0	8	5	6213	7380	3	2012-01-13 23:38:42.024533	2012-01-14 00:12:15.102401
2319	0	12	17	2513	319	2	2012-01-13 23:48:32.643527	2012-01-13 23:48:32.643527
2325	0	11	15	8059	9716	14	2012-01-13 23:49:45.333074	2012-01-14 00:24:03.331502
2321	1124	9	4	1124	4971	18	2012-01-13 23:48:50.124554	\N
2343	0	16	13	8966	1895	8	2012-01-13 23:54:13.577377	2012-01-14 06:41:13.966456
2362	0	5	1	7103	8089	8	2012-01-13 23:59:49.0538	2012-01-14 00:09:53.257522
2313	0	18	11	3739	5222	9	2012-01-13 23:47:06.402068	2012-01-14 00:03:02.345364
2352	0	17	1	8989	9987	12	2012-01-13 23:56:43.775553	2012-01-14 00:25:10.490133
2327	0	6	2	2502	5833	20	2012-01-13 23:50:18.753001	2012-01-14 00:52:28.24555
2286	0	10	12	4279	5691	8	2012-01-13 23:36:07.66371	2012-01-14 01:34:56.589519
2318	0	12	15	5675	2572	8	2012-01-13 23:48:14.624217	2012-01-13 23:51:30.316819
2328	0	11	12	8781	1444	2	2012-01-13 23:50:25.468008	2012-01-13 23:50:25.468008
2333	0	18	12	3250	3280	8	2012-01-13 23:51:30.316819	2012-01-13 23:51:30.316819
2341	0	5	10	3165	8952	4	2012-01-13 23:53:37.809156	2012-01-14 02:17:01.862906
2335	3162	2	13	3162	9494	8	2012-01-13 23:52:12.599803	\N
2338	261	1	11	261	6043	15	2012-01-13 23:52:53.88844	\N
2339	2545	16	1	2545	8711	14	2012-01-13 23:53:00.334695	\N
2290	0	17	4	3685	8034	14	2012-01-13 23:37:33.09461	2012-01-14 00:34:24.465528
2304	0	16	1	7252	3307	13	2012-01-13 23:43:09.321135	2012-01-14 03:27:50.232295
2323	0	6	19	6228	7227	12	2012-01-13 23:49:18.568387	2012-01-14 00:07:28.129819
2280	0	13	15	2806	4409	16	2012-01-13 23:35:05.102989	2012-01-14 00:05:08.844092
2345	0	11	12	4923	6069	11	2012-01-13 23:55:22.368161	2012-01-14 00:03:02.345364
2330	0	10	20	538	724	11	2012-01-13 23:50:51.550134	2012-01-14 02:17:01.862906
2348	3357	9	8	3357	8107	17	2012-01-13 23:56:07.231836	\N
2349	539	12	5	539	8427	9	2012-01-13 23:56:24.242306	\N
2351	2952	4	17	2952	8655	14	2012-01-13 23:56:36.672889	\N
2355	0	3	18	4846	2807	20	2012-01-13 23:57:25.467902	2012-01-14 00:27:32.795919
2353	428	6	15	428	3292	9	2012-01-13 23:57:11.704274	\N
2302	0	15	14	7088	2905	6	2012-01-13 23:41:57.439171	2012-01-14 04:25:04.656422
2295	0	1	17	5555	5325	16	2012-01-13 23:39:36.152319	2012-01-13 23:57:18.730333
2354	0	17	1	6663	4098	7	2012-01-13 23:57:18.730333	2012-01-13 23:57:18.730333
2284	0	4	20	1664	1833	13	2012-01-13 23:35:50.426594	2012-01-14 00:28:06.502198
2322	0	9	5	7373	6687	13	2012-01-13 23:48:55.654657	2012-01-14 05:43:40.588778
2326	0	6	10	2055	4825	16	2012-01-13 23:50:11.859755	2012-01-13 23:58:47.083443
2337	0	10	13	6639	2864	7	2012-01-13 23:52:42.471613	2012-01-13 23:58:47.083443
2358	0	2	19	1175	263	3	2012-01-13 23:58:47.083443	2012-01-13 23:58:47.083443
2344	0	12	5	9946	5594	4	2012-01-13 23:54:51.410586	2012-01-14 00:10:33.652874
2340	0	19	9	1206	7431	12	2012-01-13 23:53:31.004294	2012-01-14 00:28:06.502198
2364	0	5	10	5710	129	13	2012-01-14 00:00:22.037065	2012-01-14 00:00:22.037065
2324	0	7	8	6475	9056	1	2012-01-13 23:49:32.183577	2012-01-14 00:00:47.854862
2350	0	18	8	4947	5345	8	2012-01-13 23:56:30.53248	2012-01-14 00:00:47.854862
2420	1123	14	11	1123	7922	14	2012-01-14 00:18:10.76409	\N
2367	2170	5	7	2170	3992	1	2012-01-14 00:01:08.674276	\N
2406	0	8	4	5076	4758	15	2012-01-14 00:13:22.514925	2012-01-14 00:30:04.946206
2369	2425	16	13	2425	8328	13	2012-01-14 00:01:49.657592	\N
2371	2895	12	5	2895	6825	7	2012-01-14 00:02:56.277487	\N
2421	3986	16	6	3986	2572	10	2012-01-14 00:18:18.074258	\N
2374	1711	18	19	1711	7369	5	2012-01-14 00:04:36.484122	\N
2400	0	15	8	2716	479	14	2012-01-14 00:12:15.102401	2012-01-14 00:12:15.102401
2376	0	5	2	289	74	16	2012-01-14 00:05:08.844092	2012-01-14 00:05:08.844092
2401	501	2	18	501	5652	7	2012-01-14 00:12:21.490224	\N
2402	535	11	20	535	8691	2	2012-01-14 00:12:28.029498	\N
2372	0	12	3	7550	9537	17	2012-01-14 00:03:02.345364	2012-01-14 00:05:48.726932
2379	0	19	12	7920	896	8	2012-01-14 00:05:48.726932	2012-01-14 00:05:48.726932
2380	8202	16	10	8202	8019	20	2012-01-14 00:05:55.767048	\N
2445	0	4	19	7501	6378	4	2012-01-14 00:25:36.794912	2012-01-14 00:30:48.691713
2403	5711	3	1	5711	6916	18	2012-01-14 00:12:34.390643	\N
2383	1908	4	6	1908	3117	9	2012-01-14 00:07:21.443249	\N
2441	0	5	13	1538	4681	13	2012-01-14 00:24:57.012022	2012-01-14 00:50:29.584942
2366	0	8	9	7155	5553	20	2012-01-14 00:00:47.854862	2012-01-14 00:07:28.129819
2384	0	19	8	5778	6171	9	2012-01-14 00:07:28.129819	2012-01-14 00:07:28.129819
2385	3317	3	9	3317	9260	8	2012-01-14 00:07:48.700396	\N
2419	0	9	10	9716	8616	6	2012-01-14 00:17:32.791629	2012-01-14 00:22:34.489271
2387	0	2	13	7782	1146	7	2012-01-14 00:08:51.424643	2012-01-14 00:08:51.424643
2388	123	14	20	123	9415	17	2012-01-14 00:08:57.855634	\N
2389	6805	16	11	6805	2926	6	2012-01-14 00:09:10.770455	\N
2390	0	14	5	2068	2601	1	2012-01-14 00:09:53.257522	2012-01-14 00:09:53.257522
2432	0	3	1	1232	764	11	2012-01-14 00:22:15.182279	2012-01-14 01:38:24.804832
2434	0	10	9	7253	944	14	2012-01-14 00:22:34.489271	2012-01-14 00:22:34.489271
2404	0	8	15	6699	8161	17	2012-01-14 00:12:57.295155	2012-01-14 00:48:14.344588
2453	0	8	13	5956	7192	10	2012-01-14 00:27:39.630366	2012-01-14 00:32:33.571775
2394	0	5	12	9085	8222	17	2012-01-14 00:10:33.652874	2012-01-14 00:10:33.652874
2395	146	9	14	146	1511	20	2012-01-14 00:10:46.335054	\N
2436	0	2	7	9044	5683	19	2012-01-14 00:22:53.483562	2012-01-14 00:52:28.24555
2407	0	6	10	1221	2618	11	2012-01-14 00:13:42.192461	2012-01-14 00:13:42.192461
2416	0	11	13	6230	8277	7	2012-01-14 00:16:33.683504	2012-01-14 05:58:13.48236
2409	427	19	2	427	3288	16	2012-01-14 00:14:18.739811	\N
2391	0	11	2	7840	8750	17	2012-01-14 00:10:00.112526	2012-01-14 01:33:10.456807
2392	0	6	19	5897	5576	1	2012-01-14 00:10:19.590053	2012-01-14 00:14:39.016369
2411	0	19	20	4865	1000	19	2012-01-14 00:14:39.016369	2012-01-14 00:14:39.016369
2412	1208	16	10	1208	8947	11	2012-01-14 00:14:45.537084	\N
2425	654	11	13	654	894	15	2012-01-14 00:19:57.858181	\N
2408	0	4	7	7768	5551	20	2012-01-14 00:13:49.419887	2012-01-14 05:51:12.501509
2415	385	10	13	385	2792	8	2012-01-14 00:16:27.558311	\N
2418	2069	16	1	2069	1484	2	2012-01-14 00:17:15.405075	\N
2426	8319	3	19	8319	7951	13	2012-01-14 00:20:04.744755	\N
2427	2288	10	17	2288	8502	10	2012-01-14 00:20:41.823149	\N
2428	5587	8	14	5587	4304	10	2012-01-14 00:21:00.987404	\N
2429	4098	15	12	4098	8141	17	2012-01-14 00:21:20.604518	\N
2435	2426	9	6	2426	3233	10	2012-01-14 00:22:41.021026	\N
2422	0	12	1	9425	6751	9	2012-01-14 00:18:41.102084	2012-01-14 00:21:41.953034
2405	0	20	15	3389	2735	20	2012-01-14 00:13:16.277989	2012-01-14 00:21:41.953034
2430	0	15	12	3591	4315	2	2012-01-14 00:21:41.953034	2012-01-14 00:21:41.953034
2397	0	13	6	7455	5365	3	2012-01-14 00:11:29.246819	2012-01-14 00:51:40.260294
2447	0	3	16	1065	4684	5	2012-01-14 00:25:57.32585	2012-01-14 02:24:46.276028
2450	0	12	3	3277	6766	18	2012-01-14 00:26:57.732772	2012-01-14 00:57:33.797198
2423	0	15	6	8825	7185	16	2012-01-14 00:19:07.287963	2012-01-14 01:24:24.177833
2442	0	1	17	2759	528	19	2012-01-14 00:25:10.490133	2012-01-14 00:25:10.490133
2455	0	3	5	9265	7002	12	2012-01-14 00:28:27.152867	2012-01-14 03:14:56.36778
2438	0	15	5	4111	1036	6	2012-01-14 00:24:03.331502	2012-01-14 00:24:03.331502
2440	162	14	17	162	7325	9	2012-01-14 00:24:49.71485	\N
2431	0	18	2	5417	6161	14	2012-01-14 00:21:55.764163	2012-01-14 00:29:12.052234
2444	0	6	1	3284	2023	1	2012-01-14 00:25:29.78719	2012-01-14 00:25:29.78719
2446	0	18	12	8172	2657	10	2012-01-14 00:25:50.943987	2012-01-14 00:25:50.943987
2449	6248	8	19	6248	9678	5	2012-01-14 00:26:44.600948	\N
2381	0	16	10	6908	1205	3	2012-01-14 00:06:42.699811	2012-01-14 00:29:04.225053
2451	0	19	1	9619	9644	4	2012-01-14 00:27:04.43242	2012-01-14 00:27:32.795919
2393	0	11	3	3590	7417	16	2012-01-14 00:10:26.486325	2012-01-14 00:27:32.795919
2452	0	18	19	7300	84	14	2012-01-14 00:27:32.795919	2012-01-14 00:27:32.795919
2414	0	13	19	9782	6879	4	2012-01-14 00:16:06.985656	2012-01-14 00:28:06.502198
2439	0	9	8	8338	2869	5	2012-01-14 00:24:10.415734	2012-01-14 00:28:06.502198
2454	0	8	4	6211	4033	19	2012-01-14 00:28:06.502198	2012-01-14 00:28:06.502198
2448	0	15	20	8790	6440	14	2012-01-14 00:26:10.131801	2012-01-14 00:28:51.486492
2456	0	20	9	7998	8793	1	2012-01-14 00:28:51.486492	2012-01-14 00:28:51.486492
2457	0	13	16	3323	2102	16	2012-01-14 00:29:04.225053	2012-01-14 00:29:04.225053
2368	0	2	10	2286	8803	18	2012-01-14 00:01:29.892977	2012-01-14 00:29:12.052234
2458	0	10	18	4935	721	8	2012-01-14 00:29:12.052234	2012-01-14 00:29:12.052234
2487	0	4	11	7586	8054	8	2012-01-14 00:36:29.79159	2012-01-14 01:45:59.058076
2491	0	1	14	614	102	8	2012-01-14 00:38:20.397488	2012-01-14 00:38:20.397488
2460	0	5	15	6862	3436	9	2012-01-14 00:29:36.943006	2012-01-14 00:29:36.943006
2498	0	16	5	8821	1993	11	2012-01-14 00:40:44.067272	2012-01-14 02:32:54.606524
2462	0	18	8	4400	250	4	2012-01-14 00:30:04.946206	2012-01-14 00:30:04.946206
2493	6686	16	12	6686	4401	5	2012-01-14 00:39:02.786023	\N
2464	0	12	20	9430	715	14	2012-01-14 00:30:24.862132	2012-01-14 00:30:24.862132
2461	0	19	7	7478	2707	18	2012-01-14 00:29:43.241512	2012-01-14 00:30:48.691713
2467	0	15	4	4868	3606	14	2012-01-14 00:30:48.691713	2012-01-14 00:30:48.691713
2468	3993	9	10	3993	9731	1	2012-01-14 00:31:15.662225	\N
2518	0	15	12	4420	3397	3	2012-01-14 00:47:29.651048	2012-01-14 00:48:14.344588
2510	0	6	10	6817	4197	6	2012-01-14 00:44:49.071519	2012-01-14 00:44:49.071519
2465	0	12	1	3459	1342	19	2012-01-14 00:30:30.788615	2012-01-14 00:39:38.529843
2472	259	4	8	259	1151	20	2012-01-14 00:32:26.74227	\N
2463	0	13	11	6213	9326	16	2012-01-14 00:30:11.031007	2012-01-14 00:32:33.571775
2473	0	11	8	6274	912	19	2012-01-14 00:32:33.571775	2012-01-14 00:32:33.571775
2474	3956	4	7	3956	8673	18	2012-01-14 00:32:40.088377	\N
2475	0	13	10	7542	6457	1	2012-01-14 00:33:09.289874	2012-01-14 00:33:09.289874
2553	1002	19	7	1002	6355	5	2012-01-14 00:57:19.405539	\N
2477	0	5	1	3197	429	12	2012-01-14 00:33:47.127908	2012-01-14 00:33:47.127908
2520	0	2	8	3496	3630	16	2012-01-14 00:48:14.344588	2012-01-14 00:48:14.344588
2479	1801	16	10	1801	2764	8	2012-01-14 00:34:07.381008	\N
2480	0	4	5	8023	131	20	2012-01-14 00:34:24.465528	2012-01-14 00:34:24.465528
2539	0	1	14	7088	2334	11	2012-01-14 00:52:48.41986	2012-01-14 01:33:10.456807
2481	0	2	5	5707	5883	11	2012-01-14 00:34:31.395966	2012-01-14 01:32:44.355986
2535	0	7	1	589	8028	11	2012-01-14 00:52:01.198632	2012-01-14 03:32:02.135701
2556	0	17	19	5737	6126	9	2012-01-14 00:57:47.041985	2012-01-14 01:31:32.005205
2485	4931	18	7	4931	4456	1	2012-01-14 00:35:56.289735	\N
2538	0	15	11	5442	1577	15	2012-01-14 00:52:35.606093	2012-01-14 01:08:37.826355
2558	0	20	5	8094	5794	15	2012-01-14 00:59:55.535073	2012-01-14 01:50:43.605486
2506	0	13	19	2622	3542	19	2012-01-14 00:43:13.238447	2012-01-14 03:54:32.641246
2555	0	5	12	2372	1778	20	2012-01-14 00:57:33.797198	2012-01-14 00:57:33.797198
2490	4451	10	17	4451	7109	10	2012-01-14 00:37:55.825263	\N
2469	0	5	1	8977	6961	6	2012-01-14 00:31:32.95373	2012-01-14 00:38:20.397488
2497	456	17	4	456	9094	5	2012-01-14 00:40:37.169865	\N
2483	0	8	14	8115	4626	19	2012-01-14 00:34:51.036935	2012-01-14 02:45:43.095521
2499	603	2	3	603	5729	11	2012-01-14 00:41:21.277992	\N
2500	4634	10	14	4634	4428	2	2012-01-14 00:41:28.476609	\N
2543	0	6	11	1569	1716	4	2012-01-14 00:54:26.635109	2012-01-14 01:14:49.41845
2502	8550	3	14	8550	9505	11	2012-01-14 00:41:53.749122	\N
2466	0	9	12	1355	784	5	2012-01-14 00:30:42.797406	2012-01-14 06:21:27.088263
2522	0	5	7	4675	7893	7	2012-01-14 00:48:56.904847	2012-01-14 04:43:02.787694
2507	818	13	7	818	5744	1	2012-01-14 00:43:20.334679	\N
2508	0	14	5	1302	1306	12	2012-01-14 00:43:35.780828	2012-01-14 00:43:35.780828
2545	0	13	14	5913	3552	10	2012-01-14 00:54:56.973479	2012-01-14 01:07:31.623446
2513	0	5	17	9341	945	5	2012-01-14 00:45:23.928571	2012-01-14 00:45:23.928571
2514	2597	9	2	2597	8884	1	2012-01-14 00:45:30.36146	\N
2509	0	3	20	9645	9224	2	2012-01-14 00:43:43.449776	2012-01-14 02:22:16.428414
2516	5260	16	2	5260	3922	19	2012-01-14 00:45:49.756742	\N
2517	6580	16	6	6580	6410	18	2012-01-14 00:46:19.323257	\N
2488	0	10	7	9312	3394	5	2012-01-14 00:36:50.559207	2012-01-14 00:51:10.409785
2494	0	1	5	5904	3046	19	2012-01-14 00:39:38.529843	2012-01-14 00:50:29.584942
2527	0	13	1	2614	338	6	2012-01-14 00:50:29.584942	2012-01-14 00:50:29.584942
2531	0	7	10	5626	742	4	2012-01-14 00:51:10.409785	2012-01-14 00:51:10.409785
2525	2167	12	5	2167	6500	16	2012-01-14 00:49:55.115251	\N
2529	1073	5	17	1073	4412	8	2012-01-14 00:50:56.566467	\N
2482	0	7	19	9847	7229	15	2012-01-14 00:34:38.00099	2012-01-14 00:52:28.24555
2521	0	13	8	6943	6659	1	2012-01-14 00:48:21.043152	2012-01-14 00:51:03.396454
2530	0	7	13	3873	1627	4	2012-01-14 00:51:03.396454	2012-01-14 00:51:03.396454
2533	0	14	13	4052	3245	6	2012-01-14 00:51:40.260294	2012-01-14 00:51:40.260294
2537	0	17	6	7696	222	14	2012-01-14 00:52:28.24555	2012-01-14 00:52:28.24555
2501	0	18	12	6275	8721	17	2012-01-14 00:41:40.606712	2012-01-14 01:11:58.560515
2459	0	8	14	5150	1735	12	2012-01-14 00:29:18.24865	2012-01-14 01:38:57.593469
2496	0	8	11	5547	9109	7	2012-01-14 00:40:10.919497	2012-01-14 01:25:14.985818
2515	0	6	1	723	2256	4	2012-01-14 00:45:42.468	2012-01-14 02:10:02.503046
2547	1779	17	15	1779	7837	1	2012-01-14 00:55:24.727591	\N
2549	1064	18	4	1064	6525	12	2012-01-14 00:56:05.636229	\N
2551	6139	9	14	6139	4538	13	2012-01-14 00:56:33.787745	\N
2476	0	10	15	7823	8296	9	2012-01-14 00:33:16.366874	2012-01-14 00:57:12.4723
2552	0	15	10	3830	1885	20	2012-01-14 00:57:12.4723	2012-01-14 00:57:12.4723
2542	0	9	20	4889	5023	7	2012-01-14 00:53:55.259198	2012-01-14 00:57:26.652284
2489	0	20	18	9704	5639	6	2012-01-14 00:37:30.610775	2012-01-14 00:57:26.652284
2554	0	18	9	3652	373	17	2012-01-14 00:57:26.652284	2012-01-14 00:57:26.652284
2557	7777	16	19	7777	8645	13	2012-01-14 00:58:16.804426	\N
2536	0	8	5	9037	7508	4	2012-01-14 00:52:08.17225	2012-01-14 01:05:37.896472
2559	244	18	10	244	4683	4	2012-01-14 01:00:35.610288	\N
2560	692	10	20	692	8623	11	2012-01-14 01:00:49.23174	\N
2630	0	13	20	3248	6977	8	2012-01-14 01:23:40.189481	2012-01-14 01:50:43.605486
2614	0	4	17	6953	3113	16	2012-01-14 01:18:08.811631	2012-01-14 01:36:39.169331
2563	53	2	3	53	2147	15	2012-01-14 01:01:13.803201	\N
2564	0	6	19	9374	1969	4	2012-01-14 01:01:20.759551	2012-01-14 01:01:20.759551
2566	3595	16	2	3595	9831	14	2012-01-14 01:01:50.944579	\N
2640	0	15	12	6261	6270	3	2012-01-14 01:26:30.942513	2012-01-14 01:52:38.874447
2642	0	1	17	2783	4669	6	2012-01-14 01:27:14.398968	2012-01-14 01:37:13.30649
2569	1904	8	11	1904	5731	20	2012-01-14 01:04:33.805725	\N
2576	0	15	6	6038	1581	18	2012-01-14 01:06:19.345317	2012-01-14 01:11:58.560515
2570	0	2	9	5623	432	2	2012-01-14 01:04:54.082806	2012-01-14 01:04:54.082806
2634	0	9	10	9304	2125	12	2012-01-14 01:24:55.259715	2012-01-14 01:34:56.589519
2592	0	6	18	6722	5536	19	2012-01-14 01:11:58.560515	2012-01-14 01:11:58.560515
2573	0	5	8	6706	4364	2	2012-01-14 01:05:37.896472	2012-01-14 01:05:37.896472
2622	0	2	6	3559	3420	2	2012-01-14 01:21:01.762837	2012-01-14 06:50:45.629742
2612	0	5	11	9511	9747	12	2012-01-14 01:17:41.918062	2012-01-14 01:55:31.30782
2579	2742	8	15	2742	7334	17	2012-01-14 01:07:10.661522	\N
2486	0	14	18	1393	3914	19	2012-01-14 00:36:22.635449	2012-01-14 01:07:31.623446
2580	0	18	13	5050	2965	16	2012-01-14 01:07:31.623446	2012-01-14 01:07:31.623446
2575	0	9	11	3918	2839	7	2012-01-14 01:06:07.112295	2012-01-14 05:27:51.927097
2615	5740	16	2	5740	7197	12	2012-01-14 01:18:23.291855	\N
2583	0	19	10	4653	1528	5	2012-01-14 01:08:37.826355	2012-01-14 01:08:37.826355
2584	4618	2	11	4618	7834	14	2012-01-14 01:08:45.728722	\N
2585	2252	12	11	2252	4569	2	2012-01-14 01:08:52.320567	\N
2561	0	5	20	2290	4538	6	2012-01-14 01:00:55.401504	2012-01-14 01:50:27.783996
2597	0	13	3	3112	654	14	2012-01-14 01:13:48.830005	2012-01-14 01:13:48.830005
2595	0	18	6	5549	4143	5	2012-01-14 01:12:52.019619	2012-01-14 04:02:59.905667
2598	177	16	8	177	5327	19	2012-01-14 01:13:56.520809	\N
2590	5664	11	19	5664	6417	16	2012-01-14 01:11:29.75501	\N
2599	6025	18	14	6025	7008	2	2012-01-14 01:14:02.343176	\N
2600	428	9	19	428	3623	14	2012-01-14 01:14:36.630057	\N
2616	2014	18	6	2014	6887	16	2012-01-14 01:19:30.747327	\N
2601	0	17	5	2699	51	17	2012-01-14 01:14:49.41845	2012-01-14 01:14:49.41845
2602	37	19	2	37	8727	19	2012-01-14 01:14:56.649807	\N
2617	3139	8	4	3139	9942	9	2012-01-14 01:19:44.703664	\N
2586	0	5	13	5269	6706	4	2012-01-14 01:09:04.948982	2012-01-14 01:48:14.187474
2604	0	12	3	2858	3811	5	2012-01-14 01:15:16.944807	2012-01-14 01:16:01.123253
2606	0	6	12	7187	33	12	2012-01-14 01:16:01.123253	2012-01-14 01:16:01.123253
2607	1855	2	6	1855	1224	20	2012-01-14 01:16:08.990506	\N
2588	0	15	1	4064	6858	20	2012-01-14 01:10:16.907031	2012-01-14 03:34:12.660664
2641	0	20	10	2298	5149	8	2012-01-14 01:26:53.337279	2012-01-14 02:58:35.546794
2610	2123	15	5	2123	9367	15	2012-01-14 01:17:21.914906	\N
2636	0	4	14	6895	989	9	2012-01-14 01:25:22.037375	2012-01-14 01:34:56.589519
2650	0	8	4	3271	5786	8	2012-01-14 01:30:28.846506	2012-01-14 02:16:45.608146
2613	1597	12	15	1597	5686	10	2012-01-14 01:18:02.135843	\N
2619	0	11	10	1743	945	19	2012-01-14 01:20:13.464249	2012-01-14 01:20:13.464249
2620	6095	20	5	6095	7224	8	2012-01-14 01:20:21.302591	\N
2621	3066	3	6	3066	8632	7	2012-01-14 01:20:48.844012	\N
2571	0	4	14	4208	1981	13	2012-01-14 01:05:01.168444	2012-01-14 06:59:12.659348
2562	0	9	8	2785	1573	18	2012-01-14 01:01:01.940687	2012-01-14 01:35:05.145677
2639	186	9	11	186	3790	8	2012-01-14 01:26:24.482265	\N
2626	761	15	5	761	5060	10	2012-01-14 01:22:04.754636	\N
2596	0	13	8	7053	7094	20	2012-01-14 01:13:12.675637	2012-01-14 01:25:14.985818
2629	768	14	6	768	9533	17	2012-01-14 01:23:24.705657	\N
2567	0	2	1	4179	5043	7	2012-01-14 01:03:08.268349	2012-01-14 01:52:22.572226
2593	0	9	12	7178	2637	15	2012-01-14 01:12:13.834197	2012-01-14 01:52:46.781198
2635	0	18	13	3503	424	10	2012-01-14 01:25:14.985818	2012-01-14 01:25:14.985818
2594	0	7	15	6407	8818	16	2012-01-14 01:12:44.986244	2012-01-14 01:24:24.177833
2632	0	6	7	9622	1598	9	2012-01-14 01:24:24.177833	2012-01-14 01:24:24.177833
2609	0	12	14	8261	5731	16	2012-01-14 01:16:55.815207	2012-01-14 02:23:57.858081
2655	0	11	7	7657	2984	19	2012-01-14 01:31:54.88503	2012-01-14 01:41:04.810828
2637	1080	9	2	1080	5274	1	2012-01-14 01:25:44.043905	\N
2638	2303	2	13	2303	7351	11	2012-01-14 01:26:17.581092	\N
2618	0	8	12	5988	7680	14	2012-01-14 01:19:59.603691	2012-01-14 03:01:46.915235
2572	0	7	11	5049	8093	6	2012-01-14 01:05:16.13759	2012-01-14 01:41:04.810828
2643	5022	16	6	5022	3406	16	2012-01-14 01:27:29.43761	\N
2644	2796	12	18	2796	9507	10	2012-01-14 01:28:02.966343	\N
2646	1972	11	7	1972	4935	15	2012-01-14 01:28:47.638922	\N
2647	7968	3	13	7968	6023	10	2012-01-14 01:28:55.99425	\N
2649	5225	2	7	5225	7140	8	2012-01-14 01:29:51.3876	\N
2651	7133	16	13	7133	1662	19	2012-01-14 01:30:43.944511	\N
2652	737	13	2	737	8122	5	2012-01-14 01:31:24.130479	\N
2611	0	3	17	4042	2116	15	2012-01-14 01:17:35.891564	2012-01-14 01:31:32.005205
2653	0	19	3	1762	2044	8	2012-01-14 01:31:32.005205	2012-01-14 01:31:32.005205
2605	0	9	8	7136	8781	6	2012-01-14 01:15:23.772104	2012-01-14 01:46:06.56924
2631	0	20	17	3962	5188	11	2012-01-14 01:24:03.72889	2012-01-14 01:50:27.783996
2685	0	4	11	5530	5108	14	2012-01-14 01:44:20.863363	2012-01-14 01:44:20.863363
2657	0	5	2	7751	6899	11	2012-01-14 01:32:44.355986	2012-01-14 01:32:44.355986
2686	0	11	4	4791	14	8	2012-01-14 01:45:59.058076	2012-01-14 01:45:59.058076
2687	0	8	9	9012	365	1	2012-01-14 01:46:06.56924	2012-01-14 01:46:06.56924
2661	5492	2	11	5492	8139	11	2012-01-14 01:34:13.089859	\N
2662	0	14	16	1124	4182	12	2012-01-14 01:34:56.589519	2012-01-14 01:34:56.589519
2688	649	19	20	649	6420	17	2012-01-14 01:46:13.71485	\N
2663	0	8	9	6564	9930	12	2012-01-14 01:35:05.145677	2012-01-14 01:35:05.145677
2664	8526	3	11	8526	4531	18	2012-01-14 01:35:37.193496	\N
2665	0	17	10	4645	352	1	2012-01-14 01:36:39.169331	2012-01-14 01:36:39.169331
2666	5113	10	18	5113	6173	4	2012-01-14 01:36:46.928828	\N
2667	2959	3	14	2959	2225	3	2012-01-14 01:37:01.03774	\N
2658	0	2	1	6940	1498	14	2012-01-14 01:33:10.456807	2012-01-14 01:37:13.30649
2690	6435	16	6	6435	2188	12	2012-01-14 01:46:43.673923	\N
2691	2391	4	17	2391	8181	1	2012-01-14 01:47:09.192045	\N
2692	3019	10	11	3019	6096	5	2012-01-14 01:47:23.861341	\N
2669	0	4	19	7606	2769	17	2012-01-14 01:37:31.26764	2012-01-14 01:38:24.804832
2668	0	19	3	1720	2927	13	2012-01-14 01:37:13.30649	2012-01-14 01:38:24.804832
2672	0	1	20	4006	145	11	2012-01-14 01:38:24.804832	2012-01-14 01:38:24.804832
2673	3182	20	8	3182	8564	11	2012-01-14 01:38:44.33707	\N
2674	0	14	8	2396	3892	18	2012-01-14 01:38:57.593469	2012-01-14 01:38:57.593469
2694	0	17	4	2173	4403	20	2012-01-14 01:47:44.161634	2012-01-14 03:32:50.757337
2732	0	9	13	5958	2858	7	2012-01-14 01:58:46.966303	2012-01-14 03:38:52.023956
2677	2351	13	18	2351	7370	7	2012-01-14 01:40:06.250673	\N
2678	2781	3	7	2781	8453	15	2012-01-14 01:40:23.389597	\N
2679	0	6	11	4505	5957	15	2012-01-14 01:41:04.810828	2012-01-14 01:41:04.810828
2744	0	13	8	3042	7496	17	2012-01-14 02:03:51.342012	2012-01-14 04:14:14.265375
2680	0	17	11	4566	4014	2	2012-01-14 01:41:31.20757	2012-01-14 06:35:47.801919
2682	1888	10	15	1888	4434	2	2012-01-14 01:43:02.665504	\N
2709	2454	10	17	2454	4352	17	2012-01-14 01:51:19.787245	\N
2734	0	4	12	6852	6236	19	2012-01-14 02:00:01.264925	2012-01-14 02:22:33.140023
2683	0	11	9	7017	7558	7	2012-01-14 01:43:16.352399	2012-01-14 01:44:20.863363
2696	0	13	5	8653	3062	2	2012-01-14 01:48:14.187474	2012-01-14 01:48:14.187474
2740	513	10	4	513	3572	17	2012-01-14 02:03:14.709897	\N
2710	0	18	2	4220	7056	11	2012-01-14 01:51:26.819464	2012-01-14 02:17:18.816114
2699	17	2	12	17	7956	2	2012-01-14 01:48:53.148707	\N
2717	0	4	1	9828	6639	7	2012-01-14 01:52:54.270412	2012-01-14 02:58:52.667682
2700	0	13	3	1906	8943	5	2012-01-14 01:49:00.136402	2012-01-14 02:44:50.183751
2698	0	6	5	2031	2455	3	2012-01-14 01:48:36.968719	2012-01-14 02:17:01.862906
2719	7764	16	6	7764	3116	15	2012-01-14 01:53:58.309014	\N
2704	3079	20	13	3079	4964	17	2012-01-14 01:50:20.84835	\N
2695	0	18	5	7395	3050	20	2012-01-14 01:48:07.082465	2012-01-14 01:50:27.783996
2701	0	17	20	4027	6432	1	2012-01-14 01:49:08.321403	2012-01-14 02:30:50.737465
2706	0	5	13	3045	1316	17	2012-01-14 01:50:43.605486	2012-01-14 01:50:43.605486
2707	0	13	12	9454	7705	12	2012-01-14 01:50:50.988089	2012-01-14 01:50:50.988089
2712	1017	17	12	1017	3397	6	2012-01-14 01:52:14.792075	\N
2708	0	9	2	9754	761	5	2012-01-14 01:51:06.391831	2012-01-14 01:52:22.572226
2713	0	1	15	5417	3641	13	2012-01-14 01:52:22.572226	2012-01-14 01:52:22.572226
2714	113	1	5	113	4545	6	2012-01-14 01:52:30.713107	\N
2703	0	8	15	7166	6155	2	2012-01-14 01:49:58.206242	2012-01-14 01:52:38.874447
2715	0	17	8	2852	1247	11	2012-01-14 01:52:38.874447	2012-01-14 01:52:38.874447
2716	0	12	9	8468	1690	11	2012-01-14 01:52:46.781198	2012-01-14 01:52:46.781198
2722	0	4	5	4212	1770	1	2012-01-14 01:55:23.524131	2012-01-14 03:10:05.333719
2731	3507	11	14	3507	3807	15	2012-01-14 01:58:32.12648	\N
2718	0	10	16	8705	361	17	2012-01-14 01:53:50.482523	2012-01-14 01:53:50.482523
2675	0	20	2	6908	7786	16	2012-01-14 01:39:13.068982	2012-01-14 03:11:41.506812
2723	0	6	5	9291	897	1	2012-01-14 01:55:31.30782	2012-01-14 01:55:31.30782
2724	292	11	8	292	8201	1	2012-01-14 01:55:39.417451	\N
2681	0	9	19	9584	6472	5	2012-01-14 01:41:38.494813	2012-01-14 05:18:40.799177
2725	0	17	12	7245	156	5	2012-01-14 01:55:55.788596	2012-01-14 01:55:55.788596
2729	8021	16	17	8021	9574	16	2012-01-14 01:56:45.223954	\N
2693	0	8	12	5469	6784	10	2012-01-14 01:47:30.661107	2012-01-14 03:51:22.27465
2726	0	2	17	4108	5567	16	2012-01-14 01:56:03.251596	2012-01-14 01:58:09.450876
2733	1714	20	6	1714	1214	2	2012-01-14 01:59:27.68002	\N
2705	0	17	18	2109	1967	8	2012-01-14 01:50:27.783996	2012-01-14 02:29:52.000585
2728	0	16	8	2851	512	7	2012-01-14 01:56:26.761448	2012-01-14 04:57:16.542017
2736	8196	16	10	8196	7874	20	2012-01-14 02:00:45.662853	\N
2741	1546	13	12	1546	3957	11	2012-01-14 02:03:21.750055	\N
2737	0	7	15	9068	5082	20	2012-01-14 02:02:19.658061	2012-01-14 02:02:19.658061
2721	0	4	1	7393	2640	16	2012-01-14 01:55:00.230879	2012-01-14 02:02:27.621805
2697	0	1	6	2932	1582	13	2012-01-14 01:48:21.953829	2012-01-14 02:02:27.621805
2730	0	17	12	9684	4603	14	2012-01-14 01:58:09.450876	2012-01-14 02:02:27.621805
2738	0	12	6	8038	4815	8	2012-01-14 02:02:27.621805	2012-01-14 02:02:27.621805
2742	1292	8	5	1292	6716	1	2012-01-14 02:03:29.382671	\N
2743	2693	4	14	2693	7466	5	2012-01-14 02:03:36.749651	\N
2745	4732	16	4	4732	9375	5	2012-01-14 02:03:58.794449	\N
2702	0	4	10	9807	9418	12	2012-01-14 01:49:23.736824	2012-01-14 02:09:03.523079
2780	562	20	5	562	3760	20	2012-01-14 02:15:54.760038	\N
2830	0	13	8	4885	6945	1	2012-01-14 02:31:30.588892	2012-01-14 03:51:22.27465
2750	3818	10	14	3818	7997	5	2012-01-14 02:06:42.202015	\N
2776	0	16	1	5815	3189	16	2012-01-14 02:14:23.968959	2012-01-14 06:42:53.982416
2751	0	9	12	6483	5348	16	2012-01-14 02:07:04.02719	2012-01-14 06:25:07.463064
2796	0	16	11	2446	283	19	2012-01-14 02:20:57.497124	2012-01-14 06:16:58.844327
2753	0	17	9	3411	1344	4	2012-01-14 02:07:38.201821	2012-01-14 02:07:38.201821
2755	5446	11	19	5446	8208	14	2012-01-14 02:08:12.053564	\N
2799	0	6	7	2138	1231	13	2012-01-14 02:22:07.251752	2012-01-14 02:45:07.014222
2807	614	18	17	614	2091	2	2012-01-14 02:24:13.767274	\N
2754	0	6	9	2790	8617	19	2012-01-14 02:07:46.165363	2012-01-14 02:09:03.523079
2735	0	10	8	5852	3936	13	2012-01-14 02:00:24.880277	2012-01-14 02:09:03.523079
2757	0	8	7	7398	296	15	2012-01-14 02:09:03.523079	2012-01-14 02:09:03.523079
2758	4532	20	14	4532	5304	8	2012-01-14 02:09:19.587548	\N
2759	7230	8	19	7230	9362	17	2012-01-14 02:09:33.259212	\N
2760	637	9	10	637	5906	1	2012-01-14 02:09:55.747758	\N
2783	0	4	8	9037	3725	5	2012-01-14 02:16:45.608146	2012-01-14 02:16:45.608146
2761	0	1	6	7885	2270	8	2012-01-14 02:10:02.503046	2012-01-14 02:10:02.503046
2762	0	7	1	4146	1690	19	2012-01-14 02:10:27.483146	2012-01-14 02:10:27.483146
2828	490	5	8	490	9984	4	2012-01-14 02:31:15.298036	\N
2765	5046	5	17	5046	9721	5	2012-01-14 02:11:19.956916	\N
2812	0	10	4	1602	1855	5	2012-01-14 02:25:46.702138	2012-01-14 04:59:47.524657
2767	135	7	11	135	8069	7	2012-01-14 02:12:14.195394	\N
2748	0	1	19	7191	4304	15	2012-01-14 02:05:55.185973	2012-01-14 03:34:12.660664
2831	0	4	20	7657	8515	17	2012-01-14 02:31:47.424012	2012-01-14 02:48:10.373285
2770	2954	17	13	2954	8629	19	2012-01-14 02:12:53.952888	\N
2784	0	2	6	4164	995	11	2012-01-14 02:17:01.862906	2012-01-14 02:17:01.862906
2749	0	8	3	5825	8181	15	2012-01-14 02:06:18.791065	2012-01-14 02:13:01.988601
2771	0	4	8	4318	638	18	2012-01-14 02:13:01.988601	2012-01-14 02:13:01.988601
2772	8800	17	7	8800	8728	9	2012-01-14 02:13:10.172576	\N
2773	2744	5	11	2744	4867	13	2012-01-14 02:13:51.931981	\N
2820	0	11	17	7529	9241	7	2012-01-14 02:28:46.968119	2012-01-14 03:04:37.650457
2777	2917	20	15	2917	9849	1	2012-01-14 02:15:31.349939	\N
2779	3624	20	17	3624	6944	19	2012-01-14 02:15:47.294144	\N
2785	0	2	18	6012	1564	16	2012-01-14 02:17:18.816114	2012-01-14 02:17:18.816114
2819	0	4	3	2079	3250	14	2012-01-14 02:28:28.775602	2012-01-14 02:43:38.180341
2825	0	2	7	9854	2082	19	2012-01-14 02:30:25.59385	2012-01-14 02:45:34.478226
2808	0	4	17	5825	3548	11	2012-01-14 02:24:29.80858	2012-01-14 02:48:01.268461
2782	0	3	11	8966	2810	2	2012-01-14 02:16:24.08892	2012-01-14 02:44:50.183751
2790	2272	4	2	2272	5302	14	2012-01-14 02:18:53.740369	\N
2791	3141	3	11	3141	7395	12	2012-01-14 02:19:27.113447	\N
2788	0	2	6	6516	3607	3	2012-01-14 02:18:12.150258	2012-01-14 02:45:51.832818
2793	3350	9	11	3350	5217	11	2012-01-14 02:19:56.791911	\N
2800	0	20	3	7759	2970	17	2012-01-14 02:22:16.428414	2012-01-14 02:22:16.428414
2801	2438	17	11	2438	3685	5	2012-01-14 02:22:24.579771	\N
2795	26	17	8	26	9164	15	2012-01-14 02:20:40.633993	\N
2752	0	6	14	878	1390	5	2012-01-14 02:07:30.411911	2012-01-14 06:18:25.38871
2797	5932	17	14	5932	9410	5	2012-01-14 02:21:11.071814	\N
2809	0	10	3	5066	2669	18	2012-01-14 02:24:46.276028	2012-01-14 02:24:46.276028
2746	0	19	4	3613	9067	14	2012-01-14 02:05:07.088772	2012-01-14 02:22:33.140023
2769	0	12	15	5795	9393	20	2012-01-14 02:12:38.683435	2012-01-14 02:22:33.140023
2802	0	15	19	6162	1459	10	2012-01-14 02:22:33.140023	2012-01-14 02:22:33.140023
2803	8887	9	14	8887	5257	10	2012-01-14 02:22:41.026309	\N
2768	0	19	17	1342	5613	13	2012-01-14 02:12:30.747482	2012-01-14 03:07:42.952808
2789	0	14	19	5341	6838	2	2012-01-14 02:18:37.201593	2012-01-14 02:23:57.858081
2805	0	19	12	5207	2104	1	2012-01-14 02:23:57.858081	2012-01-14 02:23:57.858081
2816	0	6	4	3024	8083	12	2012-01-14 02:27:28.696837	2012-01-14 02:45:51.832818
2833	0	2	14	2381	850	20	2012-01-14 02:32:37.869396	2012-01-14 04:59:57.681641
2815	7080	16	7	7080	3729	19	2012-01-14 02:26:46.895819	\N
2774	0	15	3	4322	6609	10	2012-01-14 02:13:59.718674	2012-01-14 03:04:19.430709
2822	0	18	17	965	727	5	2012-01-14 02:29:52.000585	2012-01-14 02:29:52.000585
2810	0	9	17	9287	3553	13	2012-01-14 02:24:54.245543	2012-01-14 02:27:55.836105
2817	0	15	9	4633	3329	9	2012-01-14 02:27:55.836105	2012-01-14 02:27:55.836105
2818	2131	10	3	2131	8003	4	2012-01-14 02:28:13.061574	\N
2823	1198	17	7	1198	3669	16	2012-01-14 02:30:00.045943	\N
2766	0	8	11	6620	8347	16	2012-01-14 02:11:51.026536	2012-01-14 04:30:23.179745
2824	2066	5	6	2066	8676	8	2012-01-14 02:30:08.61718	\N
2763	0	20	13	9645	5899	4	2012-01-14 02:10:35.405446	2012-01-14 02:30:50.737465
2778	0	13	5	6164	3755	13	2012-01-14 02:15:38.866511	2012-01-14 02:30:50.737465
2826	0	5	17	1774	2761	8	2012-01-14 02:30:50.737465	2012-01-14 02:30:50.737465
2829	3620	3	8	3620	7317	4	2012-01-14 02:31:23.178901	\N
2781	0	9	10	3390	7613	1	2012-01-14 02:16:10.140836	2012-01-14 05:06:41.265964
2836	5447	16	14	5447	4754	18	2012-01-14 02:33:03.363841	\N
2834	0	13	9	2849	122	2	2012-01-14 02:32:45.615302	2012-01-14 02:32:45.615302
2835	0	5	16	6888	2390	8	2012-01-14 02:32:54.606524	2012-01-14 02:32:54.606524
2792	0	15	10	2593	2901	9	2012-01-14 02:19:48.327437	2012-01-14 02:43:28.858049
2786	0	10	8	8895	3441	11	2012-01-14 02:17:26.509538	2012-01-14 02:43:28.858049
2900	8	2	3	8	4254	1	2012-01-14 02:58:26.448157	\N
2839	2336	15	5	2336	5306	14	2012-01-14 02:34:44.876176	\N
2870	6777	16	3	6777	7750	1	2012-01-14 02:46:25.624834	\N
2841	6255	10	19	6255	4997	17	2012-01-14 02:35:10.05903	\N
2842	2064	12	20	2064	6743	5	2012-01-14 02:35:42.063218	\N
2919	7768	20	11	7768	8702	18	2012-01-14 03:04:47.030143	\N
2844	0	4	20	6155	44	11	2012-01-14 02:35:58.355015	2012-01-14 02:35:58.355015
2871	0	18	19	3062	3102	13	2012-01-14 02:47:14.920936	2012-01-14 05:25:52.084653
2849	0	4	11	7040	6903	15	2012-01-14 02:38:36.66216	2012-01-14 05:38:25.805394
2847	7787	16	6	7787	4795	6	2012-01-14 02:36:47.568797	\N
2908	0	13	12	1652	4189	6	2012-01-14 03:01:37.765211	2012-01-14 05:51:12.501509
2872	3484	10	14	3484	8880	8	2012-01-14 02:47:22.71709	\N
2851	1872	5	20	1872	5587	14	2012-01-14 02:40:04.36585	\N
2852	3895	9	12	3895	8330	10	2012-01-14 02:40:12.542615	\N
2879	0	11	19	8989	5100	13	2012-01-14 02:49:36.589175	2012-01-14 03:43:48.602075
2878	0	5	3	3309	7369	5	2012-01-14 02:49:28.125076	2012-01-14 03:51:22.27465
2856	298	18	10	298	6140	8	2012-01-14 02:42:19.529775	\N
2857	5756	16	17	5756	2016	12	2012-01-14 02:42:27.969129	\N
2858	2425	13	2	2425	8707	6	2012-01-14 02:42:50.153151	\N
2873	0	13	4	8476	256	19	2012-01-14 02:48:01.268461	2012-01-14 02:48:01.268461
2806	0	8	17	4219	7233	3	2012-01-14 02:24:06.124607	2012-01-14 02:43:28.858049
2859	0	17	15	9491	287	11	2012-01-14 02:43:28.858049	2012-01-14 02:43:28.858049
2846	0	1	4	1533	4370	19	2012-01-14 02:36:38.719624	2012-01-14 02:43:38.180341
2860	0	15	1	5348	96	14	2012-01-14 02:43:38.180341	2012-01-14 02:43:38.180341
2861	2454	8	11	2454	5190	4	2012-01-14 02:43:46.753164	\N
2862	8406	16	6	8406	3047	13	2012-01-14 02:43:55.279768	\N
2863	0	11	13	6421	1035	15	2012-01-14 02:44:50.183751	2012-01-14 02:44:50.183751
2864	1885	1	13	1885	8830	12	2012-01-14 02:44:58.774202	\N
2874	0	20	2	5015	672	10	2012-01-14 02:48:10.373285	2012-01-14 02:48:10.373285
2865	0	7	6	9020	7411	20	2012-01-14 02:45:07.014222	2012-01-14 02:45:07.014222
2866	0	7	17	9982	4470	16	2012-01-14 02:45:34.478226	2012-01-14 02:45:34.478226
2875	856	2	16	856	9685	1	2012-01-14 02:48:18.161079	\N
2867	0	14	8	9098	1558	7	2012-01-14 02:45:43.095521	2012-01-14 02:45:43.095521
2840	0	4	13	3426	1560	1	2012-01-14 02:34:53.137637	2012-01-14 02:45:51.832818
2868	0	13	15	4639	409	18	2012-01-14 02:45:51.832818	2012-01-14 02:45:51.832818
2924	0	20	17	6231	9807	13	2012-01-14 03:06:39.123804	2012-01-14 06:03:03.040166
2876	2657	11	19	2657	8407	11	2012-01-14 02:48:53.67831	\N
2855	0	11	2	6004	7527	2	2012-01-14 02:41:51.009901	2012-01-14 03:36:59.982949
2845	0	9	10	4245	4525	19	2012-01-14 02:36:06.859354	2012-01-14 04:41:49.482362
2853	0	14	7	3986	5598	6	2012-01-14 02:41:23.685517	2012-01-14 03:36:59.982949
2883	2307	15	5	2307	4000	14	2012-01-14 02:51:27.575213	\N
2884	5810	2	19	5810	8751	8	2012-01-14 02:51:36.608983	\N
2886	8053	19	14	8053	8244	17	2012-01-14 02:52:41.143701	\N
2887	2237	8	19	2237	8956	9	2012-01-14 02:53:06.506543	\N
2888	4735	17	20	4735	7423	15	2012-01-14 02:53:31.136245	\N
2889	711	16	17	711	6660	16	2012-01-14 02:53:47.95317	\N
2880	0	15	20	6680	8322	8	2012-01-14 02:50:01.346849	2012-01-14 02:58:35.546794
2913	3802	17	7	3802	5039	12	2012-01-14 03:03:45.208148	\N
2901	0	10	15	3793	210	15	2012-01-14 02:58:35.546794	2012-01-14 02:58:35.546794
2902	456	11	18	456	9158	1	2012-01-14 02:58:43.720954	\N
2869	0	12	1	5324	9826	12	2012-01-14 02:46:00.700487	2012-01-14 05:58:13.48236
2903	0	1	4	6976	3573	19	2012-01-14 02:58:52.667682	2012-01-14 02:58:52.667682
2921	0	2	8	2761	4698	13	2012-01-14 03:05:38.212117	2012-01-14 03:11:41.506812
2898	337	14	12	337	8277	13	2012-01-14 02:57:58.828026	\N
2838	0	10	12	9249	5621	11	2012-01-14 02:33:57.114922	2012-01-14 02:58:16.85139
2899	0	19	10	4489	2365	5	2012-01-14 02:58:16.85139	2012-01-14 02:58:16.85139
2905	122	8	16	122	4595	14	2012-01-14 02:59:10.363141	\N
2906	9825	16	19	9825	6305	2	2012-01-14 02:59:29.128807	\N
2891	0	3	20	1675	872	18	2012-01-14 02:54:53.073564	2012-01-14 03:01:46.915235
2912	0	12	5	9324	7604	15	2012-01-14 03:03:09.896376	2012-01-14 03:32:50.757337
2910	0	4	12	3852	8194	10	2012-01-14 03:02:15.385944	2012-01-14 06:51:59.945998
2885	0	10	20	8621	7340	10	2012-01-14 02:52:01.137492	2012-01-14 06:57:06.303194
2914	758	5	9	758	4334	6	2012-01-14 03:03:54.367276	\N
2915	1274	10	13	1274	1970	14	2012-01-14 03:04:03.268962	\N
2843	0	18	11	3877	2396	19	2012-01-14 02:35:50.292913	2012-01-14 03:04:37.650457
2916	0	12	15	4845	2700	7	2012-01-14 03:04:19.430709	2012-01-14 03:04:19.430709
2917	894	14	19	894	8692	12	2012-01-14 03:04:28.461387	\N
2920	2846	4	20	2846	7119	15	2012-01-14 03:05:21.552473	\N
2892	0	17	14	8503	3958	9	2012-01-14 02:55:00.544039	2012-01-14 03:04:37.650457
2918	0	14	1	9077	1604	10	2012-01-14 03:04:37.650457	2012-01-14 03:04:37.650457
2882	0	8	17	8922	8336	5	2012-01-14 02:50:35.055783	2012-01-14 03:32:50.757337
2923	6463	15	14	6463	9038	9	2012-01-14 03:06:13.428554	\N
2922	0	12	10	2509	1056	8	2012-01-14 03:06:04.54155	2012-01-14 03:06:04.54155
2925	2263	11	4	2263	9258	15	2012-01-14 03:07:04.945713	\N
2926	772	17	15	772	6490	6	2012-01-14 03:07:33.817158	\N
2904	0	17	12	1736	3063	13	2012-01-14 02:59:01.646252	2012-01-14 03:07:42.952808
2909	0	12	5	4813	2234	20	2012-01-14 03:01:46.915235	2012-01-14 03:07:42.952808
2927	0	5	19	4179	330	20	2012-01-14 03:07:42.952808	2012-01-14 03:07:42.952808
2928	4014	12	13	4014	6888	18	2012-01-14 03:07:51.003898	\N
2995	586	10	5	586	9373	1	2012-01-14 03:36:31.237626	\N
2960	0	10	2	8103	9420	16	2012-01-14 03:20:49.093816	2012-01-14 04:25:04.656422
2931	590	13	11	590	7854	8	2012-01-14 03:09:17.158338	\N
2932	47	17	5	47	8603	17	2012-01-14 03:09:26.682277	\N
2929	0	6	13	9497	8514	7	2012-01-14 03:07:59.586245	2012-01-14 03:20:39.258811
2959	0	13	7	1128	163	20	2012-01-14 03:20:39.258811	2012-01-14 03:20:39.258811
2934	0	5	4	4341	6878	10	2012-01-14 03:10:05.333719	2012-01-14 03:10:05.333719
3008	0	1	15	2594	4155	12	2012-01-14 03:41:50.007846	2012-01-14 05:04:33.125138
2936	78	2	5	78	9574	1	2012-01-14 03:10:51.648104	\N
2950	0	8	10	6479	9990	7	2012-01-14 03:16:05.525637	2012-01-14 04:25:27.086353
2938	0	8	20	8514	580	6	2012-01-14 03:11:41.506812	2012-01-14 03:11:41.506812
3010	0	9	8	8961	6149	6	2012-01-14 03:42:27.83553	2012-01-14 04:30:33.976166
2943	2592	12	7	2592	3568	5	2012-01-14 03:13:09.349828	\N
2944	2368	2	20	2368	9665	4	2012-01-14 03:13:28.429716	\N
2962	1759	15	8	1759	4075	12	2012-01-14 03:23:55.874537	\N
2946	869	3	8	869	3479	15	2012-01-14 03:14:19.633519	\N
2996	2264	4	5	2264	1871	17	2012-01-14 03:36:40.395392	\N
2948	0	5	7	9876	586	10	2012-01-14 03:14:56.36778	2012-01-14 03:32:02.135701
2963	7700	8	7	7700	9050	6	2012-01-14 03:24:15.044581	\N
3022	0	5	14	8616	4834	10	2012-01-14 03:49:38.062907	2012-01-14 04:30:33.976166
2952	1389	20	7	1389	3034	6	2012-01-14 03:17:03.817034	\N
2935	0	1	7	7647	2734	11	2012-01-14 03:10:23.566756	2012-01-14 05:01:49.345005
2983	1735	1	5	3635	3230	12	2012-01-14 03:32:02.135701	2012-01-14 03:32:02.135701
2967	466	9	4	466	593	1	2012-01-14 03:25:40.473359	\N
2969	196	20	2	196	9749	15	2012-01-14 03:26:30.107706	\N
2970	1410	16	13	1410	5886	6	2012-01-14 03:26:39.576217	\N
2984	0	13	4	5701	3697	4	2012-01-14 03:32:31.693567	2012-01-14 03:32:31.693567
2942	0	1	3	5453	4570	7	2012-01-14 03:13:00.224989	2012-01-14 03:27:50.232295
2972	0	15	16	5797	5478	12	2012-01-14 03:27:50.232295	2012-01-14 03:27:50.232295
2973	1601	11	7	1601	7582	15	2012-01-14 03:28:10.530058	\N
2974	5834	9	14	5834	3423	7	2012-01-14 03:28:29.45146	\N
2953	0	4	3	880	1728	15	2012-01-14 03:17:12.868512	2012-01-14 04:59:47.524657
2977	0	2	18	3707	1360	7	2012-01-14 03:30:00.162419	2012-01-14 03:36:59.982949
2947	0	2	10	2739	9978	1	2012-01-14 03:14:27.863023	2012-01-14 03:32:42.022042
2985	0	10	2	9296	506	17	2012-01-14 03:32:42.022042	2012-01-14 03:32:42.022042
2979	1630	19	5	1630	8191	20	2012-01-14 03:30:28.579601	\N
2980	4552	20	5	4552	5112	5	2012-01-14 03:30:39.196518	\N
2981	1059	16	18	1059	7055	6	2012-01-14 03:30:58.585806	\N
2982	1213	11	7	1213	8241	1	2012-01-14 03:31:39.210416	\N
2964	0	18	14	7311	3003	3	2012-01-14 03:24:43.621587	2012-01-14 03:36:59.982949
2941	0	5	8	5221	7467	4	2012-01-14 03:12:51.418202	2012-01-14 03:32:50.757337
2986	0	4	12	5155	1858	3	2012-01-14 03:32:50.757337	2012-01-14 03:32:50.757337
2987	3174	10	7	3174	8241	18	2012-01-14 03:32:59.693113	\N
3020	4730	16	10	4730	8861	12	2012-01-14 03:46:38.948414	\N
2997	117	7	11	2165	4617	6	2012-01-14 03:36:59.982949	2012-01-14 03:36:59.982949
2998	3238	9	11	3238	6758	9	2012-01-14 03:37:32.566459	\N
2990	0	19	15	5220	3397	17	2012-01-14 03:34:12.660664	2012-01-14 03:34:12.660664
2991	503	1	5	503	9223	13	2012-01-14 03:34:22.219625	\N
2961	0	16	20	9729	5782	3	2012-01-14 03:21:24.876621	2012-01-14 06:13:47.507635
2994	4339	16	7	4339	8299	3	2012-01-14 03:35:14.673242	\N
2999	1648	8	20	1648	2438	20	2012-01-14 03:38:05.134682	\N
3000	4487	20	13	4487	6773	19	2012-01-14 03:38:33.572796	\N
3009	812	15	7	812	2875	19	2012-01-14 03:42:07.975651	\N
2965	0	1	8	850	2615	18	2012-01-14 03:25:00.788557	2012-01-14 03:38:42.977745
3001	0	8	1	2377	658	19	2012-01-14 03:38:42.977745	2012-01-14 03:38:42.977745
3002	0	13	9	4712	3381	19	2012-01-14 03:38:52.023956	2012-01-14 03:38:52.023956
2930	0	9	1	7688	1933	7	2012-01-14 03:08:18.334094	2012-01-14 04:16:35.123663
2975	0	2	17	6255	8786	3	2012-01-14 03:28:52.81214	2012-01-14 04:54:03.165042
3004	0	11	19	9055	6269	1	2012-01-14 03:39:31.358481	2012-01-14 04:01:11.615246
2993	0	20	11	3271	1650	10	2012-01-14 03:34:56.245557	2012-01-14 03:43:48.602075
3016	0	13	11	5028	6694	10	2012-01-14 03:45:11.929256	2012-01-14 05:28:25.015548
2988	0	19	15	5420	9581	12	2012-01-14 03:33:26.000173	2012-01-14 03:43:48.602075
3011	0	15	20	294	520	3	2012-01-14 03:43:48.602075	2012-01-14 03:43:48.602075
3014	5406	20	11	5406	4688	14	2012-01-14 03:44:35.701084	\N
2992	0	9	7	5593	2472	5	2012-01-14 03:34:31.58487	2012-01-14 06:03:03.040166
3015	0	10	19	1197	107	2	2012-01-14 03:45:03.508809	2012-01-14 03:45:03.508809
3018	921	8	10	921	9013	2	2012-01-14 03:46:00.685243	\N
3012	0	18	20	1319	2086	16	2012-01-14 03:43:57.982565	2012-01-14 03:46:29.655564
3019	0	20	18	2574	179	20	2012-01-14 03:46:29.655564	2012-01-14 03:46:29.655564
3021	909	10	4	909	6741	2	2012-01-14 03:49:01.06319	\N
3025	0	6	10	2749	9323	6	2012-01-14 03:50:50.893662	2012-01-14 05:04:33.125138
3023	6072	3	10	6072	9632	2	2012-01-14 03:49:55.715895	\N
3024	3880	17	11	3880	5792	10	2012-01-14 03:50:31.957926	\N
2939	0	10	17	6212	2790	19	2012-01-14 03:11:50.292306	2012-01-14 04:25:27.086353
3013	0	4	5	5508	2988	13	2012-01-14 03:44:07.165396	2012-01-14 03:51:22.27465
3026	0	12	4	8085	6061	7	2012-01-14 03:51:22.27465	2012-01-14 03:51:22.27465
3027	9862	10	5	9862	9954	19	2012-01-14 03:52:02.938808	\N
3114	0	3	18	5567	2411	5	2012-01-14 04:32:59.22867	2012-01-14 06:13:47.507635
3030	2272	5	6	2272	3622	6	2012-01-14 03:54:23.3118	\N
3028	0	18	17	4002	7430	14	2012-01-14 03:53:26.998627	2012-01-14 06:03:36.802837
3031	0	19	13	957	47	16	2012-01-14 03:54:32.641246	2012-01-14 03:54:32.641246
3033	785	15	3	785	4803	7	2012-01-14 03:55:02.024639	\N
3063	6714	15	19	6714	9295	19	2012-01-14 04:09:45.648876	\N
3035	0	6	12	4685	2882	11	2012-01-14 03:56:03.010756	2012-01-14 03:56:03.010756
3037	2374	16	20	2374	5938	19	2012-01-14 03:56:32.377907	\N
3081	0	1	9	4090	8142	12	2012-01-14 04:19:03.285586	2012-01-14 06:21:27.088263
3040	321	16	11	321	3200	16	2012-01-14 03:58:03.06125	\N
3041	1969	16	15	1969	9542	1	2012-01-14 03:58:19.559559	\N
3042	750	15	11	750	1768	9	2012-01-14 03:59:28.644133	\N
3101	708	4	1	708	1845	8	2012-01-14 04:28:22.976805	\N
3065	9506	3	1	9506	5621	11	2012-01-14 04:11:35.980254	\N
3044	0	12	6	7782	3535	17	2012-01-14 03:59:47.636142	2012-01-14 04:00:27.06107
3046	0	16	12	9853	984	10	2012-01-14 04:00:27.06107	2012-01-14 04:00:27.06107
3047	1975	11	1	1975	6655	17	2012-01-14 04:00:51.90112	\N
3067	599	9	11	599	7931	2	2012-01-14 04:14:05.518096	\N
3043	0	8	9	878	3012	6	2012-01-14 03:59:37.827651	2012-01-14 04:14:14.265375
3068	0	9	13	9007	478	9	2012-01-14 04:14:14.265375	2012-01-14 04:14:14.265375
3052	0	6	12	8755	8356	3	2012-01-14 04:02:59.905667	2012-01-14 04:02:59.905667
3053	2425	4	1	2425	4646	5	2012-01-14 04:03:19.531041	\N
3109	0	19	20	3807	8755	6	2012-01-14 04:30:44.600847	2012-01-14 05:27:51.927097
3056	51	20	13	51	3284	13	2012-01-14 04:04:26.478759	\N
3057	3225	10	6	3225	4887	8	2012-01-14 04:04:35.512187	\N
3059	7838	16	1	7838	9212	10	2012-01-14 04:05:27.194365	\N
3102	1087	9	10	1087	7456	14	2012-01-14 04:28:43.435599	\N
3095	7256	18	5	7256	5991	20	2012-01-14 04:26:34.922368	\N
3099	0	15	6	7686	2083	16	2012-01-14 04:27:52.960941	2012-01-14 05:04:33.125138
3076	0	6	15	1823	7018	18	2012-01-14 04:17:29.146045	2012-01-14 05:38:25.805394
3073	1986	16	20	1986	3436	12	2012-01-14 04:16:08.88868	\N
3070	0	1	13	7360	6869	4	2012-01-14 04:14:42.579536	2012-01-14 04:16:35.123663
3074	0	13	9	4576	140	17	2012-01-14 04:16:35.123663	2012-01-14 04:16:35.123663
3075	7534	16	11	7534	5023	13	2012-01-14 04:16:46.139236	\N
3039	0	11	17	3949	7427	20	2012-01-14 03:57:44.011171	2012-01-14 05:41:48.832166
3077	3384	10	6	3384	8513	9	2012-01-14 04:17:49.735616	\N
3111	5554	10	14	5554	1912	20	2012-01-14 04:31:58.231426	\N
3085	9753	18	11	9753	8980	9	2012-01-14 04:20:58.609639	\N
3086	5299	4	11	5299	5844	19	2012-01-14 04:21:48.183851	\N
3080	1650	3	15	1650	4464	16	2012-01-14 04:18:36.917153	\N
3087	573	15	10	573	3087	5	2012-01-14 04:22:28.934142	\N
3088	5001	1	14	5001	7653	17	2012-01-14 04:23:00.737342	\N
3055	0	7	15	3134	6192	20	2012-01-14 04:04:16.490938	2012-01-14 04:29:01.778036
3103	0	15	7	7524	1000	17	2012-01-14 04:29:01.778036	2012-01-14 04:29:01.778036
3060	0	2	7	908	381	2	2012-01-14 04:08:28.576003	2012-01-14 04:25:04.656422
3064	0	7	15	7527	8939	4	2012-01-14 04:10:44.924993	2012-01-14 04:25:04.656422
3091	0	14	10	787	2630	10	2012-01-14 04:25:04.656422	2012-01-14 04:25:04.656422
3092	0	17	8	2314	836	13	2012-01-14 04:25:27.086353	2012-01-14 04:25:27.086353
3093	3477	16	4	3477	3426	1	2012-01-14 04:25:37.763265	\N
3078	0	19	13	6254	4208	7	2012-01-14 04:18:08.113225	2012-01-14 04:27:24.466734
3048	0	6	17	6099	7014	11	2012-01-14 04:01:11.615246	2012-01-14 04:27:24.466734
3097	0	17	19	7991	318	17	2012-01-14 04:27:24.466734	2012-01-14 04:27:24.466734
3066	0	8	5	7477	5646	9	2012-01-14 04:13:25.389698	2012-01-14 04:30:33.976166
3054	0	1	4	6538	6042	5	2012-01-14 04:03:47.884817	2012-01-14 05:05:43.821117
3100	939	13	7	939	7854	13	2012-01-14 04:28:12.760034	\N
3106	939	6	5	939	4886	13	2012-01-14 04:30:02.338577	\N
3112	595	7	5	595	1787	4	2012-01-14 04:32:16.395496	\N
3105	0	2	8	8434	6123	17	2012-01-14 04:29:32.850447	2012-01-14 04:30:23.179745
3107	0	11	2	6937	3979	5	2012-01-14 04:30:23.179745	2012-01-14 04:30:23.179745
3108	0	14	9	3759	2833	7	2012-01-14 04:30:33.976166	2012-01-14 04:30:33.976166
3123	0	17	12	6807	3865	16	2012-01-14 04:36:21.277739	2012-01-14 05:41:48.832166
3115	3294	16	2	3294	6901	15	2012-01-14 04:33:17.534128	\N
3117	216	9	15	216	2545	17	2012-01-14 04:34:20.957515	\N
3121	4433	17	13	4433	9048	2	2012-01-14 04:35:20.647555	\N
3062	0	17	12	5046	7048	13	2012-01-14 04:08:56.730887	2012-01-14 04:35:01.369025
3110	0	12	16	2280	8501	17	2012-01-14 04:31:15.985772	2012-01-14 04:35:01.369025
3119	0	3	17	6841	1016	9	2012-01-14 04:35:01.369025	2012-01-14 04:35:01.369025
3125	2999	19	13	2999	6483	3	2012-01-14 04:37:35.768267	\N
3120	0	13	8	1618	1231	20	2012-01-14 04:35:10.464701	2012-01-14 04:35:51.503508
3061	0	2	4	4047	6912	2	2012-01-14 04:08:46.960169	2012-01-14 04:35:51.503508
3122	0	4	13	6077	3047	16	2012-01-14 04:35:51.503508	2012-01-14 04:35:51.503508
3126	7591	17	19	7591	6344	4	2012-01-14 04:37:45.879512	\N
3127	1963	7	12	1963	7453	10	2012-01-14 04:38:05.785548	\N
3071	0	10	16	581	5958	14	2012-01-14 04:15:29.082307	2012-01-14 04:57:16.542017
3128	2522	1	17	2522	8640	4	2012-01-14 04:38:16.317893	\N
3129	4854	10	6	4854	6756	3	2012-01-14 04:38:36.014339	\N
3131	7592	10	5	7592	8361	5	2012-01-14 04:39:16.792886	\N
3196	0	3	15	3504	2463	10	2012-01-14 05:09:50.246269	2012-01-14 07:09:17.219283
3216	5214	17	6	6626	2077	19	2012-01-14 05:21:31.394688	2012-01-14 06:18:25.38871
3213	0	10	11	8030	4096	3	2012-01-14 05:19:43.05683	2012-01-14 05:58:13.48236
3135	0	10	9	9322	6532	14	2012-01-14 04:41:49.482362	2012-01-14 04:41:49.482362
3136	2548	20	4	2548	5723	13	2012-01-14 04:42:08.654467	\N
3137	0	10	16	3669	5208	10	2012-01-14 04:42:52.441421	2012-01-14 04:42:52.441421
3164	0	17	2	8590	4663	15	2012-01-14 04:54:03.165042	2012-01-14 04:54:03.165042
3138	0	7	5	7940	1668	3	2012-01-14 04:43:02.787694	2012-01-14 04:43:02.787694
3139	0	13	6	7254	2517	20	2012-01-14 04:43:13.577782	2012-01-14 04:43:13.577782
3141	6019	3	15	6019	9236	8	2012-01-14 04:43:55.622139	\N
3142	3977	11	1	3977	9024	8	2012-01-14 04:44:51.603998	\N
3170	0	5	14	9790	4524	6	2012-01-14 04:58:10.177973	2012-01-14 05:26:04.392466
3144	7053	10	14	7053	8666	18	2012-01-14 04:45:23.828075	\N
3145	136	20	9	136	7911	19	2012-01-14 04:46:10.647543	\N
3146	648	16	20	648	6559	19	2012-01-14 04:46:21.279374	\N
3147	4157	12	7	4157	5862	7	2012-01-14 04:46:48.157076	\N
3148	3914	9	6	3914	1764	16	2012-01-14 04:47:18.041224	\N
3166	9991	16	4	9991	6622	9	2012-01-14 04:54:48.244544	\N
3167	9826	8	7	9826	5902	13	2012-01-14 04:56:32.158893	\N
3151	6716	17	7	6716	8620	20	2012-01-14 04:48:42.622022	\N
3152	4180	15	7	4180	7364	20	2012-01-14 04:49:35.310931	\N
3153	5229	18	19	5229	7972	14	2012-01-14 04:50:17.056187	\N
3208	0	20	11	9901	9089	10	2012-01-14 05:17:37.811372	2012-01-14 06:57:06.303194
3191	3228	18	12	3228	5744	10	2012-01-14 05:07:22.734434	\N
3181	3177	11	18	3177	5094	20	2012-01-14 05:03:50.031769	\N
3157	58	4	12	58	1752	8	2012-01-14 04:51:59.810351	\N
3158	1217	16	19	1217	419	13	2012-01-14 04:52:10.043248	\N
3160	7480	8	12	7480	7733	16	2012-01-14 04:52:39.473184	\N
3182	242	8	20	242	3971	12	2012-01-14 05:04:01.223258	\N
3161	0	1	10	5748	2649	6	2012-01-14 04:53:20.27494	2012-01-14 04:57:16.542017
3162	0	1	13	2941	171	3	2012-01-14 04:53:41.614745	2012-01-14 04:53:41.614745
3134	0	8	6	9706	2641	8	2012-01-14 04:41:29.166953	2012-01-14 05:38:25.805394
3169	1096	18	14	1096	6431	1	2012-01-14 04:57:50.165647	\N
3212	0	3	8	4524	2449	9	2012-01-14 05:19:13.367287	2012-01-14 05:27:51.927097
3183	9712	18	6	9712	8131	1	2012-01-14 05:04:12.377833	\N
3173	3200	9	1	3200	5891	5	2012-01-14 04:59:28.220382	\N
3180	0	10	14	7374	1449	19	2012-01-14 05:03:21.63407	2012-01-14 05:04:33.125138
3156	0	15	10	6503	4536	4	2012-01-14 04:51:38.638785	2012-01-14 04:59:47.524657
3174	0	3	15	2826	150	2	2012-01-14 04:59:47.524657	2012-01-14 04:59:47.524657
3192	317	5	10	317	6853	13	2012-01-14 05:07:32.324198	\N
3175	0	14	2	4733	7524	8	2012-01-14 04:59:57.681641	2012-01-14 04:59:57.681641
3177	9305	10	14	9305	2942	6	2012-01-14 05:01:05.941442	\N
3178	464	19	8	464	8776	16	2012-01-14 05:01:25.318335	\N
3154	0	8	11	5385	3839	15	2012-01-14 04:50:46.944546	2012-01-14 06:47:11.470168
3176	0	7	10	4318	6478	15	2012-01-14 05:00:32.587684	2012-01-14 05:01:49.345005
3179	0	15	1	8759	9958	13	2012-01-14 05:01:49.345005	2012-01-14 05:01:49.345005
3193	2260	17	2	2260	8619	20	2012-01-14 05:07:42.895833	\N
3168	0	8	9	4718	3176	7	2012-01-14 04:57:16.542017	2012-01-14 05:27:51.927097
3184	0	14	1	954	1499	2	2012-01-14 05:04:33.125138	2012-01-14 05:05:43.821117
3155	0	4	10	4269	8951	18	2012-01-14 04:51:17.082493	2012-01-14 05:05:43.821117
3187	0	10	14	9185	2944	11	2012-01-14 05:05:43.821117	2012-01-14 05:05:43.821117
3188	311	12	11	311	8060	18	2012-01-14 05:06:30.956706	\N
3189	0	10	9	8754	3707	9	2012-01-14 05:06:41.265964	2012-01-14 05:06:41.265964
3199	5937	16	11	5937	5009	4	2012-01-14 05:11:12.782854	\N
3200	8508	16	4	8508	9936	12	2012-01-14 05:12:29.838703	\N
3197	7907	18	6	7907	9135	14	2012-01-14 05:10:08.678589	\N
3198	3172	13	5	3172	9126	12	2012-01-14 05:10:38.897362	\N
3132	0	1	2	4664	9214	17	2012-01-14 04:40:36.911435	2012-01-14 07:06:45.484923
3163	0	12	6	5359	2889	10	2012-01-14 04:53:52.041805	2012-01-14 05:16:02.889403
3203	3622	1	7	3622	5238	9	2012-01-14 05:15:22.183725	\N
3204	290	11	13	290	4134	8	2012-01-14 05:15:52.468795	\N
3205	0	6	12	6236	203	16	2012-01-14 05:16:02.889403	2012-01-14 05:16:02.889403
3206	8515	9	11	8515	8195	20	2012-01-14 05:16:13.7143	\N
3133	0	4	19	1459	1011	6	2012-01-14 04:41:19.162159	2012-01-14 06:13:47.507635
3210	0	19	9	2610	2912	2	2012-01-14 05:18:40.799177	2012-01-14 05:18:40.799177
3211	3291	15	5	3291	9464	9	2012-01-14 05:18:52.080106	\N
3209	0	1	18	7182	5566	18	2012-01-14 05:18:09.652107	2012-01-14 06:03:36.802837
3185	0	12	14	2179	1543	19	2012-01-14 05:04:56.296873	2012-01-14 06:21:27.088263
3214	946	3	1	946	9936	5	2012-01-14 05:20:50.866639	\N
3215	1647	19	13	1647	9497	1	2012-01-14 05:21:20.183511	\N
3217	1729	2	14	1729	8868	15	2012-01-14 05:22:05.587175	\N
3194	0	10	18	6044	2004	7	2012-01-14 05:08:15.839745	2012-01-14 05:25:52.084653
3143	0	19	6	7243	5546	15	2012-01-14 04:45:12.808648	2012-01-14 05:25:52.084653
3252	5891	9	1	5891	8392	9	2012-01-14 05:41:59.872598	\N
3222	0	6	10	2591	666	15	2012-01-14 05:25:52.084653	2012-01-14 05:25:52.084653
3253	997	12	18	997	5453	16	2012-01-14 05:42:40.703759	\N
3223	0	14	5	2990	201	4	2012-01-14 05:26:04.392466	2012-01-14 05:26:04.392466
3225	388	16	13	388	1894	20	2012-01-14 05:26:39.664286	\N
3254	930	16	5	930	2886	8	2012-01-14 05:43:02.267755	\N
3226	0	8	15	6626	3305	18	2012-01-14 05:26:57.58774	2012-01-14 05:26:57.58774
3255	47	3	9	47	7053	12	2012-01-14 05:43:31.30914	\N
3072	0	20	3	1955	5000	18	2012-01-14 04:15:48.401475	2012-01-14 05:27:51.927097
3228	0	11	19	2273	642	6	2012-01-14 05:27:51.927097	2012-01-14 05:27:51.927097
3273	5416	8	14	5416	7712	3	2012-01-14 05:54:08.230646	\N
3230	0	11	13	1982	1317	17	2012-01-14 05:28:25.015548	2012-01-14 05:28:25.015548
3256	0	5	9	3645	1834	15	2012-01-14 05:43:40.588778	2012-01-14 05:43:40.588778
3232	4152	9	4	4152	8333	6	2012-01-14 05:29:32.138297	\N
3233	1363	10	2	1363	6052	14	2012-01-14 05:29:52.038921	\N
3234	9653	2	11	9653	9773	14	2012-01-14 05:30:02.039541	\N
3235	7823	16	10	7823	4335	1	2012-01-14 05:30:44.680672	\N
3236	659	20	17	659	4731	16	2012-01-14 05:32:26.364007	\N
3313	5684	7	1	5684	7769	10	2012-01-14 06:13:59.890333	\N
3258	4002	19	2	4002	4860	9	2012-01-14 05:44:25.911729	\N
3240	9084	16	17	9084	4621	1	2012-01-14 05:34:18.176118	\N
3241	182	18	12	182	381	3	2012-01-14 05:37:06.771606	\N
3242	2114	9	4	2114	3632	16	2012-01-14 05:37:17.452148	\N
3243	242	1	19	242	1650	10	2012-01-14 05:37:38.497103	\N
3244	2164	7	8	2164	7507	7	2012-01-14 05:37:49.162503	\N
3229	0	15	4	5505	2636	10	2012-01-14 05:28:03.165622	2012-01-14 05:38:25.805394
3245	0	3	8	2575	79	12	2012-01-14 05:38:25.805394	2012-01-14 05:38:25.805394
3246	1483	11	18	1483	7249	16	2012-01-14 05:38:35.916031	\N
3247	813	16	8	813	3473	18	2012-01-14 05:38:58.72738	\N
3248	53	17	20	53	8287	2	2012-01-14 05:39:37.528163	\N
3249	2754	1	2	2754	5806	10	2012-01-14 05:39:48.412435	\N
3250	8913	16	17	8913	6934	12	2012-01-14 05:40:09.676331	\N
3251	0	12	11	7953	4162	17	2012-01-14 05:41:48.832166	2012-01-14 05:41:48.832166
3259	4148	3	18	4148	5036	14	2012-01-14 05:45:02.061538	\N
3260	70	12	11	70	852	17	2012-01-14 05:46:32.927439	\N
3275	3955	17	11	3955	4850	1	2012-01-14 05:54:52.46349	\N
3264	3244	17	1	3244	5177	12	2012-01-14 05:48:32.631957	\N
3266	3313	16	8	3313	8888	3	2012-01-14 05:49:06.33119	\N
3276	0	8	4	8847	2543	3	2012-01-14 05:55:26.162212	2012-01-14 05:55:26.162212
3295	4002	5	6	4002	8274	7	2012-01-14 06:05:27.200091	\N
3267	0	12	4	5916	4956	3	2012-01-14 05:50:02.998102	2012-01-14 05:51:12.501509
3269	0	7	13	4392	2579	9	2012-01-14 05:51:12.501509	2012-01-14 05:51:12.501509
3288	252	4	6	252	5600	14	2012-01-14 06:00:49.623788	\N
3271	437	18	5	437	6263	2	2012-01-14 05:52:50.541222	\N
3278	1125	14	13	1125	2963	6	2012-01-14 05:56:12.623361	\N
3279	7965	9	14	7965	4738	8	2012-01-14 05:56:24.204645	\N
3280	363	13	19	363	2222	20	2012-01-14 05:57:03.542618	\N
3281	1778	17	12	1778	5587	14	2012-01-14 05:57:15.163374	\N
3289	5620	16	17	5620	9843	6	2012-01-14 06:01:00.653521	\N
3272	0	1	10	7674	7613	12	2012-01-14 05:53:12.717812	2012-01-14 05:58:13.48236
3283	0	13	12	6843	641	10	2012-01-14 05:58:13.48236	2012-01-14 05:58:13.48236
3287	0	19	9	4267	7460	3	2012-01-14 05:59:51.538475	2012-01-14 06:03:03.040166
3286	3974	4	18	3974	5820	3	2012-01-14 05:59:40.637217	\N
3268	0	7	20	3096	5899	8	2012-01-14 05:50:36.705905	2012-01-14 06:03:03.040166
3290	0	17	19	5322	1637	2	2012-01-14 06:03:03.040166	2012-01-14 06:03:03.040166
3291	821	15	14	821	2063	17	2012-01-14 06:03:26.185719	\N
3293	0	8	4	4769	7710	10	2012-01-14 06:03:57.2876	2012-01-14 06:59:12.659348
3219	0	17	9	9311	9154	12	2012-01-14 05:23:09.653444	2012-01-14 06:03:36.802837
3292	0	9	1	5884	3752	9	2012-01-14 06:03:36.802837	2012-01-14 06:03:36.802837
3306	0	4	13	6607	5917	16	2012-01-14 06:11:31.267925	2012-01-14 07:08:27.572635
3301	1916	7	5	1916	7626	18	2012-01-14 06:08:55.393357	\N
3297	8766	3	17	8766	4117	5	2012-01-14 06:06:36.570281	\N
3298	4924	4	9	4924	9313	6	2012-01-14 06:07:35.753098	\N
3299	6352	15	4	6352	5201	4	2012-01-14 06:08:32.763396	\N
3317	0	5	12	1700	2336	4	2012-01-14 06:15:35.957285	2012-01-14 06:27:25.088944
3304	4225	18	12	4225	9748	18	2012-01-14 06:10:27.631111	\N
3303	4982	12	17	4982	8711	5	2012-01-14 06:09:42.460057	\N
3296	0	8	9	6193	7916	4	2012-01-14 06:06:02.178901	2012-01-14 06:57:30.743718
3285	1002	2	14	5166	3328	3	2012-01-14 05:58:58.93815	2012-01-14 07:09:17.219283
3307	1061	15	8	1061	9598	9	2012-01-14 06:11:53.534147	\N
3309	3822	12	7	3822	4158	14	2012-01-14 06:12:59.283362	\N
3300	0	12	8	4181	4629	13	2012-01-14 06:08:43.896355	2012-01-14 06:25:07.463064
3305	0	11	17	2094	4082	19	2012-01-14 06:11:08.081742	2012-01-14 06:47:11.470168
3311	0	20	3	3274	4584	8	2012-01-14 06:13:35.555567	2012-01-14 06:13:47.507635
3238	0	18	4	5889	4991	3	2012-01-14 05:33:11.443976	2012-01-14 06:13:47.507635
3312	0	19	16	7409	517	6	2012-01-14 06:13:47.507635	2012-01-14 06:13:47.507635
3316	841	11	15	841	4293	12	2012-01-14 06:15:22.823941	\N
3315	0	10	16	4036	6716	1	2012-01-14 06:15:11.885319	2012-01-14 06:42:53.982416
3318	4096	15	14	4096	5617	4	2012-01-14 06:16:12.162147	\N
3347	6334	4	13	6334	8739	9	2012-01-14 06:36:55.386095	\N
3319	0	19	4	9242	15	16	2012-01-14 06:16:46.567729	2012-01-14 06:16:46.567729
3348	3849	2	14	3849	8570	2	2012-01-14 06:37:31.007242	\N
3405	4619	13	6	4619	2166	1	2012-01-14 07:09:54.983806	\N
3349	6038	18	5	6038	4339	7	2012-01-14 06:38:05.991855	\N
3323	235	17	6	235	705	5	2012-01-14 06:18:55.740496	\N
3350	3968	9	20	3968	4988	9	2012-01-14 06:38:29.016661	\N
3325	3714	12	11	3714	4335	18	2012-01-14 06:19:48.143801	\N
3326	7133	12	6	7133	2740	8	2012-01-14 06:20:24.669149	\N
3369	9578	17	6	9578	9484	11	2012-01-14 06:48:31.154932	\N
3310	0	13	1	2941	2298	4	2012-01-14 06:13:23.460379	2012-01-14 06:21:27.088263
3328	0	14	13	2489	493	19	2012-01-14 06:21:27.088263	2012-01-14 06:21:27.088263
3329	1357	10	2	1357	1472	3	2012-01-14 06:21:39.785497	\N
3352	6015	16	6	6015	9146	16	2012-01-14 06:39:20.008153	\N
3331	5031	11	6	5031	8032	6	2012-01-14 06:23:06.564472	\N
3333	0	8	9	8774	5770	4	2012-01-14 06:25:07.463064	2012-01-14 06:25:07.463064
3335	1399	5	12	1399	2733	18	2012-01-14 06:26:45.370978	\N
3336	190	4	2	190	3011	13	2012-01-14 06:27:12.925132	\N
3354	0	2	9	2678	531	14	2012-01-14 06:40:39.48521	2012-01-14 06:40:39.48521
3320	0	11	16	1999	7717	14	2012-01-14 06:16:58.844327	2012-01-14 06:27:25.088944
3337	0	12	11	8434	5345	9	2012-01-14 06:27:25.088944	2012-01-14 06:27:25.088944
3355	5891	11	18	5891	9329	14	2012-01-14 06:40:50.97574	\N
3339	1138	14	18	1138	9742	2	2012-01-14 06:29:36.683598	\N
3340	6196	9	13	6196	9958	12	2012-01-14 06:29:50.261269	\N
3341	9459	16	19	9459	3427	20	2012-01-14 06:31:20.159864	\N
3370	4020	16	15	4020	5243	11	2012-01-14 06:49:31.969001	\N
3343	2967	16	7	2967	2057	2	2012-01-14 06:33:40.251893	\N
3344	1721	7	14	1721	9283	12	2012-01-14 06:34:11.645811	\N
3322	0	14	17	1976	1541	8	2012-01-14 06:18:25.38871	2012-01-14 06:35:47.801919
3345	0	11	14	4814	2146	10	2012-01-14 06:35:47.801919	2012-01-14 06:35:47.801919
3346	6782	16	2	6782	2420	4	2012-01-14 06:36:45.44487	\N
3356	0	13	16	303	1295	16	2012-01-14 06:41:13.966456	2012-01-14 06:41:13.966456
3381	2144	19	17	2144	3584	12	2012-01-14 06:55:29.98471	\N
3371	0	6	2	3339	1557	3	2012-01-14 06:50:45.629742	2012-01-14 06:50:45.629742
3342	0	1	15	4441	4616	3	2012-01-14 06:32:48.584655	2012-01-14 06:42:53.982416
3358	0	15	10	8472	8840	9	2012-01-14 06:42:53.982416	2012-01-14 06:42:53.982416
3359	2656	9	2	2656	3161	18	2012-01-14 06:43:47.476014	\N
3360	1420	3	14	1420	4561	13	2012-01-14 06:43:58.138593	\N
3361	3627	10	2	3627	4213	4	2012-01-14 06:44:49.065845	\N
3362	7444	16	20	7444	1742	16	2012-01-14 06:45:00.528165	\N
3363	4224	1	12	4224	7389	6	2012-01-14 06:45:51.309596	\N
3364	1960	18	19	1960	9189	16	2012-01-14 06:46:12.262448	\N
3365	778	12	3	778	3199	20	2012-01-14 06:46:59.464649	\N
3394	9174	12	7	9174	6789	2	2012-01-14 07:02:53.806006	\N
3366	0	17	8	3162	1939	16	2012-01-14 06:47:11.470168	2012-01-14 06:47:11.470168
3368	1633	10	13	1633	9659	9	2012-01-14 06:47:59.331523	\N
3382	9714	4	20	9714	7818	8	2012-01-14 06:55:41.782152	\N
3374	0	12	4	2921	1030	13	2012-01-14 06:51:59.945998	2012-01-14 06:51:59.945998
3375	2322	10	9	2322	6841	14	2012-01-14 06:52:12.266798	\N
3383	2730	14	2	2730	8133	1	2012-01-14 06:56:06.002934	\N
3384	5587	11	1	5587	6671	13	2012-01-14 06:56:30.532413	\N
3385	3074	11	17	3074	5263	18	2012-01-14 06:56:54.06088	\N
3378	2456	1	12	2456	7997	19	2012-01-14 06:53:20.384039	\N
3379	1844	16	1	1844	4060	5	2012-01-14 06:53:42.736456	\N
3380	501	16	6	501	8934	2	2012-01-14 06:54:23.774063	\N
3386	0	11	10	8820	1685	13	2012-01-14 06:57:06.303194	2012-01-14 06:57:06.303194
3387	2280	19	18	2280	8366	6	2012-01-14 06:57:18.374622	\N
3372	0	13	5	6150	7795	17	2012-01-14 06:50:58.466481	2012-01-14 06:57:30.743718
3353	0	5	8	4332	5756	15	2012-01-14 06:40:13.828677	2012-01-14 06:57:30.743718
3388	0	9	13	6370	1967	17	2012-01-14 06:57:30.743718	2012-01-14 06:57:30.743718
3389	2738	10	11	2738	9369	2	2012-01-14 06:57:41.767598	\N
3395	5483	16	3	5483	5480	17	2012-01-14 07:03:17.281949	\N
3391	0	14	8	511	624	5	2012-01-14 06:59:12.659348	2012-01-14 06:59:12.659348
3392	1655	6	4	1655	5798	17	2012-01-14 06:59:25.278498	\N
3393	4884	16	11	4884	5731	14	2012-01-14 06:59:50.121205	\N
3396	8875	15	12	8875	6257	17	2012-01-14 07:04:44.841098	\N
3397	9134	15	18	9134	7318	5	2012-01-14 07:05:31.497146	\N
3398	0	2	1	6388	1990	5	2012-01-14 07:06:45.484923	2012-01-14 07:06:45.484923
3399	1090	14	1	1090	6259	19	2012-01-14 07:06:57.301745	\N
3400	3755	9	12	3755	6433	14	2012-01-14 07:07:20.744466	\N
3321	0	13	17	6062	7086	14	2012-01-14 06:17:36.124523	2012-01-14 07:08:27.572635
3402	0	17	4	7200	58	3	2012-01-14 07:08:27.572635	2012-01-14 07:08:27.572635
3403	411	14	3	2629	6594	3	2012-01-14 07:08:39.629921	2012-01-14 07:09:17.219283
3404	3728	15	2	5721	4120	4	2012-01-14 07:09:17.219283	2012-01-14 07:09:17.219283
3406	8917	16	7	8917	2742	11	2012-01-14 07:10:20.029697	\N
\.


--
-- Data for Name: towner; Type: TABLE DATA; Schema: t; Owner: olivier
--

COPY towner (id, name, created, updated) FROM stdin;
1	w17	2012-01-13 20:24:49.90166	\N
2	w9	2012-01-13 20:24:49.9351	\N
3	w19	2012-01-13 20:24:49.946362	\N
4	w6	2012-01-13 20:24:49.957579	\N
5	w7	2012-01-13 20:24:49.968886	\N
6	w3	2012-01-13 20:24:49.991001	\N
7	w10	2012-01-13 20:24:50.002203	\N
8	w1	2012-01-13 20:24:50.013403	\N
9	w18	2012-01-13 20:24:50.046717	\N
10	w4	2012-01-13 20:24:50.102948	\N
11	w2	2012-01-13 20:24:50.11391	\N
12	w13	2012-01-13 20:24:50.180927	\N
13	w5	2012-01-13 20:24:50.191928	\N
14	w11	2012-01-13 20:24:50.225446	\N
15	w8	2012-01-13 20:24:50.236764	\N
16	w12	2012-01-13 20:24:50.325892	\N
17	w14	2012-01-13 20:24:50.426647	\N
18	w15	2012-01-13 20:24:50.472399	\N
19	w20	2012-01-13 20:24:50.504917	\N
20	w16	2012-01-13 20:24:50.618126	\N
\.


--
-- Data for Name: tquality; Type: TABLE DATA; Schema: t; Owner: olivier
--

COPY tquality (id, name, idd, depository, qtt, created, updated) FROM stdin;
7	olivier/q17	1	olivier	873846	2012-01-13 20:24:49.957579	2012-01-14 07:10:20.029697
16	olivier/q3	1	olivier	182043	2012-01-13 20:24:50.180927	2012-01-14 07:10:20.029697
20	olivier/q2	1	olivier	492197	2012-01-13 20:24:50.460243	2012-01-14 06:55:41.782152
19	olivier/q4	1	olivier	758285	2012-01-13 20:24:50.393354	2012-01-14 06:57:18.374622
10	olivier/q20	1	olivier	500626	2012-01-13 20:24:49.991001	2012-01-14 06:57:41.767598
8	olivier/q19	1	olivier	658688	2012-01-13 20:24:49.957579	2012-01-14 06:59:12.659348
11	olivier/q5	1	olivier	767335	2012-01-13 20:24:50.035638	2012-01-14 06:59:50.121205
18	olivier/q9	1	olivier	579755	2012-01-13 20:24:50.325892	2012-01-14 07:05:31.497146
1	olivier/q6	1	olivier	718592	2012-01-13 20:24:49.90166	2012-01-14 07:06:57.301745
5	olivier/q16	1	olivier	725344	2012-01-13 20:24:49.946362	2012-01-14 06:50:58.466481
12	olivier/q7	1	olivier	682190	2012-01-13 20:24:50.035638	2012-01-14 07:07:20.744466
9	olivier/q14	1	olivier	570495	2012-01-13 20:24:49.968886	2012-01-14 07:07:20.744466
4	olivier/q12	1	olivier	641686	2012-01-13 20:24:49.9351	2012-01-14 07:08:27.572635
17	olivier/q1	1	olivier	732442	2012-01-13 20:24:50.236764	2012-01-14 07:08:27.572635
3	olivier/q10	1	olivier	348196	2012-01-13 20:24:49.9351	2012-01-14 07:08:39.629921
14	olivier/q8	1	olivier	775262	2012-01-13 20:24:50.136091	2012-01-14 07:08:39.629921
2	olivier/q11	1	olivier	665028	2012-01-13 20:24:49.90166	2012-01-14 07:09:17.219283
15	olivier/q18	1	olivier	664199	2012-01-13 20:24:50.147281	2012-01-14 07:09:17.219283
6	olivier/q13	1	olivier	934607	2012-01-13 20:24:49.946362	2012-01-14 07:09:54.983806
13	olivier/q15	1	olivier	757202	2012-01-13 20:24:50.069227	2012-01-14 07:09:54.983806
\.


--
-- Data for Name: trefused; Type: TABLE DATA; Schema: t; Owner: olivier
--

COPY trefused (x, y, created) FROM stdin;
16	4	2012-01-13 20:24:50.11391
57	59	2012-01-13 20:24:50.674017
62	11	2012-01-13 20:24:50.718613
40	49	2012-01-13 20:24:50.80784
69	65	2012-01-13 20:24:50.841069
50	18	2012-01-13 20:24:50.88558
50	78	2012-01-13 20:24:50.997171
43	82	2012-01-13 20:24:51.064248
47	60	2012-01-13 20:24:51.064248
47	85	2012-01-13 20:24:51.097676
87	53	2012-01-13 20:24:51.141962
271	430	2012-01-13 20:25:55.542392
87	34	2012-01-13 20:24:51.141962
87	44	2012-01-13 20:24:51.141962
36	89	2012-01-13 20:24:51.186636
91	1	2012-01-13 20:24:51.220091
91	76	2012-01-13 20:24:51.220091
40	46	2012-01-13 20:24:51.509503
12	111	2012-01-13 20:24:51.598601
84	111	2012-01-13 20:24:51.631912
90	107	2012-01-13 20:24:51.665529
62	76	2012-01-13 20:24:51.756474
120	12	2012-01-13 20:24:51.787534
106	123	2012-01-13 20:24:51.84324
124	13	2012-01-13 20:24:51.878609
166	580	2012-01-13 20:26:55.605378
124	18	2012-01-13 20:24:51.922951
128	92	2012-01-13 20:24:51.967165
113	131	2012-01-13 20:24:52.03415
12	435	2012-01-13 20:25:56.00765
12	135	2012-01-13 20:24:52.123111
1199	968	2012-01-13 20:49:48.532262
106	137	2012-01-13 20:24:52.178584
432	435	2012-01-13 20:25:56.00765
109	18	2012-01-13 20:24:52.245554
68	77	2012-01-13 20:24:52.312186
151	112	2012-01-13 20:24:52.445701
136	152	2012-01-13 20:24:52.468013
151	77	2012-01-13 20:24:52.97711
109	155	2012-01-13 20:24:52.998596
79	160	2012-01-13 20:24:53.109777
55	160	2012-01-13 20:24:53.109777
73	161	2012-01-13 20:24:53.131904
121	140	2012-01-13 20:24:53.232101
52	160	2012-01-13 20:24:53.232101
151	169	2012-01-13 20:24:53.309988
104	160	2012-01-13 20:24:53.309988
170	140	2012-01-13 20:24:53.343223
374	435	2012-01-13 20:25:56.00765
102	160	2012-01-13 20:24:54.493129
180	168	2012-01-13 20:24:54.493129
82	183	2012-01-13 20:24:55.03493
140	55	2012-01-13 20:24:55.03493
144	180	2012-01-13 20:24:55.323135
106	186	2012-01-13 20:24:55.356705
183	139	2012-01-13 20:24:55.423533
110	183	2012-01-13 20:24:55.423533
356	435	2012-01-13 20:25:56.680877
187	436	2012-01-13 20:25:56.680877
113	189	2012-01-13 20:24:55.66931
38	160	2012-01-13 20:24:55.66931
191	165	2012-01-13 20:24:55.714208
113	194	2012-01-13 20:24:55.769845
421	422	2012-01-13 20:25:56.680877
40	140	2012-01-13 20:24:56.500398
121	202	2012-01-13 20:24:56.522567
119	30	2012-01-13 20:24:56.522567
170	202	2012-01-13 20:24:56.522567
109	188	2012-01-13 20:24:56.655908
40	202	2012-01-13 20:24:56.69947
186	202	2012-01-13 20:24:56.69947
204	139	2012-01-13 20:24:56.69947
204	105	2012-01-13 20:24:56.69947
204	123	2012-01-13 20:24:56.69947
584	543	2012-01-13 20:26:55.971255
205	123	2012-01-13 20:24:56.943951
109	206	2012-01-13 20:24:56.986864
209	202	2012-01-13 20:24:57.097913
191	206	2012-01-13 20:24:57.097913
210	135	2012-01-13 20:24:57.353194
170	212	2012-01-13 20:24:57.606082
214	160	2012-01-13 20:24:57.705841
402	299	2012-01-13 20:25:56.680877
215	168	2012-01-13 20:24:57.838795
215	179	2012-01-13 20:24:57.838795
216	134	2012-01-13 20:24:57.883109
216	181	2012-01-13 20:24:57.883109
181	119	2012-01-13 20:24:57.883109
216	217	2012-01-13 20:24:57.938455
215	218	2012-01-13 20:24:57.960501
109	220	2012-01-13 20:24:58.280882
205	139	2012-01-13 20:24:58.280882
220	131	2012-01-13 20:24:58.280882
189	202	2012-01-13 20:24:58.280882
319	438	2012-01-13 20:25:57.618307
216	223	2012-01-13 20:24:58.657279
154	215	2012-01-13 20:24:59.099196
1224	712	2012-01-13 20:49:48.532262
186	178	2012-01-13 20:24:59.5311
231	236	2012-01-13 20:24:59.62002
73	236	2012-01-13 20:24:59.886139
531	460	2012-01-13 20:26:56.180609
238	105	2012-01-13 20:25:00.05132
239	18	2012-01-13 20:25:00.128555
202	240	2012-01-13 20:25:00.216932
241	73	2012-01-13 20:25:00.283555
440	419	2012-01-13 20:25:58.083234
26	236	2012-01-13 20:25:00.935613
233	139	2012-01-13 20:25:00.935613
189	246	2012-01-13 20:25:01.046513
42	236	2012-01-13 20:25:01.112818
441	435	2012-01-13 20:25:58.25983
144	250	2012-01-13 20:25:01.333941
144	252	2012-01-13 20:25:01.435324
113	253	2012-01-13 20:25:01.479708
249	30	2012-01-13 20:25:02.408217
237	139	2012-01-13 20:25:02.662852
444	586	2012-01-13 20:26:56.481582
212	259	2012-01-13 20:25:02.662852
212	261	2012-01-13 20:25:02.916909
327	569	2012-01-13 20:26:56.481582
264	189	2012-01-13 20:25:03.139226
264	266	2012-01-13 20:25:03.215546
40	587	2012-01-13 20:26:56.746826
46	268	2012-01-13 20:25:03.315542
144	441	2012-01-13 20:25:58.25983
68	269	2012-01-13 20:25:03.381918
151	269	2012-01-13 20:25:03.381918
275	162	2012-01-13 20:25:04.067807
464	587	2012-01-13 20:26:56.746826
279	18	2012-01-13 20:25:04.344413
279	142	2012-01-13 20:25:04.344413
444	213	2012-01-13 20:25:58.912178
249	444	2012-01-13 20:25:58.912178
444	218	2012-01-13 20:25:59.265901
40	212	2012-01-13 20:25:04.599367
280	105	2012-01-13 20:25:04.599367
280	139	2012-01-13 20:25:04.599367
280	265	2012-01-13 20:25:04.599367
445	414	2012-01-13 20:25:59.265901
588	543	2012-01-13 20:26:57.055778
200	110	2012-01-13 20:25:05.548304
186	246	2012-01-13 20:25:05.548304
447	415	2012-01-13 20:25:59.696429
151	30	2012-01-13 20:25:06.057094
286	280	2012-01-13 20:25:06.211918
154	588	2012-01-13 20:26:57.055778
269	250	2012-01-13 20:25:06.35563
287	30	2012-01-13 20:25:06.35563
300	588	2012-01-13 20:26:57.055778
269	22	2012-01-13 20:25:06.35563
982	1224	2012-01-13 20:49:48.532262
441	426	2012-01-13 20:25:59.696429
15	189	2012-01-13 20:25:08.378123
77	240	2012-01-13 20:25:08.378123
546	588	2012-01-13 20:26:57.055778
48	295	2012-01-13 20:25:08.378123
136	296	2012-01-13 20:25:08.948451
285	245	2012-01-13 20:25:09.062947
402	448	2012-01-13 20:26:01.003013
298	240	2012-01-13 20:25:09.173886
151	298	2012-01-13 20:25:09.173886
68	298	2012-01-13 20:25:09.173886
899	698	2012-01-13 20:31:58.539322
435	446	2012-01-13 20:26:01.301248
249	269	2012-01-13 20:25:14.577425
237	308	2012-01-13 20:25:14.697089
280	308	2012-01-13 20:25:14.697089
233	308	2012-01-13 20:25:14.697089
200	309	2012-01-13 20:25:14.874942
369	574	2012-01-13 20:26:57.055778
278	310	2012-01-13 20:25:15.173774
310	202	2012-01-13 20:25:15.173774
310	246	2012-01-13 20:25:15.173774
402	44	2012-01-13 20:26:01.301248
239	310	2012-01-13 20:25:15.173774
414	450	2012-01-13 20:26:01.785059
239	311	2012-01-13 20:25:15.747712
278	311	2012-01-13 20:25:15.747712
82	283	2012-01-13 20:25:15.747712
447	402	2012-01-13 20:26:01.785059
264	312	2012-01-13 20:25:15.891305
450	447	2012-01-13 20:26:02.957449
287	19	2012-01-13 20:25:15.891305
98	312	2012-01-13 20:25:15.891305
216	315	2012-01-13 20:25:16.730533
359	356	2012-01-13 20:26:03.156406
318	136	2012-01-13 20:25:16.962794
186	319	2012-01-13 20:25:17.084535
592	213	2012-01-13 20:26:59.849931
154	592	2012-01-13 20:26:59.849931
121	319	2012-01-13 20:25:17.084535
283	297	2012-01-13 20:25:17.084535
40	319	2012-01-13 20:25:17.084535
454	341	2012-01-13 20:26:03.156406
283	200	2012-01-13 20:25:18.233537
447	391	2012-01-13 20:26:04.10921
278	79	2012-01-13 20:25:18.357631
297	323	2012-01-13 20:25:18.357631
268	323	2012-01-13 20:25:18.578293
264	324	2012-01-13 20:25:18.578293
165	418	2012-01-13 20:26:04.10921
444	379	2012-01-13 20:26:04.10921
106	308	2012-01-13 20:25:18.578293
326	162	2012-01-13 20:25:19.04237
318	240	2012-01-13 20:25:19.04237
303	159	2012-01-13 20:25:19.142275
241	283	2012-01-13 20:25:19.142275
328	143	2012-01-13 20:25:19.263657
330	19	2012-01-13 20:25:19.716155
272	356	2012-01-13 20:26:04.649435
456	291	2012-01-13 20:26:04.649435
419	441	2012-01-13 20:26:04.649435
176	335	2012-01-13 20:25:20.457236
457	449	2012-01-13 20:26:05.20078
187	335	2012-01-13 20:25:20.457236
592	251	2012-01-13 20:26:59.849931
201	265	2012-01-13 20:25:20.690134
200	335	2012-01-13 20:25:20.811023
336	328	2012-01-13 20:25:20.811023
337	283	2012-01-13 20:25:20.811023
68	337	2012-01-13 20:25:20.811023
438	416	2012-01-13 20:26:05.20078
819	696	2012-01-13 20:31:58.539322
144	328	2012-01-13 20:25:21.187488
328	339	2012-01-13 20:25:21.253067
592	334	2012-01-13 20:26:59.849931
278	340	2012-01-13 20:25:21.441162
191	340	2012-01-13 20:25:21.441162
218	341	2012-01-13 20:25:21.651041
159	341	2012-01-13 20:25:21.651041
237	342	2012-01-13 20:25:21.817145
106	342	2012-01-13 20:25:21.817145
460	435	2012-01-13 20:26:06.504313
300	592	2012-01-13 20:26:59.849931
414	444	2012-01-13 20:26:06.504313
347	341	2012-01-13 20:25:23.441294
461	213	2012-01-13 20:26:07.012761
455	594	2012-01-13 20:27:01.374142
350	464	2012-01-13 20:26:07.442738
350	341	2012-01-13 20:25:24.225984
583	595	2012-01-13 20:27:01.739781
356	466	2012-01-13 20:26:08.226983
216	351	2012-01-13 20:25:24.524966
596	468	2012-01-13 20:27:01.927376
350	467	2012-01-13 20:26:08.515129
352	324	2012-01-13 20:25:24.679348
239	340	2012-01-13 20:25:24.679348
351	595	2012-01-13 20:27:01.927376
163	340	2012-01-13 20:25:25.088845
596	351	2012-01-13 20:27:01.927376
216	468	2012-01-13 20:26:08.993884
355	101	2012-01-13 20:25:25.905984
444	470	2012-01-13 20:26:09.784958
202	355	2012-01-13 20:25:25.905984
318	355	2012-01-13 20:25:25.905984
1144	1208	2012-01-13 20:49:48.532262
461	470	2012-01-13 20:26:09.784958
444	179	2012-01-13 20:26:10.205771
300	471	2012-01-13 20:26:10.205771
298	204	2012-01-13 20:25:28.590079
360	218	2012-01-13 20:25:28.799978
360	143	2012-01-13 20:25:28.799978
360	168	2012-01-13 20:25:28.799978
361	101	2012-01-13 20:25:29.364368
597	580	2012-01-13 20:27:02.579728
136	363	2012-01-13 20:25:29.871271
360	179	2012-01-13 20:25:30.070189
472	402	2012-01-13 20:26:10.724954
410	391	2012-01-13 20:26:11.133413
369	268	2012-01-13 20:25:31.694716
474	341	2012-01-13 20:26:11.133413
557	154	2012-01-13 20:27:02.579728
375	341	2012-01-13 20:25:34.668473
328	376	2012-01-13 20:25:34.843733
216	480	2012-01-13 20:26:13.697
165	234	2012-01-13 20:26:13.697
144	402	2012-01-13 20:26:13.697
410	402	2012-01-13 20:26:13.697
377	356	2012-01-13 20:25:35.120918
328	379	2012-01-13 20:25:35.837319
300	597	2012-01-13 20:27:02.579728
224	362	2012-01-13 20:25:35.837319
179	380	2012-01-13 20:25:36.364394
574	26	2012-01-13 20:27:04.301701
218	381	2012-01-13 20:25:36.61131
26	362	2012-01-13 20:25:36.765973
480	587	2012-01-13 20:27:04.301701
384	368	2012-01-13 20:25:37.395187
410	602	2012-01-13 20:27:05.639036
375	381	2012-01-13 20:25:37.716988
350	386	2012-01-13 20:25:37.882085
386	101	2012-01-13 20:25:37.882085
359	450	2012-01-13 20:26:14.704783
328	218	2012-01-13 20:25:37.882085
234	481	2012-01-13 20:26:14.704783
388	341	2012-01-13 20:25:39.682393
388	381	2012-01-13 20:25:39.682393
350	443	2012-01-13 20:26:14.704783
388	12	2012-01-13 20:25:39.682393
433	485	2012-01-13 20:26:17.010159
434	485	2012-01-13 20:26:17.010159
12	390	2012-01-13 20:25:40.323873
371	362	2012-01-13 20:25:40.323873
336	391	2012-01-13 20:25:40.544705
393	486	2012-01-13 20:26:17.630109
461	218	2012-01-13 20:26:17.950008
19	148	2012-01-13 20:25:41.059107
350	487	2012-01-13 20:26:17.950008
489	440	2012-01-13 20:26:18.403152
359	77	2012-01-13 20:25:41.828135
352	148	2012-01-13 20:25:42.038561
359	19	2012-01-13 20:25:42.137754
557	602	2012-01-13 20:27:05.639036
354	399	2012-01-13 20:25:42.237515
363	240	2012-01-13 20:25:42.237515
369	399	2012-01-13 20:25:42.237515
398	139	2012-01-13 20:25:42.635867
400	339	2012-01-13 20:25:42.635867
440	134	2012-01-13 20:26:18.690097
402	351	2012-01-13 20:25:43.485398
237	404	2012-01-13 20:25:44.866441
216	299	2012-01-13 20:25:45.552604
406	148	2012-01-13 20:25:45.71751
324	399	2012-01-13 20:25:45.71751
877	900	2012-01-13 20:32:00.714857
364	406	2012-01-13 20:25:45.71751
371	406	2012-01-13 20:25:45.71751
440	315	2012-01-13 20:26:18.690097
406	194	2012-01-13 20:25:46.481537
409	341	2012-01-13 20:25:47.352319
82	409	2012-01-13 20:25:47.352319
490	187	2012-01-13 20:26:18.690097
412	143	2012-01-13 20:25:48.236938
412	379	2012-01-13 20:25:48.236938
412	179	2012-01-13 20:25:48.236938
412	339	2012-01-13 20:25:48.236938
300	490	2012-01-13 20:26:18.690097
402	163	2012-01-13 20:25:49.321705
414	337	2012-01-13 20:25:49.473838
204	342	2012-01-13 20:25:49.473838
410	415	2012-01-13 20:25:49.783471
144	415	2012-01-13 20:25:49.783471
40	416	2012-01-13 20:25:50.159602
284	490	2012-01-13 20:26:18.690097
491	157	2012-01-13 20:26:19.6324
149	416	2012-01-13 20:25:50.159602
410	284	2012-01-13 20:26:19.982601
416	18	2012-01-13 20:25:50.159602
900	463	2012-01-13 20:32:00.714857
434	493	2012-01-13 20:26:20.237003
363	418	2012-01-13 20:25:51.518088
419	402	2012-01-13 20:25:51.628678
216	419	2012-01-13 20:25:51.628678
234	420	2012-01-13 20:25:51.849554
421	245	2012-01-13 20:25:51.993038
402	134	2012-01-13 20:25:52.125733
402	315	2012-01-13 20:25:52.125733
402	302	2012-01-13 20:25:52.125733
436	493	2012-01-13 20:26:20.237003
413	425	2012-01-13 20:25:52.811065
350	494	2012-01-13 20:26:20.779675
293	494	2012-01-13 20:26:20.779675
214	425	2012-01-13 20:25:52.811065
414	356	2012-01-13 20:25:53.419586
374	426	2012-01-13 20:25:53.419586
306	427	2012-01-13 20:25:53.62875
495	251	2012-01-13 20:26:20.966066
427	418	2012-01-13 20:25:53.62875
419	495	2012-01-13 20:26:20.966066
495	179	2012-01-13 20:26:20.966066
306	431	2012-01-13 20:25:54.711783
430	425	2012-01-13 20:25:54.711783
432	426	2012-01-13 20:25:54.92227
472	495	2012-01-13 20:26:20.966066
306	433	2012-01-13 20:25:55.209868
495	427	2012-01-13 20:26:20.966066
40	187	2012-01-13 20:25:55.209868
497	481	2012-01-13 20:26:21.772045
40	497	2012-01-13 20:26:21.772045
359	498	2012-01-13 20:26:21.955232
1896	1870	2012-01-13 22:19:21.600848
410	495	2012-01-13 20:26:21.955232
154	901	2012-01-13 20:32:02.348422
1122	1226	2012-01-13 20:50:04.666399
144	440	2012-01-13 20:26:22.369715
359	444	2012-01-13 20:26:22.369715
278	846	2012-01-13 20:32:04.103023
557	606	2012-01-13 20:27:08.126319
175	501	2012-01-13 20:26:22.977284
472	157	2012-01-13 20:26:22.977284
462	501	2012-01-13 20:26:22.977284
904	817	2012-01-13 20:32:07.104794
495	218	2012-01-13 20:26:23.408801
410	606	2012-01-13 20:27:08.126319
218	502	2012-01-13 20:26:23.408801
904	900	2012-01-13 20:32:07.104794
495	249	2012-01-13 20:26:24.072818
1161	1226	2012-01-13 20:50:04.666399
468	505	2012-01-13 20:26:24.401936
502	505	2012-01-13 20:26:24.401936
595	607	2012-01-13 20:27:09.200037
480	506	2012-01-13 20:26:24.855913
40	506	2012-01-13 20:26:24.855913
350	507	2012-01-13 20:26:25.131563
136	505	2012-01-13 20:26:25.131563
337	607	2012-01-13 20:27:09.200037
83	607	2012-01-13 20:27:09.200037
284	509	2012-01-13 20:26:25.706154
513	505	2012-01-13 20:26:27.484337
580	608	2012-01-13 20:27:09.638584
359	503	2012-01-13 20:26:27.484337
144	495	2012-01-13 20:26:27.484337
487	513	2012-01-13 20:26:27.484337
300	609	2012-01-13 20:27:09.837167
1228	631	2012-01-13 20:50:10.122462
359	514	2012-01-13 20:26:28.227661
546	609	2012-01-13 20:27:09.837167
68	514	2012-01-13 20:26:28.227661
1181	1027	2012-01-13 20:50:11.637793
350	515	2012-01-13 20:26:28.700817
293	517	2012-01-13 20:26:28.854551
609	580	2012-01-13 20:27:09.837167
15	519	2012-01-13 20:26:29.319404
359	570	2012-01-13 20:27:09.837167
144	520	2012-01-13 20:26:29.618398
520	505	2012-01-13 20:26:29.618398
639	904	2012-01-13 20:32:07.104794
337	610	2012-01-13 20:27:10.799209
557	611	2012-01-13 20:27:11.350734
427	521	2012-01-13 20:26:30.214922
393	434	2012-01-13 20:26:30.503365
410	157	2012-01-13 20:26:30.503365
40	523	2012-01-13 20:26:30.702262
887	905	2012-01-13 20:32:11.077612
272	570	2012-01-13 20:27:11.350734
154	613	2012-01-13 20:27:12.190184
546	613	2012-01-13 20:27:12.190184
1896	1702	2012-01-13 22:19:21.600848
982	1230	2012-01-13 20:50:13.217246
1897	1711	2012-01-13 22:19:34.404559
40	525	2012-01-13 20:26:31.321923
525	434	2012-01-13 20:26:31.321923
596	608	2012-01-13 20:27:12.610463
413	526	2012-01-13 20:26:31.97472
144	1898	2012-01-13 22:19:41.660954
470	547	2012-01-13 20:27:13.073847
522	528	2012-01-13 20:26:32.94461
176	505	2012-01-13 20:26:32.94461
472	531	2012-01-13 20:26:34.590877
531	251	2012-01-13 20:26:34.590877
144	531	2012-01-13 20:26:34.590877
359	532	2012-01-13 20:26:35.227057
300	533	2012-01-13 20:26:35.364327
284	533	2012-01-13 20:26:35.364327
389	533	2012-01-13 20:26:35.364327
617	522	2012-01-13 20:27:13.550268
12	618	2012-01-13 20:27:13.725915
596	291	2012-01-13 20:27:14.082147
619	543	2012-01-13 20:27:14.082147
354	619	2012-01-13 20:27:14.511477
535	519	2012-01-13 20:26:35.927924
635	908	2012-01-13 20:32:16.317894
271	535	2012-01-13 20:26:35.927924
389	536	2012-01-13 20:26:36.704061
994	1086	2012-01-13 20:50:13.217246
337	538	2012-01-13 20:26:36.855695
293	487	2012-01-13 20:27:14.846835
410	531	2012-01-13 20:26:37.420051
249	503	2012-01-13 20:26:37.420051
26	542	2012-01-13 20:26:37.630144
1181	1230	2012-01-13 20:50:20.655722
371	542	2012-01-13 20:26:37.630144
542	444	2012-01-13 20:26:37.630144
176	543	2012-01-13 20:26:38.449933
520	543	2012-01-13 20:26:38.449933
513	543	2012-01-13 20:26:38.449933
545	468	2012-01-13 20:26:38.978074
546	536	2012-01-13 20:26:39.165498
150	546	2012-01-13 20:26:39.165498
548	543	2012-01-13 20:26:39.430458
40	548	2012-01-13 20:26:39.430458
576	594	2012-01-13 20:27:14.846835
622	337	2012-01-13 20:27:15.36623
622	570	2012-01-13 20:27:15.36623
550	548	2012-01-13 20:26:40.247963
444	460	2012-01-13 20:27:15.36623
1194	1167	2012-01-13 20:50:20.655722
551	389	2012-01-13 20:26:40.625146
622	444	2012-01-13 20:27:15.36623
564	911	2012-01-13 20:32:20.586325
300	622	2012-01-13 20:27:15.36623
385	552	2012-01-13 20:26:40.778912
317	552	2012-01-13 20:26:40.778912
912	139	2012-01-13 20:32:22.087351
176	553	2012-01-13 20:26:41.51072
912	265	2012-01-13 20:32:22.087351
1231	773	2012-01-13 20:50:20.655722
545	351	2012-01-13 20:26:42.039073
213	538	2012-01-13 20:26:42.171179
557	531	2012-01-13 20:26:42.171179
557	157	2012-01-13 20:26:42.171179
176	558	2012-01-13 20:26:42.746415
468	558	2012-01-13 20:26:42.746415
444	560	2012-01-13 20:26:43.717375
531	560	2012-01-13 20:26:43.717375
513	558	2012-01-13 20:26:44.083296
337	481	2012-01-13 20:26:44.083296
562	467	2012-01-13 20:26:44.425577
562	487	2012-01-13 20:26:44.425577
562	494	2012-01-13 20:26:44.425577
487	519	2012-01-13 20:26:44.425577
318	563	2012-01-13 20:26:44.835147
439	619	2012-01-13 20:27:16.913832
369	561	2012-01-13 20:26:45.088549
565	519	2012-01-13 20:26:45.320227
1865	1901	2012-01-13 22:19:56.217468
513	553	2012-01-13 20:26:45.320227
557	565	2012-01-13 20:26:45.320227
557	624	2012-01-13 20:27:17.354319
410	624	2012-01-13 20:27:17.354319
625	621	2012-01-13 20:27:17.75135
144	565	2012-01-13 20:26:45.320227
625	626	2012-01-13 20:27:17.940949
566	531	2012-01-13 20:26:48.924462
286	567	2012-01-13 20:26:49.274485
371	567	2012-01-13 20:26:49.274485
224	567	2012-01-13 20:26:49.274485
557	568	2012-01-13 20:26:50.801543
462	569	2012-01-13 20:26:51.141382
569	519	2012-01-13 20:26:51.141382
531	249	2012-01-13 20:26:51.373511
628	468	2012-01-13 20:27:18.371529
628	177	2012-01-13 20:27:18.371529
272	514	2012-01-13 20:27:18.371529
531	586	2012-01-13 20:27:19.122869
157	630	2012-01-13 20:27:19.122869
535	541	2012-01-13 20:26:51.958648
914	796	2012-01-13 20:32:24.978917
444	631	2012-01-13 20:27:19.610568
574	439	2012-01-13 20:26:52.334326
410	520	2012-01-13 20:26:53.074279
634	528	2012-01-13 20:27:20.316835
628	291	2012-01-13 20:27:20.316835
635	467	2012-01-13 20:27:20.725934
300	579	2012-01-13 20:26:54.179162
154	579	2012-01-13 20:26:54.179162
914	751	2012-01-13 20:32:24.978917
531	213	2012-01-13 20:26:54.179162
546	579	2012-01-13 20:26:54.179162
580	468	2012-01-13 20:26:54.788619
580	351	2012-01-13 20:26:54.788619
26	580	2012-01-13 20:26:54.788619
300	581	2012-01-13 20:26:55.307155
546	581	2012-01-13 20:26:55.307155
635	12	2012-01-13 20:27:20.725934
12	528	2012-01-13 20:27:20.725934
552	630	2012-01-13 20:27:21.71967
847	908	2012-01-13 20:32:26.383426
625	541	2012-01-13 20:27:22.11801
638	619	2012-01-13 20:27:22.11801
615	541	2012-01-13 20:27:22.11801
639	468	2012-01-13 20:27:22.660397
639	291	2012-01-13 20:27:22.660397
639	293	2012-01-13 20:27:23.101123
464	641	2012-01-13 20:27:23.310665
641	619	2012-01-13 20:27:23.310665
642	581	2012-01-13 20:27:23.675529
592	470	2012-01-13 20:27:23.675529
2924	3290	2012-01-14 06:03:03.040166
642	592	2012-01-13 20:27:23.675529
592	586	2012-01-13 20:27:23.675529
676	865	2012-01-13 20:32:27.299923
207	630	2012-01-13 20:27:23.675529
857	761	2012-01-13 20:32:28.856621
557	643	2012-01-13 20:27:25.756329
410	643	2012-01-13 20:27:25.756329
369	619	2012-01-13 20:27:25.756329
617	630	2012-01-13 20:27:25.756329
644	628	2012-01-13 20:27:26.627213
272	337	2012-01-13 20:27:26.627213
912	761	2012-01-13 20:32:28.856621
851	920	2012-01-13 20:32:32.510957
177	645	2012-01-13 20:27:27.177657
237	645	2012-01-13 20:27:27.177657
921	865	2012-01-13 20:32:33.297074
144	648	2012-01-13 20:27:28.645509
546	649	2012-01-13 20:27:29.409865
642	649	2012-01-13 20:27:29.409865
83	651	2012-01-13 20:27:29.960862
464	652	2012-01-13 20:27:30.115446
653	528	2012-01-13 20:27:30.502679
635	653	2012-01-13 20:27:30.502679
642	655	2012-01-13 20:27:31.099204
546	655	2012-01-13 20:27:31.099204
1903	1600	2012-01-13 22:20:09.782261
656	607	2012-01-13 20:27:31.629665
470	628	2012-01-13 20:27:31.83916
657	586	2012-01-13 20:27:31.83916
1903	1864	2012-01-13 22:20:09.782261
657	460	2012-01-13 20:27:31.83916
658	503	2012-01-13 20:27:32.802319
639	658	2012-01-13 20:27:32.802319
166	659	2012-01-13 20:27:33.220289
337	651	2012-01-13 20:27:33.220289
431	660	2012-01-13 20:27:33.739715
658	478	2012-01-13 20:27:34.159468
680	890	2012-01-13 20:32:33.297074
663	659	2012-01-13 20:27:35.009743
922	761	2012-01-13 20:32:36.51549
1233	1030	2012-01-13 20:50:36.996007
1233	792	2012-01-13 20:50:36.996007
664	619	2012-01-13 20:27:35.885473
1233	975	2012-01-13 20:50:36.996007
1782	3291	2012-01-14 06:03:26.185719
924	817	2012-01-13 20:32:39.382656
1048	1236	2012-01-13 20:50:47.445854
666	659	2012-01-13 20:27:36.98878
843	761	2012-01-13 20:32:39.382656
154	649	2012-01-13 20:27:36.98878
623	925	2012-01-13 20:32:42.203439
499	666	2012-01-13 20:27:36.98878
667	503	2012-01-13 20:27:37.806981
669	460	2012-01-13 20:27:38.313007
669	431	2012-01-13 20:27:38.313007
670	528	2012-01-13 20:27:38.822509
669	251	2012-01-13 20:27:38.822509
669	433	2012-01-13 20:27:38.822509
585	659	2012-01-13 20:27:38.822509
546	670	2012-01-13 20:27:38.822509
433	672	2012-01-13 20:27:39.947963
662	925	2012-01-13 20:32:42.203439
237	672	2012-01-13 20:27:39.947963
926	817	2012-01-13 20:32:43.492864
674	503	2012-01-13 20:27:40.920161
663	674	2012-01-13 20:27:40.920161
846	667	2012-01-13 20:32:44.253835
675	674	2012-01-13 20:27:41.451246
676	467	2012-01-13 20:27:41.982167
166	677	2012-01-13 20:27:42.246088
608	677	2012-01-13 20:27:42.246088
664	634	2012-01-13 20:27:42.246088
1001	1236	2012-01-13 20:50:47.445854
619	678	2012-01-13 20:27:43.153128
249	680	2012-01-13 20:27:43.947982
673	664	2012-01-13 20:27:44.190343
674	514	2012-01-13 20:27:44.522184
556	682	2012-01-13 20:27:44.522184
930	693	2012-01-13 20:32:48.262847
685	207	2012-01-13 20:27:45.726074
931	623	2012-01-13 20:32:49.666772
1181	901	2012-01-13 20:50:51.753479
667	680	2012-01-13 20:27:47.09604
640	1205	2012-01-13 20:50:51.753479
689	672	2012-01-13 20:27:47.738811
933	492	2012-01-13 20:32:54.446808
585	690	2012-01-13 20:27:48.2796
615	935	2012-01-13 20:32:57.794192
462	685	2012-01-13 20:27:49.768799
692	672	2012-01-13 20:27:49.768799
693	468	2012-01-13 20:27:50.223249
908	935	2012-01-13 20:32:57.794192
177	672	2012-01-13 20:27:50.223249
144	693	2012-01-13 20:27:50.223249
619	696	2012-01-13 20:27:53.082703
635	698	2012-01-13 20:27:53.394368
676	698	2012-01-13 20:27:53.394368
700	467	2012-01-13 20:27:54.520991
936	677	2012-01-13 20:32:59.166732
1811	1903	2012-01-13 22:20:09.782261
149	700	2012-01-13 20:27:54.520991
685	174	2012-01-13 20:27:54.520991
136	696	2012-01-13 20:27:55.782609
556	702	2012-01-13 20:27:55.782609
525	703	2012-01-13 20:27:56.368084
640	936	2012-01-13 20:32:59.166732
692	704	2012-01-13 20:27:56.964651
174	704	2012-01-13 20:27:56.964651
369	916	2012-01-13 20:50:57.226198
410	905	2012-01-13 20:32:59.166732
705	704	2012-01-13 20:27:58.159689
271	706	2012-01-13 20:27:58.47749
410	707	2012-01-13 20:27:58.786823
144	707	2012-01-13 20:27:58.786823
708	481	2012-01-13 20:27:59.550707
709	704	2012-01-13 20:27:59.847268
572	796	2012-01-13 20:32:59.166732
154	710	2012-01-13 20:28:01.197385
431	706	2012-01-13 20:28:01.197385
546	710	2012-01-13 20:28:01.197385
938	854	2012-01-13 20:33:07.822687
770	938	2012-01-13 20:33:07.822687
926	939	2012-01-13 20:33:09.460777
877	939	2012-01-13 20:33:09.460777
924	939	2012-01-13 20:33:09.460777
176	639	2012-01-13 20:28:01.197385
625	711	2012-01-13 20:28:03.406616
711	698	2012-01-13 20:28:03.406616
98	711	2012-01-13 20:28:03.406616
361	711	2012-01-13 20:28:03.406616
926	623	2012-01-13 20:33:12.507874
887	693	2012-01-13 20:33:13.347209
942	696	2012-01-13 20:33:13.347209
933	943	2012-01-13 20:33:14.640107
639	712	2012-01-13 20:28:05.883179
154	943	2012-01-13 20:33:14.640107
714	662	2012-01-13 20:28:07.236178
714	639	2012-01-13 20:28:07.236178
714	543	2012-01-13 20:28:07.236178
680	682	2012-01-13 20:28:07.236178
300	943	2012-01-13 20:33:14.640107
1213	891	2012-01-13 20:50:57.226198
625	715	2012-01-13 20:28:08.343807
717	706	2012-01-13 20:28:10.141392
778	945	2012-01-13 20:33:19.267611
1209	1240	2012-01-13 20:51:00.147979
719	704	2012-01-13 20:28:11.720719
596	945	2012-01-13 20:33:19.267611
1782	1888	2012-01-13 22:20:23.826224
887	1240	2012-01-13 20:51:00.147979
673	706	2012-01-13 20:28:11.720719
1906	778	2012-01-13 22:20:47.650022
926	946	2012-01-13 20:33:23.804093
669	249	2012-01-13 20:28:14.681883
877	946	2012-01-13 20:33:23.804093
857	920	2012-01-13 20:33:24.92525
723	669	2012-01-13 20:28:16.528111
639	726	2012-01-13 20:28:20.416433
912	920	2012-01-13 20:33:24.92525
655	726	2012-01-13 20:28:20.416433
690	706	2012-01-13 20:28:21.214135
948	947	2012-01-13 20:33:26.273867
572	925	2012-01-13 20:33:27.18942
727	677	2012-01-13 20:28:21.214135
908	949	2012-01-13 20:33:27.18942
727	690	2012-01-13 20:28:21.214135
950	875	2012-01-13 20:33:28.793106
615	715	2012-01-13 20:28:23.126934
706	728	2012-01-13 20:28:23.126934
249	728	2012-01-13 20:28:23.126934
361	715	2012-01-13 20:28:23.998824
950	790	2012-01-13 20:33:28.793106
144	1240	2012-01-13 20:51:00.147979
681	731	2012-01-13 20:28:26.052669
410	732	2012-01-13 20:28:26.648126
144	732	2012-01-13 20:28:26.648126
733	525	2012-01-13 20:28:27.266538
778	790	2012-01-13 20:33:30.404425
361	734	2012-01-13 20:28:27.553693
735	251	2012-01-13 20:28:28.139819
154	735	2012-01-13 20:28:28.139819
410	693	2012-01-13 20:28:28.915063
738	471	2012-01-13 20:28:29.102554
685	740	2012-01-13 20:28:30.162169
1181	1147	2012-01-13 20:51:08.141328
740	677	2012-01-13 20:28:30.162169
951	949	2012-01-13 20:33:30.404425
1907	1600	2012-01-13 22:20:51.850677
623	953	2012-01-13 20:33:35.404908
361	744	2012-01-13 20:28:31.554673
682	709	2012-01-13 20:28:31.554673
690	745	2012-01-13 20:28:32.28619
673	745	2012-01-13 20:28:32.28619
1811	1907	2012-01-13 22:20:51.850677
623	955	2012-01-13 20:33:38.366756
746	677	2012-01-13 20:28:33.124813
410	747	2012-01-13 20:28:34.021147
144	747	2012-01-13 20:28:34.021147
615	711	2012-01-13 20:28:34.804193
673	439	2012-01-13 20:28:34.804193
1242	1226	2012-01-13 20:51:12.687848
955	890	2012-01-13 20:33:38.366756
639	749	2012-01-13 20:28:35.367121
749	728	2012-01-13 20:28:35.367121
842	955	2012-01-13 20:33:38.366756
924	666	2012-01-13 20:33:41.991818
596	749	2012-01-13 20:28:35.367121
271	750	2012-01-13 20:28:36.883445
750	711	2012-01-13 20:28:36.883445
693	875	2012-01-13 20:33:41.991818
640	662	2012-01-13 20:28:37.520949
752	467	2012-01-13 20:28:38.061679
507	682	2012-01-13 20:28:38.061679
747	753	2012-01-13 20:28:38.636104
154	753	2012-01-13 20:28:38.636104
854	859	2012-01-13 20:33:41.991818
174	756	2012-01-13 20:28:39.498005
750	757	2012-01-13 20:28:40.216557
607	704	2012-01-13 20:28:40.216557
805	890	2012-01-13 20:33:41.991818
747	759	2012-01-13 20:28:40.978078
908	958	2012-01-13 20:33:45.696673
846	958	2012-01-13 20:33:45.696673
1209	688	2012-01-13 20:51:12.687848
698	463	2012-01-13 20:28:41.853385
757	607	2012-01-13 20:28:42.281558
761	677	2012-01-13 20:28:42.281558
1242	916	2012-01-13 20:51:12.687848
174	762	2012-01-13 20:28:43.401434
3219	3292	2012-01-14 06:03:36.802837
460	463	2012-01-13 20:28:43.806353
1907	1864	2012-01-13 22:20:51.850677
764	177	2012-01-13 20:28:44.968139
177	704	2012-01-13 20:28:44.968139
750	764	2012-01-13 20:28:44.968139
361	764	2012-01-13 20:28:44.968139
765	753	2012-01-13 20:28:46.581818
765	649	2012-01-13 20:28:46.581818
15	765	2012-01-13 20:28:46.581818
667	960	2012-01-13 20:33:49.161529
767	754	2012-01-13 20:28:49.140487
272	960	2012-01-13 20:33:49.161529
649	767	2012-01-13 20:28:49.140487
1244	1208	2012-01-13 20:51:23.669786
705	762	2012-01-13 20:28:50.831202
843	993	2012-01-13 20:35:56.231516
770	682	2012-01-13 20:28:51.705568
752	698	2012-01-13 20:28:53.969707
327	773	2012-01-13 20:28:53.969707
1244	1204	2012-01-13 20:51:23.669786
3293	3133	2012-01-14 06:03:57.2876
999	677	2012-01-13 20:35:58.867699
924	999	2012-01-13 20:35:58.867699
777	775	2012-01-13 20:28:59.229316
778	749	2012-01-13 20:28:59.694213
749	680	2012-01-13 20:29:01.560065
781	749	2012-01-13 20:29:01.560065
782	754	2012-01-13 20:29:02.533545
520	1208	2012-01-13 20:51:26.567667
673	750	2012-01-13 20:29:03.462888
747	785	2012-01-13 20:29:04.041479
300	785	2012-01-13 20:29:04.041479
765	785	2012-01-13 20:29:04.041479
368	1247	2012-01-13 20:51:35.653322
785	265	2012-01-13 20:29:04.041479
1226	1245	2012-01-13 20:51:35.653322
786	773	2012-01-13 20:29:06.240551
768	786	2012-01-13 20:29:06.240551
966	841	2012-01-13 20:36:03.365007
711	640	2012-01-13 20:29:07.571793
1238	1823	2012-01-13 22:21:09.663689
174	791	2012-01-13 20:29:10.035135
317	792	2012-01-13 20:29:10.521904
1181	1248	2012-01-13 20:51:39.988643
653	463	2012-01-13 20:29:10.985215
793	698	2012-01-13 20:29:10.985215
794	525	2012-01-13 20:29:12.313421
144	1001	2012-01-13 20:36:04.187831
793	768	2012-01-13 20:29:12.852115
662	792	2012-01-13 20:29:12.852115
673	792	2012-01-13 20:29:12.852115
317	796	2012-01-13 20:29:14.83361
673	796	2012-01-13 20:29:14.83361
798	492	2012-01-13 20:29:17.457189
224	801	2012-01-13 20:29:22.272918
174	761	2012-01-13 20:29:22.272918
144	1909	2012-01-13 22:21:14.028383
1004	945	2012-01-13 20:36:10.518385
798	785	2012-01-13 20:29:31.442811
781	177	2012-01-13 20:29:31.442811
177	806	2012-01-13 20:29:32.514609
857	993	2012-01-13 20:36:12.284943
692	791	2012-01-13 20:29:36.885657
951	1005	2012-01-13 20:36:12.284943
811	681	2012-01-13 20:29:40.011454
912	993	2012-01-13 20:36:12.284943
811	326	2012-01-13 20:29:40.011454
1910	913	2012-01-13 22:21:19.508601
813	768	2012-01-13 20:29:43.236734
994	1006	2012-01-13 20:36:14.473954
327	816	2012-01-13 20:29:45.645578
775	786	2012-01-13 20:29:45.645578
757	817	2012-01-13 20:29:46.652672
656	817	2012-01-13 20:29:46.652672
615	818	2012-01-13 20:29:47.491868
750	818	2012-01-13 20:29:47.491868
1007	841	2012-01-13 20:36:16.238954
1011	925	2012-01-13 20:36:24.078219
855	1253	2012-01-13 20:51:55.458654
844	865	2012-01-13 20:36:26.037135
520	1253	2012-01-13 20:51:55.458654
819	662	2012-01-13 20:29:48.519792
820	775	2012-01-13 20:29:52.710024
749	820	2012-01-13 20:29:52.710024
249	821	2012-01-13 20:29:53.743274
662	750	2012-01-13 20:29:53.743274
804	791	2012-01-13 20:29:57.090563
1014	955	2012-01-13 20:36:35.133636
793	467	2012-01-13 20:29:57.090563
825	707	2012-01-13 20:29:58.825306
825	693	2012-01-13 20:29:58.825306
826	817	2012-01-13 20:29:59.874111
1253	1245	2012-01-13 20:51:55.458654
1185	1253	2012-01-13 20:51:55.458654
1254	891	2012-01-13 20:52:01.549944
844	983	2012-01-13 20:36:46.392118
1910	1341	2012-01-13 22:21:19.508601
757	827	2012-01-13 20:30:02.77253
656	827	2012-01-13 20:30:02.77253
410	830	2012-01-13 20:30:06.101708
1019	790	2012-01-13 20:36:48.203526
1019	855	2012-01-13 20:36:48.203526
752	507	2012-01-13 20:30:08.006536
249	832	2012-01-13 20:30:08.47719
174	806	2012-01-13 20:30:09.030186
692	761	2012-01-13 20:30:09.030186
775	251	2012-01-13 20:30:10.831115
1910	820	2012-01-13 22:21:19.508601
1892	1911	2012-01-13 22:21:34.421591
662	796	2012-01-13 20:30:18.47446
825	747	2012-01-13 20:30:19.092343
1020	583	2012-01-13 20:36:50.202769
842	796	2012-01-13 20:30:20.009241
615	1021	2012-01-13 20:36:52.896792
1022	993	2012-01-13 20:36:53.767863
1256	985	2012-01-13 20:52:12.430979
1259	1226	2012-01-13 20:52:23.497431
783	843	2012-01-13 20:30:21.934777
1022	920	2012-01-13 20:36:53.767863
749	821	2012-01-13 20:30:21.934777
844	507	2012-01-13 20:30:23.953608
845	463	2012-01-13 20:30:24.636908
926	980	2012-01-13 20:36:53.767863
846	818	2012-01-13 20:30:25.90868
846	711	2012-01-13 20:30:25.90868
783	681	2012-01-13 20:36:53.767863
847	467	2012-01-13 20:30:27.820115
525	849	2012-01-13 20:30:30.071978
825	602	2012-01-13 20:30:30.071978
781	850	2012-01-13 20:30:31.488226
1175	712	2012-01-13 20:52:25.23474
1136	865	2012-01-13 20:52:25.23474
778	850	2012-01-13 20:30:31.488226
887	1023	2012-01-13 20:37:02.383573
667	853	2012-01-13 20:30:36.136266
525	854	2012-01-13 20:30:37.287726
1019	979	2012-01-13 20:37:02.383573
604	854	2012-01-13 20:30:37.287726
855	696	2012-01-13 20:30:40.128519
705	920	2012-01-13 20:33:52.032934
639	855	2012-01-13 20:30:40.128519
3293	2154	2012-01-14 06:03:57.2876
825	858	2012-01-13 20:30:45.293772
786	961	2012-01-13 20:33:52.032934
850	677	2012-01-13 20:30:45.293772
604	849	2012-01-13 20:30:47.551087
861	677	2012-01-13 20:30:49.368236
847	698	2012-01-13 20:30:49.368236
667	861	2012-01-13 20:30:49.368236
749	861	2012-01-13 20:30:49.368236
862	251	2012-01-13 20:30:51.438333
1170	1263	2012-01-13 20:52:39.567069
1264	1161	2012-01-13 20:52:42.421042
966	471	2012-01-13 20:34:03.9644
847	865	2012-01-13 20:30:54.23219
751	865	2012-01-13 20:30:54.23219
843	139	2012-01-13 20:30:54.23219
662	751	2012-01-13 20:30:54.23219
866	463	2012-01-13 20:30:56.741562
492	890	2012-01-13 20:34:03.9644
1215	1190	2012-01-13 20:52:43.88756
278	866	2012-01-13 20:30:56.741562
623	968	2012-01-13 20:34:08.820608
867	817	2012-01-13 20:30:59.967325
1267	935	2012-01-13 20:52:49.341711
623	792	2012-01-13 20:30:59.967325
623	796	2012-01-13 20:30:59.967325
914	968	2012-01-13 20:34:08.820608
1267	1166	2012-01-13 20:52:49.341711
869	251	2012-01-13 20:31:05.52758
576	1911	2012-01-13 22:21:34.421591
870	139	2012-01-13 20:31:06.202371
667	821	2012-01-13 20:31:09.194598
639	875	2012-01-13 20:31:14.021407
1267	1216	2012-01-13 20:52:49.341711
846	935	2012-01-13 20:34:12.345734
796	971	2012-01-13 20:34:14.34627
751	876	2012-01-13 20:31:15.416721
908	972	2012-01-13 20:34:15.162587
877	817	2012-01-13 20:31:16.741603
846	972	2012-01-13 20:34:15.162587
1910	1876	2012-01-13 22:21:47.996638
751	698	2012-01-13 20:31:16.741603
599	843	2012-01-13 20:31:16.741603
760	775	2012-01-13 20:31:16.741603
877	599	2012-01-13 20:31:16.741603
154	878	2012-01-13 20:31:22.733796
878	463	2012-01-13 20:31:22.733796
842	975	2012-01-13 20:34:25.907184
975	920	2012-01-13 20:34:25.907184
639	881	2012-01-13 20:31:27.187019
782	971	2012-01-13 20:34:25.907184
144	982	2012-01-13 20:52:49.341711
881	698	2012-01-13 20:31:27.187019
914	975	2012-01-13 20:34:25.907184
881	653	2012-01-13 20:31:27.187019
881	865	2012-01-13 20:31:27.187019
877	623	2012-01-13 20:31:31.247335
1170	1269	2012-01-13 20:52:59.738206
883	876	2012-01-13 20:31:31.949258
883	865	2012-01-13 20:31:31.949258
596	1269	2012-01-13 20:52:59.738206
653	1912	2012-01-13 22:21:47.996638
778	875	2012-01-13 20:31:34.116746
854	884	2012-01-13 20:31:34.116746
748	1912	2012-01-13 22:21:47.996638
887	707	2012-01-13 20:31:39.29332
1913	1269	2012-01-13 22:22:07.260568
623	975	2012-01-13 20:34:25.907184
778	976	2012-01-13 20:34:36.58878
2472	3293	2012-01-14 06:03:57.2876
1014	1270	2012-01-13 20:53:06.381562
851	891	2012-01-13 20:31:44.885904
891	773	2012-01-13 20:31:44.885904
1064	1270	2012-01-13 20:53:06.381562
604	892	2012-01-13 20:31:47.049981
893	463	2012-01-13 20:31:47.831477
976	861	2012-01-13 20:34:36.58878
976	680	2012-01-13 20:34:36.58878
819	639	2012-01-13 20:31:53.275624
3286	2485	2012-01-14 06:03:57.2876
977	971	2012-01-13 20:34:42.758485
1185	1170	2012-01-13 20:53:11.891289
966	977	2012-01-13 20:34:42.758485
278	890	2012-01-13 20:34:42.758485
596	1271	2012-01-13 20:53:11.891289
1144	1167	2012-01-13 20:53:14.317664
978	971	2012-01-13 20:34:48.226188
1103	1273	2012-01-13 20:53:15.918252
1274	1207	2012-01-13 20:53:18.636647
839	978	2012-01-13 20:34:48.226188
778	979	2012-01-13 20:34:51.700927
696	890	2012-01-13 20:34:52.426513
795	1275	2012-01-13 20:53:21.410818
980	696	2012-01-13 20:34:52.426513
924	980	2012-01-13 20:34:52.426513
980	936	2012-01-13 20:34:52.426513
782	981	2012-01-13 20:34:56.902698
1213	1915	2012-01-13 22:22:21.306746
933	759	2012-01-13 20:34:56.902698
677	965	2012-01-13 20:34:59.124014
982	471	2012-01-13 20:34:59.124014
1170	1276	2012-01-13 20:53:24.856834
1888	1915	2012-01-13 22:22:21.306746
751	983	2012-01-13 20:35:02.492161
676	983	2012-01-13 20:35:02.492161
385	3293	2012-01-14 06:03:57.2876
881	983	2012-01-13 20:35:02.492161
984	680	2012-01-13 20:35:08.382784
984	913	2012-01-13 20:35:08.382784
898	1277	2012-01-13 20:53:29.815579
1277	1215	2012-01-13 20:53:29.815579
1030	1279	2012-01-13 20:53:35.389575
985	980	2012-01-13 20:35:12.323979
1113	1253	2012-01-13 20:53:35.389575
1244	1253	2012-01-13 20:53:35.389575
1157	1279	2012-01-13 20:53:35.389575
737	955	2012-01-13 20:35:12.323979
410	986	2012-01-13 20:35:17.383561
224	677	2012-01-13 20:35:17.383561
986	961	2012-01-13 20:35:17.383561
933	987	2012-01-13 20:35:20.484393
966	987	2012-01-13 20:35:20.484393
987	979	2012-01-13 20:35:20.484393
1279	1136	2012-01-13 20:53:35.389575
1281	1216	2012-01-13 20:53:46.722126
987	881	2012-01-13 20:35:20.484393
1916	1889	2012-01-13 22:22:45.123451
681	965	2012-01-13 20:35:28.521742
844	989	2012-01-13 20:35:28.521742
1264	1213	2012-01-13 20:53:48.114062
1184	1282	2012-01-13 20:53:48.114062
1283	1264	2012-01-13 20:53:52.425829
271	990	2012-01-13 20:35:32.226055
1284	1030	2012-01-13 20:53:53.825085
778	991	2012-01-13 20:35:33.061079
1284	792	2012-01-13 20:53:53.825085
623	990	2012-01-13 20:35:33.061079
1916	1442	2012-01-13 22:22:45.123451
174	993	2012-01-13 20:35:41.066598
705	993	2012-01-13 20:35:41.066598
994	623	2012-01-13 20:35:42.936653
1284	1222	2012-01-13 20:53:53.825085
737	990	2012-01-13 20:35:42.936653
1713	1917	2012-01-13 22:22:54.001501
898	1285	2012-01-13 20:54:00.316924
778	712	2012-01-13 20:35:46.097699
924	623	2012-01-13 20:35:48.084183
869	924	2012-01-13 20:35:48.084183
774	996	2012-01-13 20:35:48.084183
410	1286	2012-01-13 20:54:01.769339
144	1286	2012-01-13 20:54:01.769339
869	631	2012-01-13 20:35:50.62472
705	783	2012-01-13 20:35:50.62472
844	997	2012-01-13 20:35:50.62472
887	1286	2012-01-13 20:54:01.769339
271	925	2012-01-13 20:37:02.383573
1006	913	2012-01-13 20:37:02.383573
1157	1287	2012-01-13 20:54:06.490967
1024	970	2012-01-13 20:37:07.168336
1026	677	2012-01-13 20:37:12.465709
1281	1285	2012-01-13 20:54:06.490967
1006	680	2012-01-13 20:37:12.465709
801	1287	2012-01-13 20:54:06.490967
870	993	2012-01-13 20:37:16.777436
966	1027	2012-01-13 20:37:16.777436
1916	985	2012-01-13 22:22:58.198349
1007	1027	2012-01-13 20:37:16.777436
3106	3295	2012-01-14 06:05:27.200091
1281	1290	2012-01-13 20:54:23.353611
1030	961	2012-01-13 20:37:26.983054
1290	970	2012-01-13 20:54:23.353611
1019	945	2012-01-13 20:37:27.974342
980	1032	2012-01-13 20:37:30.007919
1036	1290	2012-01-13 20:54:23.353611
1290	1229	2012-01-13 20:54:23.353611
1037	905	2012-01-13 20:37:43.668614
1037	1023	2012-01-13 20:37:43.668614
1012	1039	2012-01-13 20:37:47.858069
174	1040	2012-01-13 20:37:48.793093
877	1006	2012-01-13 20:37:54.281146
98	1290	2012-01-13 20:54:23.353611
1238	1282	2012-01-13 20:54:23.353611
688	1290	2012-01-13 20:54:23.353611
1040	677	2012-01-13 20:37:54.281146
596	1042	2012-01-13 20:37:54.281146
912	1040	2012-01-13 20:37:54.281146
583	965	2012-01-13 20:37:59.182626
966	1043	2012-01-13 20:37:59.182626
1918	1671	2012-01-13 22:22:58.198349
667	820	2012-01-13 20:37:59.182626
1007	1043	2012-01-13 20:37:59.182626
1045	943	2012-01-13 20:38:04.632713
471	1046	2012-01-13 20:38:05.714585
1046	993	2012-01-13 20:38:05.714585
136	1046	2012-01-13 20:38:05.714585
176	1046	2012-01-13 20:38:05.714585
556	1291	2012-01-13 20:54:37.875321
615	1047	2012-01-13 20:38:10.027664
1045	951	2012-01-13 20:38:10.027664
1281	935	2012-01-13 20:54:39.685931
1396	1167	2012-01-13 21:05:56.453198
1870	1626	2012-01-13 22:22:58.198349
842	1048	2012-01-13 20:38:15.751503
1014	1048	2012-01-13 20:38:15.751503
774	1048	2012-01-13 20:38:15.751503
914	1048	2012-01-13 20:38:15.751503
841	983	2012-01-13 20:38:19.660588
1918	1736	2012-01-13 22:22:58.198349
1611	1918	2012-01-13 22:22:58.198349
1399	1323	2012-01-13 21:06:21.658182
1045	471	2012-01-13 20:38:22.078382
174	920	2012-01-13 20:38:22.078382
1287	782	2012-01-13 21:06:21.658182
790	1046	2012-01-13 20:38:25.315701
1191	1919	2012-01-13 22:23:24.686187
908	1053	2012-01-13 20:38:34.245897
951	1053	2012-01-13 20:38:34.245897
1053	920	2012-01-13 20:38:34.245897
1053	265	2012-01-13 20:38:34.245897
615	1053	2012-01-13 20:38:34.245897
1053	993	2012-01-13 20:38:34.245897
923	1053	2012-01-13 20:38:34.245897
596	1054	2012-01-13 20:38:42.319464
995	925	2012-01-13 20:38:42.319464
778	1054	2012-01-13 20:38:42.319464
1036	1297	2012-01-13 21:06:21.658182
858	1054	2012-01-13 20:38:42.319464
1383	1400	2012-01-13 21:06:28.999124
1056	631	2012-01-13 20:38:51.0229
1347	1400	2012-01-13 21:06:28.999124
1400	623	2012-01-13 21:06:28.999124
1400	516	2012-01-13 21:06:28.999124
877	1056	2012-01-13 20:38:51.0229
844	908	2012-01-13 20:38:51.0229
1058	925	2012-01-13 20:38:58.030948
751	908	2012-01-13 20:38:58.030948
1400	767	2012-01-13 21:06:28.999124
1014	792	2012-01-13 20:39:00.571137
1023	1061	2012-01-13 20:39:02.395962
877	1061	2012-01-13 20:39:02.395962
1191	1892	2012-01-13 22:23:34.098933
576	1921	2012-01-13 22:23:38.424399
898	1401	2012-01-13 21:06:45.515402
983	1060	2012-01-13 20:39:06.462861
898	1402	2012-01-13 21:06:47.635376
936	1062	2012-01-13 20:39:06.462861
1814	1915	2012-01-13 22:23:38.424399
1063	1062	2012-01-13 20:39:12.40599
966	759	2012-01-13 20:39:12.40599
1210	1404	2012-01-13 21:06:52.130506
782	1404	2012-01-13 21:06:52.130506
1405	1167	2012-01-13 21:06:59.513048
1063	677	2012-01-13 20:39:12.40599
1020	1060	2012-01-13 20:39:12.40599
1811	1745	2012-01-13 22:23:38.424399
40	1063	2012-01-13 20:39:12.40599
1229	1409	2012-01-13 21:07:12.220949
1064	925	2012-01-13 20:39:25.202294
1348	1409	2012-01-13 21:07:12.220949
1408	1393	2012-01-13 21:07:16.806295
1064	792	2012-01-13 20:39:25.202294
1410	1245	2012-01-13 21:07:16.806295
1066	1063	2012-01-13 20:39:34.818277
1194	3095	2012-01-14 06:05:27.200091
1920	1923	2012-01-13 22:24:02.481674
1923	1629	2012-01-13 22:24:02.481674
1020	795	2012-01-13 20:39:36.876789
782	1063	2012-01-13 20:39:43.996231
615	1069	2012-01-13 20:39:43.996231
774	1070	2012-01-13 20:39:45.688367
914	1070	2012-01-13 20:39:45.688367
1014	1070	2012-01-13 20:39:45.688367
1413	1405	2012-01-13 21:07:39.994902
1071	925	2012-01-13 20:39:49.304223
1925	1713	2012-01-13 22:24:26.732737
1071	792	2012-01-13 20:39:49.304223
640	1071	2012-01-13 20:39:49.304223
1071	955	2012-01-13 20:39:49.304223
1925	1351	2012-01-13 22:24:26.732737
1414	1287	2012-01-13 21:07:50.530741
1322	1414	2012-01-13 21:07:50.530741
1074	925	2012-01-13 20:40:05.500999
1405	1253	2012-01-13 21:07:50.530741
1095	1414	2012-01-13 21:07:50.530741
1074	792	2012-01-13 20:40:05.500999
640	1074	2012-01-13 20:40:05.500999
1074	955	2012-01-13 20:40:05.500999
1082	1414	2012-01-13 21:07:50.530741
978	1414	2012-01-13 21:07:50.530741
801	1926	2012-01-13 22:24:35.926377
966	1075	2012-01-13 20:40:16.34715
154	1075	2012-01-13 20:40:16.34715
1929	1814	2012-01-13 22:24:50.017493
1036	1365	2012-01-13 21:08:06.711324
2348	3296	2012-01-14 06:06:02.178901
1167	1416	2012-01-13 21:08:14.781015
1007	1075	2012-01-13 20:40:16.34715
3296	2466	2012-01-14 06:06:02.178901
1076	983	2012-01-13 20:40:25.31538
1076	865	2012-01-13 20:40:25.31538
1077	773	2012-01-13 20:40:27.628663
1026	1062	2012-01-13 20:40:28.941876
908	1078	2012-01-13 20:40:28.941876
3296	1698	2012-01-14 06:06:02.178901
1079	1054	2012-01-13 20:40:31.163048
609	1080	2012-01-13 20:40:35.186107
850	1080	2012-01-13 20:40:35.186107
278	1079	2012-01-13 20:40:37.225572
782	1301	2012-01-13 21:08:25.807016
904	1061	2012-01-13 20:40:37.225572
1081	981	2012-01-13 20:40:37.225572
1082	981	2012-01-13 20:40:42.234749
1084	983	2012-01-13 20:40:45.926491
844	1085	2012-01-13 20:40:47.187885
1023	1086	2012-01-13 20:40:48.281006
904	1086	2012-01-13 20:40:48.281006
1071	1088	2012-01-13 20:40:53.436793
1089	1088	2012-01-13 20:40:54.454078
1089	925	2012-01-13 20:40:54.454078
1089	955	2012-01-13 20:40:54.454078
272	1293	2012-01-13 20:54:41.243201
1036	1090	2012-01-13 20:40:57.264082
361	1090	2012-01-13 20:40:57.264082
923	1090	2012-01-13 20:40:57.264082
2818	3297	2012-01-14 06:06:36.570281
3297	3216	2012-01-14 06:06:36.570281
1993	3297	2012-01-14 06:06:36.570281
1217	1293	2012-01-13 20:54:41.243201
882	1090	2012-01-13 20:40:57.264082
1203	1293	2012-01-13 20:54:41.243201
1092	790	2012-01-13 20:41:11.774175
891	961	2012-01-13 20:41:11.774175
385	1088	2012-01-13 20:41:11.774175
844	1095	2012-01-13 20:41:21.028908
2499	3297	2012-01-14 06:06:36.570281
665	1293	2012-01-13 20:54:41.243201
1074	1088	2012-01-13 20:41:24.231315
1249	1293	2012-01-13 20:54:41.243201
1098	677	2012-01-13 20:41:25.293211
327	1937	2012-01-13 22:25:47.595062
774	1088	2012-01-13 20:41:31.011846
1014	1088	2012-01-13 20:41:31.011846
1103	925	2012-01-13 20:41:36.514292
1103	955	2012-01-13 20:41:36.514292
882	667	2012-01-13 20:41:36.514292
1105	783	2012-01-13 20:41:40.380114
1105	265	2012-01-13 20:41:40.380114
1105	782	2012-01-13 20:41:40.380114
2150	3297	2012-01-14 06:06:36.570281
887	1092	2012-01-13 20:41:40.380114
1256	712	2012-01-13 20:55:08.777061
224	1020	2012-01-13 20:41:40.380114
1106	1096	2012-01-13 20:41:47.314281
667	1106	2012-01-13 20:41:47.314281
1297	1113	2012-01-13 20:55:08.777061
272	1106	2012-01-13 20:41:47.314281
410	966	2012-01-13 20:41:50.953305
770	1096	2012-01-13 20:41:50.953305
1108	1088	2012-01-13 20:41:52.541257
1108	955	2012-01-13 20:41:52.541257
1297	623	2012-01-13 20:55:08.777061
778	1109	2012-01-13 20:41:56.41026
1092	1109	2012-01-13 20:41:56.41026
361	1297	2012-01-13 20:55:08.777061
596	1109	2012-01-13 20:41:56.41026
1297	516	2012-01-13 20:55:08.777061
1217	1175	2012-01-13 20:55:08.777061
1298	1230	2012-01-13 20:55:18.382862
951	1285	2012-01-13 20:55:18.382862
1157	1299	2012-01-13 20:55:21.369286
801	1299	2012-01-13 20:55:21.369286
98	667	2012-01-13 20:41:56.41026
1030	1299	2012-01-13 20:55:21.369286
1907	1827	2012-01-13 22:25:47.595062
1110	943	2012-01-13 20:42:11.814823
692	1111	2012-01-13 20:42:13.137706
976	913	2012-01-13 20:42:15.550722
877	1113	2012-01-13 20:42:17.889522
1300	712	2012-01-13 20:55:29.072762
3033	3297	2012-01-14 06:06:36.570281
667	913	2012-01-13 20:42:19.776569
583	1114	2012-01-13 20:42:19.776569
794	1301	2012-01-13 20:55:32.259301
1184	1301	2012-01-13 20:55:32.259301
1110	1075	2012-01-13 20:42:23.800884
1144	1253	2012-01-13 20:55:35.307921
1115	265	2012-01-13 20:42:23.800884
877	1118	2012-01-13 20:42:32.818352
1800	1939	2012-01-13 22:26:05.9182
1213	1305	2012-01-13 20:55:43.799402
1907	1939	2012-01-13 22:26:05.9182
1298	1248	2012-01-13 20:55:43.799402
867	1118	2012-01-13 20:42:32.818352
1020	631	2012-01-13 20:42:38.958217
916	773	2012-01-13 20:42:40.109501
1120	326	2012-01-13 20:42:40.109501
1121	1114	2012-01-13 20:42:42.53978
1114	311	2012-01-13 20:42:42.53978
1074	1048	2012-01-13 20:42:42.53978
1249	1306	2012-01-13 20:55:50.043592
1122	916	2012-01-13 20:42:47.99036
1306	792	2012-01-13 20:55:50.043592
872	1026	2012-01-13 20:42:47.99036
1124	981	2012-01-13 20:42:55.117176
995	1048	2012-01-13 20:42:55.117176
1085	1124	2012-01-13 20:42:55.117176
1120	1125	2012-01-13 20:42:58.259355
865	1125	2012-01-13 20:42:58.259355
877	1126	2012-01-13 20:43:01.506493
640	1127	2012-01-13 20:43:03.516232
1113	1127	2012-01-13 20:43:03.516232
882	1285	2012-01-13 20:55:50.043592
877	1128	2012-01-13 20:43:06.265977
1307	1213	2012-01-13 20:55:54.37253
1128	916	2012-01-13 20:43:06.265977
1128	1121	2012-01-13 20:43:06.265977
1051	994	2012-01-13 20:43:06.265977
692	1307	2012-01-13 20:55:54.37253
1307	477	2012-01-13 20:55:54.37253
995	882	2012-01-13 20:43:06.265977
839	1074	2012-01-13 20:43:06.265977
994	1128	2012-01-13 20:43:06.265977
1129	471	2012-01-13 20:43:18.93686
1131	1077	2012-01-13 20:43:21.311663
1110	471	2012-01-13 20:43:21.311663
1307	631	2012-01-13 20:55:54.37253
667	1133	2012-01-13 20:43:29.470609
1133	975	2012-01-13 20:43:29.470609
1133	955	2012-01-13 20:43:29.470609
1133	792	2012-01-13 20:43:29.470609
857	1134	2012-01-13 20:43:33.021816
912	1134	2012-01-13 20:43:33.021816
870	1134	2012-01-13 20:43:33.021816
1134	1077	2012-01-13 20:43:33.021816
966	943	2012-01-13 20:43:33.021816
1136	983	2012-01-13 20:43:40.188268
877	1136	2012-01-13 20:43:40.188268
640	1308	2012-01-13 20:56:02.173324
985	1136	2012-01-13 20:43:40.188268
1194	1308	2012-01-13 20:56:02.173324
1136	697	2012-01-13 20:43:40.188268
1137	1020	2012-01-13 20:43:46.804057
857	1309	2012-01-13 20:56:05.150637
1140	983	2012-01-13 20:43:53.838865
1140	698	2012-01-13 20:43:53.838865
1140	865	2012-01-13 20:43:53.838865
870	1309	2012-01-13 20:56:05.150637
887	1312	2012-01-13 20:56:18.843839
692	1140	2012-01-13 20:43:53.838865
692	1141	2012-01-13 20:44:02.696127
870	1141	2012-01-13 20:44:02.696127
1312	1253	2012-01-13 20:56:18.843839
922	1141	2012-01-13 20:44:02.696127
1940	1921	2012-01-13 22:26:13.762463
862	1143	2012-01-13 20:44:11.432504
1036	1945	2012-01-13 22:26:51.936578
596	1144	2012-01-13 20:44:14.861252
778	1144	2012-01-13 20:44:14.861252
1298	1314	2012-01-13 20:56:30.44855
887	1145	2012-01-13 20:44:16.802937
1051	913	2012-01-13 20:44:16.802937
841	865	2012-01-13 20:44:16.802937
1145	943	2012-01-13 20:44:16.802937
1077	1146	2012-01-13 20:44:23.68905
1110	1147	2012-01-13 20:44:24.831285
1147	1080	2012-01-13 20:44:24.831285
1800	1945	2012-01-13 22:26:51.936578
1020	477	2012-01-13 20:44:24.831285
1315	970	2012-01-13 20:56:31.942222
1147	1020	2012-01-13 20:44:24.831285
1122	1121	2012-01-13 20:44:24.831285
3298	2466	2012-01-14 06:07:35.753098
1298	1317	2012-01-13 20:56:39.748176
966	1147	2012-01-13 20:44:24.831285
1148	916	2012-01-13 20:44:37.789033
1077	1148	2012-01-13 20:44:37.789033
1920	1946	2012-01-13 22:26:59.861526
1095	1318	2012-01-13 20:56:41.230773
1110	1051	2012-01-13 20:44:44.856824
1150	865	2012-01-13 20:44:45.759799
870	891	2012-01-13 20:44:45.759799
886	786	2012-01-13 20:44:45.759799
1151	1113	2012-01-13 20:44:50.945287
1153	1141	2012-01-13 20:44:53.281712
1154	583	2012-01-13 20:44:55.525434
271	1155	2012-01-13 20:44:56.51087
770	1156	2012-01-13 20:44:58.708678
524	1156	2012-01-13 20:44:58.708678
1082	1157	2012-01-13 20:45:00.783801
278	1156	2012-01-13 20:45:01.87607
951	1158	2012-01-13 20:45:01.87607
1036	1158	2012-01-13 20:45:01.87607
882	1158	2012-01-13 20:45:01.87607
1158	981	2012-01-13 20:45:01.87607
3298	3242	2012-01-14 06:07:35.753098
898	1158	2012-01-13 20:45:01.87607
1110	951	2012-01-13 20:45:01.87607
1319	631	2012-01-13 20:56:48.689595
1137	1160	2012-01-13 20:45:15.569271
1156	1141	2012-01-13 20:45:16.686948
857	1141	2012-01-13 20:45:16.686948
1127	1156	2012-01-13 20:45:16.686948
1321	1191	2012-01-13 20:57:05.305137
782	1163	2012-01-13 20:45:22.518075
1082	1163	2012-01-13 20:45:22.518075
1948	1937	2012-01-13 22:27:28.360974
1910	1949	2012-01-13 22:27:35.214597
144	1950	2012-01-13 22:27:39.47426
410	1164	2012-01-13 20:45:27.592638
887	1164	2012-01-13 20:45:27.592638
144	1164	2012-01-13 20:45:27.592638
410	1145	2012-01-13 20:45:32.463402
951	1166	2012-01-13 20:45:33.496427
620	1323	2012-01-13 20:57:10.896415
1298	840	2012-01-13 20:57:10.896415
1036	1166	2012-01-13 20:45:33.496427
98	1166	2012-01-13 20:45:33.496427
588	1167	2012-01-13 20:45:38.825752
640	1167	2012-01-13 20:45:38.825752
1113	1167	2012-01-13 20:45:38.825752
3298	2967	2012-01-14 06:07:35.753098
1324	1305	2012-01-13 20:57:22.8005
782	1168	2012-01-13 20:45:41.836876
1095	1169	2012-01-13 20:45:44.953377
1169	865	2012-01-13 20:45:44.953377
978	1169	2012-01-13 20:45:44.953377
1170	1144	2012-01-13 20:45:48.961166
136	1167	2012-01-13 20:45:50.176976
564	1172	2012-01-13 20:45:51.510257
1326	1285	2012-01-13 20:57:26.502465
1173	1080	2012-01-13 20:45:52.880244
1080	1172	2012-01-13 20:45:52.880244
1173	1160	2012-01-13 20:45:52.880244
1951	888	2012-01-13 22:27:48.425678
1482	1923	2012-01-13 22:27:53.138021
1173	1020	2012-01-13 20:45:52.880244
1326	935	2012-01-13 20:57:26.502465
1910	1800	2012-01-13 22:28:01.997482
1175	976	2012-01-13 20:46:05.751141
1176	1163	2012-01-13 20:46:06.807361
1176	1169	2012-01-13 20:46:06.807361
1285	1253	2012-01-13 20:57:26.502465
857	782	2012-01-13 20:46:17.06861
912	782	2012-01-13 20:46:17.06861
912	1141	2012-01-13 20:46:17.06861
914	1180	2012-01-13 20:46:17.06861
98	914	2012-01-13 20:46:17.06861
98	1954	2012-01-13 22:28:01.997482
1326	1216	2012-01-13 20:57:26.502465
870	1137	2012-01-13 20:46:17.06861
1181	943	2012-01-13 20:46:32.137471
1182	936	2012-01-13 20:46:33.667971
1184	1169	2012-01-13 20:46:37.577622
1184	1163	2012-01-13 20:46:37.577622
1955	1245	2012-01-13 22:28:10.050904
1170	712	2012-01-13 20:46:41.171507
1175	1186	2012-01-13 20:46:42.426124
1170	1186	2012-01-13 20:46:42.426124
1327	1287	2012-01-13 20:57:42.230976
596	1186	2012-01-13 20:46:42.426124
1892	1921	2012-01-13 22:28:14.720685
439	1956	2012-01-13 22:28:14.720685
1341	1958	2012-01-13 22:28:43.51161
1707	1958	2012-01-13 22:28:43.51161
913	1958	2012-01-13 22:28:43.51161
1186	1100	2012-01-13 20:46:42.426124
1300	1328	2012-01-13 20:57:53.194338
1187	886	2012-01-13 20:46:54.062056
887	982	2012-01-13 20:46:54.062056
1187	543	2012-01-13 20:46:54.062056
439	1959	2012-01-13 22:28:57.240601
1960	1949	2012-01-13 22:29:02.072674
870	1305	2012-01-13 20:57:53.194338
1026	1020	2012-01-13 20:47:01.848376
1026	1160	2012-01-13 20:47:05.609147
1190	866	2012-01-13 20:47:05.609147
1961	1327	2012-01-13 22:29:07.218783
1181	710	2012-01-13 20:47:07.929447
1066	1191	2012-01-13 20:47:07.929447
1191	795	2012-01-13 20:47:07.929447
1191	631	2012-01-13 20:47:07.929447
1192	916	2012-01-13 20:47:14.395709
898	1192	2012-01-13 20:47:14.395709
748	1190	2012-01-13 20:47:14.395709
1181	951	2012-01-13 20:47:14.395709
1958	1880	2012-01-13 22:29:07.218783
1194	815	2012-01-13 20:47:22.099998
886	477	2012-01-13 20:47:22.099998
1181	1195	2012-01-13 20:47:24.906776
1961	1442	2012-01-13 22:29:07.218783
982	1195	2012-01-13 20:47:24.906776
1213	1309	2012-01-13 20:58:18.905234
98	1285	2012-01-13 20:58:18.905234
1007	1195	2012-01-13 20:47:24.906776
1300	1327	2012-01-13 20:58:25.209879
667	1196	2012-01-13 20:47:34.587192
1181	1197	2012-01-13 20:47:35.650637
1269	1956	2012-01-13 22:29:07.218783
3298	2751	2012-01-14 06:07:35.753098
638	1956	2012-01-13 22:29:07.218783
1064	1198	2012-01-13 20:47:40.316934
1192	3299	2012-01-14 06:08:32.763396
1199	1198	2012-01-13 20:47:42.777032
1194	1298	2012-01-13 20:58:40.509489
1175	1199	2012-01-13 20:47:42.777032
1170	1199	2012-01-13 20:47:42.777032
994	1200	2012-01-13 20:47:47.119805
1151	1200	2012-01-13 20:47:47.119805
1417	1736	2012-01-13 22:29:33.041566
1930	1849	2012-01-13 22:29:33.041566
1203	1106	2012-01-13 20:48:00.267219
368	1204	2012-01-13 20:48:01.694756
640	1204	2012-01-13 20:48:01.694756
1204	1163	2012-01-13 20:48:01.694756
368	1205	2012-01-13 20:48:05.694248
631	970	2012-01-13 20:48:05.694248
1206	1113	2012-01-13 20:48:08.080073
1336	1287	2012-01-13 20:58:46.567612
1204	1207	2012-01-13 20:48:10.255538
640	1253	2012-01-13 20:58:46.567612
368	1208	2012-01-13 20:48:13.007178
1194	1208	2012-01-13 20:48:13.007178
1323	467	2012-01-13 20:58:46.567612
1185	1208	2012-01-13 20:48:13.007178
688	935	2012-01-13 20:48:17.924634
1210	1163	2012-01-13 20:48:19.432717
1170	1210	2012-01-13 20:48:19.432717
596	1210	2012-01-13 20:48:19.432717
1210	1207	2012-01-13 20:48:19.432717
1281	1337	2012-01-13 20:58:53.595699
858	1210	2012-01-13 20:48:19.432717
688	1337	2012-01-13 20:58:53.595699
1210	1168	2012-01-13 20:48:19.432717
951	1337	2012-01-13 20:58:53.595699
1298	1338	2012-01-13 20:58:59.980515
3300	3160	2012-01-14 06:08:43.896355
1175	1210	2012-01-13 20:48:19.432717
1215	1292	2012-01-13 20:59:41.069326
857	1305	2012-01-13 20:59:41.069326
3301	2367	2012-01-14 06:08:55.393357
950	1210	2012-01-13 20:48:19.432717
1020	1336	2012-01-13 20:59:54.059448
995	1198	2012-01-13 20:48:19.432717
1213	1345	2012-01-13 20:59:54.059448
1892	938	2012-01-13 22:29:42.550858
985	1200	2012-01-13 20:48:59.53175
1181	592	2012-01-13 20:49:05.001505
1185	1205	2012-01-13 20:49:05.001505
1020	1213	2012-01-13 20:49:05.001505
1215	970	2012-01-13 20:49:10.482012
923	1216	2012-01-13 20:49:12.293669
1184	1207	2012-01-13 20:49:12.293669
688	1216	2012-01-13 20:49:12.293669
1216	865	2012-01-13 20:49:12.293669
898	1216	2012-01-13 20:49:12.293669
692	1345	2012-01-13 20:59:54.059448
1345	1245	2012-01-13 20:59:54.059448
1217	994	2012-01-13 20:49:23.568404
688	1219	2012-01-13 20:49:26.286633
951	1219	2012-01-13 20:49:26.286633
923	1219	2012-01-13 20:49:26.286633
1036	1219	2012-01-13 20:49:26.286633
1892	1964	2012-01-13 22:30:03.587727
98	1219	2012-01-13 20:49:26.286633
898	1219	2012-01-13 20:49:26.286633
951	1221	2012-01-13 20:49:39.39467
688	1221	2012-01-13 20:49:39.39467
1965	1958	2012-01-13 22:30:12.969298
842	1222	2012-01-13 20:49:43.201106
3181	3238	2012-01-14 06:09:42.460057
1209	157	2012-01-13 20:49:45.781621
857	1346	2012-01-13 21:00:10.5163
912	1346	2012-01-13 21:00:10.5163
1346	1215	2012-01-13 21:00:10.5163
3303	2680	2012-01-14 06:09:42.460057
1965	1845	2012-01-13 22:30:12.969298
1347	935	2012-01-13 21:00:35.915792
1916	1966	2012-01-13 22:30:34.279202
1347	1297	2012-01-13 21:00:35.915792
1289	1305	2012-01-13 21:00:46.045122
1289	1345	2012-01-13 21:00:46.045122
1336	1349	2012-01-13 21:00:50.423643
620	1349	2012-01-13 21:00:50.423643
623	1030	2012-01-13 21:00:50.423643
98	1968	2012-01-13 22:30:43.625738
1292	467	2012-01-13 21:01:01.572572
1963	1710	2012-01-13 22:30:43.625738
1937	1958	2012-01-13 22:30:43.625738
1963	1910	2012-01-13 22:30:43.625738
369	1351	2012-01-13 21:01:08.834666
1210	1282	2012-01-13 21:01:08.834666
1671	1970	2012-01-13 22:31:10.265584
879	1355	2012-01-13 21:01:31.723614
862	477	2012-01-13 21:01:31.723614
154	1357	2012-01-13 21:01:45.00995
3081	2751	2012-01-14 06:09:42.460057
1144	1298	2012-01-13 21:01:45.00995
1357	938	2012-01-13 21:01:45.00995
1292	1085	2012-01-13 21:01:45.00995
1357	866	2012-01-13 21:01:45.00995
1007	1357	2012-01-13 21:01:45.00995
1322	1282	2012-01-13 21:01:59.17243
1358	1245	2012-01-13 21:01:59.17243
1975	1921	2012-01-13 22:31:41.713116
1359	712	2012-01-13 21:02:04.951641
1359	1144	2012-01-13 21:02:04.951641
712	1301	2012-01-13 21:02:04.951641
1975	1911	2012-01-13 22:31:41.713116
1359	1328	2012-01-13 21:02:04.951641
1975	1515	2012-01-13 22:31:41.713116
985	939	2012-01-13 21:02:04.951641
3300	3154	2012-01-14 06:10:27.631111
1946	1626	2012-01-13 22:31:41.713116
640	1298	2012-01-13 21:02:19.39333
1360	970	2012-01-13 21:02:19.39333
1976	939	2012-01-13 22:32:06.328778
1977	1831	2012-01-13 22:32:10.790967
1287	1309	2012-01-13 21:02:43.326757
1364	1287	2012-01-13 21:02:43.326757
1580	1980	2012-01-13 22:32:29.633414
1281	1365	2012-01-13 21:02:50.919315
1930	1980	2012-01-13 22:32:29.633414
98	1365	2012-01-13 21:02:50.919315
951	1365	2012-01-13 21:02:50.919315
1366	1309	2012-01-13 21:02:59.944385
1981	1876	2012-01-13 22:32:43.324083
1983	1730	2012-01-13 22:32:57.450808
1366	1307	2012-01-13 21:02:59.944385
1113	815	2012-01-13 21:03:18.139721
1369	1245	2012-01-13 21:03:20.769031
1371	1292	2012-01-13 21:03:31.636287
1298	1195	2012-01-13 21:03:31.636287
144	1984	2012-01-13 22:33:01.308044
1985	1515	2012-01-13 22:33:07.34176
1985	1921	2012-01-13 22:33:07.34176
1318	467	2012-01-13 21:03:46.668676
1431	1671	2012-01-13 22:33:17.428456
1376	1300	2012-01-13 21:03:56.324181
1987	1599	2012-01-13 22:33:26.213005
1379	1286	2012-01-13 21:04:08.768688
982	1317	2012-01-13 21:04:08.768688
1987	1876	2012-01-13 22:33:26.213005
1345	1380	2012-01-13 21:04:16.330926
1362	1381	2012-01-13 21:04:20.624073
770	1381	2012-01-13 21:04:20.624073
1217	1383	2012-01-13 21:04:27.359495
1383	1365	2012-01-13 21:04:27.359495
1989	1870	2012-01-13 22:33:41.222729
272	1383	2012-01-13 21:04:27.359495
327	1671	2012-01-13 22:33:41.222729
1249	1383	2012-01-13 21:04:27.359495
3304	1778	2012-01-14 06:10:27.631111
638	1705	2012-01-13 22:33:54.172716
887	1385	2012-01-13 21:04:42.446045
410	1385	2012-01-13 21:04:42.446045
144	1991	2012-01-13 22:34:03.814577
1992	1889	2012-01-13 22:34:09.442874
1385	1229	2012-01-13 21:04:42.446045
144	1385	2012-01-13 21:04:42.446045
985	946	2012-01-13 22:34:09.442874
1993	1051	2012-01-13 22:34:18.668885
1993	1565	2012-01-13 22:34:18.668885
1366	1345	2012-01-13 21:05:08.277317
1916	1994	2012-01-13 22:34:27.304391
1977	1698	2012-01-13 22:34:27.304391
154	1389	2012-01-13 21:05:15.143598
1994	1937	2012-01-13 22:34:27.304391
1007	1389	2012-01-13 21:05:15.143598
3305	2680	2012-01-14 06:11:08.081742
272	1393	2012-01-13 21:05:38.285011
1217	1393	2012-01-13 21:05:38.285011
1394	1322	2012-01-13 21:05:41.502368
1394	1245	2012-01-13 21:05:41.502368
1064	1394	2012-01-13 21:05:41.502368
1977	1005	2012-01-13 22:34:44.781207
1394	1020	2012-01-13 21:05:41.502368
154	1396	2012-01-13 21:05:56.453198
1396	1253	2012-01-13 21:05:56.453198
1345	1375	2012-01-13 21:08:25.807016
887	1420	2012-01-13 21:08:38.780123
1095	1301	2012-01-13 21:08:38.780123
1026	1997	2012-01-13 22:34:53.996454
1400	1421	2012-01-13 21:08:46.660514
1422	985	2012-01-13 21:08:49.714796
1995	1997	2012-01-13 22:34:53.996454
1977	1945	2012-01-13 22:35:07.505076
1977	1494	2012-01-13 22:35:07.505076
1217	1425	2012-01-13 21:09:04.485388
1249	1425	2012-01-13 21:09:04.485388
801	1671	2012-01-13 22:35:07.505076
1855	1840	2012-01-13 22:35:07.505076
1427	1386	2012-01-13 21:09:23.597136
1580	1977	2012-01-13 22:35:24.10028
1428	1287	2012-01-13 21:09:26.317586
1800	2000	2012-01-13 22:35:24.10028
923	2000	2012-01-13 22:35:24.10028
898	1430	2012-01-13 21:09:47.618182
15	2000	2012-01-13 22:35:24.10028
1036	2000	2012-01-13 22:35:24.10028
3305	3275	2012-01-14 06:11:08.081742
98	2000	2012-01-13 22:35:24.10028
98	1430	2012-01-13 21:09:47.618182
1036	1430	2012-01-13 21:09:47.618182
923	1430	2012-01-13 21:09:47.618182
2003	1599	2012-01-13 22:36:16.200085
2003	1341	2012-01-13 22:36:16.200085
1782	3299	2012-01-14 06:11:31.267925
1993	1735	2012-01-13 22:36:16.200085
300	1230	2012-01-13 21:09:47.618182
1400	1431	2012-01-13 21:10:33.311173
1858	2005	2012-01-13 22:36:44.944887
1482	2005	2012-01-13 22:36:44.944887
1151	1431	2012-01-13 21:10:33.311173
1431	1287	2012-01-13 21:10:33.311173
2006	1494	2012-01-13 22:36:53.863193
985	1431	2012-01-13 21:10:33.311173
1432	1414	2012-01-13 21:10:45.557193
154	1434	2012-01-13 21:10:55.920095
2006	1005	2012-01-13 22:37:12.842542
1527	2008	2012-01-13 22:37:12.842542
1364	1323	2012-01-13 21:10:55.920095
1434	1351	2012-01-13 21:10:55.920095
1036	1435	2012-01-13 21:11:06.542459
898	1435	2012-01-13 21:11:06.542459
1435	1318	2012-01-13 21:11:06.542459
1432	1438	2012-01-13 21:11:20.678762
1127	1386	2012-01-13 21:11:20.678762
1238	1438	2012-01-13 21:11:20.678762
1710	2008	2012-01-13 22:37:12.842542
1985	2008	2012-01-13 22:37:12.842542
978	1438	2012-01-13 21:11:20.678762
1362	2008	2012-01-13 22:37:12.842542
1137	1997	2012-01-13 22:37:37.5281
1398	1439	2012-01-13 21:11:40.82744
3307	3296	2012-01-14 06:11:53.534147
1194	1439	2012-01-13 21:11:40.82744
3244	3160	2012-01-14 06:12:59.283362
2000	3310	2012-01-14 06:13:23.460379
1441	1245	2012-01-13 21:11:55.449518
1170	1441	2012-01-13 21:11:55.449518
1256	1441	2012-01-13 21:11:55.449518
154	1230	2012-01-13 21:11:55.449518
1203	1393	2012-01-13 21:11:55.449518
596	1441	2012-01-13 21:11:55.449518
1170	1442	2012-01-13 21:12:08.500288
596	1442	2012-01-13 21:12:08.500288
1191	2010	2012-01-13 22:37:57.819861
1085	1364	2012-01-13 21:12:08.500288
1442	1085	2012-01-13 21:12:08.500288
3311	3297	2012-01-14 06:13:35.555567
1272	1442	2012-01-13 21:12:08.500288
1393	1442	2012-01-13 21:12:08.500288
1307	1443	2012-01-13 21:12:27.878198
1445	1282	2012-01-13 21:12:35.728182
1170	2012	2012-01-13 22:38:13.129466
1447	631	2012-01-13 21:12:40.620301
1447	1213	2012-01-13 21:12:40.620301
2012	1454	2012-01-13 22:38:13.129466
154	1448	2012-01-13 21:12:47.449612
778	2012	2012-01-13 22:38:13.129466
1007	1448	2012-01-13 21:12:47.449612
3203	3313	2012-01-14 06:13:59.890333
300	1448	2012-01-13 21:12:47.449612
1450	975	2012-01-13 21:13:01.767973
1993	2013	2012-01-13 22:38:29.980523
1393	1210	2012-01-13 21:13:01.767973
154	1453	2012-01-13 21:13:13.764628
1845	2014	2012-01-13 22:38:36.923226
300	1453	2012-01-13 21:13:13.764628
1007	1453	2012-01-13 21:13:13.764628
1999	1977	2012-01-13 22:38:46.841491
1215	1454	2012-01-13 21:13:27.061812
1264	631	2012-01-13 21:13:27.061812
1427	1455	2012-01-13 21:13:32.104722
872	1455	2012-01-13 21:13:32.104722
1127	1455	2012-01-13 21:13:32.104722
1432	1301	2012-01-13 21:13:41.471952
1456	801	2012-01-13 21:13:41.471952
1388	1229	2012-01-13 21:13:41.471952
1456	1245	2012-01-13 21:13:41.471952
154	1457	2012-01-13 21:13:50.77289
2006	2015	2012-01-13 22:38:46.841491
300	1457	2012-01-13 21:13:50.77289
1007	1457	2012-01-13 21:13:50.77289
3315	2736	2012-01-14 06:15:11.885319
1215	2016	2012-01-13 22:38:59.934553
1458	478	2012-01-13 21:14:02.549662
1393	1186	2012-01-13 21:14:02.549662
923	1461	2012-01-13 21:14:26.727738
1551	2016	2012-01-13 22:38:59.934553
1462	981	2012-01-13 21:14:31.26067
1161	1462	2012-01-13 21:14:31.26067
1463	999	2012-01-13 21:14:35.832982
1463	516	2012-01-13 21:14:35.832982
1464	1253	2012-01-13 21:14:40.757967
1191	1465	2012-01-13 21:14:43.362533
1228	1465	2012-01-13 21:14:43.362533
1264	1465	2012-01-13 21:14:43.362533
887	1469	2012-01-13 21:15:32.951367
1462	1301	2012-01-13 21:15:32.951367
410	1469	2012-01-13 21:15:32.951367
1085	1351	2012-01-13 21:15:32.951367
1127	1470	2012-01-13 21:15:43.219124
2017	1997	2012-01-13 22:39:09.383272
3316	3299	2012-01-14 06:15:22.823941
1888	2018	2012-01-13 22:39:19.580923
1137	1472	2012-01-13 21:15:52.986353
1393	850	2012-01-13 21:15:52.986353
1398	1253	2012-01-13 21:15:52.986353
1474	782	2012-01-13 21:16:19.213135
1307	1465	2012-01-13 21:16:19.213135
1458	1393	2012-01-13 21:16:19.213135
3313	2983	2012-01-14 06:15:35.957285
1478	1462	2012-01-13 21:16:44.659388
898	1478	2012-01-13 21:16:44.659388
2020	2016	2012-01-13 22:39:34.057356
1144	1127	2012-01-13 21:17:49.070181
1486	1470	2012-01-13 21:17:54.37657
1486	1381	2012-01-13 21:17:54.37657
1203	1486	2012-01-13 21:17:54.37657
2020	1782	2012-01-13 22:39:34.057356
1381	1213	2012-01-13 21:17:54.37657
2021	1945	2012-01-13 22:39:43.614899
2021	1005	2012-01-13 22:39:43.614899
1488	1030	2012-01-13 21:18:11.759975
1488	975	2012-01-13 21:18:11.759975
1490	975	2012-01-13 21:18:22.926045
3278	3310	2012-01-14 06:16:12.162147
882	1219	2012-01-13 21:18:22.926045
991	1301	2012-01-13 21:18:31.114156
850	1380	2012-01-13 21:18:31.114156
887	1491	2012-01-13 21:18:31.114156
144	1491	2012-01-13 21:18:31.114156
1127	1492	2012-01-13 21:18:42.118392
2021	1435	2012-01-13 22:39:43.614899
2024	1997	2012-01-13 22:40:25.929705
1464	1493	2012-01-13 21:18:47.369711
1398	1493	2012-01-13 21:18:47.369711
882	1494	2012-01-13 21:18:55.667558
1494	1030	2012-01-13 21:18:55.667558
1494	975	2012-01-13 21:18:55.667558
1383	1494	2012-01-13 21:18:55.667558
1930	1997	2012-01-13 22:40:59.868689
1495	1380	2012-01-13 21:19:06.060789
1490	1030	2012-01-13 21:19:06.060789
1490	1270	2012-01-13 21:19:06.060789
1495	1245	2012-01-13 21:19:06.060789
1458	1496	2012-01-13 21:19:19.840286
1993	2028	2012-01-13 22:41:04.434251
1249	1496	2012-01-13 21:19:19.840286
369	3318	2012-01-14 06:16:12.162147
1752	2028	2012-01-13 22:41:04.434251
410	1491	2012-01-13 21:19:19.840286
1497	1492	2012-01-13 21:19:36.386889
1883	3310	2012-01-14 06:16:12.162147
1497	1386	2012-01-13 21:19:36.386889
498	1492	2012-01-13 21:19:46.022743
3320	624	2012-01-14 06:16:58.844327
3315	157	2012-01-14 06:16:58.844327
1500	1030	2012-01-13 21:19:54.588101
1441	1380	2012-01-13 21:19:54.588101
144	2033	2012-01-13 22:42:01.425587
1845	2037	2012-01-13 22:42:24.847609
1331	2039	2012-01-13 22:42:39.326475
1490	751	2012-01-13 21:20:09.684777
3315	2343	2012-01-14 06:17:36.124523
985	1504	2012-01-13 21:20:30.61143
1487	1504	2012-01-13 21:20:30.61143
887	1505	2012-01-13 21:20:35.975244
410	1505	2012-01-13 21:20:35.975244
3320	2651	2012-01-14 06:17:36.124523
144	1505	2012-01-13 21:20:35.975244
1509	1351	2012-01-13 21:21:05.280493
1802	2041	2012-01-13 22:42:58.314363
1509	1440	2012-01-13 21:21:05.280493
1510	1435	2012-01-13 21:21:15.009896
1461	1492	2012-01-13 21:21:15.009896
1510	935	2012-01-13 21:21:15.009896
1527	2041	2012-01-13 22:42:58.314363
1511	1347	2012-01-13 21:21:27.146481
3321	2680	2012-01-14 06:17:36.124523
1253	1490	2012-01-13 21:21:31.669943
154	1513	2012-01-13 21:21:36.784197
1736	2037	2012-01-13 22:43:13.111252
1591	2042	2012-01-13 22:43:13.111252
1109	2016	2012-01-13 22:43:22.08752
1498	1514	2012-01-13 21:21:45.756693
1458	1514	2012-01-13 21:21:45.756693
3321	3126	2012-01-14 06:17:36.124523
3322	3216	2012-01-14 06:18:25.38871
1127	1515	2012-01-13 21:21:56.525495
1516	1504	2012-01-13 21:21:59.367162
1518	1470	2012-01-13 21:22:13.633412
1518	1492	2012-01-13 21:22:13.633412
2046	2016	2012-01-13 22:43:40.747641
3320	2857	2012-01-14 06:18:55.740496
1519	773	2012-01-13 21:22:26.43383
1238	1301	2012-01-13 21:22:49.254775
778	1524	2012-01-13 21:22:49.254775
2047	2016	2012-01-13 22:43:54.153661
2049	1327	2012-01-13 22:44:03.869952
1525	1504	2012-01-13 21:22:58.550149
2021	2050	2012-01-13 22:44:08.333219
1526	1127	2012-01-13 21:23:04.045704
1526	1253	2012-01-13 21:23:04.045704
2050	2037	2012-01-13 22:44:08.333219
3320	2296	2012-01-14 06:19:48.143801
410	1528	2012-01-13 21:23:14.822654
887	1528	2012-01-13 21:23:14.822654
1528	1465	2012-01-13 21:23:14.822654
2054	960	2012-01-13 22:44:43.120293
1085	1529	2012-01-13 21:23:28.571077
1471	1530	2012-01-13 21:23:31.478421
1085	1530	2012-01-13 21:23:31.478421
1529	991	2012-01-13 21:23:37.003424
1323	1085	2012-01-13 21:23:37.003424
1082	1531	2012-01-13 21:23:37.003424
1519	1532	2012-01-13 21:23:46.406189
832	1959	2012-01-13 22:44:43.120293
1383	1534	2012-01-13 21:23:58.318177
882	1534	2012-01-13 21:23:58.318177
177	1535	2012-01-13 21:24:03.978268
1536	1504	2012-01-13 21:24:10.062027
1802	2056	2012-01-13 22:44:57.625464
1536	1086	2012-01-13 21:24:10.062027
1537	1380	2012-01-13 21:24:18.791493
2058	2054	2012-01-13 22:45:07.301076
300	1537	2012-01-13 21:24:18.791493
154	1537	2012-01-13 21:24:18.791493
1498	1341	2012-01-13 21:24:18.791493
870	1535	2012-01-13 21:24:30.469558
1482	1191	2012-01-13 21:24:30.469558
1249	2058	2012-01-13 22:45:07.301076
1540	1380	2012-01-13 21:24:47.356296
1289	1535	2012-01-13 21:24:59.692668
1534	913	2012-01-13 21:24:59.692668
1534	1341	2012-01-13 21:24:59.692668
1542	1534	2012-01-13 21:24:59.692668
2059	939	2012-01-13 22:45:15.364324
1543	898	2012-01-13 21:25:15.674685
1215	2060	2012-01-13 22:45:19.859021
1519	1323	2012-01-13 21:25:47.459331
1109	2060	2012-01-13 22:45:19.859021
887	1547	2012-01-13 21:25:52.622327
1229	604	2012-01-13 21:25:52.622327
1348	604	2012-01-13 21:25:52.622327
1458	960	2012-01-13 21:25:52.622327
985	1548	2012-01-13 21:26:04.103083
3191	3325	2012-01-14 06:19:48.143801
1525	1548	2012-01-13 21:26:04.103083
1471	1351	2012-01-13 21:26:04.103083
1548	1307	2012-01-13 21:26:04.103083
1951	1627	2012-01-13 22:45:29.688717
2062	629	2012-01-13 22:45:39.211683
1307	1336	2012-01-13 21:26:04.103083
2062	989	2012-01-13 22:45:39.211683
1525	1550	2012-01-13 21:26:34.606925
1531	2049	2012-01-13 22:45:49.605124
2068	629	2012-01-13 22:46:18.136953
1151	1550	2012-01-13 21:26:34.606925
1487	1550	2012-01-13 21:26:34.606925
2021	2069	2012-01-13 22:46:22.669178
1551	1454	2012-01-13 21:26:49.385334
1551	442	2012-01-13 21:26:49.385334
3317	3326	2012-01-14 06:20:24.669149
1553	1380	2012-01-13 21:26:58.488497
1487	1553	2012-01-13 21:26:58.488497
801	1323	2012-01-13 21:26:58.488497
1554	1323	2012-01-13 21:27:07.506967
1959	1621	2012-01-13 22:46:52.146761
1036	1534	2012-01-13 21:27:07.506967
2074	1989	2012-01-13 22:47:01.890135
1306	1030	2012-01-13 21:27:44.959606
1557	1306	2012-01-13 21:27:44.959606
144	2076	2012-01-13 22:47:11.021716
1559	1550	2012-01-13 21:27:56.114947
1559	1431	2012-01-13 21:27:56.114947
1525	1562	2012-01-13 21:28:22.446306
2077	2049	2012-01-13 22:47:17.550886
3299	2571	2012-01-14 06:20:24.669149
1597	1917	2012-01-13 22:47:17.550886
1559	1562	2012-01-13 21:28:27.60755
2077	1597	2012-01-13 22:47:17.550886
2077	1671	2012-01-13 22:47:17.550886
2077	1736	2012-01-13 22:47:17.550886
985	1562	2012-01-13 21:28:42.742636
1565	913	2012-01-13 21:28:42.742636
3320	3235	2012-01-14 06:21:39.785497
820	2078	2012-01-13 22:47:49.864614
1569	1559	2012-01-13 21:29:21.935666
1571	1564	2012-01-13 21:29:31.146332
1229	1572	2012-01-13 21:29:33.899567
1348	1572	2012-01-13 21:29:33.899567
2008	2078	2012-01-13 22:47:49.864614
1351	2078	2012-01-13 22:47:58.612884
1573	1215	2012-01-13 21:29:46.331836
1482	1301	2012-01-13 21:29:49.550132
1621	2060	2012-01-13 22:47:58.612884
1445	1301	2012-01-13 21:29:52.896254
1500	1575	2012-01-13 21:29:52.896254
2081	1993	2012-01-13 22:48:14.117703
1576	782	2012-01-13 21:30:04.709232
439	1540	2012-01-13 21:30:29.042944
1500	1394	2012-01-13 21:30:29.042944
833	1213	2012-01-13 21:30:35.520062
1580	1245	2012-01-13 21:30:35.520062
1580	1380	2012-01-13 21:30:35.520062
1445	1398	2012-01-13 21:30:48.093485
1582	1085	2012-01-13 21:30:54.128994
1582	811	2012-01-13 21:30:54.128994
1347	1583	2012-01-13 21:31:00.690483
1584	1128	2012-01-13 21:31:03.338248
1586	1386	2012-01-13 21:31:13.231093
1917	2006	2012-01-13 22:48:14.117703
898	1583	2012-01-13 21:31:13.231093
898	1587	2012-01-13 21:31:22.274644
1500	1588	2012-01-13 21:31:28.278476
801	1736	2012-01-13 22:48:31.631734
1808	2084	2012-01-13 22:48:46.051158
2084	2078	2012-01-13 22:48:46.051158
1431	1847	2012-01-13 22:48:46.051158
2157	3208	2012-01-14 06:23:06.564472
3331	1995	2012-01-14 06:23:06.564472
1447	2082	2012-01-13 22:49:07.687893
1306	1590	2012-01-13 21:31:48.869751
923	2086	2012-01-13 22:49:21.433782
1450	1590	2012-01-13 21:31:57.648531
2006	2086	2012-01-13 22:49:21.433782
410	1594	2012-01-13 21:32:14.520605
1594	1245	2012-01-13 21:32:14.520605
2090	946	2012-01-13 22:50:25.71987
2090	1810	2012-01-13 22:50:25.71987
1458	1596	2012-01-13 21:32:30.269276
1534	1596	2012-01-13 21:32:30.269276
1498	1596	2012-01-13 21:32:30.269276
2090	827	2012-01-13 22:50:25.71987
1450	1030	2012-01-13 21:32:42.337126
1925	2090	2012-01-13 22:50:25.71987
1597	1572	2012-01-13 21:32:42.337126
1531	1597	2012-01-13 21:32:42.337126
1336	1597	2012-01-13 21:32:42.337126
1256	2091	2012-01-13 22:50:50.53451
1534	1599	2012-01-13 21:33:07.739636
1458	1599	2012-01-13 21:33:07.739636
1916	2091	2012-01-13 22:50:50.53451
882	1600	2012-01-13 21:33:20.209707
2049	2091	2012-01-13 22:50:50.53451
998	2093	2012-01-13 22:51:09.643044
1736	2082	2012-01-13 22:51:09.643044
923	1601	2012-01-13 21:33:32.556492
1050	2082	2012-01-13 22:51:09.643044
1855	2093	2012-01-13 22:51:09.643044
270	2093	2012-01-13 22:51:09.643044
2098	1515	2012-01-13 22:52:32.361397
1603	1470	2012-01-13 21:33:48.872888
2098	2008	2012-01-13 22:52:32.361397
1603	938	2012-01-13 21:33:48.872888
2100	1597	2012-01-13 22:53:03.605516
1603	1515	2012-01-13 21:33:48.872888
985	1604	2012-01-13 21:34:07.054946
656	1604	2012-01-13 21:34:07.054946
1606	1604	2012-01-13 21:34:23.59684
1252	1607	2012-01-13 21:34:26.493722
576	1607	2012-01-13 21:34:26.493722
1127	1607	2012-01-13 21:34:26.493722
1609	1470	2012-01-13 21:34:40.376754
2102	1447	2012-01-13 22:53:13.460943
1435	1609	2012-01-13 21:34:40.376754
1447	2039	2012-01-13 22:53:13.460943
2104	1259	2012-01-13 22:53:26.940262
1609	1515	2012-01-13 21:34:40.376754
898	1610	2012-01-13 21:35:03.592563
1383	1610	2012-01-13 21:35:03.592563
1611	1230	2012-01-13 21:35:13.162962
898	1494	2012-01-13 21:35:19.718042
1613	1127	2012-01-13 21:35:19.718042
300	1614	2012-01-13 21:35:25.650581
1170	1327	2012-01-13 22:53:26.940262
1007	1614	2012-01-13 21:35:25.650581
1527	2105	2012-01-13 22:53:37.061034
1611	1614	2012-01-13 21:35:25.650581
300	1615	2012-01-13 21:35:49.076625
2006	2050	2012-01-13 22:53:37.061034
1007	1615	2012-01-13 21:35:49.076625
1611	1615	2012-01-13 21:35:49.076625
300	1616	2012-01-13 21:36:11.95879
1616	1086	2012-01-13 21:36:11.95879
1616	939	2012-01-13 21:36:11.95879
1616	1604	2012-01-13 21:36:11.95879
2109	2016	2012-01-13 22:54:39.344883
1383	1617	2012-01-13 21:36:25.06458
898	1617	2012-01-13 21:36:25.06458
1608	1619	2012-01-13 21:36:34.01324
1619	1086	2012-01-13 21:36:34.01324
1619	939	2012-01-13 21:36:34.01324
1620	1085	2012-01-13 21:36:44.147037
2090	2109	2012-01-13 22:54:39.344883
2110	2013	2012-01-13 22:54:47.811513
1306	1621	2012-01-13 21:36:54.992068
1014	1621	2012-01-13 21:36:54.992068
1424	1621	2012-01-13 21:36:54.992068
1494	1621	2012-01-13 21:36:54.992068
623	1621	2012-01-13 21:36:54.992068
2110	2028	2012-01-13 22:54:47.811513
886	1622	2012-01-13 21:37:21.976382
1327	2111	2012-01-13 22:55:02.050562
1572	1623	2012-01-13 21:37:28.70698
1014	1625	2012-01-13 21:37:47.288883
1625	1470	2012-01-13 21:37:47.288883
1306	1625	2012-01-13 21:37:47.288883
1458	1306	2012-01-13 21:37:56.882082
1626	1526	2012-01-13 21:37:56.882082
1626	1085	2012-01-13 21:37:56.882082
1036	1617	2012-01-13 21:38:06.835004
2112	697	2012-01-13 22:55:11.766566
1800	2113	2012-01-13 22:55:16.734535
1609	1628	2012-01-13 21:38:13.756296
1628	773	2012-01-13 21:38:13.756296
2113	2039	2012-01-13 22:55:16.734535
623	1629	2012-01-13 21:38:28.639086
1306	1629	2012-01-13 21:38:28.639086
2113	2098	2012-01-13 22:55:16.734535
1014	1629	2012-01-13 21:38:28.639086
1424	1629	2012-01-13 21:38:28.639086
1064	1629	2012-01-13 21:38:28.639086
1307	1622	2012-01-13 21:38:28.639086
1540	1245	2012-01-13 21:38:55.879925
1007	1631	2012-01-13 21:38:55.879925
300	1631	2012-01-13 21:38:55.879925
1631	1530	2012-01-13 21:38:55.879925
1611	1631	2012-01-13 21:38:55.879925
1584	1604	2012-01-13 21:38:55.879925
1127	1632	2012-01-13 21:39:11.906254
1518	1632	2012-01-13 21:39:11.906254
1635	1245	2012-01-13 21:39:29.862834
1635	1388	2012-01-13 21:39:29.862834
1595	1530	2012-01-13 21:39:36.540068
98	2113	2012-01-13 22:55:16.734535
2114	2028	2012-01-13 22:55:33.914754
1586	1638	2012-01-13 21:39:53.177825
1347	1640	2012-01-13 21:40:00.248955
361	1640	2012-01-13 21:40:00.248955
1383	1640	2012-01-13 21:40:00.248955
899	1641	2012-01-13 21:40:09.542595
1518	1638	2012-01-13 21:40:15.991234
1608	1643	2012-01-13 21:40:19.025745
2115	960	2012-01-13 22:55:38.824412
1643	1317	2012-01-13 21:40:19.025745
144	1643	2012-01-13 21:40:19.025745
951	1617	2012-01-13 21:40:19.025745
1645	1215	2012-01-13 21:40:50.211211
3315	2296	2012-01-14 06:25:07.463064
1376	2571	2012-01-14 06:26:45.370978
1498	1645	2012-01-13 21:40:50.211211
2039	1626	2012-01-13 22:55:54.984886
1636	886	2012-01-13 21:41:01.322814
1559	1604	2012-01-13 21:41:01.322814
1458	1646	2012-01-13 21:41:01.322814
1646	1597	2012-01-13 21:41:01.322814
801	2118	2012-01-13 22:55:59.852773
1498	1646	2012-01-13 21:41:01.322814
1640	1086	2012-01-13 21:41:23.59494
1647	1596	2012-01-13 21:41:23.59494
1647	913	2012-01-13 21:41:23.59494
1336	1648	2012-01-13 21:41:33.679905
1649	1347	2012-01-13 21:41:36.988469
1820	2118	2012-01-13 22:55:59.852773
1230	1306	2012-01-13 21:42:04.6439
1654	1615	2012-01-13 21:42:04.6439
422	1654	2012-01-13 21:42:04.6439
1654	368	2012-01-13 21:42:04.6439
98	1640	2012-01-13 21:42:21.960568
882	1640	2012-01-13 21:42:21.960568
1656	1245	2012-01-13 21:42:27.609039
1327	2118	2012-01-13 22:55:59.852773
1036	1640	2012-01-13 21:42:27.609039
410	1108	2012-01-13 21:42:27.609039
1417	1657	2012-01-13 21:42:39.540514
1574	1628	2012-01-13 21:42:39.540514
1519	1657	2012-01-13 21:42:39.540514
1491	1596	2012-01-13 21:42:39.540514
1574	1658	2012-01-13 21:42:53.855111
1417	1648	2012-01-13 21:42:53.855111
1659	1465	2012-01-13 21:43:00.48666
2006	2119	2012-01-13 22:56:14.582559
1613	1659	2012-01-13 21:43:00.48666
1800	2119	2012-01-13 22:56:14.582559
985	1660	2012-01-13 21:43:12.84868
1660	629	2012-01-13 21:43:12.84868
1525	1660	2012-01-13 21:43:12.84868
923	1640	2012-01-13 21:43:12.84868
1347	1662	2012-01-13 21:43:28.45012
361	1662	2012-01-13 21:43:28.45012
1665	1537	2012-01-13 21:43:43.506304
1666	1470	2012-01-13 21:43:50.733116
1665	1615	2012-01-13 21:43:54.87305
1665	1513	2012-01-13 21:43:54.87305
1122	1668	2012-01-13 21:44:10.69988
1651	1596	2012-01-13 21:44:35.574484
1289	1670	2012-01-13 21:44:38.72792
811	1530	2012-01-13 21:44:45.64593
1252	1628	2012-01-13 21:44:45.64593
1519	1671	2012-01-13 21:44:59.458457
1215	1229	2012-01-13 21:44:59.458457
923	2119	2012-01-13 22:56:14.582559
1306	882	2012-01-13 21:44:59.458457
1519	1675	2012-01-13 21:45:13.586625
1651	1646	2012-01-13 21:45:13.586625
801	1675	2012-01-13 21:45:13.586625
1454	1677	2012-01-13 21:45:34.225213
1678	939	2012-01-13 21:45:37.741246
410	1679	2012-01-13 21:45:43.827811
98	2119	2012-01-13 22:56:14.582559
144	1679	2012-01-13 21:45:43.827811
1518	1515	2012-01-13 21:46:03.161952
1306	1681	2012-01-13 21:46:03.161952
1014	1681	2012-01-13 21:46:03.161952
995	1681	2012-01-13 21:46:03.161952
1424	1681	2012-01-13 21:46:03.161952
300	1682	2012-01-13 21:46:18.581431
3320	3166	2012-01-14 06:27:12.925132
2079	2090	2012-01-13 22:56:14.582559
1651	1687	2012-01-13 21:46:44.714425
1458	1687	2012-01-13 21:46:44.714425
1531	1689	2012-01-13 21:46:53.438864
1628	1689	2012-01-13 21:46:53.438864
1692	1625	2012-01-13 21:47:18.541476
1646	1689	2012-01-13 21:47:18.541476
1362	1628	2012-01-13 21:47:28.720642
1694	1269	2012-01-13 21:47:34.625764
1694	1442	2012-01-13 21:47:34.625764
1695	985	2012-01-13 21:47:40.954385
1215	2120	2012-01-13 22:56:52.150844
385	1625	2012-01-13 21:47:40.954385
1696	1694	2012-01-13 21:47:50.819385
1662	1086	2012-01-13 21:47:54.19488
1697	1662	2012-01-13 21:47:54.19488
361	1698	2012-01-13 21:48:01.896011
1347	1698	2012-01-13 21:48:01.896011
2120	1757	2012-01-13 22:56:52.150844
300	1699	2012-01-13 21:48:10.939315
1007	1699	2012-01-13 21:48:10.939315
1346	1551	2012-01-13 22:56:52.150844
1611	1699	2012-01-13 21:48:10.939315
1252	1700	2012-01-13 21:48:21.1727
1362	1700	2012-01-13 21:48:21.1727
583	1702	2012-01-13 21:48:31.020647
1351	1702	2012-01-13 21:48:31.020647
576	1515	2012-01-13 21:48:31.020647
576	1470	2012-01-13 21:48:31.020647
1170	1328	2012-01-13 21:48:31.020647
1525	939	2012-01-13 21:48:31.020647
617	1704	2012-01-13 21:49:04.086069
576	1700	2012-01-13 21:49:04.086069
1574	1700	2012-01-13 21:49:10.43218
369	1705	2012-01-13 21:49:10.43218
2121	2028	2012-01-13 22:57:07.53215
832	1705	2012-01-13 21:49:10.43218
1051	2121	2012-01-13 22:57:07.53215
1565	2121	2012-01-13 22:57:07.53215
1259	1888	2012-01-13 22:57:21.622704
1707	1702	2012-01-13 21:49:53.862638
278	1700	2012-01-13 21:50:00.893089
1702	543	2012-01-13 21:50:00.893089
1709	985	2012-01-13 21:50:07.852055
1710	1700	2012-01-13 21:50:10.631105
1170	1524	2012-01-13 22:57:21.622704
1710	1470	2012-01-13 21:50:10.631105
1710	1515	2012-01-13 21:50:10.631105
1782	1713	2012-01-13 22:57:53.470697
882	1711	2012-01-13 21:50:28.953361
1347	1711	2012-01-13 21:50:28.953361
1586	1700	2012-01-13 21:50:28.953361
2126	801	2012-01-13 22:57:58.05438
1711	1586	2012-01-13 21:50:28.953361
2114	2128	2012-01-13 22:58:13.489358
3335	3337	2012-01-14 06:27:25.088944
98	1711	2012-01-13 21:50:28.953361
361	1711	2012-01-13 21:50:28.953361
2121	2128	2012-01-13 22:58:13.489358
1026	1712	2012-01-13 21:50:59.00882
1712	981	2012-01-13 21:50:59.00882
1713	1702	2012-01-13 21:51:09.23469
1458	2121	2012-01-13 22:58:13.489358
1985	2130	2012-01-13 22:58:34.878021
1458	2132	2012-01-13 22:58:55.107336
1671	2117	2012-01-13 22:58:55.107336
410	1715	2012-01-13 21:51:31.640996
1051	2132	2012-01-13 22:58:55.107336
1717	543	2012-01-13 21:51:46.382012
1442	1717	2012-01-13 21:51:46.382012
1700	1718	2012-01-13 21:51:52.482874
1721	564	2012-01-13 21:52:17.682456
1721	583	2012-01-13 21:52:17.682456
1646	1671	2012-01-13 21:52:17.682456
1611	1721	2012-01-13 21:52:17.682456
1951	2133	2012-01-13 22:59:09.29923
1723	1705	2012-01-13 21:52:31.944363
1723	1713	2012-01-13 21:52:31.944363
2135	2086	2012-01-13 22:59:30.925089
1611	1723	2012-01-13 21:52:31.944363
872	1695	2012-01-13 21:52:31.944363
1635	1712	2012-01-13 21:52:44.222415
1424	1498	2012-01-13 21:52:44.222415
1347	1534	2012-01-13 21:52:44.222415
1726	1307	2012-01-13 21:52:55.699881
1362	1695	2012-01-13 21:52:55.699881
1531	1671	2012-01-13 21:53:01.357892
98	1662	2012-01-13 21:53:01.357892
1695	1372	2012-01-13 21:53:01.357892
2086	1515	2012-01-13 22:59:30.925089
1729	1269	2012-01-13 21:53:17.413459
638	1729	2012-01-13 21:53:17.413459
886	1465	2012-01-13 21:53:24.013664
2135	1005	2012-01-13 22:59:30.925089
3191	3337	2012-01-14 06:27:25.088944
1259	1731	2012-01-13 21:53:30.795545
1269	1731	2012-01-13 21:53:30.795545
1732	1717	2012-01-13 21:53:44.289552
1708	1733	2012-01-13 21:53:51.062178
1712	1733	2012-01-13 21:53:51.062178
300	1735	2012-01-13 21:54:08.204054
1192	2135	2012-01-13 22:59:30.925089
1007	1735	2012-01-13 21:54:08.204054
1916	2136	2012-01-13 23:00:04.085378
2049	2136	2012-01-13 23:00:04.085378
1611	1735	2012-01-13 21:54:08.204054
1161	1729	2012-01-13 21:54:25.272036
1095	1737	2012-01-13 21:54:28.582879
1730	1738	2012-01-13 21:54:32.140968
2043	2136	2012-01-13 23:00:04.085378
1712	1737	2012-01-13 21:54:32.140968
2138	1515	2012-01-13 23:00:23.290027
1739	1662	2012-01-13 21:54:42.352811
985	1740	2012-01-13 21:54:50.566914
3339	3085	2012-01-14 06:29:36.683598
923	1662	2012-01-13 21:54:50.566914
1708	1737	2012-01-13 21:55:00.474442
2138	2008	2012-01-13 23:00:23.290027
1855	2139	2012-01-13 23:00:39.189288
1951	2122	2012-01-13 23:00:39.189288
1100	1742	2012-01-13 21:55:16.837897
1458	1743	2012-01-13 21:55:27.368698
1743	1733	2012-01-13 21:55:27.368698
1591	2016	2012-01-13 23:00:39.189288
1696	3299	2012-01-14 06:29:50.261269
1534	1743	2012-01-13 21:55:27.368698
272	1743	2012-01-13 21:55:27.368698
369	2139	2012-01-13 23:00:39.189288
1744	1458	2012-01-13 21:55:49.718399
1744	1161	2012-01-13 21:55:49.718399
300	1745	2012-01-13 21:55:55.838017
1007	1745	2012-01-13 21:55:55.838017
1611	1745	2012-01-13 21:55:55.838017
1746	1671	2012-01-13 21:56:07.737805
1597	1702	2012-01-13 21:56:07.737805
2059	2140	2012-01-13 23:01:04.264517
3321	3216	2012-01-14 06:29:50.261269
1417	1748	2012-01-13 21:56:32.897278
801	1748	2012-01-13 21:56:32.897278
1646	1748	2012-01-13 21:56:32.897278
1531	1749	2012-01-13 21:56:42.857781
1157	1749	2012-01-13 21:56:42.857781
1749	1733	2012-01-13 21:56:42.857781
1750	1465	2012-01-13 21:56:53.150447
1327	1748	2012-01-13 21:56:53.150447
1751	1515	2012-01-13 21:57:00.227107
985	2140	2012-01-13 23:01:04.264517
1026	1750	2012-01-13 21:57:00.227107
1752	1699	2012-01-13 21:57:11.429736
410	1752	2012-01-13 21:57:11.429736
1752	1745	2012-01-13 21:57:11.429736
1729	1753	2012-01-13 21:57:22.085192
2114	2141	2012-01-13 23:01:22.826355
2006	2145	2012-01-13 23:01:51.735694
543	1708	2012-01-13 21:57:31.741251
2039	2146	2012-01-13 23:01:56.318292
410	1755	2012-01-13 21:57:39.027227
144	1755	2012-01-13 21:57:39.027227
1756	939	2012-01-13 21:57:47.100799
1635	1750	2012-01-13 21:57:50.443771
1959	2146	2012-01-13 23:01:56.318292
857	1757	2012-01-13 21:57:50.443771
1917	2146	2012-01-13 23:01:56.318292
3340	3321	2012-01-14 06:29:50.261269
2148	1515	2012-01-13 23:02:16.431421
1756	1660	2012-01-13 21:58:21.16923
1760	1702	2012-01-13 21:58:21.16923
1761	1215	2012-01-13 21:58:28.455531
1820	2149	2012-01-13 23:02:26.120031
1730	543	2012-01-13 21:58:28.455531
1762	913	2012-01-13 21:58:39.370938
144	1762	2012-01-13 21:58:39.370938
1916	1327	2012-01-13 23:02:26.120031
1752	1763	2012-01-13 21:58:50.569159
2150	1824	2012-01-13 23:02:36.380675
2150	1631	2012-01-13 23:02:36.380675
832	1729	2012-01-13 21:59:17.322442
1767	913	2012-01-13 21:59:17.322442
1514	1729	2012-01-13 21:59:17.322442
1767	1341	2012-01-13 21:59:17.322442
278	1770	2012-01-13 21:59:51.221738
576	1770	2012-01-13 21:59:51.221738
1259	1729	2012-01-13 21:59:51.221738
1730	886	2012-01-13 21:59:51.221738
1194	886	2012-01-13 21:59:51.221738
2151	2145	2012-01-13 23:02:51.502364
1772	1760	2012-01-13 22:00:18.555751
1753	1245	2012-01-13 22:00:37.627424
1775	1702	2012-01-13 22:00:41.495542
2151	2086	2012-01-13 23:02:51.502364
2151	1005	2012-01-13 23:02:51.502364
144	2153	2012-01-13 23:03:26.329626
385	1776	2012-01-13 22:00:56.11528
623	1776	2012-01-13 22:00:56.11528
1347	1494	2012-01-13 22:00:56.11528
1170	1778	2012-01-13 22:01:10.546664
1695	1778	2012-01-13 22:01:10.546664
1696	1729	2012-01-13 22:01:10.546664
1767	1335	2012-01-13 22:01:24.228911
1758	1780	2012-01-13 22:01:28.017965
2098	2154	2012-01-13 23:03:39.68284
1442	1780	2012-01-13 22:01:28.017965
1531	1748	2012-01-13 22:01:38.644908
2114	1631	2012-01-13 23:04:29.021795
1729	1328	2012-01-13 22:01:46.42016
1458	1341	2012-01-13 22:01:57.890654
2158	2122	2012-01-13 23:04:34.258444
2112	2158	2012-01-13 23:04:34.258444
385	3296	2012-01-14 06:29:50.261269
1774	1787	2012-01-13 22:02:19.153065
361	1788	2012-01-13 22:02:26.823191
1347	1788	2012-01-13 22:02:26.823191
2159	1917	2012-01-13 23:04:49.485074
2059	1740	2012-01-13 23:04:49.485074
1695	1442	2012-01-13 22:02:41.360277
985	1086	2012-01-13 22:02:45.042459
1790	1713	2012-01-13 22:02:45.042459
1792	913	2012-01-13 22:02:57.701632
1757	2160	2012-01-13 23:04:58.723105
1695	1327	2012-01-13 22:03:05.819077
1580	1794	2012-01-13 22:03:09.715955
1796	1708	2012-01-13 22:03:17.592506
998	1729	2012-01-13 22:03:21.602107
1798	1735	2012-01-13 22:03:25.147371
1616	1798	2012-01-13 22:03:25.147371
1711	1256	2012-01-13 22:03:36.397214
1799	1695	2012-01-13 22:03:36.397214
1800	1534	2012-01-13 22:03:43.771618
1800	1711	2012-01-13 22:03:47.589372
3315	3341	2012-01-14 06:31:20.159864
144	1752	2012-01-13 22:03:47.589372
617	1671	2012-01-13 22:03:47.589372
1801	1215	2012-01-13 22:03:47.589372
985	1798	2012-01-13 22:04:07.465443
1695	1269	2012-01-13 22:04:07.465443
1917	2162	2012-01-13 23:05:18.840765
1959	2162	2012-01-13 23:05:18.840765
1782	1729	2012-01-13 22:04:19.524417
1805	1743	2012-01-13 22:04:26.826771
1540	1794	2012-01-13 22:04:30.971077
1036	2163	2012-01-13 23:05:29.177518
1798	1699	2012-01-13 22:04:39.297055
2151	2163	2012-01-13 23:05:29.177518
1498	913	2012-01-13 22:04:48.521655
1458	1809	2012-01-13 22:04:54.623318
1792	1809	2012-01-13 22:04:54.623318
985	1810	2012-01-13 22:05:05.993656
1811	1631	2012-01-13 22:05:09.568288
1811	1616	2012-01-13 22:05:09.568288
1646	1814	2012-01-13 22:05:38.644478
2006	2163	2012-01-13 23:05:29.177518
1729	1327	2012-01-13 22:05:38.644478
1753	1794	2012-01-13 22:05:52.060271
1855	2164	2012-01-13 23:06:01.371056
1800	1788	2012-01-13 22:06:19.323623
1122	2164	2012-01-13 23:06:01.371056
1729	1818	2012-01-13 22:06:28.052861
2875	3341	2012-01-14 06:31:20.159864
1820	1671	2012-01-13 22:06:44.550109
1823	543	2012-01-13 22:06:56.853537
978	1823	2012-01-13 22:06:56.853537
1798	1824	2012-01-13 22:07:04.929955
882	1827	2012-01-13 22:07:20.909753
1036	1827	2012-01-13 22:07:20.909753
361	1827	2012-01-13 22:07:20.909753
1800	1827	2012-01-13 22:07:20.909753
1347	1827	2012-01-13 22:07:20.909753
1828	1794	2012-01-13 22:07:40.512654
3033	3065	2012-01-14 06:32:48.584655
1808	1829	2012-01-13 22:07:49.506895
1816	1829	2012-01-13 22:07:49.506895
1800	1831	2012-01-13 22:08:05.705961
1347	1831	2012-01-13 22:08:05.705961
1249	2166	2012-01-13 23:06:22.490174
1036	1831	2012-01-13 22:08:05.705961
1818	960	2012-01-13 22:08:20.943448
827	2160	2012-01-13 23:06:22.490174
1835	1702	2012-01-13 22:08:41.379654
1458	2166	2012-01-13 23:06:22.490174
1818	1646	2012-01-13 22:08:51.494408
1531	1814	2012-01-13 22:08:51.494408
1818	1837	2012-01-13 22:08:59.799869
1837	1702	2012-01-13 22:08:59.799869
1906	2166	2012-01-13 23:06:22.490174
758	2166	2012-01-13 23:06:22.490174
886	1838	2012-01-13 22:09:21.090987
763	1838	2012-01-13 22:09:21.090987
2167	1930	2012-01-13 23:07:00.15751
2171	2165	2012-01-13 23:07:22.203711
3342	3299	2012-01-14 06:32:48.584655
1811	1839	2012-01-13 22:09:29.651406
1839	653	2012-01-13 22:09:29.651406
998	1840	2012-01-13 22:09:45.947554
1782	1840	2012-01-13 22:09:45.947554
1792	832	2012-01-13 22:09:45.947554
1800	1841	2012-01-13 22:09:59.031476
882	1841	2012-01-13 22:09:59.031476
1347	1841	2012-01-13 22:09:59.031476
361	1841	2012-01-13 22:09:59.031476
1222	1842	2012-01-13 22:10:20.265254
1626	1842	2012-01-13 22:10:20.265254
882	1788	2012-01-13 22:10:28.176726
1798	1745	2012-01-13 22:10:32.446837
2114	1824	2012-01-13 23:07:37.900413
1818	820	2012-01-13 22:10:36.778071
1646	1847	2012-01-13 22:11:04.253984
1855	1713	2012-01-13 23:07:37.900413
1792	1646	2012-01-13 22:11:04.253984
1848	1702	2012-01-13 22:11:17.075117
1259	1959	2012-01-13 23:07:47.97185
1580	1849	2012-01-13 22:11:25.333224
1838	543	2012-01-13 22:11:25.333224
1646	1851	2012-01-13 22:11:44.156894
1843	1851	2012-01-13 22:11:44.156894
2173	1170	2012-01-13 23:07:47.97185
1417	1851	2012-01-13 22:11:44.156894
1457	1851	2012-01-13 22:11:44.156894
1852	1269	2012-01-13 22:12:07.827345
1707	1854	2012-01-13 22:12:17.137572
3315	3343	2012-01-14 06:33:40.251893
1738	2073	2012-01-13 23:07:47.97185
1798	1537	2012-01-13 22:12:29.589975
1855	1540	2012-01-13 22:12:29.589975
1818	913	2012-01-13 22:12:29.589975
1843	1814	2012-01-13 22:12:29.589975
1774	1458	2012-01-13 23:07:47.97185
2173	1525	2012-01-13 23:07:47.97185
1841	1857	2012-01-13 22:13:01.909331
1906	2173	2012-01-13 23:07:47.97185
2008	2174	2012-01-13 23:08:29.863735
882	1864	2012-01-13 22:13:49.771948
1800	1864	2012-01-13 22:13:49.771948
1137	1865	2012-01-13 22:13:57.330754
1828	1865	2012-01-13 22:13:57.330754
1868	1213	2012-01-13 22:14:29.146419
1992	2177	2012-01-13 23:09:22.829591
2178	1005	2012-01-13 23:09:34.398047
576	1695	2012-01-13 22:14:42.730576
2008	2179	2012-01-13 23:09:46.072787
2180	2039	2012-01-13 23:09:51.161808
1458	1993	2012-01-13 23:09:51.161808
2073	2183	2012-01-13 23:10:27.5679
1872	1851	2012-01-13 22:15:12.155588
1811	1872	2012-01-13 22:15:12.155588
1999	2183	2012-01-13 23:10:27.5679
3344	3322	2012-01-14 06:34:11.645811
1713	2174	2012-01-13 23:10:43.683098
1873	1222	2012-01-13 22:15:29.007046
1874	1806	2012-01-13 22:15:33.196879
1713	1870	2012-01-13 22:15:37.183337
1792	1875	2012-01-13 22:15:37.183337
1818	1876	2012-01-13 22:15:45.546448
1458	1876	2012-01-13 22:15:45.546448
1792	1876	2012-01-13 22:15:45.546448
1858	1823	2012-01-13 22:16:27.663261
3315	1950	2012-01-14 06:34:11.645811
3321	2772	2012-01-14 06:34:11.645811
327	1851	2012-01-13 22:16:46.617889
1613	1880	2012-01-13 22:16:46.617889
1881	1806	2012-01-13 22:16:55.858142
2187	2184	2012-01-13 23:11:20.138478
1782	1440	2012-01-13 23:11:20.138478
1838	1880	2012-01-13 22:17:24.139234
1824	2174	2012-01-13 23:11:30.666849
2098	1921	2012-01-13 23:11:30.666849
1816	1858	2012-01-13 22:17:48.068448
1887	1816	2012-01-13 22:17:48.068448
2049	1889	2012-01-13 23:11:30.666849
439	1888	2012-01-13 22:17:56.512097
778	1889	2012-01-13 22:18:06.730674
910	2184	2012-01-13 23:11:30.666849
1458	913	2012-01-13 22:18:15.311362
2006	2189	2012-01-13 23:11:52.169747
1892	1515	2012-01-13 22:18:33.904903
3208	3345	2012-01-14 06:35:47.801919
3234	3345	2012-01-14 06:35:47.801919
1798	1389	2012-01-13 22:18:33.904903
2151	2189	2012-01-13 23:11:52.169747
2191	2183	2012-01-13 23:12:17.824331
3315	3346	2012-01-14 06:36:45.44487
2192	2183	2012-01-13 23:12:38.94013
3264	3342	2012-01-14 06:37:31.007242
2151	2193	2012-01-13 23:12:59.315714
2008	2194	2012-01-13 23:13:04.142989
1713	2194	2012-01-13 23:13:04.142989
3181	3349	2012-01-14 06:38:05.991855
1930	2183	2012-01-13 23:13:18.929063
1636	3349	2012-01-14 06:38:05.991855
2114	2197	2012-01-13 23:13:46.817856
2150	2197	2012-01-13 23:13:46.817856
1926	2183	2012-01-13 23:13:46.817856
3296	3350	2012-01-14 06:38:29.016661
3315	3352	2012-01-14 06:39:20.008153
1993	2197	2012-01-13 23:13:46.817856
1858	2198	2012-01-13 23:14:17.044782
1238	2198	2012-01-13 23:14:17.044782
2199	1249	2012-01-13 23:14:28.12461
2150	1051	2012-01-13 23:14:28.12461
1738	2200	2012-01-13 23:14:37.785046
2177	1921	2012-01-13 23:14:37.785046
1931	2200	2012-01-13 23:14:55.351989
2177	2008	2012-01-13 23:14:55.351989
2085	2202	2012-01-13 23:15:04.637681
2114	2203	2012-01-13 23:15:21.727778
1238	2202	2012-01-13 23:15:21.727778
3244	3296	2012-01-14 06:39:20.008153
2875	3352	2012-01-14 06:39:20.008153
1993	2203	2012-01-13 23:15:21.727778
1858	2202	2012-01-13 23:15:45.733502
2205	2164	2012-01-13 23:15:52.625281
1740	2207	2012-01-13 23:16:08.501706
2151	2208	2012-01-13 23:16:14.028528
98	2208	2012-01-13 23:16:14.028528
1036	2208	2012-01-13 23:16:14.028528
1995	2183	2012-01-13 23:16:14.028528
15	2208	2012-01-13 23:16:14.028528
2209	1713	2012-01-13 23:16:45.392659
2164	2183	2012-01-13 23:16:45.392659
2210	2132	2012-01-13 23:16:57.714412
1710	2207	2012-01-13 23:17:09.63935
2120	2212	2012-01-13 23:17:16.572697
3353	3154	2012-01-14 06:40:13.828677
1778	3349	2012-01-14 06:40:13.828677
3355	3349	2012-01-14 06:40:50.97574
2213	697	2012-01-13 23:17:33.386898
1095	2215	2012-01-13 23:17:59.090134
1858	2215	2012-01-13 23:17:59.090134
3355	3085	2012-01-14 06:40:50.97574
1238	2215	2012-01-13 23:17:59.090134
1836	2215	2012-01-13 23:17:59.090134
2216	2202	2012-01-13 23:18:26.72595
1327	1736	2012-01-13 23:18:33.608775
2217	758	2012-01-13 23:18:33.608775
2217	1906	2012-01-13 23:18:33.608775
1736	2220	2012-01-13 23:18:58.48931
1774	2220	2012-01-13 23:18:58.48931
1890	2220	2012-01-13 23:18:58.48931
2117	2220	2012-01-13 23:18:58.48931
1671	2224	2012-01-13 23:20:10.696424
1840	2224	2012-01-13 23:20:10.696424
2112	2224	2012-01-13 23:20:10.696424
2049	2225	2012-01-13 23:20:25.981421
1916	2225	2012-01-13 23:20:25.981421
3315	2076	2012-01-14 06:42:53.982416
2043	2225	2012-01-13 23:20:25.981421
1993	3196	2012-01-14 06:42:53.982416
423	2227	2012-01-13 23:21:03.692046
1017	2227	2012-01-13 23:21:03.692046
1482	2202	2012-01-13 23:22:07.97587
1095	2202	2012-01-13 23:22:14.864629
1985	2232	2012-01-13 23:22:14.864629
1789	2232	2012-01-13 23:22:14.864629
2233	1752	2012-01-13 23:22:31.741921
2233	2153	2012-01-13 23:22:31.741921
2233	1762	2012-01-13 23:22:31.741921
2235	2154	2012-01-13 23:22:57.08068
2235	2008	2012-01-13 23:22:57.08068
2232	2224	2012-01-13 23:22:57.08068
2114	2236	2012-01-13 23:23:14.342232
2237	1736	2012-01-13 23:23:19.072162
2237	1671	2012-01-13 23:23:19.072162
3355	3095	2012-01-14 06:43:47.476014
2069	2202	2012-01-13 23:23:36.598812
2238	2189	2012-01-13 23:23:36.598812
3360	3278	2012-01-14 06:43:58.138593
1883	3321	2012-01-14 06:43:58.138593
2240	957	2012-01-13 23:24:04.584474
1808	2235	2012-01-13 23:24:04.584474
3033	3360	2012-01-14 06:43:58.138593
3235	3361	2012-01-14 06:44:49.065845
1626	2242	2012-01-13 23:24:27.518388
2154	2242	2012-01-13 23:24:27.518388
2112	2242	2012-01-13 23:24:27.518388
2875	3362	2012-01-14 06:45:00.528165
1602	2243	2012-01-13 23:24:55.338308
2157	1642	2012-01-13 23:24:55.338308
2267	3362	2012-01-14 06:45:00.528165
2233	2244	2012-01-13 23:25:18.037122
2287	3362	2012-01-14 06:45:00.528165
1951	2235	2012-01-13 23:25:26.121234
2905	3362	2012-01-14 06:45:00.528165
1256	2245	2012-01-13 23:25:26.121234
2943	3313	2012-01-14 06:45:51.309596
2251	2112	2012-01-13 23:26:42.127536
3147	3313	2012-01-14 06:45:51.309596
2251	2120	2012-01-13 23:26:42.127536
3364	3258	2012-01-14 06:46:12.262448
2253	2242	2012-01-13 23:27:40.591252
2151	2255	2012-01-13 23:28:01.755571
3365	3065	2012-01-14 06:46:59.464649
3368	3321	2012-01-14 06:47:59.331523
2257	2227	2012-01-13 23:29:08.437975
1599	2258	2012-01-13 23:29:19.645779
1696	2259	2012-01-13 23:29:31.664011
1855	2259	2012-01-13 23:29:31.664011
2260	2154	2012-01-13 23:29:48.276224
3321	3369	2012-01-14 06:48:31.154932
2260	1921	2012-01-13 23:29:48.276224
2114	2264	2012-01-13 23:30:51.341697
2150	2264	2012-01-13 23:30:51.341697
2267	624	2012-01-13 23:31:52.537981
2765	3369	2012-01-14 06:48:31.154932
1738	2258	2012-01-13 23:31:58.550117
2114	2268	2012-01-13 23:31:58.550117
1442	2242	2012-01-13 23:32:14.41579
816	2227	2012-01-13 23:32:14.41579
1447	3369	2012-01-14 06:48:31.154932
2353	3299	2012-01-14 06:48:31.154932
2271	2194	2012-01-13 23:32:50.266621
2273	2227	2012-01-13 23:33:46.92471
1238	2274	2012-01-13 23:33:52.761264
1836	2274	2012-01-13 23:33:52.761264
2275	2258	2012-01-13 23:34:04.605962
1642	2275	2012-01-13 23:34:04.605962
3370	3299	2012-01-14 06:49:31.969001
902	2275	2012-01-13 23:34:04.605962
2875	3370	2012-01-14 06:49:31.969001
2276	1738	2012-01-13 23:34:28.47861
2140	2242	2012-01-13 23:34:41.150758
2279	2215	2012-01-13 23:34:59.344644
2280	2259	2012-01-13 23:35:05.102989
2284	827	2012-01-13 23:35:50.426594
2059	623	2012-01-13 23:35:56.494305
758	2286	2012-01-13 23:36:07.66371
2905	3370	2012-01-14 06:49:31.969001
2267	2244	2012-01-13 23:36:07.66371
1906	2286	2012-01-13 23:36:07.66371
2287	624	2012-01-13 23:36:30.110553
2288	2284	2012-01-13 23:36:37.29211
2233	3370	2012-01-14 06:49:31.969001
1642	2274	2012-01-13 23:36:37.29211
2290	2154	2012-01-13 23:37:33.09461
3296	2000	2012-01-14 06:50:58.466481
2232	2242	2012-01-13 23:37:33.09461
2267	2291	2012-01-13 23:37:53.91398
2287	2291	2012-01-13 23:37:53.91398
2291	2284	2012-01-13 23:37:53.91398
2233	2291	2012-01-13 23:37:53.91398
2291	2105	2012-01-13 23:37:53.91398
144	2291	2012-01-13 23:37:53.91398
1671	2242	2012-01-13 23:38:42.024533
3125	3372	2012-01-14 06:50:58.466481
623	2292	2012-01-13 23:38:42.024533
1458	2293	2012-01-13 23:39:06.445425
1642	2295	2012-01-13 23:39:36.152319
3375	2468	2012-01-14 06:52:12.266798
2295	2277	2012-01-13 23:39:36.152319
1238	2295	2012-01-13 23:39:36.152319
2295	910	2012-01-13 23:39:36.152319
2267	2296	2012-01-13 23:40:19.555584
2233	2296	2012-01-13 23:40:19.555584
827	2258	2012-01-13 23:40:19.555584
2287	2296	2012-01-13 23:40:19.555584
144	2296	2012-01-13 23:40:19.555584
3379	2983	2012-01-14 06:53:42.736456
3379	3132	2012-01-14 06:53:42.736456
2298	2118	2012-01-13 23:41:12.396
2300	2292	2012-01-13 23:41:38.280353
2301	910	2012-01-13 23:41:44.447217
2280	2302	2012-01-13 23:41:57.439171
3380	3106	2012-01-14 06:54:23.774063
1995	3313	2012-01-14 06:54:23.774063
2287	2244	2012-01-13 23:42:16.109411
2303	2284	2012-01-13 23:42:16.109411
758	2303	2012-01-13 23:42:16.109411
2287	2304	2012-01-13 23:43:09.321135
2233	2304	2012-01-13 23:43:09.321135
2304	2274	2012-01-13 23:43:09.321135
3381	3126	2012-01-14 06:55:29.98471
3136	3382	2012-01-14 06:55:41.782152
2304	2275	2012-01-13 23:43:09.321135
3293	3382	2012-01-14 06:55:41.782152
3383	3285	2012-01-14 06:56:06.002934
3383	3234	2012-01-14 06:56:06.002934
144	2304	2012-01-13 23:43:09.321135
3132	3234	2012-01-14 06:56:30.532413
3385	3275	2012-01-14 06:56:54.06088
3387	3349	2012-01-14 06:57:18.374622
2280	1713	2012-01-13 23:44:47.535056
2306	2059	2012-01-13 23:44:53.370481
2425	3321	2012-01-14 06:57:41.767598
3389	1847	2012-01-14 06:57:41.767598
2875	3235	2012-01-14 06:57:41.767598
3389	3355	2012-01-14 06:57:41.767598
3389	3384	2012-01-14 06:57:41.767598
2310	1752	2012-01-13 23:46:27.748285
3382	2733	2012-01-14 06:59:25.278498
2311	2277	2012-01-13 23:46:41.663922
1458	2286	2012-01-13 23:46:41.663922
2114	1735	2012-01-13 23:47:06.402068
2317	2225	2012-01-13 23:48:08.53411
2043	2318	2012-01-13 23:48:14.624217
1992	2318	2012-01-13 23:48:14.624217
2318	2302	2012-01-13 23:48:14.624217
1642	2320	2012-01-13 23:48:38.290222
2320	2140	2012-01-13 23:48:38.290222
2321	2151	2012-01-13 23:48:50.124554
1739	2322	2012-01-13 23:48:55.654657
2151	2322	2012-01-13 23:48:55.654657
3393	2590	2012-01-14 06:59:50.121205
2238	2322	2012-01-13 23:48:55.654657
1931	2323	2012-01-13 23:49:18.568387
2212	2323	2012-01-13 23:49:18.568387
2324	2162	2012-01-13 23:49:32.183577
2281	2324	2012-01-13 23:49:32.183577
2325	2302	2012-01-13 23:49:45.333074
2100	2325	2012-01-13 23:49:45.333074
1431	2325	2012-01-13 23:49:45.333074
2326	1599	2012-01-13 23:50:11.859755
2327	697	2012-01-13 23:50:18.753001
2330	827	2012-01-13 23:50:51.550134
2281	2332	2012-01-13 23:51:17.220713
3385	3216	2012-01-14 06:59:50.121205
923	2334	2012-01-13 23:51:49.238531
2233	3393	2012-01-14 06:59:50.121205
1036	2334	2012-01-13 23:51:49.238531
1697	2334	2012-01-13 23:51:49.238531
2335	2112	2012-01-13 23:52:12.599803
2280	1840	2012-01-13 23:52:12.599803
1249	2337	2012-01-13 23:52:42.471613
2326	2337	2012-01-13 23:52:42.471613
2338	2118	2012-01-13 23:52:53.88844
2339	2274	2012-01-13 23:53:00.334695
2233	2339	2012-01-13 23:53:00.334695
2339	2275	2012-01-13 23:53:00.334695
2287	2339	2012-01-13 23:53:00.334695
2339	2295	2012-01-13 23:53:00.334695
2069	2274	2012-01-13 23:53:31.004294
2287	3393	2012-01-14 06:59:50.121205
2341	2166	2012-01-13 23:53:37.809156
1993	2342	2012-01-13 23:53:50.435348
2212	2258	2012-01-13 23:53:50.435348
2150	2342	2012-01-13 23:53:50.435348
2233	2343	2012-01-13 23:54:13.577377
2267	2343	2012-01-13 23:54:13.577377
3393	1926	2012-01-14 06:59:50.121205
3384	2983	2012-01-14 06:59:50.121205
3321	1458	2012-01-14 06:59:50.121205
2287	2343	2012-01-13 23:54:13.577377
2286	2344	2012-01-13 23:54:51.410586
2049	2344	2012-01-13 23:54:51.410586
1256	2344	2012-01-13 23:54:51.410586
3355	2485	2012-01-14 06:59:50.121205
2345	2344	2012-01-13 23:55:22.368161
1994	2345	2012-01-13 23:55:22.368161
2345	1327	2012-01-13 23:55:22.368161
2888	2673	2012-01-14 06:59:50.121205
2284	2347	2012-01-13 23:55:55.152637
3393	2149	2012-01-14 06:59:50.121205
15	2348	2012-01-13 23:56:07.231836
1527	923	2012-01-13 23:56:07.231836
2059	2347	2012-01-13 23:56:24.242306
2150	1735	2012-01-13 23:56:30.53248
2351	2290	2012-01-13 23:56:36.672889
2352	2295	2012-01-13 23:56:43.775553
2352	2274	2012-01-13 23:56:43.775553
3393	3384	2012-01-14 06:59:50.121205
3363	3394	2012-01-14 07:02:53.806006
2353	1713	2012-01-13 23:57:11.704274
2150	2355	2012-01-13 23:57:25.467902
2114	2355	2012-01-13 23:57:25.467902
2356	2344	2012-01-13 23:57:37.077953
2114	2356	2012-01-13 23:57:37.077953
1144	2350	2012-01-13 23:57:37.077953
3160	3394	2012-01-14 07:02:53.806006
1993	2356	2012-01-13 23:57:37.077953
2233	3395	2012-01-14 07:03:17.281949
2212	2359	2012-01-13 23:58:53.869838
827	2359	2012-01-13 23:58:53.869838
879	2359	2012-01-13 23:58:53.869838
1752	2264	2012-01-13 23:59:20.641846
2360	2244	2012-01-13 23:59:20.641846
3395	3196	2012-01-14 07:03:17.281949
2362	2274	2012-01-13 23:59:49.0538
3395	2236	2012-01-14 07:03:17.281949
3395	2268	2012-01-14 07:03:17.281949
2363	2292	2012-01-14 00:00:15.476873
1985	2154	2012-01-14 00:00:28.54401
3395	3297	2012-01-14 07:03:17.281949
2213	2365	2012-01-14 00:00:28.54401
2366	2189	2012-01-14 00:00:47.854862
2367	957	2012-01-14 00:01:08.674276
1122	1713	2012-01-14 00:01:08.674276
2330	2140	2012-01-14 00:01:29.892977
2368	1599	2012-01-14 00:01:29.892977
2363	2366	2012-01-14 00:01:29.892977
2369	1454	2012-01-14 00:01:49.657592
1454	2258	2012-01-14 00:01:49.657592
2905	3395	2012-01-14 07:03:17.281949
1454	1985	2012-01-14 00:01:49.657592
2284	623	2012-01-14 00:01:49.657592
2369	2280	2012-01-14 00:01:49.657592
2613	3396	2012-01-14 07:04:44.841098
3365	3196	2012-01-14 07:04:44.841098
2372	2236	2012-01-14 00:03:02.345364
2372	2356	2012-01-14 00:03:02.345364
2039	2366	2012-01-14 00:04:36.484122
2049	2372	2012-01-14 00:04:36.484122
3396	3326	2012-01-14 07:04:44.841098
2380	1496	2012-01-14 00:05:55.767048
2233	2380	2012-01-14 00:05:55.767048
2209	3396	2012-01-14 07:04:44.841098
1259	3397	2012-01-14 07:05:31.497146
2380	2132	2012-01-14 00:05:55.767048
2287	2380	2012-01-14 00:05:55.767048
3397	3349	2012-01-14 07:05:31.497146
2360	2381	2012-01-14 00:06:42.699811
2267	2381	2012-01-14 00:06:42.699811
2233	2381	2012-01-14 00:06:42.699811
1985	2383	2012-01-14 00:07:21.443249
2323	2384	2012-01-14 00:07:28.129819
2777	3397	2012-01-14 07:05:31.497146
2385	2193	2012-01-14 00:07:48.700396
2547	3397	2012-01-14 07:05:31.497146
2385	2189	2012-01-14 00:07:48.700396
2334	2284	2012-01-14 00:07:48.700396
2385	2322	2012-01-14 00:07:48.700396
2267	1752	2012-01-14 00:07:48.700396
3196	3397	2012-01-14 07:05:31.497146
2385	2334	2012-01-14 00:07:48.700396
3397	3095	2012-01-14 07:05:31.497146
2388	827	2012-01-14 00:08:57.855634
2360	2389	2012-01-14 00:09:10.770455
2233	2389	2012-01-14 00:09:10.770455
2267	2389	2012-01-14 00:09:10.770455
2287	2389	2012-01-14 00:09:10.770455
3399	2983	2012-01-14 07:06:57.301745
144	2389	2012-01-14 00:09:10.770455
3249	3285	2012-01-14 07:06:57.301745
1820	2391	2012-01-14 00:10:00.112526
1916	2344	2012-01-14 00:10:00.112526
2212	2392	2012-01-14 00:10:19.590053
2393	1872	2012-01-14 00:10:26.486325
1351	2394	2012-01-14 00:10:33.652874
2395	1951	2012-01-14 00:10:46.335054
2047	2397	2012-01-14 00:11:29.246819
3400	758	2012-01-14 07:07:20.744466
2401	1738	2012-01-14 00:12:21.490224
2402	1431	2012-01-14 00:12:28.029498
2320	2347	2012-01-14 00:12:34.390643
2393	2403	2012-01-14 00:12:34.390643
2114	2403	2012-01-14 00:12:34.390643
2360	1752	2012-01-14 00:12:34.390643
2363	2404	2012-01-14 00:12:57.295155
623	2404	2012-01-14 00:12:57.295155
2039	2404	2012-01-14 00:12:57.295155
2059	2405	2012-01-14 00:13:16.277989
623	2406	2012-01-14 00:13:22.514925
2284	2405	2012-01-14 00:13:22.514925
2105	2406	2012-01-14 00:13:22.514925
1985	2408	2012-01-14 00:13:49.419887
1122	2302	2012-01-14 00:13:49.419887
2406	2408	2012-01-14 00:13:49.419887
3400	3326	2012-01-14 07:07:20.744466
697	2392	2012-01-14 00:14:18.739811
2412	1293	2012-01-14 00:14:45.537084
2393	1824	2012-01-14 00:14:45.537084
2412	2132	2012-01-14 00:14:45.537084
2412	1837	2012-01-14 00:14:45.537084
2412	2303	2012-01-14 00:14:45.537084
1458	3177	2012-01-14 07:08:39.629921
2047	2414	2012-01-14 00:16:06.985656
910	2414	2012-01-14 00:16:06.985656
3403	3196	2012-01-14 07:08:39.629921
1417	2416	2012-01-14 00:16:33.683504
2416	2397	2012-01-14 00:16:33.683504
3403	2203	2012-01-14 07:08:39.629921
2416	2414	2012-01-14 00:16:33.683504
2320	915	2012-01-14 00:17:15.405075
2233	2418	2012-01-14 00:17:15.405075
998	3404	2012-01-14 07:09:17.219283
1315	2414	2012-01-14 00:17:32.791629
2419	2132	2012-01-14 00:17:32.791629
2385	2419	2012-01-14 00:17:32.791629
15	2419	2012-01-14 00:17:32.791629
457	2419	2012-01-14 00:17:32.791629
2425	3405	2012-01-14 07:09:54.983806
2360	2421	2012-01-14 00:18:18.074258
2233	2421	2012-01-14 00:18:18.074258
2267	2421	2012-01-14 00:18:18.074258
2287	2421	2012-01-14 00:18:18.074258
2049	2422	2012-01-14 00:18:41.102084
3000	3405	2012-01-14 07:09:54.983806
1916	2422	2012-01-14 00:18:41.102084
1820	2049	2012-01-14 00:18:41.102084
2267	3406	2012-01-14 07:10:20.029697
2423	2359	2012-01-14 00:19:07.287963
2875	3406	2012-01-14 07:10:20.029697
2425	2414	2012-01-14 00:19:57.858181
126	2359	2012-01-14 00:20:04.744755
2393	2426	2012-01-14 00:20:04.744755
2114	2426	2012-01-14 00:20:04.744755
2340	2419	2012-01-14 00:20:04.744755
2427	1458	2012-01-14 00:20:41.823149
2427	2277	2012-01-14 00:20:41.823149
2233	3406	2012-01-14 07:10:20.029697
623	2428	2012-01-14 00:21:00.987404
2363	2428	2012-01-14 00:21:00.987404
2039	2428	2012-01-14 00:21:00.987404
2429	2422	2012-01-14 00:21:20.604518
2905	3406	2012-01-14 07:10:20.029697
2325	2430	2012-01-14 00:21:41.953034
2393	2355	2012-01-14 00:21:55.764163
1144	2431	2012-01-14 00:21:55.764163
2393	2432	2012-01-14 00:22:15.182279
2360	1739	2012-01-14 00:22:41.021026
2140	2436	2012-01-14 00:22:53.483562
2327	2436	2012-01-14 00:22:53.483562
2340	2439	2012-01-14 00:24:10.415734
923	2439	2012-01-14 00:24:10.415734
2385	2439	2012-01-14 00:24:10.415734
2404	2302	2012-01-14 00:24:49.71485
2441	2397	2012-01-14 00:24:57.012022
1985	2445	2012-01-14 00:25:36.794912
2447	2381	2012-01-14 00:25:57.32585
2447	1752	2012-01-14 00:25:57.32585
2404	2448	2012-01-14 00:26:10.131801
2039	2449	2012-01-14 00:26:44.600948
2450	2356	2012-01-14 00:26:57.732772
2171	2118	2012-01-14 00:27:04.43242
2198	2451	2012-01-14 00:27:04.43242
2393	878	2012-01-14 00:27:04.43242
2406	2445	2012-01-14 00:27:04.43242
2453	2397	2012-01-14 00:27:39.630366
2453	2414	2012-01-14 00:27:39.630366
2360	2296	2012-01-14 00:27:39.630366
1122	2448	2012-01-14 00:28:06.502198
2105	2454	2012-01-14 00:28:06.502198
2114	2455	2012-01-14 00:28:27.152867
1993	2455	2012-01-14 00:28:27.152867
2059	915	2012-01-14 00:28:27.152867
2456	2322	2012-01-14 00:28:51.486492
623	2459	2012-01-14 00:29:18.24865
2039	2459	2012-01-14 00:29:18.24865
1951	2461	2012-01-14 00:29:43.241512
2449	2461	2012-01-14 00:29:43.241512
2118	2461	2012-01-14 00:29:43.241512
2463	2416	2012-01-14 00:30:11.031007
2463	2425	2012-01-14 00:30:11.031007
2198	2461	2012-01-14 00:30:30.788615
1992	2465	2012-01-14 00:30:30.788615
2385	2466	2012-01-14 00:30:42.797406
998	2467	2012-01-14 00:30:48.691713
866	2397	2012-01-14 00:30:48.691713
2404	2467	2012-01-14 00:30:48.691713
2385	2468	2012-01-14 00:31:15.662225
2468	2132	2012-01-14 00:31:15.662225
2468	2286	2012-01-14 00:31:15.662225
2277	2469	2012-01-14 00:31:32.95373
2008	2469	2012-01-14 00:31:32.95373
2472	1527	2012-01-14 00:32:26.74227
2474	957	2012-01-14 00:32:40.088377
1793	2474	2012-01-14 00:32:40.088377
758	2476	2012-01-14 00:33:16.366874
2341	2476	2012-01-14 00:33:16.366874
1906	2476	2012-01-14 00:33:16.366874
2476	2423	2012-01-14 00:33:16.366874
2286	2450	2012-01-14 00:34:07.381008
2479	1496	2012-01-14 00:34:07.381008
2479	1837	2012-01-14 00:34:07.381008
1137	2482	2012-01-14 00:34:38.00099
623	2483	2012-01-14 00:34:51.036935
2039	2483	2012-01-14 00:34:51.036935
2363	2483	2012-01-14 00:34:51.036935
2105	2483	2012-01-14 00:34:51.036935
2485	2482	2012-01-14 00:35:56.289735
1754	2485	2012-01-14 00:35:56.289735
1738	2359	2012-01-14 00:36:22.635449
2391	2481	2012-01-14 00:36:29.79159
2138	2487	2012-01-14 00:36:29.79159
1817	2488	2012-01-14 00:36:50.559207
2447	2244	2012-01-14 00:36:50.559207
1051	2488	2012-01-14 00:36:50.559207
1762	2488	2012-01-14 00:36:50.559207
2059	2489	2012-01-14 00:37:30.610775
1525	2489	2012-01-14 00:37:30.610775
2157	2489	2012-01-14 00:37:30.610775
1458	2490	2012-01-14 00:37:55.825263
2490	2277	2012-01-14 00:37:55.825263
2447	2493	2012-01-14 00:39:02.786023
2493	2465	2012-01-14 00:39:02.786023
2233	2493	2012-01-14 00:39:02.786023
2267	2493	2012-01-14 00:39:02.786023
2287	2493	2012-01-14 00:39:02.786023
1176	2494	2012-01-14 00:39:38.529843
2391	2436	2012-01-14 00:40:10.919497
2496	1736	2012-01-14 00:40:10.919497
2496	2116	2012-01-14 00:40:10.919497
2496	2391	2012-01-14 00:40:10.919497
2497	2351	2012-01-14 00:40:37.169865
2267	2498	2012-01-14 00:40:44.067272
2341	2488	2012-01-14 00:40:44.067272
2447	2498	2012-01-14 00:40:44.067272
2287	2498	2012-01-14 00:40:44.067272
2499	2236	2012-01-14 00:41:21.277992
2341	2500	2012-01-14 00:41:28.476609
2450	2264	2012-01-14 00:41:40.606712
2501	855	2012-01-14 00:41:40.606712
2450	2502	2012-01-14 00:41:53.749122
2114	2502	2012-01-14 00:41:53.749122
1883	2397	2012-01-14 00:41:53.749122
1627	910	2012-01-14 00:43:13.238447
2507	2482	2012-01-14 00:43:20.334679
2114	2509	2012-01-14 00:43:43.449776
2509	2489	2012-01-14 00:43:43.449776
1642	2494	2012-01-14 00:43:43.449776
2509	623	2012-01-14 00:43:43.449776
2509	2140	2012-01-14 00:43:43.449776
1916	2450	2012-01-14 00:45:30.36146
2499	2385	2012-01-14 00:45:30.36146
2515	2494	2012-01-14 00:45:42.468
2436	2482	2012-01-14 00:45:49.756742
2267	2516	2012-01-14 00:45:49.756742
2447	2516	2012-01-14 00:45:49.756742
2233	2516	2012-01-14 00:45:49.756742
2360	2517	2012-01-14 00:46:19.323257
2287	2517	2012-01-14 00:46:19.323257
2517	2359	2012-01-14 00:46:19.323257
1985	1992	2012-01-14 00:46:19.323257
1194	2501	2012-01-14 00:46:19.323257
2517	2327	2012-01-14 00:46:19.323257
270	2518	2012-01-14 00:47:29.651048
2521	2459	2012-01-14 00:48:21.043152
1626	2436	2012-01-14 00:48:21.043152
2047	2521	2012-01-14 00:48:21.043152
2150	1027	2012-01-14 00:48:21.043152
1238	2494	2012-01-14 00:48:56.904847
2360	2498	2012-01-14 00:48:56.904847
2360	624	2012-01-14 00:48:56.904847
1739	2466	2012-01-14 00:49:55.115251
2330	2489	2012-01-14 00:49:55.115251
2341	2286	2012-01-14 00:49:55.115251
910	2521	2012-01-14 00:50:56.566467
2535	2239	2012-01-14 00:52:01.198632
623	2536	2012-01-14 00:52:08.17225
2522	2482	2012-01-14 00:52:08.17225
1631	2538	2012-01-14 00:52:35.606093
998	2538	2012-01-14 00:52:35.606093
270	2538	2012-01-14 00:52:48.41986
1238	2539	2012-01-14 00:52:48.41986
794	2539	2012-01-14 00:52:48.41986
2385	2542	2012-01-14 00:53:55.259198
923	2542	2012-01-14 00:53:55.259198
2542	2489	2012-01-14 00:53:55.259198
1259	2538	2012-01-14 00:54:56.973479
369	2538	2012-01-14 00:54:56.973479
2547	2538	2012-01-14 00:55:24.727591
2547	1264	2012-01-14 00:55:24.727591
2549	2487	2012-01-14 00:56:05.636229
866	2545	2012-01-14 00:56:05.636229
2385	2551	2012-01-14 00:56:33.787745
1739	2551	2012-01-14 00:56:33.787745
2543	2118	2012-01-14 00:57:19.405539
2450	2455	2012-01-14 00:57:33.797198
2116	2556	2012-01-14 00:57:47.041985
2360	1991	2012-01-14 00:57:47.041985
1774	2556	2012-01-14 00:57:47.041985
2212	2543	2012-01-14 00:58:16.804426
2447	2557	2012-01-14 00:58:16.804426
2360	2557	2012-01-14 00:58:16.804426
2287	2557	2012-01-14 00:58:16.804426
2353	2538	2012-01-14 00:58:16.804426
1836	2539	2012-01-14 00:58:16.804426
2233	2557	2012-01-14 00:58:16.804426
2409	2481	2012-01-14 00:58:16.804426
2330	2558	2012-01-14 00:59:55.535073
1514	2538	2012-01-14 00:59:55.535073
2509	2558	2012-01-14 00:59:55.535073
2157	2558	2012-01-14 00:59:55.535073
2559	1687	2012-01-14 01:00:35.610288
1875	2538	2012-01-14 01:00:35.610288
2560	2558	2012-01-14 01:00:49.23174
2561	2558	2012-01-14 01:00:55.401504
1036	2562	2012-01-14 01:01:01.940687
2385	2562	2012-01-14 01:01:01.940687
2566	2481	2012-01-14 01:01:50.944579
2566	2117	2012-01-14 01:01:50.944579
2233	2566	2012-01-14 01:01:50.944579
1916	2177	2012-01-14 01:01:50.944579
2117	2039	2012-01-14 01:01:50.944579
2567	2539	2012-01-14 01:03:08.268349
1761	2543	2012-01-14 01:03:08.268349
1804	2567	2012-01-14 01:03:08.268349
2569	1736	2012-01-14 01:04:33.805725
2569	2391	2012-01-14 01:04:33.805725
2116	2039	2012-01-14 01:04:33.805725
2177	2571	2012-01-14 01:05:01.168444
2572	1926	2012-01-14 01:05:16.13759
2114	1147	2012-01-14 01:05:16.13759
2385	2575	2012-01-14 01:06:07.112295
1036	2575	2012-01-14 01:06:07.112295
1631	2576	2012-01-14 01:06:19.345317
1782	2576	2012-01-14 01:06:19.345317
2579	2538	2012-01-14 01:07:10.661522
2579	2363	2012-01-14 01:07:10.661522
2584	2391	2012-01-14 01:08:45.728722
1754	2501	2012-01-14 01:08:52.320567
2317	2585	2012-01-14 01:08:52.320567
2360	1505	2012-01-14 01:09:04.948982
1440	2586	2012-01-14 01:09:04.948982
2588	2539	2012-01-14 01:10:16.907031
2079	2588	2012-01-14 01:10:16.907031
2572	2391	2012-01-14 01:10:16.907031
126	2543	2012-01-14 01:11:29.75501
2572	2590	2012-01-14 01:11:29.75501
1738	2592	2012-01-14 01:11:58.560515
923	2593	2012-01-14 01:12:13.834197
2385	2593	2012-01-14 01:12:13.834197
1036	2593	2012-01-14 01:12:13.834197
1739	2593	2012-01-14 01:12:13.834197
2594	2164	2012-01-14 01:12:44.986244
1754	2595	2012-01-14 01:12:52.019619
2268	2595	2012-01-14 01:12:52.019619
2416	2596	2012-01-14 01:13:12.675637
2596	2459	2012-01-14 01:13:12.675637
2586	2596	2012-01-14 01:13:12.675637
2150	2447	2012-01-14 01:13:56.520809
1754	2599	2012-01-14 01:14:02.343176
1398	2599	2012-01-14 01:14:02.343176
2268	2599	2012-01-14 01:14:02.343176
2602	2186	2012-01-14 01:14:56.649807
2385	2605	2012-01-14 01:15:23.772104
2605	2459	2012-01-14 01:15:23.772104
1036	2605	2012-01-14 01:15:23.772104
2605	582	2012-01-14 01:15:23.772104
1626	2607	2012-01-14 01:16:08.990506
2317	2609	2012-01-14 01:16:55.815207
1992	2609	2012-01-14 01:16:55.815207
2429	2609	2012-01-14 01:16:55.815207
2367	2594	2012-01-14 01:17:21.914906
2150	2611	2012-01-14 01:17:35.891564
2481	2612	2012-01-14 01:17:41.918062
2114	2611	2012-01-14 01:17:41.918062
1440	2612	2012-01-14 01:17:41.918062
2613	2429	2012-01-14 01:18:02.135843
1710	2614	2012-01-14 01:18:08.811631
1362	2614	2012-01-14 01:18:08.811631
2615	2607	2012-01-14 01:18:23.291855
2615	2481	2012-01-14 01:18:23.291855
2615	989	2012-01-14 01:18:23.291855
2447	2615	2012-01-14 01:18:23.291855
1789	2614	2012-01-14 01:18:23.291855
2046	2596	2012-01-14 01:18:23.291855
2612	2138	2012-01-14 01:18:23.291855
1985	2487	2012-01-14 01:19:30.747327
1752	2268	2012-01-14 01:19:30.747327
2617	2614	2012-01-14 01:19:44.703664
866	2596	2012-01-14 01:19:44.703664
2177	2614	2012-01-14 01:19:59.603691
2618	2012	2012-01-14 01:19:59.603691
2561	2620	2012-01-14 01:20:21.302591
2620	2612	2012-01-14 01:20:21.302591
2330	2620	2012-01-14 01:20:21.302591
2157	2620	2012-01-14 01:20:21.302591
2287	1752	2012-01-14 01:20:48.844012
1985	2614	2012-01-14 01:21:01.762837
2232	2622	2012-01-14 01:21:01.762837
2522	2594	2012-01-14 01:22:04.754636
2515	2539	2012-01-14 01:23:24.705657
1740	2614	2012-01-14 01:23:40.189481
2630	2558	2012-01-14 01:23:40.189481
2631	910	2012-01-14 01:24:03.72889
2630	2631	2012-01-14 01:24:03.72889
2631	1458	2012-01-14 01:24:03.72889
2385	2634	2012-01-14 01:24:55.259715
98	2634	2012-01-14 01:24:55.259715
457	2634	2012-01-14 01:24:55.259715
1574	2636	2012-01-14 01:25:22.037375
1985	2636	2012-01-14 01:25:22.037375
1740	2636	2012-01-14 01:25:22.037375
2637	2607	2012-01-14 01:25:44.043905
2630	2140	2012-01-14 01:26:17.581092
2639	2114	2012-01-14 01:26:24.482265
2177	2636	2012-01-14 01:26:30.942513
2613	2640	2012-01-14 01:26:30.942513
2641	2330	2012-01-14 01:26:53.337279
2303	2636	2012-01-14 01:26:53.337279
2561	2641	2012-01-14 01:26:53.337279
2642	2556	2012-01-14 01:27:14.398968
2642	910	2012-01-14 01:27:14.398968
2360	2643	2012-01-14 01:27:29.43761
2267	2643	2012-01-14 01:27:29.43761
2287	2643	2012-01-14 01:27:29.43761
1259	2640	2012-01-14 01:28:02.966343
1170	2644	2012-01-14 01:28:02.966343
1697	2593	2012-01-14 01:28:02.966343
2644	2485	2012-01-14 01:28:02.966343
2646	2572	2012-01-14 01:28:47.638922
2140	2607	2012-01-14 01:28:55.99425
1752	2647	2012-01-14 01:28:55.99425
2385	1698	2012-01-14 01:29:51.3876
2360	1420	2012-01-14 01:29:51.3876
1417	2149	2012-01-14 01:29:51.3876
2650	2614	2012-01-14 01:30:28.846506
2650	2154	2012-01-14 01:30:28.846506
2360	2651	2012-01-14 01:30:43.944511
2267	2651	2012-01-14 01:30:43.944511
2447	2651	2012-01-14 01:30:43.944511
2287	2651	2012-01-14 01:30:43.944511
2652	2046	2012-01-14 01:31:24.130479
1872	2655	2012-01-14 01:31:54.88503
1417	2655	2012-01-14 01:31:54.88503
1036	2634	2012-01-14 01:32:44.355986
1372	2658	2012-01-14 01:33:10.456807
2661	2655	2012-01-14 01:34:13.089859
2663	2593	2012-01-14 01:35:05.145677
2334	2614	2012-01-14 01:35:05.145677
1461	2614	2012-01-14 01:35:05.145677
2664	2655	2012-01-14 01:35:37.193496
2114	2664	2012-01-14 01:35:37.193496
2149	2658	2012-01-14 01:35:37.193496
1752	2664	2012-01-14 01:35:37.193496
2499	2664	2012-01-14 01:35:37.193496
2138	2614	2012-01-14 01:35:37.193496
2641	2666	2012-01-14 01:36:46.928828
2114	2667	2012-01-14 01:37:01.03774
1752	2667	2012-01-14 01:37:01.03774
2668	2236	2012-01-14 01:37:13.30649
1740	2669	2012-01-14 01:37:31.26764
1188	2669	2012-01-14 01:37:31.26764
1985	2669	2012-01-14 01:37:31.26764
2509	2673	2012-01-14 01:38:44.33707
2674	2428	2012-01-14 01:38:57.593469
2630	2675	2012-01-14 01:39:13.068982
2114	1614	2012-01-14 01:40:06.250673
2677	2595	2012-01-14 01:40:06.250673
2678	2572	2012-01-14 01:40:23.389597
2679	816	2012-01-14 01:41:04.810828
2116	2680	2012-01-14 01:41:31.20757
1697	2681	2012-01-14 01:41:38.494813
1036	2681	2012-01-14 01:41:38.494813
923	2681	2012-01-14 01:41:38.494813
15	2681	2012-01-14 01:41:38.494813
2385	2681	2012-01-14 01:41:38.494813
457	2681	2012-01-14 01:41:38.494813
98	2681	2012-01-14 01:41:38.494813
2447	1697	2012-01-14 01:41:38.494813
2238	2681	2012-01-14 01:41:38.494813
2682	1440	2012-01-14 01:43:02.665504
2683	2334	2012-01-14 01:43:16.352399
2683	2322	2012-01-14 01:43:16.352399
2683	2593	2012-01-14 01:44:20.863363
1985	2685	2012-01-14 01:44:20.863363
1698	2607	2012-01-14 01:44:20.863363
2688	2558	2012-01-14 01:46:13.71485
2360	2690	2012-01-14 01:46:43.673923
2267	2690	2012-01-14 01:46:43.673923
2287	2690	2012-01-14 01:46:43.673923
2447	2690	2012-01-14 01:46:43.673923
2691	1710	2012-01-14 01:47:09.192045
2691	2039	2012-01-14 01:47:09.192045
385	2693	2012-01-14 01:47:30.661107
2693	1372	2012-01-14 01:47:30.661107
2694	2154	2012-01-14 01:47:44.161634
2694	2232	2012-01-14 01:47:44.161634
2351	2694	2012-01-14 01:47:44.161634
1636	2695	2012-01-14 01:48:07.082465
2515	2697	2012-01-14 01:48:21.953829
1920	2697	2012-01-14 01:48:21.953829
2698	2612	2012-01-14 01:48:36.968719
2567	2697	2012-01-14 01:48:36.968719
855	2695	2012-01-14 01:48:53.148707
2700	2647	2012-01-14 01:49:00.136402
2701	2631	2012-01-14 01:49:08.321403
2701	2558	2012-01-14 01:49:08.321403
2666	2695	2012-01-14 01:49:23.736824
498	2702	2012-01-14 01:49:23.736824
787	2702	2012-01-14 01:49:23.736824
2363	2703	2012-01-14 01:49:58.206242
385	2703	2012-01-14 01:49:58.206242
2630	2704	2012-01-14 01:50:20.84835
2705	2595	2012-01-14 01:50:27.783996
2416	2707	2012-01-14 01:50:50.988089
2385	2708	2012-01-14 01:51:06.391831
15	2708	2012-01-14 01:51:06.391831
2694	2702	2012-01-14 01:51:19.787245
2117	2705	2012-01-14 01:51:26.819464
2710	2567	2012-01-14 01:51:26.819464
2710	2607	2012-01-14 01:51:26.819464
2712	1372	2012-01-14 01:52:14.792075
2341	1176	2012-01-14 01:52:30.713107
2717	2697	2012-01-14 01:52:54.270412
2694	2717	2012-01-14 01:52:54.270412
1985	2717	2012-01-14 01:52:54.270412
2198	126	2012-01-14 01:52:54.270412
2138	2717	2012-01-14 01:52:54.270412
2157	1586	2012-01-14 01:52:54.270412
1793	2717	2012-01-14 01:52:54.270412
2360	2719	2012-01-14 01:53:58.309014
2287	2719	2012-01-14 01:53:58.309014
2267	2719	2012-01-14 01:53:58.309014
2447	2719	2012-01-14 01:53:58.309014
1357	2721	2012-01-14 01:55:00.230879
2694	2721	2012-01-14 01:55:00.230879
2138	2722	2012-01-14 01:55:23.524131
2650	2721	2012-01-14 01:55:39.417451
2724	2693	2012-01-14 01:55:39.417451
2701	2140	2012-01-14 01:56:03.251596
2360	2728	2012-01-14 01:56:26.761448
2267	2728	2012-01-14 01:56:26.761448
2721	2697	2012-01-14 01:56:45.223954
2729	2680	2012-01-14 01:56:45.223954
2138	2702	2012-01-14 01:56:45.223954
2233	2729	2012-01-14 01:56:45.223954
2287	2729	2012-01-14 01:56:45.223954
2694	2722	2012-01-14 01:56:45.223954
2529	2730	2012-01-14 01:58:09.450876
2726	2730	2012-01-14 01:58:09.450876
2420	2731	2012-01-14 01:58:32.12648
862	2680	2012-01-14 01:58:32.12648
2385	2732	2012-01-14 01:58:46.966303
1985	2721	2012-01-14 01:58:46.966303
1697	2732	2012-01-14 01:58:46.966303
1376	2721	2012-01-14 02:00:01.264925
1376	2734	2012-01-14 02:00:01.264925
1804	2607	2012-01-14 02:00:01.264925
2650	2722	2012-01-14 02:00:24.880277
2702	2735	2012-01-14 02:00:24.880277
2447	2736	2012-01-14 02:00:45.662853
2736	1687	2012-01-14 02:00:45.662853
2233	2736	2012-01-14 02:00:45.662853
2736	2735	2012-01-14 02:00:45.662853
2709	2730	2012-01-14 02:00:45.662853
2287	2736	2012-01-14 02:00:45.662853
2490	2680	2012-01-14 02:00:45.662853
787	2722	2012-01-14 02:00:45.662853
2734	2738	2012-01-14 02:02:27.621805
2493	2738	2012-01-14 02:02:27.621805
2740	2702	2012-01-14 02:03:14.709897
1350	2741	2012-01-14 02:03:21.750055
2341	2735	2012-01-14 02:03:29.382671
1574	2743	2012-01-14 02:03:36.749651
2138	2743	2012-01-14 02:03:36.749651
2650	866	2012-01-14 02:03:51.342012
2745	2722	2012-01-14 02:03:58.794449
2745	2734	2012-01-14 02:03:58.794449
2745	866	2012-01-14 02:03:58.794449
2745	2702	2012-01-14 02:03:58.794449
2287	2745	2012-01-14 02:03:58.794449
2745	2717	2012-01-14 02:03:58.794449
2746	2722	2012-01-14 02:05:07.088772
2746	2734	2012-01-14 02:05:07.088772
40	2748	2012-01-14 02:05:55.185973
1238	2748	2012-01-14 02:05:55.185973
1836	2748	2012-01-14 02:05:55.185973
2447	2728	2012-01-14 02:06:18.791065
2749	2509	2012-01-14 02:06:18.791065
2746	2702	2012-01-14 02:06:42.202015
1574	2702	2012-01-14 02:06:42.202015
1458	2750	2012-01-14 02:06:42.202015
1036	2751	2012-01-14 02:07:04.02719
923	2751	2012-01-14 02:07:04.02719
1951	126	2012-01-14 02:07:30.411911
2754	2466	2012-01-14 02:07:46.165363
855	2595	2012-01-14 02:07:46.165363
2754	2575	2012-01-14 02:08:12.053564
2746	2154	2012-01-14 02:08:12.053564
914	2757	2012-01-14 02:09:03.523079
2700	2509	2012-01-14 02:09:19.587548
2105	2759	2012-01-14 02:09:33.259212
1993	2385	2012-01-14 02:09:55.747758
1238	2761	2012-01-14 02:10:02.503046
499	2763	2012-01-14 02:10:35.405446
2509	2763	2012-01-14 02:10:35.405446
2765	2705	2012-01-14 02:11:19.956916
2749	2455	2012-01-14 02:11:19.956916
1873	2766	2012-01-14 02:11:51.026536
2767	1926	2012-01-14 02:12:14.195394
2768	2680	2012-01-14 02:12:30.747482
2429	2769	2012-01-14 02:12:38.683435
2363	2693	2012-01-14 02:12:38.683435
2749	592	2012-01-14 02:12:53.952888
1228	2772	2012-01-14 02:13:10.172576
2765	2772	2012-01-14 02:13:10.172576
1574	2722	2012-01-14 02:13:10.172576
2529	2772	2012-01-14 02:13:10.172576
2768	2772	2012-01-14 02:13:10.172576
2774	1631	2012-01-14 02:13:59.718674
2360	2776	2012-01-14 02:14:23.968959
2447	2776	2012-01-14 02:14:23.968959
2287	2776	2012-01-14 02:14:23.968959
2774	2509	2012-01-14 02:15:31.349939
2763	2778	2012-01-14 02:15:38.866511
2779	2701	2012-01-14 02:15:47.294144
2341	2330	2012-01-14 02:15:54.760038
2765	2701	2012-01-14 02:15:54.760038
2781	1875	2012-01-14 02:16:10.140836
2385	2781	2012-01-14 02:16:10.140836
2114	2782	2012-01-14 02:16:24.08892
1752	2782	2012-01-14 02:16:24.08892
2416	2778	2012-01-14 02:16:24.08892
1527	2783	2012-01-14 02:16:45.608146
844	2784	2012-01-14 02:17:01.862906
1249	2786	2012-01-14 02:17:26.509538
2244	2786	2012-01-14 02:17:26.509538
2149	2788	2012-01-14 02:18:12.150258
2746	2571	2012-01-14 02:18:37.201593
888	2789	2012-01-14 02:18:37.201593
2790	2788	2012-01-14 02:18:53.740369
2790	2186	2012-01-14 02:18:53.740369
2047	2778	2012-01-14 02:18:53.740369
1789	2790	2012-01-14 02:18:53.740369
2114	2791	2012-01-14 02:19:27.113447
2791	2416	2012-01-14 02:19:27.113447
1875	2792	2012-01-14 02:19:48.327437
2385	2793	2012-01-14 02:19:56.791911
1036	2793	2012-01-14 02:19:56.791911
2793	2416	2012-01-14 02:19:56.791911
2774	2782	2012-01-14 02:20:40.633993
2795	1331	2012-01-14 02:20:40.633993
2267	2796	2012-01-14 02:20:57.497124
2447	2796	2012-01-14 02:20:57.497124
2797	2789	2012-01-14 02:21:11.071814
1883	2778	2012-01-14 02:21:11.071814
1017	2799	2012-01-14 02:22:07.251752
1697	2803	2012-01-14 02:22:41.026309
2385	2803	2012-01-14 02:22:41.026309
1036	2803	2012-01-14 02:22:41.026309
15	2803	2012-01-14 02:22:41.026309
2806	2039	2012-01-14 02:24:06.124607
2807	2705	2012-01-14 02:24:13.767274
2701	2763	2012-01-14 02:24:13.767274
2694	2808	2012-01-14 02:24:29.80858
2138	2808	2012-01-14 02:24:29.80858
2385	2810	2012-01-14 02:24:54.245543
1036	2810	2012-01-14 02:24:54.245543
2812	2808	2012-01-14 02:25:46.702138
2360	2815	2012-01-14 02:26:46.895819
2267	2815	2012-01-14 02:26:46.895819
2233	2815	2012-01-14 02:26:46.895819
2287	2815	2012-01-14 02:26:46.895819
2816	2808	2012-01-14 02:27:28.696837
2717	2748	2012-01-14 02:27:28.696837
2817	2732	2012-01-14 02:27:55.836105
2818	1631	2012-01-14 02:28:13.061574
2818	1051	2012-01-14 02:28:13.061574
878	2778	2012-01-14 02:28:28.775602
2792	2786	2012-01-14 02:28:28.775602
2820	2680	2012-01-14 02:28:46.968119
2819	2782	2012-01-14 02:28:46.968119
2816	2722	2012-01-14 02:30:08.61718
2360	2796	2012-01-14 02:30:25.59385
2149	2825	2012-01-14 02:30:25.59385
2792	1837	2012-01-14 02:31:15.298036
2579	2774	2012-01-14 02:31:23.178901
2830	2766	2012-01-14 02:31:30.588892
1586	2831	2012-01-14 02:31:47.424012
2675	2788	2012-01-14 02:31:47.424012
2831	915	2012-01-14 02:31:47.424012
2641	2786	2012-01-14 02:31:47.424012
2154	2833	2012-01-14 02:32:37.869396
2360	2836	2012-01-14 02:33:03.363841
2233	2836	2012-01-14 02:33:03.363841
2792	2838	2012-01-14 02:33:57.114922
1804	2788	2012-01-14 02:33:57.114922
758	2838	2012-01-14 02:33:57.114922
1906	2838	2012-01-14 02:33:57.114922
2839	2765	2012-01-14 02:34:44.876176
1527	2840	2012-01-14 02:34:53.137637
2812	2840	2012-01-14 02:34:53.137637
2841	126	2012-01-14 02:35:10.05903
2792	2841	2012-01-14 02:35:10.05903
1817	2841	2012-01-14 02:35:10.05903
2641	2838	2012-01-14 02:35:42.063218
2268	2843	2012-01-14 02:35:50.292913
2845	2786	2012-01-14 02:36:06.859354
2845	2838	2012-01-14 02:36:06.859354
2385	2845	2012-01-14 02:36:06.859354
2846	2717	2012-01-14 02:36:38.719624
2360	2847	2012-01-14 02:36:47.568797
2233	2847	2012-01-14 02:36:47.568797
2287	2847	2012-01-14 02:36:47.568797
1793	2849	2012-01-14 02:38:36.66216
2816	2849	2012-01-14 02:38:36.66216
2851	1896	2012-01-14 02:40:04.36585
855	2843	2012-01-14 02:40:12.542615
2774	2385	2012-01-14 02:40:12.542615
2816	2840	2012-01-14 02:40:12.542615
2852	1994	2012-01-14 02:40:12.542615
2613	2774	2012-01-14 02:40:12.542615
957	2853	2012-01-14 02:41:23.685517
2855	2607	2012-01-14 02:41:51.009901
2661	2855	2012-01-14 02:41:51.009901
2856	2838	2012-01-14 02:42:19.529775
2233	2857	2012-01-14 02:42:27.969129
2360	2857	2012-01-14 02:42:27.969129
2858	2788	2012-01-14 02:42:50.153151
2855	2788	2012-01-14 02:43:46.753164
2360	2862	2012-01-14 02:43:55.279768
2267	2862	2012-01-14 02:43:55.279768
2287	2862	2012-01-14 02:43:55.279768
2233	2862	2012-01-14 02:43:55.279768
1626	2788	2012-01-14 02:44:58.774202
2816	2408	2012-01-14 02:45:07.014222
1995	2865	2012-01-14 02:45:07.014222
2869	2748	2012-01-14 02:46:00.700487
1398	2843	2012-01-14 02:46:00.700487
2233	2870	2012-01-14 02:46:25.624834
2870	2455	2012-01-14 02:46:25.624834
2870	208	2012-01-14 02:46:25.624834
2287	2870	2012-01-14 02:46:25.624834
1398	2871	2012-01-14 02:47:14.920936
1574	2808	2012-01-14 02:47:22.71709
1883	2830	2012-01-14 02:47:22.71709
1574	2831	2012-01-14 02:47:22.71709
1951	1817	2012-01-14 02:47:22.71709
2875	2796	2012-01-14 02:48:18.161079
2875	2728	2012-01-14 02:48:18.161079
2878	2455	2012-01-14 02:49:28.125076
2641	1875	2012-01-14 02:50:01.346849
2880	1896	2012-01-14 02:50:01.346849
2882	2680	2012-01-14 02:50:35.055783
1538	2830	2012-01-14 02:50:35.055783
2801	2416	2012-01-14 02:50:35.055783
2878	579	2012-01-14 02:51:27.575213
2855	2884	2012-01-14 02:51:36.608983
1817	2838	2012-01-14 02:51:36.608983
2641	2885	2012-01-14 02:52:01.137492
1458	2885	2012-01-14 02:52:01.137492
1051	2885	2012-01-14 02:52:01.137492
984	2885	2012-01-14 02:52:01.137492
2875	1491	2012-01-14 02:52:01.137492
1951	2886	2012-01-14 02:52:41.143701
2420	2879	2012-01-14 02:52:41.143701
2843	2879	2012-01-14 02:52:41.143701
2887	126	2012-01-14 02:53:06.506543
2887	2886	2012-01-14 02:53:06.506543
623	2882	2012-01-14 02:53:31.136245
1431	2820	2012-01-14 02:53:31.136245
2889	2680	2012-01-14 02:53:47.95317
2889	2888	2012-01-14 02:53:47.95317
2680	2879	2012-01-14 02:53:47.95317
2878	2891	2012-01-14 02:54:53.073564
862	2892	2012-01-14 02:55:00.544039
2820	2892	2012-01-14 02:55:00.544039
2855	2833	2012-01-14 02:57:58.828026
2898	1524	2012-01-14 02:57:58.828026
2900	2891	2012-01-14 02:58:26.448157
2902	2843	2012-01-14 02:58:43.720954
1994	2820	2012-01-14 02:59:01.646252
2905	1752	2012-01-14 02:59:10.363141
2905	2796	2012-01-14 02:59:10.363141
2906	126	2012-01-14 02:59:29.128807
2680	2149	2012-01-14 02:59:29.128807
2875	2906	2012-01-14 02:59:29.128807
2233	2906	2012-01-14 02:59:29.128807
2905	2906	2012-01-14 02:59:29.128807
2267	2906	2012-01-14 02:59:29.128807
2287	2906	2012-01-14 02:59:29.128807
2904	2909	2012-01-14 03:01:46.915235
2356	2909	2012-01-14 03:01:46.915235
2878	2236	2012-01-14 03:02:15.385944
1376	2910	2012-01-14 03:02:15.385944
2356	2912	2012-01-14 03:03:09.896376
2904	2912	2012-01-14 03:03:09.896376
2317	2912	2012-01-14 03:03:09.896376
2712	2912	2012-01-14 03:03:09.896376
2914	2322	2012-01-14 03:03:54.367276
1778	2843	2012-01-14 03:04:03.268962
2830	2693	2012-01-14 03:04:03.268962
2917	2886	2012-01-14 03:04:28.461387
2830	2882	2012-01-14 03:04:47.030143
2919	2879	2012-01-14 03:04:47.030143
2920	2779	2012-01-14 03:05:21.552473
2921	2882	2012-01-14 03:05:38.212117
2693	2909	2012-01-14 03:05:38.212117
369	2923	2012-01-14 03:06:13.428554
2744	2882	2012-01-14 03:06:13.428554
2924	2888	2012-01-14 03:06:39.123804
2925	2722	2012-01-14 03:07:04.945713
2925	2849	2012-01-14 03:07:04.945713
2363	2882	2012-01-14 03:07:33.817158
442	2929	2012-01-14 03:07:59.586245
1697	2930	2012-01-14 03:08:18.334094
2385	2930	2012-01-14 03:08:18.334094
2930	2748	2012-01-14 03:08:18.334094
98	2930	2012-01-14 03:08:18.334094
1036	2930	2012-01-14 03:08:18.334094
2931	2879	2012-01-14 03:09:17.158338
878	2830	2012-01-14 03:09:26.682277
1992	2912	2012-01-14 03:10:05.333719
2535	2935	2012-01-14 03:10:23.566756
1482	2935	2012-01-14 03:10:23.566756
2930	2935	2012-01-14 03:10:23.566756
1458	2939	2012-01-14 03:11:50.292306
1817	2939	2012-01-14 03:11:50.292306
758	2939	2012-01-14 03:11:50.292306
1491	2939	2012-01-14 03:11:50.292306
1051	2939	2012-01-14 03:11:50.292306
2693	2912	2012-01-14 03:12:51.418202
977	2942	2012-01-14 03:13:00.224989
1261	2929	2012-01-14 03:13:09.349828
1017	2929	2012-01-14 03:13:09.349828
1642	2942	2012-01-14 03:13:28.429716
2944	2919	2012-01-14 03:13:28.429716
2869	2942	2012-01-14 03:14:19.633519
2947	2939	2012-01-14 03:14:27.863023
2947	2253	2012-01-14 03:14:27.863023
2285	2948	2012-01-14 03:14:56.36778
2950	2939	2012-01-14 03:16:05.525637
2950	2885	2012-01-14 03:16:05.525637
2666	2595	2012-01-14 03:16:05.525637
2535	2942	2012-01-14 03:17:03.817034
2953	878	2012-01-14 03:17:12.868512
2960	2607	2012-01-14 03:20:49.093816
2947	2960	2012-01-14 03:20:49.093816
1896	2948	2012-01-14 03:21:24.876621
2360	2961	2012-01-14 03:21:24.876621
2875	2961	2012-01-14 03:21:24.876621
2233	2961	2012-01-14 03:21:24.876621
2961	1896	2012-01-14 03:21:24.876621
2905	2961	2012-01-14 03:21:24.876621
2287	2961	2012-01-14 03:21:24.876621
144	2961	2012-01-14 03:21:24.876621
2962	2950	2012-01-14 03:23:55.874537
2942	878	2012-01-14 03:24:15.044581
2830	2963	2012-01-14 03:24:15.044581
422	2964	2012-01-14 03:24:43.621587
2677	2964	2012-01-14 03:24:43.621587
2965	2693	2012-01-14 03:25:00.788557
2385	2967	2012-01-14 03:25:40.473359
1482	2942	2012-01-14 03:26:39.576217
2830	751	2012-01-14 03:26:39.576217
2766	2879	2012-01-14 03:26:39.576217
2950	2960	2012-01-14 03:26:39.576217
614	2972	2012-01-14 03:27:50.232295
2385	2974	2012-01-14 03:28:29.45146
2908	2912	2012-01-14 03:28:29.45146
2855	2975	2012-01-14 03:28:52.81214
2801	2855	2012-01-14 03:28:52.81214
2851	2980	2012-01-14 03:30:39.196518
2980	2941	2012-01-14 03:30:39.196518
2981	2595	2012-01-14 03:30:58.585806
1170	2912	2012-01-14 03:30:58.585806
1170	1804	2012-01-14 03:30:58.585806
2981	2549	2012-01-14 03:30:58.585806
2982	957	2012-01-14 03:31:39.210416
977	2983	2012-01-14 03:32:02.135701
2914	2930	2012-01-14 03:32:02.135701
1934	2830	2012-01-14 03:32:59.693113
2360	1491	2012-01-14 03:32:59.693113
2588	2748	2012-01-14 03:33:26.000173
2950	2841	2012-01-14 03:33:26.000173
2991	2878	2012-01-14 03:34:22.219625
2385	2992	2012-01-14 03:34:31.58487
1697	2992	2012-01-14 03:34:31.58487
2855	2977	2012-01-14 03:34:56.245557
2888	2993	2012-01-14 03:34:56.245557
2360	2994	2012-01-14 03:35:14.673242
2875	2994	2012-01-14 03:35:14.673242
2994	957	2012-01-14 03:35:14.673242
1817	2812	2012-01-14 03:35:14.673242
2988	2883	2012-01-14 03:35:14.673242
2741	1804	2012-01-14 03:35:14.673242
2878	878	2012-01-14 03:36:31.237626
1043	2977	2012-01-14 03:36:40.395392
2138	2996	2012-01-14 03:36:40.395392
2997	1926	2012-01-14 03:36:59.982949
1238	2935	2012-01-14 03:36:59.982949
2998	2879	2012-01-14 03:37:32.566459
2385	2998	2012-01-14 03:37:32.566459
1036	2998	2012-01-14 03:37:32.566459
2999	2993	2012-01-14 03:38:05.134682
1642	2935	2012-01-14 03:38:05.134682
2157	2993	2012-01-14 03:39:31.358481
2363	2766	2012-01-14 03:39:31.358481
2997	3004	2012-01-14 03:42:07.975651
1951	2988	2012-01-14 03:42:07.975651
2385	3010	2012-01-14 03:42:27.83553
3012	1896	2012-01-14 03:43:57.982565
2138	3013	2012-01-14 03:44:07.165396
2812	3013	2012-01-14 03:44:07.165396
1710	3013	2012-01-14 03:44:07.165396
2999	3014	2012-01-14 03:44:35.701084
2888	3014	2012-01-14 03:44:35.701084
3012	3014	2012-01-14 03:44:35.701084
2425	3016	2012-01-14 03:45:11.929256
3016	2416	2012-01-14 03:45:11.929256
3018	2939	2012-01-14 03:46:00.685243
3020	2939	2012-01-14 03:46:38.948414
2885	915	2012-01-14 03:46:38.948414
3020	2960	2012-01-14 03:46:38.948414
3020	2812	2012-01-14 03:46:38.948414
2233	3020	2012-01-14 03:46:38.948414
3021	3013	2012-01-14 03:49:01.06319
3021	2996	2012-01-14 03:49:01.06319
1574	3013	2012-01-14 03:49:38.062907
570	3022	2012-01-14 03:49:38.062907
3023	2939	2012-01-14 03:49:55.715895
1993	3023	2012-01-14 03:49:55.715895
2149	2975	2012-01-14 03:50:31.957926
2885	2733	2012-01-14 03:50:50.893662
3025	2939	2012-01-14 03:50:50.893662
3026	3013	2012-01-14 03:51:22.27465
1992	3026	2012-01-14 03:51:22.27465
2910	3026	2012-01-14 03:51:22.27465
3025	3027	2012-01-14 03:52:02.938808
1458	3027	2012-01-14 03:52:02.938808
2680	3004	2012-01-14 03:52:02.938808
2950	3027	2012-01-14 03:52:02.938808
2149	2607	2012-01-14 03:52:02.938808
2765	2680	2012-01-14 03:52:02.938808
3028	2680	2012-01-14 03:53:26.998627
1458	2666	2012-01-14 03:53:26.998627
2712	855	2012-01-14 03:53:26.998627
3025	2885	2012-01-14 03:54:23.3118
3033	2236	2012-01-14 03:55:02.024639
3037	915	2012-01-14 03:56:32.377907
3037	3014	2012-01-14 03:56:32.377907
3037	1896	2012-01-14 03:56:32.377907
3037	2733	2012-01-14 03:56:32.377907
2233	3037	2012-01-14 03:56:32.377907
3039	2680	2012-01-14 03:57:44.011171
3040	3004	2012-01-14 03:58:03.06125
3040	2114	2012-01-14 03:58:03.06125
3041	326	2012-01-14 03:58:19.559559
2363	751	2012-01-14 03:58:19.559559
3041	1440	2012-01-14 03:58:19.559559
2429	2136	2012-01-14 03:58:19.559559
2233	3041	2012-01-14 03:58:19.559559
2157	3014	2012-01-14 03:58:19.559559
3041	2363	2012-01-14 03:58:19.559559
3042	3004	2012-01-14 03:59:28.644133
2845	2939	2012-01-14 03:59:37.827651
2908	3044	2012-01-14 03:59:47.636142
1961	3044	2012-01-14 03:59:47.636142
2875	3046	2012-01-14 04:00:27.06107
3047	2935	2012-01-14 04:00:51.90112
1447	2680	2012-01-14 04:00:51.90112
2888	2733	2012-01-14 04:01:11.615246
2888	915	2012-01-14 04:01:11.615246
831	3052	2012-01-14 04:02:59.905667
3053	2935	2012-01-14 04:03:19.531041
3053	2983	2012-01-14 04:03:19.531041
3043	2930	2012-01-14 04:03:47.884817
3025	3057	2012-01-14 04:04:35.512187
3059	3054	2012-01-14 04:05:27.194365
3054	2154	2012-01-14 04:05:27.194365
3054	2996	2012-01-14 04:05:27.194365
3059	2935	2012-01-14 04:05:27.194365
3059	2983	2012-01-14 04:05:27.194365
1761	3048	2012-01-14 04:05:27.194365
2233	3059	2012-01-14 04:05:27.194365
2905	3059	2012-01-14 04:05:27.194365
2287	3059	2012-01-14 04:05:27.194365
3025	2812	2012-01-14 04:05:27.194365
3059	3008	2012-01-14 04:05:27.194365
2858	3060	2012-01-14 04:08:28.576003
2960	3060	2012-01-14 04:08:28.576003
3061	2232	2012-01-14 04:08:46.960169
1804	2622	2012-01-14 04:08:56.730887
2136	2607	2012-01-14 04:08:56.730887
2975	3062	2012-01-14 04:08:56.730887
3048	2772	2012-01-14 04:09:45.648876
3008	3063	2012-01-14 04:09:45.648876
1804	3060	2012-01-14 04:10:44.924993
2363	2963	2012-01-14 04:10:44.924993
2953	3065	2012-01-14 04:11:35.980254
2154	3060	2012-01-14 04:11:35.980254
3065	2935	2012-01-14 04:11:35.980254
2114	3065	2012-01-14 04:11:35.980254
2875	1752	2012-01-14 04:11:35.980254
2150	3065	2012-01-14 04:11:35.980254
2363	3066	2012-01-14 04:13:25.389698
3010	3066	2012-01-14 04:13:25.389698
2114	2385	2012-01-14 04:14:05.518096
1482	3070	2012-01-14 04:14:42.579536
3047	3070	2012-01-14 04:14:42.579536
442	3048	2012-01-14 04:14:42.579536
3053	3070	2012-01-14 04:14:42.579536
3071	2728	2012-01-14 04:15:29.082307
3071	1491	2012-01-14 04:15:29.082307
3072	592	2012-01-14 04:15:48.401475
2233	3073	2012-01-14 04:16:08.88868
3073	1896	2012-01-14 04:16:08.88868
2875	3075	2012-01-14 04:16:46.139236
2233	3075	2012-01-14 04:16:46.139236
3071	3075	2012-01-14 04:16:46.139236
3076	326	2012-01-14 04:17:29.146045
3025	3077	2012-01-14 04:17:49.735616
3077	3048	2012-01-14 04:17:49.735616
2590	3078	2012-01-14 04:18:08.113225
3033	3080	2012-01-14 04:18:36.917153
784	3081	2012-01-14 04:19:03.285586
3081	2466	2012-01-14 04:19:03.285586
3081	1435	2012-01-14 04:19:03.285586
2268	3085	2012-01-14 04:20:58.609639
2677	3085	2012-01-14 04:20:58.609639
1778	3085	2012-01-14 04:20:58.609639
2138	3086	2012-01-14 04:21:48.183851
3061	3086	2012-01-14 04:21:48.183851
3064	2302	2012-01-14 04:21:48.183851
3047	3054	2012-01-14 04:21:48.183851
3087	2885	2012-01-14 04:22:28.934142
3087	2939	2012-01-14 04:22:28.934142
1951	3078	2012-01-14 04:23:00.737342
794	3088	2012-01-14 04:23:00.737342
1176	3088	2012-01-14 04:23:00.737342
1238	3088	2012-01-14 04:23:00.737342
1574	2154	2012-01-14 04:23:00.737342
1804	2833	2012-01-14 04:25:04.656422
2875	3093	2012-01-14 04:25:37.763265
3093	2996	2012-01-14 04:25:37.763265
2233	3093	2012-01-14 04:25:37.763265
1636	3095	2012-01-14 04:26:34.922368
2677	3095	2012-01-14 04:26:34.922368
3076	3099	2012-01-14 04:27:52.960941
1875	3099	2012-01-14 04:27:52.960941
3100	3055	2012-01-14 04:28:12.760034
3055	3099	2012-01-14 04:28:22.976805
3101	3054	2012-01-14 04:28:22.976805
2812	2996	2012-01-14 04:28:43.435599
3072	3065	2012-01-14 04:28:43.435599
751	3105	2012-01-14 04:29:32.850447
1043	3105	2012-01-14 04:29:32.850447
2136	3105	2012-01-14 04:29:32.850447
3106	1669	2012-01-14 04:30:02.338577
1696	3099	2012-01-14 04:30:02.338577
3109	3014	2012-01-14 04:30:44.600847
3109	1548	2012-01-14 04:30:44.600847
3110	2796	2012-01-14 04:31:15.985772
3110	1752	2012-01-14 04:31:15.985772
3110	2857	2012-01-14 04:31:15.985772
3110	2343	2012-01-14 04:31:15.985772
1458	3111	2012-01-14 04:31:58.231426
369	3099	2012-01-14 04:31:58.231426
2114	3114	2012-01-14 04:32:59.22867
3110	3115	2012-01-14 04:33:17.534128
2875	3115	2012-01-14 04:33:17.534128
3117	3099	2012-01-14 04:34:20.957515
2579	3099	2012-01-14 04:35:10.464701
3121	3120	2012-01-14 04:35:20.647555
3121	3016	2012-01-14 04:35:20.647555
1482	3054	2012-01-14 04:35:51.503508
1782	3099	2012-01-14 04:35:51.503508
2975	3123	2012-01-14 04:36:21.277739
3016	2590	2012-01-14 04:37:35.768267
2779	3126	2012-01-14 04:37:45.879512
3039	3126	2012-01-14 04:37:45.879512
3054	2408	2012-01-14 04:38:05.785548
1066	3128	2012-01-14 04:38:16.317893
3128	3123	2012-01-14 04:38:16.317893
3025	3129	2012-01-14 04:38:36.014339
1906	3129	2012-01-14 04:38:36.014339
2765	3123	2012-01-14 04:39:16.792886
2781	3131	2012-01-14 04:39:16.792886
1458	3131	2012-01-14 04:39:16.792886
2267	1491	2012-01-14 04:39:16.792886
1095	3132	2012-01-14 04:40:36.911435
2063	3132	2012-01-14 04:40:36.911435
2279	3132	2012-01-14 04:40:36.911435
2875	2776	2012-01-14 04:40:36.911435
1238	3054	2012-01-14 04:41:19.162159
2962	3134	2012-01-14 04:41:29.166953
2781	3135	2012-01-14 04:41:49.482362
2154	2607	2012-01-14 04:42:08.654467
3136	3133	2012-01-14 04:42:08.654467
3136	2154	2012-01-14 04:42:08.654467
3136	2232	2012-01-14 04:42:08.654467
3141	3099	2012-01-14 04:43:55.622139
3033	3141	2012-01-14 04:43:55.622139
1642	3054	2012-01-14 04:43:55.622139
2150	3141	2012-01-14 04:43:55.622139
3142	2935	2012-01-14 04:44:51.603998
3142	3054	2012-01-14 04:44:51.603998
2841	3143	2012-01-14 04:45:12.808648
1951	3143	2012-01-14 04:45:23.828075
3039	3123	2012-01-14 04:45:23.828075
3023	3144	2012-01-14 04:45:23.828075
1458	3144	2012-01-14 04:45:23.828075
3145	2681	2012-01-14 04:46:10.647543
3072	3114	2012-01-14 04:46:21.279374
3146	3072	2012-01-14 04:46:21.279374
3127	3147	2012-01-14 04:46:48.157076
2914	3148	2012-01-14 04:47:18.041224
3081	3148	2012-01-14 04:47:18.041224
3151	2997	2012-01-14 04:48:42.622022
3127	1994	2012-01-14 04:48:42.622022
2807	3151	2012-01-14 04:48:42.622022
2529	3151	2012-01-14 04:48:42.622022
2765	3151	2012-01-14 04:48:42.622022
2997	2416	2012-01-14 04:49:35.310931
3076	3152	2012-01-14 04:49:35.310931
3008	3152	2012-01-14 04:49:35.310931
2268	3153	2012-01-14 04:50:17.056187
3153	3143	2012-01-14 04:50:17.056187
3155	2812	2012-01-14 04:51:17.082493
3155	498	2012-01-14 04:51:17.082493
2682	3156	2012-01-14 04:51:38.638785
1875	3156	2012-01-14 04:51:38.638785
3076	3156	2012-01-14 04:51:59.810351
3071	3158	2012-01-14 04:52:10.043248
385	3160	2012-01-14 04:52:39.473184
1176	3161	2012-01-14 04:53:20.27494
2102	3161	2012-01-14 04:53:20.27494
2924	3123	2012-01-14 04:53:52.041805
3053	3161	2012-01-14 04:54:48.244544
3065	3161	2012-01-14 04:54:48.244544
2875	3166	2012-01-14 04:54:48.244544
2233	3166	2012-01-14 04:54:48.244544
2287	3166	2012-01-14 04:54:48.244544
2869	3161	2012-01-14 04:56:32.158893
2673	3167	2012-01-14 04:56:32.158893
2363	3167	2012-01-14 04:56:32.158893
3168	2466	2012-01-14 04:57:16.542017
3168	2751	2012-01-14 04:57:16.542017
2953	3114	2012-01-14 04:57:50.165647
1238	2983	2012-01-14 04:58:10.177973
2980	3170	2012-01-14 04:58:10.177973
2105	3168	2012-01-14 04:59:28.220382
3081	3173	2012-01-14 04:59:28.220382
3025	3111	2012-01-14 04:59:57.681641
3168	2992	2012-01-14 05:00:32.587684
3081	2992	2012-01-14 05:00:32.587684
2666	2485	2012-01-14 05:00:32.587684
3025	3177	2012-01-14 05:01:05.941442
3176	3177	2012-01-14 05:01:05.941442
3178	3168	2012-01-14 05:01:25.318335
3178	3134	2012-01-14 05:01:25.318335
3008	3179	2012-01-14 05:01:49.345005
3133	3143	2012-01-14 05:01:49.345005
2466	3163	2012-01-14 05:01:49.345005
2105	3134	2012-01-14 05:01:49.345005
3025	3180	2012-01-14 05:03:21.63407
3155	3180	2012-01-14 05:03:21.63407
3181	3085	2012-01-14 05:03:50.031769
1194	3183	2012-01-14 05:04:12.377833
3168	2803	2012-01-14 05:04:33.125138
3155	3187	2012-01-14 05:05:43.821117
3023	3187	2012-01-14 05:05:43.821117
2468	3189	2012-01-14 05:06:41.265964
3191	1778	2012-01-14 05:07:22.734434
3192	2885	2012-01-14 05:07:32.324198
3193	2186	2012-01-14 05:07:42.895833
3193	2661	2012-01-14 05:07:42.895833
758	3194	2012-01-14 05:08:15.839745
1906	3194	2012-01-14 05:08:15.839745
1458	3194	2012-01-14 05:08:15.839745
2468	3194	2012-01-14 05:08:15.839745
2114	3196	2012-01-14 05:09:50.246269
3072	3196	2012-01-14 05:09:50.246269
3087	3194	2012-01-14 05:10:08.678589
1194	3197	2012-01-14 05:10:08.678589
3198	3170	2012-01-14 05:10:38.897362
2875	3199	2012-01-14 05:11:12.782854
2233	3199	2012-01-14 05:11:12.782854
2287	3199	2012-01-14 05:11:12.782854
3200	2154	2012-01-14 05:12:29.838703
2233	3200	2012-01-14 05:12:29.838703
2875	3200	2012-01-14 05:12:29.838703
2287	3200	2012-01-14 05:12:29.838703
3200	2996	2012-01-14 05:12:29.838703
2905	3200	2012-01-14 05:12:29.838703
3200	2232	2012-01-14 05:12:29.838703
3200	3053	2012-01-14 05:12:29.838703
3142	3203	2012-01-14 05:15:22.183725
2869	3203	2012-01-14 05:15:22.183725
3173	3203	2012-01-14 05:15:22.183725
3204	3016	2012-01-14 05:15:52.468795
2363	3168	2012-01-14 05:16:13.7143
3081	3206	2012-01-14 05:16:13.7143
2385	3206	2012-01-14 05:16:13.7143
3109	3208	2012-01-14 05:17:37.811372
2888	3208	2012-01-14 05:17:37.811372
3047	3209	2012-01-14 05:18:09.652107
3209	3191	2012-01-14 05:18:09.652107
3211	2765	2012-01-14 05:18:52.080106
2114	3212	2012-01-14 05:19:13.367287
3072	3212	2012-01-14 05:19:13.367287
1458	3213	2012-01-14 05:19:43.05683
2468	3213	2012-01-14 05:19:43.05683
758	3213	2012-01-14 05:19:43.05683
1051	3213	2012-01-14 05:19:43.05683
3087	3213	2012-01-14 05:19:43.05683
1906	3213	2012-01-14 05:19:43.05683
2468	2885	2012-01-14 05:20:50.866639
3214	3209	2012-01-14 05:20:50.866639
3028	3216	2012-01-14 05:21:31.394688
2765	3216	2012-01-14 05:21:31.394688
3039	3216	2012-01-14 05:21:31.394688
3219	2575	2012-01-14 05:23:09.653444
3219	2466	2012-01-14 05:23:09.653444
3219	2322	2012-01-14 05:23:09.653444
3219	2992	2012-01-14 05:23:09.653444
3039	3219	2012-01-14 05:23:09.653444
3225	3016	2012-01-14 05:26:39.664286
2962	3226	2012-01-14 05:26:57.58774
3196	3229	2012-01-14 05:28:03.165622
3076	3229	2012-01-14 05:28:03.165622
3232	2996	2012-01-14 05:29:32.138297
3232	2849	2012-01-14 05:29:32.138297
2875	2736	2012-01-14 05:29:52.038921
3219	1698	2012-01-14 05:30:02.039541
2149	3234	2012-01-14 05:30:02.039541
3235	3213	2012-01-14 05:30:44.680672
2267	3235	2012-01-14 05:30:44.680672
2682	3229	2012-01-14 05:30:44.680672
2233	3235	2012-01-14 05:30:44.680672
2905	3235	2012-01-14 05:30:44.680672
3236	2888	2012-01-14 05:32:26.364007
1844	3238	2012-01-14 05:33:11.443976
2677	3238	2012-01-14 05:33:11.443976
3053	3209	2012-01-14 05:33:11.443976
2905	3240	2012-01-14 05:34:18.176118
2267	3240	2012-01-14 05:34:18.176118
2287	3240	2012-01-14 05:34:18.176118
3240	3123	2012-01-14 05:34:18.176118
2233	3240	2012-01-14 05:34:18.176118
3240	3219	2012-01-14 05:34:18.176118
3240	3216	2012-01-14 05:34:18.176118
144	3240	2012-01-14 05:34:18.176118
2869	3209	2012-01-14 05:37:06.771606
3242	2996	2012-01-14 05:37:17.452148
3242	2154	2012-01-14 05:37:17.452148
3243	1238	2012-01-14 05:37:38.497103
3244	3134	2012-01-14 05:37:49.162503
3238	2996	2012-01-14 05:38:35.916031
3246	3085	2012-01-14 05:38:35.916031
3247	3154	2012-01-14 05:38:58.72738
2999	2980	2012-01-14 05:38:58.72738
2905	3247	2012-01-14 05:38:58.72738
3248	2924	2012-01-14 05:39:37.528163
1095	3249	2012-01-14 05:39:48.412435
2063	3249	2012-01-14 05:39:48.412435
3250	3123	2012-01-14 05:40:09.676331
2233	3250	2012-01-14 05:40:09.676331
2967	2996	2012-01-14 05:40:09.676331
3252	3209	2012-01-14 05:41:59.872598
3219	3252	2012-01-14 05:41:59.872598
3081	3252	2012-01-14 05:41:59.872598
3028	3219	2012-01-14 05:42:40.703759
2267	3254	2012-01-14 05:43:02.267755
1587	3238	2012-01-14 05:43:02.267755
3255	2992	2012-01-14 05:43:31.30914
2186	3258	2012-01-14 05:44:25.911729
3238	3133	2012-01-14 05:44:25.911729
3258	3234	2012-01-14 05:44:25.911729
3259	3095	2012-01-14 05:45:02.061538
3028	1458	2012-01-14 05:45:02.061538
3033	3259	2012-01-14 05:45:02.061538
3259	3238	2012-01-14 05:45:02.061538
3264	3209	2012-01-14 05:48:32.631957
2233	3266	2012-01-14 05:49:06.33119
3266	3154	2012-01-14 05:49:06.33119
2905	3266	2012-01-14 05:49:06.33119
2999	1896	2012-01-14 05:49:06.33119
3267	2408	2012-01-14 05:50:02.998102
1992	3267	2012-01-14 05:50:02.998102
2105	3167	2012-01-14 05:50:36.705905
3267	3133	2012-01-14 05:51:12.501509
2765	3219	2012-01-14 05:52:50.541222
1176	3272	2012-01-14 05:53:12.717812
3272	3213	2012-01-14 05:53:12.717812
3272	2885	2012-01-14 05:53:12.717812
1993	3065	2012-01-14 05:53:12.717812
2673	3273	2012-01-14 05:54:08.230646
1951	3258	2012-01-14 05:54:08.230646
3028	3275	2012-01-14 05:54:52.46349
3275	1926	2012-01-14 05:54:52.46349
3238	2571	2012-01-14 05:56:12.623361
3219	3279	2012-01-14 05:56:24.204645
2875	2857	2012-01-14 05:56:24.204645
1836	3209	2012-01-14 05:58:58.93815
2858	3285	2012-01-14 05:58:58.93815
3258	3285	2012-01-14 05:58:58.93815
2149	3285	2012-01-14 05:58:58.93815
3286	3238	2012-01-14 05:59:40.637217
2967	3133	2012-01-14 05:59:51.538475
3287	2992	2012-01-14 05:59:51.538475
3287	2466	2012-01-14 05:59:51.538475
3287	1698	2012-01-14 05:59:51.538475
1194	3238	2012-01-14 06:00:49.623788
3289	3219	2012-01-14 06:01:00.653521
\.


--
-- Data for Name: tuser; Type: TABLE DATA; Schema: t; Owner: olivier
--

COPY tuser (id, name, spent, quota, last_in, created, updated) FROM stdin;
1	olivier	26902043	0	2012-01-14 07:10:20.030139	2012-01-13 20:24:49.881034	2012-01-14 07:10:20.029697
\.


--
-- Name: tconst_pkey; Type: CONSTRAINT; Schema: t; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY tconst
    ADD CONSTRAINT tconst_pkey PRIMARY KEY (name);


--
-- Name: tmarket_id_key; Type: CONSTRAINT; Schema: t; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY tmarket
    ADD CONSTRAINT tmarket_id_key UNIQUE (id);


--
-- Name: tmvt_id_key; Type: CONSTRAINT; Schema: t; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY tmvt
    ADD CONSTRAINT tmvt_id_key UNIQUE (id);


--
-- Name: torder_pkey; Type: CONSTRAINT; Schema: t; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY torder
    ADD CONSTRAINT torder_pkey PRIMARY KEY (id);


--
-- Name: towner_name_key; Type: CONSTRAINT; Schema: t; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY towner
    ADD CONSTRAINT towner_name_key UNIQUE (name);


--
-- Name: towner_pkey; Type: CONSTRAINT; Schema: t; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY towner
    ADD CONSTRAINT towner_pkey PRIMARY KEY (id);


--
-- Name: tquality_name_key; Type: CONSTRAINT; Schema: t; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY tquality
    ADD CONSTRAINT tquality_name_key UNIQUE (name);


--
-- Name: trefused_pkey; Type: CONSTRAINT; Schema: t; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY trefused
    ADD CONSTRAINT trefused_pkey PRIMARY KEY (x, y);


--
-- Name: tuser_id_key; Type: CONSTRAINT; Schema: t; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY tuser
    ADD CONSTRAINT tuser_id_key UNIQUE (id);


--
-- Name: tuser_pkey; Type: CONSTRAINT; Schema: t; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY tuser
    ADD CONSTRAINT tuser_pkey PRIMARY KEY (name);


--
-- Name: tmvt_did_idx; Type: INDEX; Schema: t; Owner: olivier; Tablespace: 
--

CREATE INDEX tmvt_did_idx ON tmvt USING btree (grp);


--
-- Name: tmvt_nat_idx; Type: INDEX; Schema: t; Owner: olivier; Tablespace: 
--

CREATE INDEX tmvt_nat_idx ON tmvt USING btree (nat);


--
-- Name: tmvt_own_dst_idx; Type: INDEX; Schema: t; Owner: olivier; Tablespace: 
--

CREATE INDEX tmvt_own_dst_idx ON tmvt USING btree (own_dst);


--
-- Name: tmvt_own_src_idx; Type: INDEX; Schema: t; Owner: olivier; Tablespace: 
--

CREATE INDEX tmvt_own_src_idx ON tmvt USING btree (own_src);


--
-- Name: torder_np_idx; Type: INDEX; Schema: t; Owner: olivier; Tablespace: 
--

CREATE INDEX torder_np_idx ON torder USING btree (np);


--
-- Name: torder_nr_idx; Type: INDEX; Schema: t; Owner: olivier; Tablespace: 
--

CREATE INDEX torder_nr_idx ON torder USING btree (nr);


--
-- Name: towner_name_idx; Type: INDEX; Schema: t; Owner: olivier; Tablespace: 
--

CREATE INDEX towner_name_idx ON towner USING btree (name);


--
-- Name: tquality_name_idx; Type: INDEX; Schema: t; Owner: olivier; Tablespace: 
--

CREATE INDEX tquality_name_idx ON tquality USING btree (name);


--
-- Name: trig_befa_towner; Type: TRIGGER; Schema: t; Owner: olivier
--

CREATE TRIGGER trig_befa_towner BEFORE INSERT OR UPDATE ON towner FOR EACH ROW EXECUTE PROCEDURE ftime_updated();


--
-- Name: trig_befa_tquality; Type: TRIGGER; Schema: t; Owner: olivier
--

CREATE TRIGGER trig_befa_tquality BEFORE INSERT OR UPDATE ON tquality FOR EACH ROW EXECUTE PROCEDURE ftime_updated();


--
-- Name: trig_befa_tuser; Type: TRIGGER; Schema: t; Owner: olivier
--

CREATE TRIGGER trig_befa_tuser BEFORE INSERT OR UPDATE ON tuser FOR EACH ROW EXECUTE PROCEDURE ftime_updated();


--
-- Name: tmvt_grp_fkey; Type: FK CONSTRAINT; Schema: t; Owner: olivier
--

ALTER TABLE ONLY tmvt
    ADD CONSTRAINT tmvt_grp_fkey FOREIGN KEY (grp) REFERENCES tmvt(id);


--
-- Name: tmvt_nat_fkey; Type: FK CONSTRAINT; Schema: t; Owner: olivier
--

ALTER TABLE ONLY tmvt
    ADD CONSTRAINT tmvt_nat_fkey FOREIGN KEY (nat) REFERENCES tquality(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: tmvt_orid_fkey; Type: FK CONSTRAINT; Schema: t; Owner: olivier
--

ALTER TABLE ONLY tmvt
    ADD CONSTRAINT tmvt_orid_fkey FOREIGN KEY (orid) REFERENCES torder(id);


--
-- Name: tmvt_own_dst_fkey; Type: FK CONSTRAINT; Schema: t; Owner: olivier
--

ALTER TABLE ONLY tmvt
    ADD CONSTRAINT tmvt_own_dst_fkey FOREIGN KEY (own_dst) REFERENCES towner(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: tmvt_own_src_fkey; Type: FK CONSTRAINT; Schema: t; Owner: olivier
--

ALTER TABLE ONLY tmvt
    ADD CONSTRAINT tmvt_own_src_fkey FOREIGN KEY (own_src) REFERENCES towner(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: torder_np_fkey; Type: FK CONSTRAINT; Schema: t; Owner: olivier
--

ALTER TABLE ONLY torder
    ADD CONSTRAINT torder_np_fkey FOREIGN KEY (np) REFERENCES tquality(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: torder_nr_fkey; Type: FK CONSTRAINT; Schema: t; Owner: olivier
--

ALTER TABLE ONLY torder
    ADD CONSTRAINT torder_nr_fkey FOREIGN KEY (nr) REFERENCES tquality(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: torder_own_fkey; Type: FK CONSTRAINT; Schema: t; Owner: olivier
--

ALTER TABLE ONLY torder
    ADD CONSTRAINT torder_own_fkey FOREIGN KEY (own) REFERENCES towner(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: tquality_idd_fkey; Type: FK CONSTRAINT; Schema: t; Owner: olivier
--

ALTER TABLE ONLY tquality
    ADD CONSTRAINT tquality_idd_fkey FOREIGN KEY (idd) REFERENCES tuser(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: trefused_x_fkey; Type: FK CONSTRAINT; Schema: t; Owner: olivier
--

ALTER TABLE ONLY trefused
    ADD CONSTRAINT trefused_x_fkey FOREIGN KEY (x) REFERENCES torder(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: trefused_y_fkey; Type: FK CONSTRAINT; Schema: t; Owner: olivier
--

ALTER TABLE ONLY trefused
    ADD CONSTRAINT trefused_y_fkey FOREIGN KEY (y) REFERENCES torder(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: public; Type: ACL; Schema: -; Owner: olivier
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM olivier;
GRANT ALL ON SCHEMA public TO olivier;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- Name: fackmvt(bigint); Type: ACL; Schema: t; Owner: olivier
--

REVOKE ALL ON FUNCTION fackmvt(_mid bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION fackmvt(_mid bigint) FROM olivier;
GRANT ALL ON FUNCTION fackmvt(_mid bigint) TO olivier;
GRANT ALL ON FUNCTION fackmvt(_mid bigint) TO PUBLIC;
GRANT ALL ON FUNCTION fackmvt(_mid bigint) TO market;


--
-- Name: fadmin(); Type: ACL; Schema: t; Owner: olivier
--

REVOKE ALL ON FUNCTION fadmin() FROM PUBLIC;
REVOKE ALL ON FUNCTION fadmin() FROM olivier;
GRANT ALL ON FUNCTION fadmin() TO olivier;
GRANT ALL ON FUNCTION fadmin() TO PUBLIC;
GRANT ALL ON FUNCTION fadmin() TO admin;


--
-- Name: fdroporder(bigint); Type: ACL; Schema: t; Owner: olivier
--

REVOKE ALL ON FUNCTION fdroporder(_oid bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION fdroporder(_oid bigint) FROM olivier;
GRANT ALL ON FUNCTION fdroporder(_oid bigint) TO olivier;
GRANT ALL ON FUNCTION fdroporder(_oid bigint) TO PUBLIC;
GRANT ALL ON FUNCTION fdroporder(_oid bigint) TO market;


--
-- Name: fget_omegas(text, text); Type: ACL; Schema: t; Owner: olivier
--

REVOKE ALL ON FUNCTION fget_omegas(_qr text, _qp text) FROM PUBLIC;
REVOKE ALL ON FUNCTION fget_omegas(_qr text, _qp text) FROM olivier;
GRANT ALL ON FUNCTION fget_omegas(_qr text, _qp text) TO olivier;
GRANT ALL ON FUNCTION fget_omegas(_qr text, _qp text) TO PUBLIC;
GRANT ALL ON FUNCTION fget_omegas(_qr text, _qp text) TO market;


--
-- Name: fgetconst(text); Type: ACL; Schema: t; Owner: olivier
--

REVOKE ALL ON FUNCTION fgetconst(_name text) FROM PUBLIC;
REVOKE ALL ON FUNCTION fgetconst(_name text) FROM olivier;
GRANT ALL ON FUNCTION fgetconst(_name text) TO olivier;
GRANT ALL ON FUNCTION fgetconst(_name text) TO PUBLIC;
GRANT ALL ON FUNCTION fgetconst(_name text) TO market;


--
-- Name: finsertorder(text, text, bigint, bigint, text); Type: ACL; Schema: t; Owner: olivier
--

REVOKE ALL ON FUNCTION finsertorder(_owner text, _qualityprovided text, _qttprovided bigint, _qttrequired bigint, _qualityrequired text) FROM PUBLIC;
REVOKE ALL ON FUNCTION finsertorder(_owner text, _qualityprovided text, _qttprovided bigint, _qttrequired bigint, _qualityrequired text) FROM olivier;
GRANT ALL ON FUNCTION finsertorder(_owner text, _qualityprovided text, _qttprovided bigint, _qttrequired bigint, _qualityrequired text) TO olivier;
GRANT ALL ON FUNCTION finsertorder(_owner text, _qualityprovided text, _qttprovided bigint, _qttrequired bigint, _qualityrequired text) TO PUBLIC;
GRANT ALL ON FUNCTION finsertorder(_owner text, _qualityprovided text, _qttprovided bigint, _qttrequired bigint, _qualityrequired text) TO market;


--
-- Name: fuser(text, bigint); Type: ACL; Schema: t; Owner: olivier
--

REVOKE ALL ON FUNCTION fuser(_she text, _quota bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION fuser(_she text, _quota bigint) FROM olivier;
GRANT ALL ON FUNCTION fuser(_she text, _quota bigint) TO olivier;
GRANT ALL ON FUNCTION fuser(_she text, _quota bigint) TO PUBLIC;
GRANT ALL ON FUNCTION fuser(_she text, _quota bigint) TO market;


--
-- Name: towner; Type: ACL; Schema: t; Owner: olivier
--

REVOKE ALL ON TABLE towner FROM PUBLIC;
REVOKE ALL ON TABLE towner FROM olivier;
GRANT ALL ON TABLE towner TO olivier;
GRANT SELECT ON TABLE towner TO market;


--
-- Name: tquality; Type: ACL; Schema: t; Owner: olivier
--

REVOKE ALL ON TABLE tquality FROM PUBLIC;
REVOKE ALL ON TABLE tquality FROM olivier;
GRANT ALL ON TABLE tquality TO olivier;
GRANT SELECT ON TABLE tquality TO market;


--
-- Name: tuser; Type: ACL; Schema: t; Owner: olivier
--

REVOKE ALL ON TABLE tuser FROM PUBLIC;
REVOKE ALL ON TABLE tuser FROM olivier;
GRANT ALL ON TABLE tuser TO olivier;
GRANT SELECT ON TABLE tuser TO market;


--
-- Name: vmvt; Type: ACL; Schema: t; Owner: olivier
--

REVOKE ALL ON TABLE vmvt FROM PUBLIC;
REVOKE ALL ON TABLE vmvt FROM olivier;
GRANT ALL ON TABLE vmvt TO olivier;
GRANT SELECT ON TABLE vmvt TO market;


--
-- Name: vorder; Type: ACL; Schema: t; Owner: olivier
--

REVOKE ALL ON TABLE vorder FROM PUBLIC;
REVOKE ALL ON TABLE vorder FROM olivier;
GRANT ALL ON TABLE vorder TO olivier;
GRANT SELECT ON TABLE vorder TO market;


--
-- Name: vstat; Type: ACL; Schema: t; Owner: olivier
--

REVOKE ALL ON TABLE vstat FROM PUBLIC;
REVOKE ALL ON TABLE vstat FROM olivier;
GRANT ALL ON TABLE vstat TO olivier;
GRANT SELECT ON TABLE vstat TO market;


--
-- PostgreSQL database dump complete
--

