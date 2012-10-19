--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

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

CREATE EXTENSION IF NOT EXISTS flow WITH SCHEMA public;


--
-- Name: EXTENSION flow; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION flow IS 'data type for cycle of orders';


SET search_path = public, pg_catalog;

--
-- Name: dquantity; Type: DOMAIN; Schema: public; Owner: olivier
--

CREATE DOMAIN dquantity AS bigint
	CONSTRAINT dquantity_check CHECK ((VALUE > 0));


ALTER DOMAIN public.dquantity OWNER TO olivier;

--
-- Name: ymarketstatus; Type: TYPE; Schema: public; Owner: olivier
--

CREATE TYPE ymarketstatus AS ENUM (
    'INITIALIZING',
    'OPENED',
    'STOPPING',
    'CLOSED',
    'STARTING'
);


ALTER TYPE public.ymarketstatus OWNER TO olivier;

--
-- Name: yresorder; Type: TYPE; Schema: public; Owner: olivier
--

CREATE TYPE yresorder AS (
	id integer,
	uuid text,
	own integer,
	nr integer,
	qtt_requ bigint,
	np integer,
	qtt_prov bigint,
	qtt_in bigint,
	qtt_out bigint,
	flows yflow[]
);


ALTER TYPE public.yresorder OWNER TO olivier;

--
-- Name: yresprequote; Type: TYPE; Schema: public; Owner: olivier
--

CREATE TYPE yresprequote AS (
	own integer,
	nr integer,
	np integer,
	qtt_prov bigint,
	qtt_in_min bigint,
	qtt_out_min bigint,
	qtt_in_max bigint,
	qtt_out_max bigint,
	qtt_in_sum bigint,
	qtt_out_sum bigint,
	flows text
);


ALTER TYPE public.yresprequote OWNER TO olivier;

--
-- Name: fbalance(); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fbalance() RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE 
	_cnt 		int;
BEGIN
	WITH accounting_order AS (SELECT np,sum(qtt) AS qtt FROM torder GROUP BY np),
	     accounting_mvt   AS (SELECT nat as np,sum(qtt) AS qtt FROM tmvt GROUP BY nat)
	SELECT count(*) INTO _cnt FROM tquality,accounting_order,accounting_mvt
	WHERE tquality.id=accounting_order.np AND tquality.id=accounting_mvt.np
		AND tquality.qtt != accounting_order.qtt + accounting_mvt.qtt;
	RETURN _cnt;
END;		
$$;


ALTER FUNCTION public.fbalance() OWNER TO olivier;

--
-- Name: fchangestatemarket(boolean); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fchangestatemarket(_execute boolean) RETURNS TABLE(_market_session integer, _market_status ymarketstatus)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
	_cnt int;
	_hm tmarket%rowtype;
	_action text;
	_prev_status ymarketstatus;
	_res bool;
	_new_status ymarketstatus;
BEGIN

	SELECT market_status,market_session INTO _prev_status,_market_session FROM vmarket;
	_market_status := _prev_status;
	IF NOT FOUND THEN 
		_action := 'init';
		_prev_status := 'INITIALIZING';
		_new_status := 'OPENED';
		
	ELSIF (_prev_status = 'STARTING') THEN		
		_action := 'open';
		_new_status := 'OPENED';
		
	ELSIF (_prev_status = 'OPENED') THEN
		_action := 'stop';
		_new_status := 'STOPPING';
		
	ELSIF (_prev_status = 'STOPPING') THEN
		_action := 'close';
		_new_status := 'CLOSED';
		
	ELSE -- _prev_status='CLOSED'
		_action := 'start';
		_new_status := 'STARTING';
	END IF;

	-- RAISE NOTICE 'market_status %->%',_prev_status,_new_status;

	IF NOT _execute THEN
		RAISE NOTICE 'The next market state will be %',_new_status;
		RETURN NEXT;
		RETURN;
	END IF;
	
	INSERT INTO tmarket (created) VALUES (statement_timestamp()) RETURNING * INTO _hm;
	SELECT market_status,market_session INTO _new_status,_market_session FROM vmarket;
	_market_status := _new_status;
	
	IF (_action = 'init' OR _action = 'open') THEN
		-- INITIALIZING	->OPENED
		-- STARTING		->OPENED 		
		GRANT client_opened_role TO client;
				
	ELSIF (_action = 'stop') THEN
		-- OPENED		->STOPPING
		REVOKE client_opened_role FROM client;
		GRANT  client_stopping_role TO client;			
		
	ELSIF (_action = 'close') THEN
		-- STOPPING		->CLOSED 
		REVOKE client_stopping_role FROM client;
		GRANT DELETE ON TABLE torderremoved,tmvtremoved TO admin;
		RAISE NOTICE 'Connexions by clients are forbidden. The role admin has exclusive access to the market.';
					
	ELSE -- _action='start'
		-- CLOSED		->STARTING
		REVOKE DELETE ON TABLE torderremoved,tmvtremoved FROM admin;
		_res := frenumbertables(true);
		IF NOT _res THEN
			RAISE EXCEPTION USING ERRCODE='YA001';
		END IF;	
		RAISE NOTICE 'A new market session is created. Run the command: VACUUM FULL ANALYZE before changing the market state to OPENED.';		

	END IF;
	
	
	RETURN NEXT;
	RETURN;
	 
END;
$$;


ALTER FUNCTION public.fchangestatemarket(_execute boolean) OWNER TO olivier;

--
-- Name: fcreate_tmp(integer, yorder, integer, integer); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fcreate_tmp(_id integer, _ord yorder, _np integer, _nr integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE 
	_MAXORDERFETCH	 int := fgetconst('MAXORDERFETCH'); 
	_MAXCYCLE 	int := fgetconst('MAXCYCLE');
	_cnt int;
BEGIN
/*	DROP TABLE IF EXISTS _tmp;
	RAISE NOTICE 'select * from fcreate_tmp(%,yorder_get%,%,%)',_id,_ord,_np,_nr;
	CREATE TEMPORARY TABLE _tmp ON COMMIT DROP  AS (
*/	
	CREATE TEMPORARY TABLE _tmp ON COMMIT DROP AS (
		SELECT A.id,A.ord,A.nr,A.pat FROM (
			WITH RECURSIVE search_backward(id,ord,pat,nr) AS (
				SELECT 	_id,_ord,yflow_get(_ord),_nr
				UNION ALL
				SELECT 	X.id,X.ord,
					yflow_get(X.ord,Y.pat), 
					-- add the order at the beginning of the yflow
					X.nr
					FROM search_backward Y,vorderinsert X
					WHERE   yflow_follow(_MAXCYCLE,X.ord,Y.pat) 
					-- X->Y === X.qtt>0 and X.np=Y[0].nr
					-- Y.pat does not contain X.ord 
					-- len(X.ord+Y.path) <= _MAXCYCLE	
					-- it is not an unexpected cycle: Y[!=-1]|->X === Y[i].np != X.nr with i!= -1
					 
			)
			SELECT id,ord,nr,pat 
			FROM search_backward LIMIT _MAXORDERFETCH 
		) A WHERE  yflow_status(A.pat)=3 --draft
	);
	SELECT COUNT(*) INTO _cnt FROM _tmp;

	RETURN _cnt;
END;
$$;


ALTER FUNCTION public.fcreate_tmp(_id integer, _ord yorder, _np integer, _nr integer) OWNER TO olivier;

--
-- Name: fcreateowner(text); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fcreateowner(_name text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
	_wid int;
BEGIN
	LOOP
		SELECT id INTO _wid FROM towner WHERE name=_name;
		IF found THEN
			RAISE WARNING 'The owner % was already created',_name;
			return _wid;
		END IF;
		BEGIN
			if(char_length(_name)<1) THEN
				RAISE NOTICE 'Owner s name cannot be empty';
				RAISE EXCEPTION USING ERRCODE='YU001';
			END IF;
			INSERT INTO towner (name) VALUES (_name) RETURNING id INTO _wid;
			RAISE NOTICE 'owner % created',_name;
			return _wid;
		EXCEPTION WHEN unique_violation THEN
			--
		END;
	END LOOP;
END;
$$;


ALTER FUNCTION public.fcreateowner(_name text) OWNER TO olivier;

--
-- Name: fcreateuser(text); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fcreateuser(_name text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
	_user	tuser%rowtype;
	_super	bool;
	_market_status	text;
BEGIN
	IF( _name IN ('admin','client','client_opened_role','client_stopping_role')) THEN
		RAISE WARNING 'The name % is not allowed',_name USING ERRCODE='YU001';
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	SELECT * INTO _user FROM tuser WHERE name=_name;
	IF FOUND THEN
		RAISE WARNING 'The user % exists',_name USING ERRCODE='YU001';
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	INSERT INTO tuser (name) VALUES (_name);
	
	SELECT rolsuper INTO _super FROM pg_authid where rolname=_name;
	IF NOT FOUND THEN
		_super := false;
		EXECUTE 'CREATE ROLE ' || _name;
	ELSE
		IF(_super) THEN
			-- RAISE NOTICE 'The role % is a super user.',_name;
			RAISE NOTICE 'The role is a super user.';
		ELSE
			-- RAISE WARNING 'The user is not found but a role % already exists - unchanged.',_name;
			RAISE NOTICE 'The user is not found but the role already exists - unchanged.';
			-- RAISE EXCEPTION USING ERRCODE='YU001';	
			
		END IF;
	END IF;
	
	IF (NOT _super) THEN
		EXECUTE 'GRANT client TO ' || _name;
		EXECUTE 'ALTER ROLE ' || _name || ' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION'; 
		EXECUTE 'ALTER ROLE ' || _name || ' LOGIN ';	
	END IF;
	
	RETURN;
		
END;
$$;


ALTER FUNCTION public.fcreateuser(_name text) OWNER TO olivier;

--
-- Name: fexecquote(text, integer); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fexecquote(_owner text, _idquote integer) RETURNS yresorder
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
	
DECLARE
	_wid		int;
	_o		torder%rowtype;
	_idd		int;
	_q		tquote%rowtype;
	_ro		yresorder%ROWTYPE;

	_flows		yflow[];
	_ypatmax	yflow;	
	_res	        int8[];
	_qtt_prov	int8;
	_qtt_requ	int8;
	_first_mvt	int;

BEGIN
	
	_idd := fverifyquota();
	_wid := fgetowner(_owner,false); -- returns _wid == 0 if not found
	
	SELECT * INTO _q FROM tquote WHERE id=_idquote AND own=_wid;
	IF (NOT FOUND) THEN
		IF(_wid = 0) THEN
			RAISE NOTICE 'the owner % is not found',_owner;
		ELSE
			RAISE NOTICE 'this quote % was not made by owner %',_idquote,_owner;
		END IF;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	-- lock table torder in share row exclusive mode; 
	lock table torder in share update exclusive mode;
		
	-- _q.qtt_requ != 0		
	_qtt_requ := _q.qtt_requ;
	_qtt_prov := _q.qtt_prov;
	
	_o := finsert_toint(_qtt_prov,_q.nr,_q.np,_qtt_requ,_q.own);
	
	-- id,uuid,own,nr,qtt_requ,np,qtt_prov,qtt_in,qtt_out,flows
	_ro.id      	:= _o.id;
	_ro.uuid    	:= _o.uuid;
	_ro.own     	:= _q.own;
	_ro.nr      	:= _q.nr;
	_ro.qtt_requ	:= _q.qtt_requ;
	_ro.np      	:= _q.np;
	_ro.qtt_prov	:= _q.qtt_prov;
	_ro.qtt_in  	:= 0;
	_ro.qtt_out 	:= 0;
	_ro.flows   	:= ARRAY[]::yflow[];
	
	FOR _ypatmax IN SELECT _patmax  FROM finsertflows(_o) LOOP
		_first_mvt := fexecute_flow(_ypatmax);
		_res := yflow_qtts(_ypatmax);
		_ro.qtt_in  := _ro.qtt_in  + _res[1];
		_ro.qtt_out := _ro.qtt_out + _res[2];
		_ro.flows := array_append(_ro.flows,_ypatmax);
	END LOOP;
	
	
	IF (	(_ro.qtt_in = 0) OR (_qtt_requ = 0) OR
		((_ro.qtt_out::double precision)	/(_ro.qtt_in::double precision)) > 
		((_qtt_prov::double precision)		/(_qtt_requ::double precision))
	) THEN
		RAISE NOTICE 'Omega of the flows obtained is not limited by the order';
		RAISE EXCEPTION USING ERRCODE='YA003';
	END IF;
	
	PERFORM fremovequote_int(_idquote);	
	PERFORM finvalidate_treltried();
	
	RETURN _ro;
	
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	-- PERFORM fremovequote_int(_idquote); 
	-- RAISE NOTICE 'Abort; Quote removed';
	RETURN _ro; 

END; 
$$;


ALTER FUNCTION public.fexecquote(_owner text, _idquote integer) OWNER TO olivier;

--
-- Name: fexecute_flow(yflow); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fexecute_flow(_flw yflow) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
	_commits	int8[][];
	_i		int;
	_next_i		int;
	_nbcommit	int;
	
	_oid		int;
	_w_src		int;
	_w_dst		int;
	_flowr		int8;
	_first_mvt_uuid	text;
	_first_mvt  int;
	_exhausted	bool;
	_mvt_id		int;
	_qtt		int8;
	_cnt 		int;
	_oruuid		text;
	_uuid		text;
	_res		text;
BEGIN

	_commits := yflow_to_matrix(_flw);
	-- indices in _commits
	-- 1  2   3  4        5  6        7   8
	-- id,own,nr,qtt_requ,np,qtt_prov,qtt,flowr
	
	_nbcommit := yflow_dim(_flw); -- raise an error when flow->dim not in [2,8]
	_first_mvt_uuid := NULL;
	_first_mvt := NULL;
	_exhausted := false;
	-- RAISE NOTICE 'flow of % commits',_nbcommit;
	_i := _nbcommit;	
	FOR _next_i IN 1 .. _nbcommit LOOP
		-- _commits[_next_i] follows _commits[_i]
		_oid	:= _commits[_i][1]::int;
		_w_src	:= _commits[_i][2]::int;
		_w_dst	:= _commits[_next_i][2]::int;
		_flowr	:= _commits[_i][8];
		
		UPDATE torder set qtt = qtt - _flowr ,updated = statement_timestamp()
			WHERE id = _oid AND _flowr <= qtt RETURNING uuid,qtt INTO _oruuid,_qtt;
		IF(NOT FOUND) THEN
			RAISE WARNING 'the flow is not in sync with the database torder[%] does not exist or torder.qtt < %',_oid,_flowr ;
			RAISE EXCEPTION USING ERRCODE='YU002';
		END IF;
			
		INSERT INTO tmvt (uuid,nb,oruuid,grp,own_src,own_dst,qtt,nat,created) 
			VALUES('',_nbcommit,_oruuid,'',_w_src,_w_dst,_flowr,_commits[_i][5]::int,statement_timestamp())
			RETURNING id INTO _mvt_id;
		_uuid := fgetuuid(_mvt_id);
					
		IF(_first_mvt_uuid IS NULL) THEN
			_first_mvt_uuid := _uuid;
			_first_mvt := _mvt_id;
		END IF;
		
		UPDATE tmvt SET uuid = _uuid, grp = _first_mvt_uuid WHERE id=_mvt_id;
		
		IF(_qtt=0) THEN
			perform fremoveorder_int(_oid);
			_exhausted := true;
		END IF;

		_i := _next_i;
		----------------------------------------------------------------
	END LOOP;
	-- RAISE NOTICE '_first_mvt=%',_first_mvt;
	-- UPDATE tmvt SET grp = _first_mvt WHERE uuid = _first_mvt  AND (grp IS NULL); --done only for oruuid==_oruuid	
	IF(NOT FOUND) THEN
		RAISE EXCEPTION 'the movement % does not exist',_first_mvt 
			USING ERRCODE='YA003';
	END IF;
	
	IF(NOT _exhausted) THEN
		--  some order should be exhausted 
		RAISE EXCEPTION 'the cycle should exhaust some order' 
			USING ERRCODE='YA003';
	END IF;
	
	PERFORM fupdate_treltried(_commits,_nbcommit);
	
	RETURN _first_mvt;
END;
$$;


ALTER FUNCTION public.fexecute_flow(_flw yflow) OWNER TO olivier;

--
-- Name: fexplodequality(text); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fexplodequality(_quality_name text) RETURNS text[]
    LANGUAGE plpgsql
    AS $$
DECLARE
	_e int;
	_q text[];
	_CHECK_QUALITY_OWNERSHIP int := fgetconst('CHECK_QUALITY_OWNERSHIP');
BEGIN
	IF(char_length(_quality_name) <1) THEN
		RAISE NOTICE 'Quality name "%" incorrect: do not len(name)<1',_quality_name;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	IF(_CHECK_QUALITY_OWNERSHIP = 0) THEN
		_q[1] := NULL;
		_q[2] := _quality_name;
		RETURN _q;
	END IF;
	
	_e =position('/' in _quality_name);
	IF(_e < 2) THEN 
		RAISE NOTICE 'Quality name "%" incorrect: <depository>/<quality> expected',_quality_name;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	_q[1] = substring(_quality_name for _e-1);
	_q[2] = substring(_quality_name from _e+1);
	if(char_length(_q[2])<1) THEN
		RAISE NOTICE 'Quality name "%" incorrect: <depository>/<quality> expected',_quality_name;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	RETURN _q;
END;
$$;


ALTER FUNCTION public.fexplodequality(_quality_name text) OWNER TO olivier;

--
-- Name: fget_treltried(integer, integer); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fget_treltried(_np integer, _nr integer) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.fget_treltried(_np integer, _nr integer) OWNER TO olivier;

--
-- Name: fgetagr(text); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fgetagr(_grp text) RETURNS TABLE(_own text, _natp text, _qtt_prov bigint, _qtt_requ bigint, _natr text)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.fgetagr(_grp text) OWNER TO olivier;

--
-- Name: fgetconst(text); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fgetconst(_name text) RETURNS integer
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
	_ret int;
BEGIN
	SELECT value INTO _ret FROM tconst WHERE name=_name;
	IF(NOT FOUND) THEN
		RAISE WARNING 'the const % is not found',_name USING ERRCODE= 'YA002';
		RAISE EXCEPTION USING ERRCODE='YA002';
	END IF;
	IF(_name = 'MAXCYCLE' AND _ret >8) THEN
		RAISE EXCEPTION 'obCMAXVALUE must be <=8' USING ERRCODE='YA002';
	END IF;
	RETURN _ret;
END; 
$$;


ALTER FUNCTION public.fgetconst(_name text) OWNER TO olivier;

--
-- Name: fgeterrs(boolean); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fgeterrs(_details boolean) RETURNS TABLE(_name text, cnt bigint)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE 
	_i 		int;
	_cnt 		int;
BEGIN		
	_name := 'balance';
	cnt := fbalance();	
	RETURN NEXT;
	
	IF(_details) THEN
	
		_name := 'errors on quantities in mvts';
		cnt := fverifmvt();
		RETURN NEXT;
	
		_name := 'errors on agreements in mvts';
		cnt := fverifmvt2();
		RETURN NEXT;
	END IF;
	RETURN;
END;
$$;


ALTER FUNCTION public.fgeterrs(_details boolean) OWNER TO olivier;

--
-- Name: fgetowner(text, boolean); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fgetowner(_name text, _insert boolean) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
	_wid int;
BEGIN

	SELECT id INTO _wid FROM towner WHERE name=_name;
	IF NOT found THEN
		IF (_insert) THEN
			IF (fgetconst('INSERT_OWN_UNKNOWN')=1) THEN
				_wid := fcreateowner(_name);
			ELSE
				RAISE NOTICE 'The owner % is unknown',_name;
				RAISE EXCEPTION USING ERRCODE='YU001';
			END IF;
		ELSE
			_wid := 0;
		END IF;
	END IF;
	return _wid;
END;
$$;


ALTER FUNCTION public.fgetowner(_name text, _insert boolean) OWNER TO olivier;

--
-- Name: fgetprequote(text, text, bigint, text); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fgetprequote(_owner text, _qualityprovided text, _qttprovided bigint, _qualityrequired text) RETURNS yresprequote
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
	
DECLARE
	_pivot 		 torder%rowtype;
	_ypatmax	 yflow;
	_flows		 text[];
	_res	         int8[];
	_idd		 int;
	_q		 text[];
	_r		 yresprequote;
	_om_min		double precision;
	_om_max		double precision;
	_om		double precision;
BEGIN
	_idd := fverifyquota();
	
	-- quantity must be >0
	IF(_qttprovided<=0) THEN
		RAISE NOTICE 'quantities incorrect: %<=0', _qttprovided;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	_q := fexplodequality(_qualityprovided);
	IF ((_q[1] IS NOT NULL) AND (_q[1] != session_user)) THEN
		RAISE NOTICE 'depository % of quality is not the user %',_q[1],session_user;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	-- qualities are red and inserted if necessary
	_pivot.np := fgetquality(_qualityprovided,true); 
	_pivot.nr := fgetquality(_qualityrequired,true); 
	_pivot.id  := 0; 
	
	-- if does not exists, inserted
	_pivot.own := fgetowner(_owner,true); 
	 
	_pivot.qtt_requ := 0; -- lastignore == true
	_pivot.qtt_prov := _qttprovided; 
	_pivot.qtt := _qttprovided;
	
	_r.own 		:= _pivot.own;
	-- _r.flows 	:= ARRAY[]::yflow[];
	_flows		:= ARRAY[]::text[];
	_r.nr 		:= _pivot.nr;
	_r.np 		:= _pivot.np;
	_r.qtt_prov 	:= _pivot.qtt_prov;
	
	_r.qtt_in_min := 0;	_r.qtt_in_max := 0; 
	_r.qtt_out_min := 0;	_r.qtt_out_max := 0;
	_om_min := 0;		_om_max := 0;
	
	_r.qtt_in_sum := 0;
	_r.qtt_out_sum := 0;
	
	FOR _ypatmax IN SELECT _patmax  FROM finsertflows(_pivot) LOOP
		_flows := array_append(_flows,yflow_to_json(_ypatmax));
		_res := yflow_qtts(_ypatmax); -- [in,out] of the last node
		
		_r.qtt_in_sum  := _r.qtt_in_sum + _res[1];
		_r.qtt_out_sum := _r.qtt_out_sum + _res[2];
		
		_om := (_res[2]::double precision)/(_res[1]::double precision);
		
		IF(_om_min = 0 OR _om < _om_min) THEN
			_r.qtt_in_min := _res[1];
			_r.qtt_out_min := _res[2];
			_om_min := _om;
		END IF;
		IF(_om_max = 0 OR _om > _om_max) THEN
			_r.qtt_in_max := _res[1];
			_r.qtt_out_max := _res[2];
			_om_max := _om;
		END IF;
	END LOOP;
	_r.flows := array_to_json(_flows);

	RETURN _r;
END; 
$$;


ALTER FUNCTION public.fgetprequote(_owner text, _qualityprovided text, _qttprovided bigint, _qualityrequired text) OWNER TO olivier;

--
-- Name: fgetquality(text, boolean); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fgetquality(_quality_name text, insert boolean) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE 
	_idd int;
	_qlt	tquality%rowtype;
	_q text[];
	_id int;
BEGIN
	LOOP
		SELECT * INTO _qlt FROM tquality WHERE name = _quality_name;
		IF FOUND THEN
			return _qlt.id;
		END IF;
		IF(NOT insert) THEN
			return 0;
		END IF;
		
		BEGIN
			_q := fexplodequality(_quality_name);
			IF(_q[1] IS NOT NULL) THEN 	
				-- _CHECK_QUALITY_OWNERSHIP =1
				SELECT id INTO _idd FROM tuser WHERE name=_q[1];
				IF(NOT FOUND) THEN -- user should exists
					RAISE NOTICE 'The depository "%" is undefined',_q[1] ;
					RAISE EXCEPTION USING ERRCODE='YU001';
				END IF;
			ELSE
				_idd := NULL;
			END IF;
		
			INSERT INTO tquality (name,idd,depository,qtt) VALUES (_quality_name,_idd,_q[1],0)
				RETURNING * INTO _qlt;
			RETURN _qlt.id;
			
		EXCEPTION WHEN unique_violation THEN
			--
		END;
	END LOOP;

END;
$$;


ALTER FUNCTION public.fgetquality(_quality_name text, insert boolean) OWNER TO olivier;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: tquote; Type: TABLE; Schema: public; Owner: olivier; Tablespace: 
--

CREATE TABLE tquote (
    id integer NOT NULL,
    own integer NOT NULL,
    nr integer NOT NULL,
    qtt_requ bigint,
    np integer NOT NULL,
    qtt_prov bigint,
    qtt_in bigint,
    qtt_out bigint,
    flows yflow[],
    created timestamp without time zone NOT NULL,
    removed timestamp without time zone
);


ALTER TABLE public.tquote OWNER TO olivier;

--
-- Name: fgetquote(text, text, bigint, bigint, text); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fgetquote(_owner text, _qualityprovided text, _qttprovided bigint, _qttrequired bigint, _qualityrequired text) RETURNS tquote
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
	
DECLARE
	_pivot 		 torder%rowtype;
	_ypatmax	 yflow;
	_flows		 yflow[];
	_res	         int8[];
	_cumul		 int8[];
	_qtt_prov	 int8;
	_qtt_requ	 int8;
	_idd		 int;
	_q		 text[];
	_ret		 tquote%rowtype;
	_r		 tquote%rowtype;
BEGIN
	_idd := fverifyquota();
	
	-- quantities must be >0
	IF(_qttprovided<=0 OR _qttrequired<0) THEN
		RAISE NOTICE 'quantities incorrect: %<=0 or %<0', _qttprovided,_qttrequired;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	_q := fexplodequality(_qualityprovided);
	IF ((_q[1] IS NOT NULL) AND (_q[1] != session_user)) THEN
		RAISE NOTICE 'depository % of quality is not the user %',_q[1],session_user;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	-- qualities are red and inserted if necessary
	_pivot.np := fgetquality(_qualityprovided,true); 
	_pivot.nr := fgetquality(_qualityrequired,true); 
	_pivot.id  := 0; 
	
	-- if does not exists, inserted
	_pivot.own := fgetowner(_owner,true); 
	 
	_pivot.qtt_requ := _qttrequired; -- if _qttrequired==0 then lastignore == true
	_pivot.qtt_prov := _qttprovided; 
	_pivot.qtt := _qttprovided;
	
	_r.id 		:= 0;
	_r.own 		:= _pivot.own;
	_r.flows 	:= ARRAY[]::yflow[];
	_r.nr 		:= _pivot.nr;
	_r.qtt_requ 	:= _pivot.qtt_requ;
	_r.np 		:= _pivot.np;
	_r.qtt_prov 	:= _pivot.qtt_prov;
	
	_cumul[1] := 0; -- in
	_cumul[2] := 0; -- out
	FOR _ypatmax IN SELECT _patmax  FROM finsertflows(_pivot) LOOP
		_r.flows := array_append(_r.flows,_ypatmax);
		_res := yflow_qtts(_ypatmax); -- [in,out] of the last node
		IF(_qttrequired = 0) THEN
			_cumul := yorder_moyen(_cumul[1],_cumul[2],_res[1],_res[2]);
		ELSE
			_cumul[1] := _cumul[1]+_res[1];
			_cumul[2] := _cumul[2]+_res[2];
		END IF;
	END LOOP;
	_r.qtt_in  := _cumul[1];
	_r.qtt_out := _cumul[2];
	
	IF (_qttrequired != 0 AND _r.qtt_out != 0 AND _r.qtt_in != 0) THEN
		INSERT INTO tquote (own,nr,qtt_requ,np,qtt_prov,qtt_in,qtt_out,flows,created,removed) 
			VALUES (_pivot.own,_r.nr,_r.qtt_requ,_r.np,_r.qtt_prov,_r.qtt_in,_r.qtt_out,_r.flows,statement_timestamp(),NULL)
		RETURNING * INTO _ret;
		RETURN _ret;
	ELSE
		RETURN _r;
	END IF;
END; 
$$;


ALTER FUNCTION public.fgetquote(_owner text, _qualityprovided text, _qttprovided bigint, _qttrequired bigint, _qualityrequired text) OWNER TO olivier;

--
-- Name: fgetstats(boolean); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fgetstats(_details boolean) RETURNS TABLE(_name text, cnt bigint)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


ALTER FUNCTION public.fgetstats(_details boolean) OWNER TO olivier;

--
-- Name: fgetuuid(integer); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fgetuuid(_id integer) RETURNS text
    LANGUAGE plpgsql
    AS $$ 
DECLARE
	_market_session	int;
BEGIN
	SELECT market_session INTO _market_session FROM vmarket;
	-- RETURN lpad(_market_session::text,19,'0') || '-' || lpad(_id::text,19,'0');
	RETURN _market_session::text || '-' || _id::text;
END;
$$;


ALTER FUNCTION public.fgetuuid(_id integer) OWNER TO olivier;

--
-- Name: torder; Type: TABLE; Schema: public; Owner: olivier; Tablespace: 
--

CREATE TABLE torder (
    id integer NOT NULL,
    uuid text NOT NULL,
    own integer NOT NULL,
    nr integer NOT NULL,
    qtt_requ bigint NOT NULL,
    np integer NOT NULL,
    qtt_prov dquantity NOT NULL,
    qtt bigint NOT NULL,
    start bigint,
    created timestamp without time zone NOT NULL,
    updated timestamp without time zone,
    CONSTRAINT torder_check CHECK ((((qtt >= 0) AND ((qtt_prov)::bigint >= qtt)) AND (qtt_requ >= 0)))
);


ALTER TABLE public.torder OWNER TO olivier;

--
-- Name: TABLE torder; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON TABLE torder IS 'description of orders';


--
-- Name: COLUMN torder.id; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN torder.id IS 'unique id for the session of the market';


--
-- Name: COLUMN torder.uuid; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN torder.uuid IS 'unique id for all sessions';


--
-- Name: COLUMN torder.own; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN torder.own IS 'owner of the value provided';


--
-- Name: COLUMN torder.nr; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN torder.nr IS 'quality required';


--
-- Name: COLUMN torder.qtt_requ; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN torder.qtt_requ IS 'quantity required; used to express omega=qtt_prov/qtt_req';


--
-- Name: COLUMN torder.np; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN torder.np IS 'quality provided';


--
-- Name: COLUMN torder.qtt_prov; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN torder.qtt_prov IS 'quantity offered';


--
-- Name: COLUMN torder.qtt; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN torder.qtt IS 'current quantity remaining (<= quantity offered)';


--
-- Name: COLUMN torder.start; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN torder.start IS 'position of treltried[np,nr].cnt when the order is inserted';


--
-- Name: finsert_toint(bigint, integer, integer, bigint, bigint); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION finsert_toint(_qtt_prov bigint, _nr integer, _np integer, _qtt_requ bigint, _own bigint) RETURNS torder
    LANGUAGE plpgsql
    AS $$
DECLARE
	_o		 torder%rowtype;
	_id		 int;
	_uuid		 text;
	_start		 int8;
BEGIN
		
	perform fupdate_quality(_np,_qtt_prov);	
		
	INSERT INTO torder (uuid,qtt,nr,np,qtt_prov,qtt_requ,own,created,updated) 
		VALUES ('',_qtt_prov,_nr,_np,_qtt_prov,_qtt_requ,_own,statement_timestamp(),NULL)
		RETURNING id INTO _id;
	
	_uuid := fgetuuid(_id);
	_start := fget_treltried(_np,_nr);
	
	UPDATE torder SET uuid = _uuid,start = _start WHERE id=_id RETURNING * INTO _o;	
	
	RETURN _o;					
END;
$$;


ALTER FUNCTION public.finsert_toint(_qtt_prov bigint, _nr integer, _np integer, _qtt_requ bigint, _own bigint) OWNER TO olivier;

--
-- Name: finsertflows(torder); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION finsertflows(_pivot torder) RETURNS TABLE(_patmax yflow)
    LANGUAGE plpgsql
    AS $$
DECLARE

	_idpivot 	int;
	_cnt 		int;
	_o		torder%rowtype;
	_res	        int8[];
	_start		int8;
	_time_begin	timestamp;
BEGIN
	------------------------------------------------------------------------
	-- _pivot.qtt := _pivot.qtt_prov;
	_time_begin := clock_timestamp();
	
	_cnt := fcreate_tmp(_pivot.id,
			yorder_get(_pivot.id,_pivot.own,_pivot.nr,_pivot.qtt_requ,_pivot.np,_pivot.qtt_prov,_pivot.qtt),
			_pivot.np,_pivot.nr);

	IF(_cnt=0) THEN
		RETURN;
	END IF;
	_cnt := 0;
	
	LOOP		
		SELECT yflow_max(pat) INTO _patmax FROM _tmp  ;
		
		IF (yflow_status(_patmax)!=3) THEN -- status != draft
			EXIT; -- from LOOP
		END IF;
		_cnt := _cnt + 1;
		
		RETURN NEXT;

		UPDATE _tmp SET pat = yflow_reduce(pat,_patmax);
	END LOOP;
	
	DROP TABLE _tmp;
	
	perform fspendquota(_time_begin);
	
 	RETURN;
END; 
$$;


ALTER FUNCTION public.finsertflows(_pivot torder) OWNER TO olivier;

--
-- Name: finsertorder(text, text, bigint, bigint, text); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION finsertorder(_owner text, _qualityprovided text, _qttprovided bigint, _qttrequired bigint, _qualityrequired text) RETURNS yresorder
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
	
DECLARE
	_wid		int;
	_o		torder%rowtype;
	_idd		int;
	-- _expected	tquote%rowtype;
	_q		tquote%rowtype;
	_ro		yresorder%rowTYPE;
	-- _pivot		torder%rowtype;
	_qua		text[];

	_flows		yflow[];
	_ypatmax	yflow;
	_res	        int8[];
	_first_mvt	int;
BEGIN
	--lock table torder in share row exclusive mode;
	lock table torder in share update exclusive mode;
	_idd := fverifyquota();
	_q.own := fgetowner(_owner,true); -- inserted if not found
	
	-- quantities must be >0
	IF(_qttprovided<=0 OR _qttrequired<=0) THEN
		RAISE NOTICE 'quantities incorrect: %<=0 or %<=0', _qttprovided,_qttrequired;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	_qua := fexplodequality(_qualityprovided);
	IF ((_qua[1] IS NOT NULL) AND (_qua[1] != session_user)) THEN
		RAISE NOTICE 'depository % of quality is not the user %',_qua[1],session_user;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	-- qualities are red and inserted if necessary
	_q.np := fgetquality(_qualityprovided,true); 
	_q.nr := fgetquality(_qualityrequired,true); 
	-- _q.qtt_requ != 0
		
	_q.qtt_requ := _qttrequired;
	_q.qtt_prov := _qttprovided;
	
	_o := finsert_toint(_qttprovided,_q.nr,_q.np,_qttrequired,_q.own);
	
	_ro.id      	:= _o.id;
	_ro.uuid    	:= _o.uuid;
	_ro.own     	:= _q.own;
	_ro.nr      	:= _q.nr;
	_ro.qtt_requ	:= _q.qtt_requ;
	_ro.np      	:= _q.np;
	_ro.qtt_prov	:= _q.qtt_prov;
	_ro.qtt_in  	:= 0;
	_ro.qtt_out 	:= 0;
	_ro.flows   	:= ARRAY[]::yflow[];
	
	FOR _ypatmax IN SELECT _patmax  FROM finsertflows(_o) LOOP
		_first_mvt := fexecute_flow(_ypatmax);
		_res := yflow_qtts(_ypatmax);
		_ro.qtt_in  := _ro.qtt_in  + _res[1];
		_ro.qtt_out := _ro.qtt_out + _res[2];
		_ro.flows := array_append(_ro.flows,_ypatmax);
	END LOOP;
	
	
	IF (	(_ro.qtt_in != 0) AND 
		((_ro.qtt_out::double precision)	/(_ro.qtt_in::double precision)) > 
		((_qttprovided::double precision)	/(_qttrequired::double precision))
	) THEN
		RAISE NOTICE 'Omega of the flows obtained is not limited by the order';
		RAISE EXCEPTION USING ERRCODE='YA003';
	END IF;
		
	PERFORM finvalidate_treltried();
	
	RETURN _ro;


END; 
$$;


ALTER FUNCTION public.finsertorder(_owner text, _qualityprovided text, _qttprovided bigint, _qttrequired bigint, _qualityrequired text) OWNER TO olivier;

--
-- Name: finvalidate_treltried(); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION finvalidate_treltried() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE 
	_o 	torder%rowtype;
	_MAXTRY int := fgetconst('MAXTRY');
	_res	int;
	_mvt_id	int;
	_uuid   text;
BEGIN
	IF(_MAXTRY=0) THEN
		RETURN;
	END IF;
	
	FOR _o IN SELECT o.* FROM torder o,treltried r 
		WHERE o.np=r.np AND o.nr=r.nr AND o.start IS NOT NULL AND o.start + _MAXTRY < r.cnt LOOP
		
		INSERT INTO tmvt (uuid,nb,oruuid,grp,own_src,own_dst,qtt,nat,created) 
			VALUES('',1,_o.uuid,NULL,_o.own,_o.own,_o.qtt,_o.np,statement_timestamp()) 
			RETURNING id INTO _mvt_id;
		_uuid := fgetuuid(_mvt_id);
		UPDATE tmvt SET uuid = _uuid WHERE id=_mvt_id;
			
		-- the order order.qtt != 0
		perform fremoveorder_int(_o.id);			
	END LOOP;
	RETURN;
END;
$$;


ALTER FUNCTION public.finvalidate_treltried() OWNER TO olivier;

--
-- Name: fremovemvt(text); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fremovemvt(_uuid text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE 
	_qtt int8;
	_qlt tquality%rowtype;
	_mvt tmvt%rowtype;
	_CHECK_QUALITY_OWNERSHIP int := fgetconst('CHECK_QUALITY_OWNERSHIP');
BEGIN

	SELECT m.* INTO _mvt FROM tmvt m WHERE m.uuid=_uuid;
	IF NOT FOUND THEN
		RAISE WARNING 'The movement "%" does not exist',_uuid;
		RETURN 0;
	END IF;
	
	SELECT q.* INTO _qlt FROM tquality q WHERE q.id=_mvt.nat AND 
		((q.depository=session_user) OR (_CHECK_QUALITY_OWNERSHIP = 0)); 
	IF NOT FOUND THEN
		RAISE WARNING 'The movement "%" does not belong to the user "%""',_uuid,session_user;
		RETURN 0;
	END IF;
	
	UPDATE tquality SET qtt = qtt - _mvt.qtt WHERE id = _mvt.nat RETURNING qtt INTO _qtt;
	
	WITH a AS (DELETE FROM tmvt m  WHERE  m.uuid=_uuid RETURNING m.*) 
	INSERT INTO tmvtremoved SELECT id,uuid,nb,oruuid,grp,own_src,own_dst,qtt,nat,created,statement_timestamp() as deleted FROM a;	

	RETURN 1;

END;
$$;


ALTER FUNCTION public.fremovemvt(_uuid text) OWNER TO olivier;

--
-- Name: towner; Type: TABLE; Schema: public; Owner: olivier; Tablespace: 
--

CREATE TABLE towner (
    id integer NOT NULL,
    name text NOT NULL,
    created timestamp without time zone,
    updated timestamp without time zone,
    CONSTRAINT towner_name_check CHECK ((char_length(name) > 0))
);


ALTER TABLE public.towner OWNER TO olivier;

--
-- Name: TABLE towner; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON TABLE towner IS 'owners of values exchanged';


--
-- Name: tquality; Type: TABLE; Schema: public; Owner: olivier; Tablespace: 
--

CREATE TABLE tquality (
    id integer NOT NULL,
    name text NOT NULL,
    idd integer,
    depository text,
    qtt bigint DEFAULT 0,
    created timestamp without time zone,
    updated timestamp without time zone,
    CONSTRAINT tquality_check CHECK ((((char_length(name) > 0) AND (char_length(depository) > 0)) AND (qtt >= 0)))
);


ALTER TABLE public.tquality OWNER TO olivier;

--
-- Name: TABLE tquality; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON TABLE tquality IS 'description of qualities';


--
-- Name: COLUMN tquality.name; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN tquality.name IS 'name of depository/name of quality ';


--
-- Name: COLUMN tquality.idd; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN tquality.idd IS 'id of the depository';


--
-- Name: COLUMN tquality.depository; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN tquality.depository IS 'name of depository (user)';


--
-- Name: COLUMN tquality.qtt; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN tquality.qtt IS 'total quantity on the market for this quality';


--
-- Name: vorder; Type: VIEW; Schema: public; Owner: olivier
--

CREATE VIEW vorder AS
    SELECT n.id, n.uuid, w.name AS owner, qr.name AS qua_requ, n.qtt_requ, qp.name AS qua_prov, n.qtt_prov, n.qtt, n.start, n.created, n.updated FROM (((torder n JOIN tquality qr ON ((n.nr = qr.id))) JOIN tquality qp ON ((n.np = qp.id))) JOIN towner w ON ((n.own = w.id)));


ALTER TABLE public.vorder OWNER TO olivier;

--
-- Name: fremoveorder(text); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fremoveorder(_uuid text) RETURNS vorder
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
	_qtt		int8;
	_o 		torder%rowtype;
	_vo		vorder%rowtype;
	_qlt		tquality%rowtype;
	_CHECK_QUALITY_OWNERSHIP int := fgetconst('CHECK_QUALITY_OWNERSHIP');
BEGIN
	_vo.id = NULL;
	IF(_CHECK_QUALITY_OWNERSHIP != 0) THEN
		SELECT o.* INTO _o FROM torder o,tquality q 
			WHERE 	o.np=q.id AND q.depository=session_user AND o.uuid = _uuid;
		IF NOT FOUND THEN
			RAISE WARNING 'the order % on a quality belonging to % was not found',_uuid,session_user;
			RAISE EXCEPTION USING ERRCODE='YU001';
		END IF;
	ELSE
		SELECT o.* INTO _o FROM torder o WHERE o.uuid = _uuid;
		IF NOT FOUND THEN
			RAISE WARNING 'the order % was not found',_uuid;
			RAISE EXCEPTION USING ERRCODE='YU001';
		END IF;
	END IF;

	SELECT * INTO _vo FROM vorder WHERE id = _o.id;	-- _vo returned
	
		
	UPDATE tquality SET qtt = qtt - _o.qtt WHERE id = _o.np RETURNING qtt INTO _qlt;
	-- check tquality.qtt >=0	
	-- order is removed but is NOT cleared
	perform fremoveorder_int(_o.id);
	
	RETURN _vo;
	
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE NOTICE 'ABORTED';
	RETURN _vo; 
END;		
$$;


ALTER FUNCTION public.fremoveorder(_uuid text) OWNER TO olivier;

--
-- Name: fremoveorder_int(integer); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fremoveorder_int(_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN		
	WITH a AS (DELETE FROM torder o WHERE o.id=_id RETURNING *) 
	INSERT INTO torderremoved 
		SELECT id,uuid,own,nr,qtt_requ,np,qtt_prov,qtt,start,created,statement_timestamp() 
	FROM a;					
END;
$$;


ALTER FUNCTION public.fremoveorder_int(_id integer) OWNER TO olivier;

--
-- Name: fremovequote_int(integer); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fremovequote_int(_idquote integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN		
	WITH a AS (DELETE FROM tquote o WHERE o.id=_idquote RETURNING *) 
	INSERT INTO tquoteremoved 
		SELECT id,own,nr,qtt_requ,np,qtt_prov,qtt_in,qtt_out,flows,created,statement_timestamp() 
	FROM a;					
END;
$$;


ALTER FUNCTION public.fremovequote_int(_idquote integer) OWNER TO olivier;

--
-- Name: frenumbertables(boolean); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION frenumbertables(exec boolean) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
	_cnt int;
	_id int;
	_res bool;
BEGIN
	
	_res := true;
		
	IF NOT exec THEN
		RETURN _res;
	END IF;
	
	--TODO lier les id des *removed
	
	-- desable triggers
	ALTER TABLE towner DISABLE TRIGGER ALL;
	ALTER TABLE tquality DISABLE TRIGGER ALL;
	ALTER TABLE tuser DISABLE TRIGGER ALL;
	
	-- DROP CONSTRAINT ON UPDATE CASCADE on tables tquality,torder,tmvt
    ALTER TABLE tquality 
		DROP CONSTRAINT ctquality_idd,
		ADD CONSTRAINT ctquality_idd FOREIGN KEY (idd) references tuser(id) 
		ON UPDATE CASCADE;

	ALTER TABLE tquality 
		DROP CONSTRAINT ctquality_depository,
		ADD CONSTRAINT ctquality_depository FOREIGN KEY (depository) references tuser(name) 
		ON UPDATE RESTRICT;  -- must not be changed
	  			
	ALTER TABLE torder 
		DROP CONSTRAINT ctorder_own,
		ADD CONSTRAINT ctorder_own 	FOREIGN KEY (own) references towner(id) ON UPDATE CASCADE ON DELETE RESTRICT;

	ALTER TABLE torder 
		DROP CONSTRAINT ctorder_np,
		ADD CONSTRAINT ctorder_np 	FOREIGN KEY (np) references tquality(id) ON UPDATE CASCADE ON DELETE RESTRICT;

	ALTER TABLE torder 
		DROP CONSTRAINT ctorder_nr,
		ADD CONSTRAINT ctorder_nr 	FOREIGN KEY (nr) references tquality(id) ON UPDATE CASCADE ON DELETE RESTRICT;
/*
	ALTER TABLE tmvt 
		DROP CONSTRAINT ctmvt_grp,
		ADD CONSTRAINT ctmvt_grp 	FOREIGN KEY (grp) references tmvt(id) 
		ON UPDATE CASCADE;
*/
	ALTER TABLE tmvt 
		DROP CONSTRAINT ctmvt_own_src,
		ADD CONSTRAINT ctmvt_own_src 	FOREIGN KEY (own_src) references towner(id) ON UPDATE CASCADE ON DELETE RESTRICT;

	ALTER TABLE tmvt 
		DROP CONSTRAINT ctmvt_own_dst,
		ADD CONSTRAINT ctmvt_own_dst 	FOREIGN KEY (own_dst) references towner(id) ON UPDATE CASCADE ON DELETE RESTRICT;

	ALTER TABLE tmvt 
		DROP CONSTRAINT ctmvt_nat,
		ADD CONSTRAINT ctmvt_nat 	FOREIGN KEY (nat) references tquality(id) ON UPDATE CASCADE ON DELETE RESTRICT;

	-- tquote truncated
	TRUNCATE tquote;
	PERFORM setval('tquote_id_seq',1,false);
/*	
	TRUNCATE tmvt;
	PERFORM setval('tmvt_id_seq',1,false);
*/
	-- remove unused qualities
	DELETE FROM tquality q WHERE q.id NOT IN (SELECT np FROM torder UNION SELECT np FROM torderremoved )	
				AND	q.id NOT IN (SELECT nr FROM torder UNION SELECT nr FROM torderremoved )
				AND q.id NOT IN (SELECT nat FROM tmvt UNION SELECT nat FROM tmvtremoved );
	
	-- renumbering qualities
	PERFORM setval('tquality_id_seq',1,false);
	FOR _id IN SELECT * FROM tquality ORDER BY id ASC LOOP
		UPDATE tquality SET id = nextval('tquality_id_seq') WHERE a.id = tquality.id;
	END LOOP;
/*
	WITH a AS (SELECT * FROM tquality ORDER BY id ASC)
	UPDATE tquality SET id = nextval('tquality_id_seq') FROM a WHERE a.id = tquality.id;
*/
/*	
	-- remove unused users
	DELETE FROM tuser o WHERE o.id NOT IN (SELECT idd FROM tquality);
	
	-- renumbering users
	PERFORM setval('tuser_id_seq',1,false);
	WITH a AS (SELECT * FROM tuser ORDER BY id ASC)
	UPDATE tuser SET id = nextval('tuser_id_seq') FROM a WHERE a.id = tuser.id;
*/	
	-- resetting quotas
	UPDATE tuser SET spent = 0;
	-- remove quotas of unused qualities
	DELETE FROM treltried r WHERE np NOT IN (SELECT id FROM tquality) OR nr NOT IN (SELECT id FROM tquality);
		
	-- renumbering orders
	PERFORM setval('torder_id_seq',1,false);
	FOR _id IN SELECT * FROM torder ORDER BY id ASC LOOP
		UPDATE torder SET id = nextval('torder_id_seq') WHERE a.id = torder.id;
	END LOOP;
	
	-- renumbering movements
	PERFORM setval('tmvt_id_seq',1,false);
	FOR _id IN SELECT * FROM tmvt ORDER BY id ASC LOOP
		UPDATE tmvt SET id = nextval('tmvt_id_seq') WHERE a.id = tmvt.id;
	END LOOP;

/*		
	TRUNCATE torderremoved; -- does not reset associated sequence if any
	TRUNCATE tmvtremoved;
	TRUNCATE tquoteremoved;
*/
	
	-- reset of constraints
    ALTER TABLE tquality 
		DROP CONSTRAINT ctquality_idd,
		ADD CONSTRAINT ctquality_idd 	FOREIGN KEY (idd) references tuser(id);

    	ALTER TABLE tquality 
		DROP CONSTRAINT ctquality_depository,
		ADD CONSTRAINT ctquality_depository FOREIGN KEY (depository) references tuser(name);
    		
	ALTER TABLE torder 
		DROP CONSTRAINT ctorder_own,
		ADD CONSTRAINT ctorder_own 	FOREIGN KEY (own) references towner(id);

	ALTER TABLE torder 
		DROP CONSTRAINT ctorder_np,
		ADD CONSTRAINT ctorder_np 	FOREIGN KEY (np) references tquality(id);

	ALTER TABLE torder 
		DROP CONSTRAINT ctorder_nr,
		ADD CONSTRAINT ctorder_nr 	FOREIGN KEY (nr) references tquality(id);
/*
	ALTER TABLE tmvt 
		DROP CONSTRAINT ctmvt_grp,
		ADD CONSTRAINT ctmvt_grp 	FOREIGN KEY (grp) references tmvt(id);
*/
	ALTER TABLE tmvt 
		DROP CONSTRAINT ctmvt_own_src,
		ADD CONSTRAINT ctmvt_own_src 	FOREIGN KEY (own_src) references towner(id);

	ALTER TABLE tmvt 
		DROP CONSTRAINT ctmvt_own_dst,
		ADD CONSTRAINT ctmvt_own_dst 	FOREIGN KEY (own_dst) references towner(id);

	ALTER TABLE tmvt 
		DROP CONSTRAINT ctmvt_nat,
		ADD CONSTRAINT ctmvt_nat 	FOREIGN KEY (nat) references tquality(id);
	
	-- enable triggers
	ALTER TABLE towner ENABLE TRIGGER ALL;
	ALTER TABLE tquality ENABLE TRIGGER ALL;
	ALTER TABLE tuser ENABLE TRIGGER ALL;

	RETURN true;
	 
END;
$$;


ALTER FUNCTION public.frenumbertables(exec boolean) OWNER TO olivier;

--
-- Name: fspendquota(timestamp without time zone); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fspendquota(_time_begin timestamp without time zone) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE 
	_t2	timestamp;
BEGIN
	_t2 := clock_timestamp();
	UPDATE tuser SET spent = spent + extract (microseconds from (_t2-_time_begin)) WHERE name = session_user;
	RETURN true;
END;		
$$;


ALTER FUNCTION public.fspendquota(_time_begin timestamp without time zone) OWNER TO olivier;

--
-- Name: ftime_updated(); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION ftime_updated() RETURNS trigger
    LANGUAGE plpgsql
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


ALTER FUNCTION public.ftime_updated() OWNER TO olivier;

--
-- Name: FUNCTION ftime_updated(); Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON FUNCTION ftime_updated() IS 'trigger updating fields created and updated';


--
-- Name: fupdate_quality(integer, bigint); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fupdate_quality(_qid integer, _qtt bigint) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE 
	_qp tquality%rowtype;
	_q text[];
	_id int;
	_qtta int8;
BEGIN

	UPDATE tquality SET qtt = qtt + _qtt 
		WHERE id = _qid RETURNING qtt INTO _qtta;

	IF NOT FOUND THEN
		RAISE EXCEPTION USING ERRCODE='YA004';
	END IF;	
		
	IF (_qtt > 0)   THEN 
		IF (_qtta < _qtt) THEN 
			RAISE WARNING 'Quality "%" owerflows',_quality_name;
			RAISE EXCEPTION USING ERRCODE='YA004';
		END IF; 
	ELSIF (_qtt < 0) THEN
		IF (_qtta > _qtt) THEN 
			RAISE WARNING 'Quality "%" underflows',_quality_name;
			RAISE EXCEPTION USING ERRCODE='YA004';
		END IF;			
	END IF;
	
	RETURN;
END;
$$;


ALTER FUNCTION public.fupdate_quality(_qid integer, _qtt bigint) OWNER TO olivier;

--
-- Name: fupdate_treltried(bigint[], integer); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fupdate_treltried(_commits bigint[], _nbcommit integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.fupdate_treltried(_commits bigint[], _nbcommit integer) OWNER TO olivier;

--
-- Name: fverifmvt(); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fverifmvt() RETURNS integer
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.fverifmvt() OWNER TO olivier;

--
-- Name: fverifmvt2(); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fverifmvt2() RETURNS integer
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.fverifmvt2() OWNER TO olivier;

--
-- Name: tmvt; Type: TABLE; Schema: public; Owner: olivier; Tablespace: 
--

CREATE TABLE tmvt (
    id integer NOT NULL,
    uuid text NOT NULL,
    nb integer NOT NULL,
    oruuid text NOT NULL,
    grp text,
    own_src integer NOT NULL,
    own_dst integer NOT NULL,
    qtt dquantity NOT NULL,
    nat integer NOT NULL,
    created timestamp without time zone NOT NULL,
    CONSTRAINT tmvt_check CHECK ((((nb = 1) AND (own_src = own_dst)) OR (nb <> 1)))
);


ALTER TABLE public.tmvt OWNER TO olivier;

--
-- Name: TABLE tmvt; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON TABLE tmvt IS 'records a change of ownership';


--
-- Name: COLUMN tmvt.uuid; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN tmvt.uuid IS 'uuid of this movement';


--
-- Name: COLUMN tmvt.nb; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN tmvt.nb IS 'number of movements of the exchange';


--
-- Name: COLUMN tmvt.oruuid; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN tmvt.oruuid IS 'order.uuid producing this movement';


--
-- Name: COLUMN tmvt.grp; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN tmvt.grp IS 'references the first movement of the exchange';


--
-- Name: COLUMN tmvt.own_src; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN tmvt.own_src IS 'owner provider';


--
-- Name: COLUMN tmvt.own_dst; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN tmvt.own_dst IS 'owner receiver';


--
-- Name: COLUMN tmvt.qtt; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN tmvt.qtt IS 'quantity of the value moved';


--
-- Name: COLUMN tmvt.nat; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN tmvt.nat IS 'quality of the value moved';


--
-- Name: fverifmvt2_int(tmvt, tmvt); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fverifmvt2_int(_mvtprec tmvt, _mvt tmvt) RETURNS integer
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.fverifmvt2_int(_mvtprec tmvt, _mvt tmvt) OWNER TO olivier;

--
-- Name: fverifyquota(); Type: FUNCTION; Schema: public; Owner: olivier
--

CREATE FUNCTION fverifyquota() RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE 
	_u	tuser%rowtype;
BEGIN
	SELECT * INTO _u FROM tuser WHERE name=session_user;
	IF(_u.id is NULL) THEN
		RAISE WARNING 'the user % is undefined',session_user;
		RAISE EXCEPTION USING ERRCODE='YA005';
	END IF;
	UPDATE tuser SET last_in = statement_timestamp() WHERE name = session_user;
	IF(_u.quota = 0 ) THEN
		RETURN _u.id;
	END IF;

	IF(_u.quota < _u.spent) THEN
		RAISE WARNING 'the quota is reached for the user %',session_user;
		RAISE EXCEPTION USING ERRCODE='YU003';
	END IF;
	RETURN _u.id;

END;		
$$;


ALTER FUNCTION public.fverifyquota() OWNER TO olivier;

--
-- Name: tconst; Type: TABLE; Schema: public; Owner: olivier; Tablespace: 
--

CREATE TABLE tconst (
    name text NOT NULL,
    value integer
);


ALTER TABLE public.tconst OWNER TO olivier;

--
-- Name: tmarket; Type: TABLE; Schema: public; Owner: olivier; Tablespace: 
--

CREATE TABLE tmarket (
    id integer NOT NULL,
    created timestamp without time zone NOT NULL
);


ALTER TABLE public.tmarket OWNER TO olivier;

--
-- Name: tmarket_id_seq; Type: SEQUENCE; Schema: public; Owner: olivier
--

CREATE SEQUENCE tmarket_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tmarket_id_seq OWNER TO olivier;

--
-- Name: tmarket_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: olivier
--

ALTER SEQUENCE tmarket_id_seq OWNED BY tmarket.id;


--
-- Name: tmarket_id_seq; Type: SEQUENCE SET; Schema: public; Owner: olivier
--

SELECT pg_catalog.setval('tmarket_id_seq', 1, true);


--
-- Name: tmvt_id_seq; Type: SEQUENCE; Schema: public; Owner: olivier
--

CREATE SEQUENCE tmvt_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tmvt_id_seq OWNER TO olivier;

--
-- Name: tmvt_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: olivier
--

ALTER SEQUENCE tmvt_id_seq OWNED BY tmvt.id;


--
-- Name: tmvt_id_seq; Type: SEQUENCE SET; Schema: public; Owner: olivier
--

SELECT pg_catalog.setval('tmvt_id_seq', 282, true);


--
-- Name: tmvtremoved; Type: TABLE; Schema: public; Owner: olivier; Tablespace: 
--

CREATE TABLE tmvtremoved (
    id integer NOT NULL,
    uuid text NOT NULL,
    nb integer NOT NULL,
    oruuid text NOT NULL,
    grp text NOT NULL,
    own_src integer NOT NULL,
    own_dst integer NOT NULL,
    qtt dquantity NOT NULL,
    nat integer NOT NULL,
    created timestamp without time zone NOT NULL,
    deleted timestamp without time zone NOT NULL
);


ALTER TABLE public.tmvtremoved OWNER TO olivier;

--
-- Name: torder_id_seq; Type: SEQUENCE; Schema: public; Owner: olivier
--

CREATE SEQUENCE torder_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.torder_id_seq OWNER TO olivier;

--
-- Name: torder_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: olivier
--

ALTER SEQUENCE torder_id_seq OWNED BY torder.id;


--
-- Name: torder_id_seq; Type: SEQUENCE SET; Schema: public; Owner: olivier
--

SELECT pg_catalog.setval('torder_id_seq', 300, true);


--
-- Name: torderremoved; Type: TABLE; Schema: public; Owner: olivier; Tablespace: 
--

CREATE TABLE torderremoved (
    id integer NOT NULL,
    uuid text NOT NULL,
    own integer NOT NULL,
    nr integer NOT NULL,
    qtt_requ dquantity NOT NULL,
    np integer NOT NULL,
    qtt_prov dquantity NOT NULL,
    qtt bigint NOT NULL,
    start bigint,
    created timestamp without time zone NOT NULL,
    updated timestamp without time zone
);


ALTER TABLE public.torderremoved OWNER TO olivier;

--
-- Name: towner_id_seq; Type: SEQUENCE; Schema: public; Owner: olivier
--

CREATE SEQUENCE towner_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.towner_id_seq OWNER TO olivier;

--
-- Name: towner_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: olivier
--

ALTER SEQUENCE towner_id_seq OWNED BY towner.id;


--
-- Name: towner_id_seq; Type: SEQUENCE SET; Schema: public; Owner: olivier
--

SELECT pg_catalog.setval('towner_id_seq', 97, true);


--
-- Name: tquality_id_seq; Type: SEQUENCE; Schema: public; Owner: olivier
--

CREATE SEQUENCE tquality_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tquality_id_seq OWNER TO olivier;

--
-- Name: tquality_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: olivier
--

ALTER SEQUENCE tquality_id_seq OWNED BY tquality.id;


--
-- Name: tquality_id_seq; Type: SEQUENCE SET; Schema: public; Owner: olivier
--

SELECT pg_catalog.setval('tquality_id_seq', 98, true);


--
-- Name: tquote_id_seq; Type: SEQUENCE; Schema: public; Owner: olivier
--

CREATE SEQUENCE tquote_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tquote_id_seq OWNER TO olivier;

--
-- Name: tquote_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: olivier
--

ALTER SEQUENCE tquote_id_seq OWNED BY tquote.id;


--
-- Name: tquote_id_seq; Type: SEQUENCE SET; Schema: public; Owner: olivier
--

SELECT pg_catalog.setval('tquote_id_seq', 1, false);


--
-- Name: tquoteremoved; Type: TABLE; Schema: public; Owner: olivier; Tablespace: 
--

CREATE TABLE tquoteremoved (
    id integer NOT NULL,
    own integer NOT NULL,
    nr integer NOT NULL,
    qtt_requ bigint,
    np integer NOT NULL,
    qtt_prov bigint,
    qtt_in bigint,
    qtt_out bigint,
    flows yflow[],
    created timestamp without time zone,
    removed timestamp without time zone
);


ALTER TABLE public.tquoteremoved OWNER TO olivier;

--
-- Name: treltried; Type: TABLE; Schema: public; Owner: olivier; Tablespace: 
--

CREATE TABLE treltried (
    np integer NOT NULL,
    nr integer NOT NULL,
    cnt bigint DEFAULT 0,
    CONSTRAINT treltried_check CHECK (((np <> nr) AND (cnt >= 0)))
);


ALTER TABLE public.treltried OWNER TO olivier;

--
-- Name: tuser; Type: TABLE; Schema: public; Owner: olivier; Tablespace: 
--

CREATE TABLE tuser (
    id integer NOT NULL,
    name text NOT NULL,
    spent bigint DEFAULT 0 NOT NULL,
    quota bigint DEFAULT 0 NOT NULL,
    last_in timestamp without time zone,
    created timestamp without time zone,
    updated timestamp without time zone,
    CONSTRAINT tuser_check CHECK ((((char_length(name) > 0) AND (spent >= 0)) AND (quota >= 0)))
);


ALTER TABLE public.tuser OWNER TO olivier;

--
-- Name: TABLE tuser; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON TABLE tuser IS 'users that have been connected';


--
-- Name: tuser_id_seq; Type: SEQUENCE; Schema: public; Owner: olivier
--

CREATE SEQUENCE tuser_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tuser_id_seq OWNER TO olivier;

--
-- Name: tuser_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: olivier
--

ALTER SEQUENCE tuser_id_seq OWNED BY tuser.id;


--
-- Name: tuser_id_seq; Type: SEQUENCE SET; Schema: public; Owner: olivier
--

SELECT pg_catalog.setval('tuser_id_seq', 10, true);


--
-- Name: vmarkethistory; Type: VIEW; Schema: public; Owner: olivier
--

CREATE VIEW vmarkethistory AS
    SELECT tmarket.id, ((tmarket.id + 4) / 4) AS market_session, CASE WHEN (((tmarket.id - 1) % 4) = 0) THEN 'OPENED'::ymarketstatus WHEN (((tmarket.id - 1) % 4) = 1) THEN 'STOPPING'::ymarketstatus WHEN (((tmarket.id - 1) % 4) = 2) THEN 'CLOSED'::ymarketstatus WHEN (((tmarket.id - 1) % 4) = 3) THEN 'STARTING'::ymarketstatus ELSE NULL::ymarketstatus END AS market_status, tmarket.created FROM tmarket;


ALTER TABLE public.vmarkethistory OWNER TO olivier;

--
-- Name: vmarket; Type: VIEW; Schema: public; Owner: olivier
--

CREATE VIEW vmarket AS
    SELECT vmarkethistory.id, vmarkethistory.market_session, vmarkethistory.market_status, vmarkethistory.created FROM vmarkethistory ORDER BY vmarkethistory.id DESC LIMIT 1;


ALTER TABLE public.vmarket OWNER TO olivier;

--
-- Name: vmvt; Type: VIEW; Schema: public; Owner: olivier
--

CREATE VIEW vmvt AS
    SELECT m.id, m.nb, m.uuid, m.oruuid, m.grp, w_src.name AS provider, q.name AS quality, m.qtt, w_dst.name AS receiver, m.created FROM (((tmvt m JOIN towner w_src ON ((m.own_src = w_src.id))) JOIN towner w_dst ON ((m.own_dst = w_dst.id))) JOIN tquality q ON ((m.nat = q.id)));


ALTER TABLE public.vmvt OWNER TO olivier;

--
-- Name: VIEW vmvt; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON VIEW vmvt IS 'List of movements';


--
-- Name: COLUMN vmvt.nb; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN vmvt.nb IS 'number of movements of the exchange';


--
-- Name: COLUMN vmvt.uuid; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN vmvt.uuid IS 'reference this movement';


--
-- Name: COLUMN vmvt.oruuid; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN vmvt.oruuid IS 'reference to the exchange';


--
-- Name: COLUMN vmvt.grp; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN vmvt.grp IS 'id of the first movement of the exchange';


--
-- Name: COLUMN vmvt.provider; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN vmvt.provider IS 'name of the provider of the movement';


--
-- Name: COLUMN vmvt.quality; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN vmvt.quality IS 'name of the quality moved';


--
-- Name: COLUMN vmvt.qtt; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN vmvt.qtt IS 'quantity moved';


--
-- Name: COLUMN vmvt.receiver; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN vmvt.receiver IS 'name of the receiver of the movement';


--
-- Name: COLUMN vmvt.created; Type: COMMENT; Schema: public; Owner: olivier
--

COMMENT ON COLUMN vmvt.created IS 'time of the transaction';


--
-- Name: vmvtverif; Type: VIEW; Schema: public; Owner: olivier
--

CREATE VIEW vmvtverif AS
    SELECT tmvt.id, tmvt.uuid, tmvt.nb, tmvt.oruuid, tmvt.grp, tmvt.own_src, tmvt.own_dst, tmvt.qtt, tmvt.nat, false AS removed FROM tmvt WHERE (tmvt.grp IS NOT NULL) UNION ALL SELECT tmvtremoved.id, tmvtremoved.uuid, tmvtremoved.nb, tmvtremoved.oruuid, tmvtremoved.grp, tmvtremoved.own_src, tmvtremoved.own_dst, tmvtremoved.qtt, tmvtremoved.nat, true AS removed FROM tmvtremoved WHERE (tmvtremoved.grp IS NOT NULL);


ALTER TABLE public.vmvtverif OWNER TO olivier;

--
-- Name: vorderinsert; Type: VIEW; Schema: public; Owner: olivier
--

CREATE VIEW vorderinsert AS
    SELECT torder.id, yorder_get(torder.id, torder.own, torder.nr, torder.qtt_requ, torder.np, (torder.qtt_prov)::bigint, torder.qtt) AS ord, torder.np, torder.nr FROM torder ORDER BY ((torder.qtt_prov)::double precision / (torder.qtt_requ)::double precision) DESC;


ALTER TABLE public.vorderinsert OWNER TO olivier;

--
-- Name: vorderremoved; Type: VIEW; Schema: public; Owner: olivier
--

CREATE VIEW vorderremoved AS
    SELECT n.id, n.uuid, w.name AS owner, qr.name AS qua_requ, n.qtt_requ, qp.name AS qua_prov, n.qtt_prov, n.qtt, n.created, n.updated FROM (((torderremoved n JOIN tquality qr ON ((n.nr = qr.id))) JOIN tquality qp ON ((n.np = qp.id))) JOIN towner w ON ((n.own = w.id)));


ALTER TABLE public.vorderremoved OWNER TO olivier;

--
-- Name: vorderverif; Type: VIEW; Schema: public; Owner: olivier
--

CREATE VIEW vorderverif AS
    SELECT torder.id, torder.uuid, torder.own, torder.nr, torder.qtt_requ, torder.np, torder.qtt_prov, torder.qtt, false AS removed FROM torder UNION SELECT torderremoved.id, torderremoved.uuid, torderremoved.own, torderremoved.nr, torderremoved.qtt_requ, torderremoved.np, torderremoved.qtt_prov, torderremoved.qtt, true AS removed FROM torderremoved;


ALTER TABLE public.vorderverif OWNER TO olivier;

--
-- Name: vstat; Type: TABLE; Schema: public; Owner: olivier; Tablespace: 
--

CREATE TABLE vstat (
    name text,
    delta numeric,
    qtt_quality bigint,
    qtt_detail numeric
);


ALTER TABLE public.vstat OWNER TO olivier;

--
-- Name: id; Type: DEFAULT; Schema: public; Owner: olivier
--

ALTER TABLE ONLY tmarket ALTER COLUMN id SET DEFAULT nextval('tmarket_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: olivier
--

ALTER TABLE ONLY tmvt ALTER COLUMN id SET DEFAULT nextval('tmvt_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: olivier
--

ALTER TABLE ONLY torder ALTER COLUMN id SET DEFAULT nextval('torder_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: olivier
--

ALTER TABLE ONLY towner ALTER COLUMN id SET DEFAULT nextval('towner_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: olivier
--

ALTER TABLE ONLY tquality ALTER COLUMN id SET DEFAULT nextval('tquality_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: olivier
--

ALTER TABLE ONLY tquote ALTER COLUMN id SET DEFAULT nextval('tquote_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: olivier
--

ALTER TABLE ONLY tuser ALTER COLUMN id SET DEFAULT nextval('tuser_id_seq'::regclass);


--
-- Data for Name: tconst; Type: TABLE DATA; Schema: public; Owner: olivier
--

COPY tconst (name, value) FROM stdin;
MAXCYCLE	8
VERSION-X.y.z	0
VERSION-x.Y.y	4
VERSION-x.y.Z	2
INSERT_OWN_UNKNOWN	1
MAXORDERFETCH	10000
MAXTRY	10
CHECK_QUALITY_OWNERSHIP	1
options.CHECKQUALITYOWNERSHIP	1
options.iteration	100
options.maxparams	0
options.reset	0
options.threads	3
options.verif	0
results.dureeSecs	5
results.nbOper	300
\.


--
-- Data for Name: tmarket; Type: TABLE DATA; Schema: public; Owner: olivier
--

COPY tmarket (id, created) FROM stdin;
1	2012-10-18 18:29:11.316753
\.


--
-- Data for Name: tmvt; Type: TABLE DATA; Schema: public; Owner: olivier
--

COPY tmvt (id, uuid, nb, oruuid, grp, own_src, own_dst, qtt, nat, created) FROM stdin;
1	1-1	5	1-122	1-1	7	21	2864	66	2012-10-18 18:29:33.453909
2	1-2	5	1-56	1-1	21	29	5000	70	2012-10-18 18:29:33.453909
3	1-3	5	1-106	1-1	29	55	1862	72	2012-10-18 18:29:33.453909
4	1-4	5	1-121	1-1	55	64	1225	64	2012-10-18 18:29:33.453909
5	1-5	5	1-107	1-1	64	7	3643	30	2012-10-18 18:29:33.453909
6	1-6	8	1-141	1-6	21	5	4997	10	2012-10-18 18:29:33.689515
7	1-7	8	1-5	1-6	5	14	5000	9	2012-10-18 18:29:33.689515
8	1-8	8	1-16	1-6	14	68	1679	29	2012-10-18 18:29:33.689515
9	1-9	8	1-119	1-6	68	53	1503	75	2012-10-18 18:29:33.689515
10	1-10	8	1-117	1-6	53	45	3188	32	2012-10-18 18:29:33.689515
11	1-11	8	1-96	1-6	45	33	1004	65	2012-10-18 18:29:33.689515
12	1-12	8	1-132	1-6	33	3	772	11	2012-10-18 18:29:33.689515
13	1-13	8	1-110	1-6	3	21	349	12	2012-10-18 18:29:33.689515
14	1-14	8	1-166	1-14	43	7	2098	8	2012-10-18 18:29:33.990101
15	1-15	8	1-25	1-14	7	22	5000	34	2012-10-18 18:29:33.990101
16	1-16	8	1-27	1-14	22	10	3582	19	2012-10-18 18:29:33.990101
17	1-17	8	1-10	1-14	10	2	2127	18	2012-10-18 18:29:33.990101
18	1-18	8	1-99	1-14	2	24	792	35	2012-10-18 18:29:33.990101
19	1-19	8	1-30	1-14	24	53	393	49	2012-10-18 18:29:33.990101
20	1-20	8	1-85	1-14	53	36	651	72	2012-10-18 18:29:33.990101
21	1-21	8	1-71	1-14	36	43	360	55	2012-10-18 18:29:33.990101
22	1-22	4	1-170	1-22	38	53	917	75	2012-10-18 18:29:34.056812
23	1-23	4	1-117	1-22	53	28	1812	32	2012-10-18 18:29:34.056812
24	1-24	4	1-165	1-22	28	71	3898	52	2012-10-18 18:29:34.056812
25	1-25	4	1-125	1-22	71	38	1821	41	2012-10-18 18:29:34.056812
26	1-26	8	1-173	1-26	9	43	334	69	2012-10-18 18:29:34.101452
27	1-27	8	1-55	1-26	43	14	419	39	2012-10-18 18:29:34.101452
28	1-28	8	1-33	1-26	14	47	5000	14	2012-10-18 18:29:34.101452
29	1-29	8	1-63	1-26	47	48	3304	68	2012-10-18 18:29:34.101452
30	1-30	8	1-67	1-26	48	2	1289	18	2012-10-18 18:29:34.101452
31	1-31	8	1-99	1-26	2	24	451	35	2012-10-18 18:29:34.101452
32	1-32	8	1-30	1-26	24	53	210	49	2012-10-18 18:29:34.101452
33	1-33	8	1-85	1-26	53	9	328	72	2012-10-18 18:29:34.101452
34	1-34	4	1-180	1-34	87	33	2094	65	2012-10-18 18:29:34.190539
35	1-35	4	1-132	1-34	33	3	2642	11	2012-10-18 18:29:34.190539
36	1-36	4	1-110	1-34	3	60	1960	12	2012-10-18 18:29:34.190539
37	1-37	4	1-102	1-34	60	87	5000	91	2012-10-18 18:29:34.190539
38	1-38	5	1-183	1-38	10	62	28	6	2012-10-18 18:29:34.235013
39	1-39	5	1-100	1-38	62	21	5	43	2012-10-18 18:29:34.235013
40	1-40	5	1-24	1-38	21	27	5000	42	2012-10-18 18:29:34.235013
41	1-41	5	1-45	1-38	27	33	1164	57	2012-10-18 18:29:34.235013
42	1-42	5	1-41	1-38	33	10	243	56	2012-10-18 18:29:34.235013
43	1-43	4	1-201	1-43	75	25	714	49	2012-10-18 18:29:34.49064
44	1-44	4	1-159	1-43	25	77	5000	10	2012-10-18 18:29:34.49064
45	1-45	4	1-145	1-43	77	70	1819	13	2012-10-18 18:29:34.49064
46	1-46	4	1-151	1-43	70	75	724	71	2012-10-18 18:29:34.49064
47	1-47	6	1-201	1-47	75	53	1613	49	2012-10-18 18:29:34.49064
48	1-48	6	1-85	1-47	53	9	2956	72	2012-10-18 18:29:34.49064
49	1-49	6	1-173	1-47	9	58	3535	69	2012-10-18 18:29:34.49064
50	1-50	6	1-91	1-47	58	78	5000	88	2012-10-18 18:29:34.49064
51	1-51	6	1-146	1-47	78	44	2495	25	2012-10-18 18:29:34.49064
52	1-52	6	1-133	1-47	44	75	1448	71	2012-10-18 18:29:34.49064
53	1-53	8	1-202	1-53	60	75	2357	71	2012-10-18 18:29:34.501828
54	1-54	8	1-201	1-53	75	80	2673	49	2012-10-18 18:29:34.501828
55	1-55	8	1-168	1-53	80	47	1153	14	2012-10-18 18:29:34.501828
56	1-56	8	1-63	1-53	47	10	912	68	2012-10-18 18:29:34.501828
57	1-57	8	1-59	1-53	10	41	634	73	2012-10-18 18:29:34.501828
58	1-58	8	1-156	1-53	41	69	283	98	2012-10-18 18:29:34.501828
59	1-59	8	1-185	1-53	69	14	154	22	2012-10-18 18:29:34.501828
60	1-60	8	1-77	1-53	14	60	93	17	2012-10-18 18:29:34.501828
61	1-61	8	1-206	1-61	93	84	3330	76	2012-10-18 18:29:34.590776
62	1-62	8	1-167	1-61	84	54	1568	12	2012-10-18 18:29:34.590776
63	1-63	8	1-137	1-61	54	29	3249	70	2012-10-18 18:29:34.590776
64	1-64	8	1-106	1-61	29	36	1567	72	2012-10-18 18:29:34.590776
65	1-65	8	1-71	1-61	36	4	1126	55	2012-10-18 18:29:34.590776
66	1-66	8	1-194	1-61	4	82	541	25	2012-10-18 18:29:34.590776
67	1-67	8	1-157	1-61	82	67	1875	46	2012-10-18 18:29:34.590776
68	1-68	8	1-113	1-61	67	93	5000	44	2012-10-18 18:29:34.590776
69	1-69	2	1-207	1-69	8	50	5000	62	2012-10-18 18:29:34.602128
70	1-70	2	1-73	1-69	50	8	2799	8	2012-10-18 18:29:34.602128
71	1-71	7	1-216	1-71	76	10	1468	68	2012-10-18 18:29:34.779634
72	1-72	7	1-59	1-71	10	41	949	73	2012-10-18 18:29:34.779634
73	1-73	7	1-156	1-71	41	69	394	98	2012-10-18 18:29:34.779634
74	1-74	7	1-185	1-71	69	14	199	22	2012-10-18 18:29:34.779634
75	1-75	7	1-77	1-71	14	60	112	17	2012-10-18 18:29:34.779634
76	1-76	7	1-202	1-71	60	6	2643	71	2012-10-18 18:29:34.779634
77	1-77	7	1-57	1-71	6	76	2179	10	2012-10-18 18:29:34.779634
78	1-78	6	1-219	1-78	27	54	5000	61	2012-10-18 18:29:34.835174
79	1-79	6	1-190	1-78	54	15	3068	83	2012-10-18 18:29:34.835174
80	1-80	6	1-75	1-78	15	57	1946	82	2012-10-18 18:29:34.835174
81	1-81	6	1-112	1-78	57	6	1829	28	2012-10-18 18:29:34.835174
82	1-82	6	1-15	1-78	6	66	2242	27	2012-10-18 18:29:34.835174
83	1-83	6	1-138	1-78	66	27	4043	80	2012-10-18 18:29:34.835174
140	1-140	6	1-261	1-140	52	53	521	49	2012-10-18 18:29:35.692316
141	1-141	6	1-85	1-140	53	36	1065	72	2012-10-18 18:29:35.692316
142	1-142	6	1-71	1-140	36	4	727	55	2012-10-18 18:29:35.692316
143	1-143	6	1-194	1-140	4	46	332	25	2012-10-18 18:29:35.692316
144	1-144	6	1-62	1-140	46	93	189	44	2012-10-18 18:29:35.692316
145	1-145	6	1-206	1-140	93	52	120	76	2012-10-18 18:29:35.692316
146	1-146	6	1-261	1-146	52	80	1116	49	2012-10-18 18:29:35.692316
147	1-147	6	1-168	1-146	80	34	555	14	2012-10-18 18:29:35.692316
148	1-148	6	1-69	1-146	34	59	830	74	2012-10-18 18:29:35.692316
149	1-149	6	1-236	1-146	59	20	723	45	2012-10-18 18:29:35.692316
150	1-150	6	1-26	1-146	20	93	366	44	2012-10-18 18:29:35.692316
151	1-151	6	1-206	1-146	93	52	244	76	2012-10-18 18:29:35.692316
152	1-152	7	1-261	1-152	52	89	359	49	2012-10-18 18:29:35.692316
153	1-153	7	1-187	1-152	89	17	179	53	2012-10-18 18:29:35.692316
154	1-154	7	1-213	1-152	17	44	150	89	2012-10-18 18:29:35.692316
155	1-155	7	1-92	1-152	44	4	403	55	2012-10-18 18:29:35.692316
156	1-156	7	1-194	1-152	4	46	194	25	2012-10-18 18:29:35.692316
157	1-157	7	1-62	1-152	46	93	117	44	2012-10-18 18:29:35.692316
158	1-158	7	1-206	1-152	93	52	78	76	2012-10-18 18:29:35.692316
164	1-164	4	1-267	1-164	97	87	1203	19	2012-10-18 18:29:35.858873
165	1-165	4	1-255	1-164	87	66	2389	77	2012-10-18 18:29:35.858873
166	1-166	4	1-184	1-164	66	39	3549	64	2012-10-18 18:29:35.858873
167	1-167	4	1-49	1-164	39	97	3345	63	2012-10-18 18:29:35.858873
168	1-168	6	1-267	1-168	97	85	465	19	2012-10-18 18:29:35.858873
169	1-169	6	1-228	1-168	85	90	228	98	2012-10-18 18:29:35.858873
170	1-170	6	1-208	1-168	90	29	2891	54	2012-10-18 18:29:35.858873
171	1-171	6	1-37	1-168	29	17	2114	53	2012-10-18 18:29:35.858873
172	1-172	6	1-213	1-168	17	36	1603	89	2012-10-18 18:29:35.858873
173	1-173	6	1-169	1-168	36	97	1055	63	2012-10-18 18:29:35.858873
174	1-174	8	1-267	1-174	97	87	279	19	2012-10-18 18:29:35.858873
175	1-175	8	1-255	1-174	87	66	735	77	2012-10-18 18:29:35.858873
176	1-176	8	1-184	1-174	66	32	1451	64	2012-10-18 18:29:35.858873
177	1-177	8	1-266	1-174	32	35	818	22	2012-10-18 18:29:35.858873
178	1-178	8	1-88	1-174	35	48	623	37	2012-10-18 18:29:35.858873
179	1-179	8	1-214	1-174	48	17	995	53	2012-10-18 18:29:35.858873
180	1-180	8	1-213	1-174	17	36	818	89	2012-10-18 18:29:35.858873
181	1-181	8	1-169	1-174	36	97	583	63	2012-10-18 18:29:35.858873
184	1-184	8	1-270	1-184	53	66	543	27	2012-10-18 18:29:35.96972
185	1-185	8	1-138	1-184	66	44	957	80	2012-10-18 18:29:35.96972
186	1-186	8	1-70	1-184	44	25	1472	79	2012-10-18 18:29:35.96972
187	1-187	8	1-189	1-184	25	57	852	57	2012-10-18 18:29:35.96972
188	1-188	8	1-254	1-184	57	32	1024	36	2012-10-18 18:29:35.96972
189	1-189	8	1-241	1-184	32	13	746	26	2012-10-18 18:29:35.96972
190	1-190	8	1-14	1-184	13	44	1180	25	2012-10-18 18:29:35.96972
191	1-191	8	1-133	1-184	44	53	819	71	2012-10-18 18:29:35.96972
192	1-192	8	1-270	1-192	53	12	823	27	2012-10-18 18:29:35.96972
193	1-193	8	1-64	1-192	12	4	428	59	2012-10-18 18:29:35.96972
194	1-194	8	1-251	1-192	4	9	427	17	2012-10-18 18:29:35.96972
195	1-195	8	1-9	1-192	9	14	388	16	2012-10-18 18:29:35.96972
196	1-196	8	1-220	1-192	14	44	1235	2	2012-10-18 18:29:35.96972
197	1-197	8	1-172	1-192	44	24	608	50	2012-10-18 18:29:35.96972
198	1-198	8	1-231	1-192	24	60	384	94	2012-10-18 18:29:35.96972
199	1-199	8	1-115	1-192	60	53	1137	71	2012-10-18 18:29:35.96972
212	1-212	7	1-273	1-212	27	12	2393	27	2012-10-18 18:29:36.147004
213	1-213	7	1-64	1-212	12	63	1102	59	2012-10-18 18:29:36.147004
214	1-214	7	1-114	1-212	63	16	699	35	2012-10-18 18:29:36.147004
215	1-215	7	1-19	1-212	16	27	959	34	2012-10-18 18:29:36.147004
216	1-216	7	1-222	1-212	27	3	967	11	2012-10-18 18:29:36.147004
217	1-217	7	1-110	1-212	3	54	832	12	2012-10-18 18:29:36.147004
218	1-218	7	1-137	1-212	54	27	1612	70	2012-10-18 18:29:36.147004
235	1-235	8	1-285	1-235	47	15	307	33	2012-10-18 18:29:36.491168
236	1-236	8	1-18	1-235	15	28	142	32	2012-10-18 18:29:36.491168
237	1-237	8	1-165	1-235	28	96	509	52	2012-10-18 18:29:36.491168
238	1-238	8	1-271	1-235	96	13	186	26	2012-10-18 18:29:36.491168
239	1-239	8	1-14	1-235	13	44	232	25	2012-10-18 18:29:36.491168
240	1-240	8	1-133	1-235	44	6	121	71	2012-10-18 18:29:36.491168
241	1-241	8	1-57	1-235	6	77	94	10	2012-10-18 18:29:36.491168
242	1-242	8	1-145	1-235	77	47	35	13	2012-10-18 18:29:36.491168
243	1-243	4	1-285	1-243	47	15	4693	33	2012-10-18 18:29:36.491168
244	1-244	4	1-18	1-243	15	32	2533	32	2012-10-18 18:29:36.491168
245	1-245	4	1-279	1-243	32	77	1053	10	2012-10-18 18:29:36.491168
246	1-246	4	1-145	1-243	77	47	452	13	2012-10-18 18:29:36.491168
280	1-280	3	1-297	1-280	85	28	76	32	2012-10-18 18:29:36.824476
281	1-281	3	1-165	1-280	28	71	240	52	2012-10-18 18:29:36.824476
282	1-282	3	1-125	1-280	71	85	165	41	2012-10-18 18:29:36.824476
84	1-84	7	1-223	1-84	94	29	5000	54	2012-10-18 18:29:34.890838
85	1-85	7	1-37	1-84	29	17	2886	53	2012-10-18 18:29:34.890838
86	1-86	7	1-213	1-84	17	44	1727	89	2012-10-18 18:29:34.890838
87	1-87	7	1-92	1-84	44	44	4061	55	2012-10-18 18:29:34.890838
88	1-88	7	1-58	1-84	44	55	2965	72	2012-10-18 18:29:34.890838
89	1-89	7	1-121	1-84	55	39	1815	64	2012-10-18 18:29:34.890838
90	1-90	7	1-49	1-84	39	94	1655	63	2012-10-18 18:29:34.890838
91	1-91	7	1-232	1-91	82	47	2536	53	2012-10-18 18:29:35.057527
92	1-92	7	1-181	1-91	47	6	1237	28	2012-10-18 18:29:35.057527
93	1-93	7	1-15	1-91	6	12	1128	27	2012-10-18 18:29:35.057527
94	1-94	7	1-64	1-91	12	63	408	59	2012-10-18 18:29:35.057527
95	1-95	7	1-114	1-91	63	16	203	35	2012-10-18 18:29:35.057527
96	1-96	7	1-19	1-91	16	31	219	34	2012-10-18 18:29:35.057527
97	1-97	7	1-60	1-91	31	82	5000	74	2012-10-18 18:29:35.057527
101	1-101	6	1-235	1-101	41	63	1649	59	2012-10-18 18:29:35.124267
102	1-102	6	1-114	1-101	63	16	791	35	2012-10-18 18:29:35.124267
103	1-103	6	1-19	1-101	16	52	821	34	2012-10-18 18:29:35.124267
104	1-104	6	1-124	1-101	52	64	498	64	2012-10-18 18:29:35.124267
105	1-105	6	1-107	1-101	64	7	1357	30	2012-10-18 18:29:35.124267
106	1-106	6	1-122	1-101	7	41	978	66	2012-10-18 18:29:35.124267
107	1-107	6	1-235	1-107	41	63	3351	59	2012-10-18 18:29:35.124267
108	1-108	6	1-114	1-107	63	24	2220	35	2012-10-18 18:29:35.124267
109	1-109	6	1-30	1-107	24	48	1397	49	2012-10-18 18:29:35.124267
110	1-110	6	1-191	1-107	48	28	817	58	2012-10-18 18:29:35.124267
111	1-111	6	1-154	1-107	28	42	1184	67	2012-10-18 18:29:35.124267
112	1-112	6	1-53	1-107	42	41	1439	66	2012-10-18 18:29:35.124267
113	1-113	5	1-247	1-113	41	48	4416	37	2012-10-18 18:29:35.359254
114	1-114	5	1-214	1-113	48	17	2306	53	2012-10-18 18:29:35.359254
115	1-115	5	1-213	1-113	17	44	620	89	2012-10-18 18:29:35.359254
116	1-116	5	1-92	1-113	44	32	536	55	2012-10-18 18:29:35.359254
117	1-117	5	1-40	1-113	32	41	5000	7	2012-10-18 18:29:35.359254
118	1-118	5	1-247	1-118	41	83	584	37	2012-10-18 18:29:35.359254
119	1-119	5	1-161	1-118	83	24	462	3	2012-10-18 18:29:35.359254
120	1-120	5	1-98	1-118	24	5	2017	87	2012-10-18 18:29:35.359254
121	1-121	5	1-193	1-118	5	4	732	8	2012-10-18 18:29:35.359254
122	1-122	5	1-4	1-118	4	41	485	7	2012-10-18 18:29:35.359254
131	1-131	7	1-256	1-131	28	68	1968	29	2012-10-18 18:29:35.592175
132	1-132	7	1-119	1-131	68	78	3497	75	2012-10-18 18:29:35.592175
133	1-133	7	1-164	1-131	78	36	2480	45	2012-10-18 18:29:35.592175
134	1-134	7	1-46	1-131	36	4	1471	59	2012-10-18 18:29:35.592175
135	1-135	7	1-251	1-131	4	9	1358	17	2012-10-18 18:29:35.592175
136	1-136	7	1-9	1-131	9	14	1140	16	2012-10-18 18:29:35.592175
137	1-137	7	1-220	1-131	14	28	3359	2	2012-10-18 18:29:35.592175
138	1-138	2	1-259	1-138	57	70	5000	13	2012-10-18 18:29:35.659047
139	1-139	2	1-151	1-138	70	57	2134	71	2012-10-18 18:29:35.659047
159	1-159	5	1-262	1-159	87	91	3267	13	2012-10-18 18:29:35.736391
160	1-160	5	1-195	1-159	91	3	2322	11	2012-10-18 18:29:35.736391
161	1-161	5	1-110	1-159	3	8	1859	12	2012-10-18 18:29:35.736391
162	1-162	5	1-8	1-159	8	52	2380	15	2012-10-18 18:29:35.736391
163	1-163	5	1-82	1-159	52	87	5000	86	2012-10-18 18:29:35.736391
182	1-182	2	1-268	1-182	71	84	5000	54	2012-10-18 18:29:35.869993
183	1-183	2	1-171	1-182	84	71	3771	91	2012-10-18 18:29:35.869993
200	1-200	4	1-271	1-200	96	13	994	26	2012-10-18 18:29:36.05069
201	1-201	4	1-14	1-200	13	82	1212	25	2012-10-18 18:29:36.05069
202	1-202	4	1-157	1-200	82	28	3125	46	2012-10-18 18:29:36.05069
203	1-203	4	1-36	1-200	28	96	2788	52	2012-10-18 18:29:36.05069
204	1-204	8	1-271	1-204	96	13	1732	26	2012-10-18 18:29:36.05069
205	1-205	8	1-14	1-204	13	46	2376	25	2012-10-18 18:29:36.05069
206	1-206	8	1-62	1-204	46	93	1191	44	2012-10-18 18:29:36.05069
207	1-207	8	1-206	1-204	93	52	665	76	2012-10-18 18:29:36.05069
208	1-208	8	1-261	1-204	52	48	2549	49	2012-10-18 18:29:36.05069
209	1-209	8	1-191	1-204	48	40	1278	58	2012-10-18 18:29:36.05069
210	1-210	8	1-51	1-204	40	31	5000	6	2012-10-18 18:29:36.05069
211	1-211	8	1-39	1-204	31	96	4315	52	2012-10-18 18:29:36.05069
219	1-219	8	1-274	1-219	64	10	725	23	2012-10-18 18:29:36.20271
220	1-220	8	1-80	1-219	10	25	1573	9	2012-10-18 18:29:36.20271
221	1-221	8	1-31	1-219	25	59	768	50	2012-10-18 18:29:36.20271
222	1-222	8	1-94	1-219	59	58	5000	67	2012-10-18 18:29:36.20271
223	1-223	8	1-249	1-219	58	45	4894	32	2012-10-18 18:29:36.20271
224	1-224	8	1-96	1-219	45	11	2570	65	2012-10-18 18:29:36.20271
225	1-225	8	1-188	1-219	11	54	1460	30	2012-10-18 18:29:36.20271
226	1-226	8	1-250	1-219	54	64	1836	79	2012-10-18 18:29:36.20271
227	1-227	8	1-277	1-227	79	6	1269	28	2012-10-18 18:29:36.291584
228	1-228	8	1-15	1-227	6	12	1630	27	2012-10-18 18:29:36.291584
229	1-229	8	1-64	1-227	12	4	830	59	2012-10-18 18:29:36.291584
230	1-230	8	1-251	1-227	4	23	812	17	2012-10-18 18:29:36.291584
231	1-231	8	1-28	1-227	23	28	642	46	2012-10-18 18:29:36.291584
232	1-232	8	1-36	1-227	28	71	797	52	2012-10-18 18:29:36.291584
233	1-233	8	1-125	1-227	71	38	841	41	2012-10-18 18:29:36.291584
98	1-98	3	1-233	1-98	33	17	5000	96	2012-10-18 18:29:35.079708
99	1-99	3	1-198	1-98	17	38	1423	38	2012-10-18 18:29:35.079708
100	1-100	3	1-229	1-98	38	33	770	72	2012-10-18 18:29:35.079708
123	1-123	8	1-251	1-123	4	9	502	17	2012-10-18 18:29:35.470189
124	1-124	8	1-9	1-123	9	14	241	16	2012-10-18 18:29:35.470189
125	1-125	8	1-220	1-123	14	5	406	2	2012-10-18 18:29:35.470189
126	1-126	8	1-11	1-123	5	59	875	20	2012-10-18 18:29:35.470189
127	1-127	8	1-93	1-123	59	34	5000	14	2012-10-18 18:29:35.470189
128	1-128	8	1-69	1-123	34	59	4170	74	2012-10-18 18:29:35.470189
129	1-129	8	1-236	1-123	59	36	2810	45	2012-10-18 18:29:35.470189
130	1-130	8	1-46	1-123	36	4	953	59	2012-10-18 18:29:35.470189
268	1-268	4	1-287	1-268	9	28	179	58	2012-10-18 18:29:36.524428
269	1-269	4	1-154	1-268	28	58	189	67	2012-10-18 18:29:36.524428
270	1-270	4	1-249	1-268	58	28	106	32	2012-10-18 18:29:36.524428
271	1-271	4	1-165	1-268	28	9	353	52	2012-10-18 18:29:36.524428
272	1-272	8	1-293	1-272	52	76	798	17	2012-10-18 18:29:36.724542
273	1-273	8	1-142	1-272	76	72	647	13	2012-10-18 18:29:36.724542
274	1-274	8	1-126	1-272	72	47	343	14	2012-10-18 18:29:36.724542
275	1-275	8	1-63	1-272	47	10	300	68	2012-10-18 18:29:36.724542
276	1-276	8	1-59	1-272	10	41	231	73	2012-10-18 18:29:36.724542
277	1-277	8	1-156	1-272	41	90	114	98	2012-10-18 18:29:36.724542
278	1-278	8	1-208	1-272	90	84	1525	54	2012-10-18 18:29:36.724542
279	1-279	8	1-171	1-272	84	52	1229	91	2012-10-18 18:29:36.724542
234	1-234	8	1-170	1-227	38	79	958	75	2012-10-18 18:29:36.291584
247	1-247	8	1-286	1-247	80	6	1354	71	2012-10-18 18:29:36.513363
248	1-248	8	1-57	1-247	6	35	1304	10	2012-10-18 18:29:36.513363
249	1-249	8	1-44	1-247	35	54	2185	47	2012-10-18 18:29:36.513363
250	1-250	8	1-86	1-247	54	95	1507	81	2012-10-18 18:29:36.513363
251	1-251	8	1-234	1-247	95	31	706	6	2012-10-18 18:29:36.513363
252	1-252	8	1-39	1-247	31	71	685	52	2012-10-18 18:29:36.513363
253	1-253	8	1-125	1-247	71	38	659	41	2012-10-18 18:29:36.513363
254	1-254	8	1-170	1-247	38	80	683	75	2012-10-18 18:29:36.513363
255	1-255	5	1-286	1-255	80	6	1352	71	2012-10-18 18:29:36.513363
256	1-256	5	1-57	1-255	6	76	1423	10	2012-10-18 18:29:36.513363
257	1-257	5	1-216	1-255	76	56	1224	68	2012-10-18 18:29:36.513363
258	1-258	5	1-282	1-255	56	74	616	35	2012-10-18 18:29:36.513363
259	1-259	5	1-176	1-255	74	80	623	75	2012-10-18 18:29:36.513363
260	1-260	8	1-286	1-260	80	53	2294	71	2012-10-18 18:29:36.513363
261	1-261	8	1-270	1-260	53	12	1648	27	2012-10-18 18:29:36.513363
262	1-262	8	1-64	1-260	12	4	849	59	2012-10-18 18:29:36.513363
263	1-263	8	1-251	1-260	4	23	841	17	2012-10-18 18:29:36.513363
264	1-264	8	1-28	1-260	23	28	673	46	2012-10-18 18:29:36.513363
265	1-265	8	1-36	1-260	28	71	845	52	2012-10-18 18:29:36.513363
266	1-266	8	1-125	1-260	71	38	903	41	2012-10-18 18:29:36.513363
267	1-267	8	1-170	1-260	38	80	1041	75	2012-10-18 18:29:36.513363
\.


--
-- Data for Name: tmvtremoved; Type: TABLE DATA; Schema: public; Owner: olivier
--

COPY tmvtremoved (id, uuid, nb, oruuid, grp, own_src, own_dst, qtt, nat, created, deleted) FROM stdin;
\.


--
-- Data for Name: torder; Type: TABLE DATA; Schema: public; Owner: olivier
--

COPY torder (id, uuid, own, nr, qtt_requ, np, qtt_prov, qtt, start, created, updated) FROM stdin;
1	1-1	1	2	6177	1	5000	5000	0	2012-10-18 18:29:32.022375	\N
2	1-2	2	4	8617	3	5000	5000	0	2012-10-18 18:29:32.028248	\N
3	1-3	3	6	2700	5	5000	5000	0	2012-10-18 18:29:32.031691	\N
6	1-6	6	12	9335	11	5000	5000	0	2012-10-18 18:29:32.12708	\N
7	1-7	7	14	8338	13	5000	5000	0	2012-10-18 18:29:32.149455	\N
12	1-12	11	22	7489	21	5000	5000	0	2012-10-18 18:29:32.227094	\N
13	1-13	12	24	2177	23	5000	5000	0	2012-10-18 18:29:32.238221	\N
17	1-17	5	31	1924	30	5000	5000	0	2012-10-18 18:29:32.282842	\N
20	1-20	17	37	6409	36	5000	5000	0	2012-10-18 18:29:32.316208	\N
21	1-21	18	38	2571	27	5000	5000	0	2012-10-18 18:29:32.329302	\N
22	1-22	19	40	9960	39	5000	5000	0	2012-10-18 18:29:32.340386	\N
23	1-23	20	23	8416	41	5000	5000	0	2012-10-18 18:29:32.351541	\N
29	1-29	5	48	7907	47	5000	5000	0	2012-10-18 18:29:32.418376	\N
32	1-32	26	51	4049	44	5000	5000	0	2012-10-18 18:29:32.45195	\N
34	1-34	27	24	8379	46	5000	5000	0	2012-10-18 18:29:32.475066	\N
35	1-35	10	30	5238	36	5000	5000	0	2012-10-18 18:29:32.485213	\N
38	1-38	30	24	7194	31	5000	5000	0	2012-10-18 18:29:32.518573	\N
42	1-42	34	48	8769	21	5000	5000	0	2012-10-18 18:29:32.563123	\N
43	1-43	30	58	3647	7	5000	5000	0	2012-10-18 18:29:32.574345	\N
47	1-47	37	21	6941	60	5000	5000	0	2012-10-18 18:29:32.618866	\N
48	1-48	38	62	5322	61	5000	5000	0	2012-10-18 18:29:32.630072	\N
50	1-50	35	65	6299	55	5000	5000	0	2012-10-18 18:29:32.652343	\N
52	1-52	41	65	9498	7	5000	5000	0	2012-10-18 18:29:32.674586	\N
54	1-54	12	1	6822	68	5000	5000	0	2012-10-18 18:29:32.696837	\N
61	1-61	45	22	8532	64	5000	5000	0	2012-10-18 18:29:32.7748	\N
65	1-65	43	76	2642	75	5000	5000	0	2012-10-18 18:29:32.819261	\N
66	1-66	41	78	7506	77	5000	5000	0	2012-10-18 18:29:32.830445	\N
68	1-68	49	42	5714	47	5000	5000	0	2012-10-18 18:29:32.852727	\N
55	1-55	43	69	2684	39	5000	4581	0	2012-10-18 18:29:32.708002	2012-10-18 18:29:34.101452
16	1-16	14	9	6817	29	5000	3321	0	2012-10-18 18:29:32.271741	2012-10-18 18:29:33.689515
27	1-27	22	34	5006	19	5000	1418	0	2012-10-18 18:29:32.396136	2012-10-18 18:29:33.990101
10	1-10	10	19	6038	18	5000	2873	0	2012-10-18 18:29:32.204785	2012-10-18 18:29:33.990101
73	1-73	50	62	5327	8	5000	2201	0	2012-10-18 18:29:32.908387	2012-10-18 18:29:34.602128
67	1-67	48	68	8648	18	5000	3711	0	2012-10-18 18:29:32.841588	2012-10-18 18:29:34.101452
45	1-45	27	42	4561	57	5000	3836	0	2012-10-18 18:29:32.596593	2012-10-18 18:29:34.235013
41	1-41	33	57	5087	56	5000	4757	0	2012-10-18 18:29:32.552344	2012-10-18 18:29:34.235013
59	1-59	10	68	5811	73	5000	3186	0	2012-10-18 18:29:32.75255	2012-10-18 18:29:36.724542
63	1-63	47	14	5105	68	5000	484	0	2012-10-18 18:29:32.797056	2012-10-18 18:29:36.724542
31	1-31	25	9	7820	50	5000	4232	0	2012-10-18 18:29:32.440683	2012-10-18 18:29:36.20271
58	1-58	44	55	5603	72	5000	2035	0	2012-10-18 18:29:32.741422	2012-10-18 18:29:34.890838
18	1-18	15	33	7688	32	5000	2325	0	2012-10-18 18:29:32.293929	2012-10-18 18:29:36.491168
9	1-9	9	17	5412	16	5000	3231	0	2012-10-18 18:29:32.193604	2012-10-18 18:29:35.96972
53	1-53	42	67	3744	66	5000	3561	0	2012-10-18 18:29:32.685707	2012-10-18 18:29:35.124267
4	1-4	4	8	3097	7	5000	4515	0	2012-10-18 18:29:32.06063	2012-10-18 18:29:35.359254
11	1-11	5	2	1204	20	5000	4125	0	2012-10-18 18:29:32.216014	2012-10-18 18:29:35.470189
70	1-70	44	80	3084	79	5000	3528	0	2012-10-18 18:29:32.874962	2012-10-18 18:29:35.96972
46	1-46	36	45	7661	59	5000	2576	0	2012-10-18 18:29:32.607796	2012-10-18 18:29:35.592175
19	1-19	16	35	3175	34	5000	3001	0	2012-10-18 18:29:32.305055	2012-10-18 18:29:36.147004
26	1-26	20	45	9204	44	5000	4634	0	2012-10-18 18:29:32.384932	2012-10-18 18:29:35.692316
8	1-8	8	12	3168	15	5000	2620	0	2012-10-18 18:29:32.171539	2012-10-18 18:29:35.736391
44	1-44	35	10	2618	47	5000	2815	0	2012-10-18 18:29:32.585501	2012-10-18 18:29:36.513363
62	1-62	46	25	7781	44	5000	3503	0	2012-10-18 18:29:32.785919	2012-10-18 18:29:36.05069
64	1-64	12	27	9461	59	5000	1383	0	2012-10-18 18:29:32.808181	2012-10-18 18:29:36.513363
28	1-28	23	17	6093	46	5000	3685	0	2012-10-18 18:29:32.407208	2012-10-18 18:29:36.513363
36	1-36	28	46	3884	52	5000	570	0	2012-10-18 18:29:32.496335	2012-10-18 18:29:36.513363
72	1-72	38	38	7111	27	5000	5000	0	2012-10-18 18:29:32.897212	\N
78	1-78	51	84	1706	35	5000	5000	0	2012-10-18 18:29:32.964118	\N
81	1-81	14	48	3350	77	5000	5000	0	2012-10-18 18:29:32.997426	\N
84	1-84	4	22	7806	6	5000	5000	0	2012-10-18 18:29:33.030961	\N
87	1-87	55	31	8379	38	5000	5000	0	2012-10-18 18:29:33.064261	\N
90	1-90	57	31	5440	77	5000	5000	0	2012-10-18 18:29:33.097671	\N
105	1-105	63	31	7508	10	5000	5000	0	2012-10-18 18:29:33.264615	\N
108	1-108	65	59	8394	10	5000	5000	0	2012-10-18 18:29:33.29806	\N
111	1-111	19	41	1947	5	5000	5000	0	2012-10-18 18:29:33.331444	\N
120	1-120	69	96	7336	95	5000	5000	0	2012-10-18 18:29:33.431693	\N
123	1-123	70	14	5878	5	5000	5000	0	2012-10-18 18:29:33.465029	\N
129	1-129	14	76	5963	95	5000	5000	0	2012-10-18 18:29:33.554154	\N
135	1-135	48	4	7902	35	5000	5000	0	2012-10-18 18:29:33.620881	\N
141	1-141	21	12	160	10	5000	3	0	2012-10-18 18:29:33.689515	2012-10-18 18:29:33.689515
204	1-204	20	84	1356	57	5000	5000	0	2012-10-18 18:29:34.557255	\N
144	1-144	77	19	6505	57	5000	5000	0	2012-10-18 18:29:33.745094	\N
147	1-147	74	97	9439	35	5000	5000	0	2012-10-18 18:29:33.77853	\N
150	1-150	2	58	8923	10	5000	5000	0	2012-10-18 18:29:33.811921	\N
153	1-153	81	90	8218	57	5000	5000	0	2012-10-18 18:29:33.845359	\N
162	1-162	41	45	8947	82	5000	5000	0	2012-10-18 18:29:33.945526	\N
288	1-288	18	13	2922	16	5000	5000	0	2012-10-18 18:29:36.580013	\N
99	1-99	2	18	9636	35	5000	3757	0	2012-10-18 18:29:33.197851	2012-10-18 18:29:34.101452
174	1-174	85	82	6718	68	5000	5000	0	2012-10-18 18:29:34.112507	\N
177	1-177	4	17	5378	57	5000	5000	0	2012-10-18 18:29:34.157043	\N
180	1-180	87	91	8967	65	5000	2906	0	2012-10-18 18:29:34.190539	2012-10-18 18:29:34.190539
132	1-132	33	65	2977	11	5000	1586	0	2012-10-18 18:29:33.587412	2012-10-18 18:29:34.190539
183	1-183	10	56	9104	6	5000	4972	0	2012-10-18 18:29:34.235013	2012-10-18 18:29:34.235013
186	1-186	15	98	4342	5	5000	5000	0	2012-10-18 18:29:34.279537	\N
192	1-192	90	31	6914	80	5000	5000	0	2012-10-18 18:29:34.357413	\N
225	1-225	84	40	4978	95	5000	5000	0	2012-10-18 18:29:34.935323	\N
210	1-210	66	21	6175	65	5000	5000	0	2012-10-18 18:29:34.668688	\N
75	1-75	15	83	7255	82	5000	3054	0	2012-10-18 18:29:32.93059	2012-10-18 18:29:34.835174
198	1-198	17	96	6522	38	5000	3577	0	2012-10-18 18:29:34.457281	2012-10-18 18:29:35.079708
276	1-276	96	21	8471	19	5000	5000	0	2012-10-18 18:29:36.26922	\N
237	1-237	4	97	6942	5	5000	5000	0	2012-10-18 18:29:35.179732	\N
240	1-240	19	48	7784	6	5000	5000	0	2012-10-18 18:29:35.246301	\N
243	1-243	19	85	3042	27	5000	5000	0	2012-10-18 18:29:35.279711	\N
246	1-246	3	39	2300	57	5000	5000	0	2012-10-18 18:29:35.348152	\N
273	1-273	27	70	3145	27	5000	2607	0	2012-10-18 18:29:36.147004	2012-10-18 18:29:36.147004
252	1-252	34	9	4694	16	5000	5000	0	2012-10-18 18:29:35.492459	\N
258	1-258	10	3	8588	16	5000	5000	0	2012-10-18 18:29:35.636635	\N
168	1-168	80	49	9361	14	5000	3292	0	2012-10-18 18:29:34.012323	2012-10-18 18:29:35.692316
126	1-126	72	13	8435	14	5000	4657	0	2012-10-18 18:29:33.520682	2012-10-18 18:29:36.724542
114	1-114	63	59	6868	35	5000	1087	0	2012-10-18 18:29:33.364815	2012-10-18 18:29:36.147004
195	1-195	91	13	5706	11	5000	2678	0	2012-10-18 18:29:34.39077	2012-10-18 18:29:35.736391
264	1-264	64	53	4556	11	5000	5000	0	2012-10-18 18:29:35.792115	\N
189	1-189	25	79	7776	57	5000	4148	0	2012-10-18 18:29:34.312876	2012-10-18 18:29:35.96972
228	1-228	85	19	8661	98	5000	4772	0	2012-10-18 18:29:35.001943	2012-10-18 18:29:35.858873
291	1-291	54	21	1299	77	5000	5000	0	2012-10-18 18:29:36.691092	\N
267	1-267	97	63	9622	19	5000	3053	0	2012-10-18 18:29:35.858873	2012-10-18 18:29:35.858873
255	1-255	87	19	1743	77	5000	1876	0	2012-10-18 18:29:35.559033	2012-10-18 18:29:35.858873
213	1-213	17	53	5593	89	5000	82	0	2012-10-18 18:29:34.713125	2012-10-18 18:29:35.858873
231	1-231	24	50	7778	94	5000	4616	0	2012-10-18 18:29:35.04637	2012-10-18 18:29:35.96972
261	1-261	52	76	1017	49	5000	455	0	2012-10-18 18:29:35.692316	2012-10-18 18:29:36.05069
222	1-222	27	34	4631	11	5000	4033	0	2012-10-18 18:29:34.879753	2012-10-18 18:29:36.147004
96	1-96	45	32	7267	65	5000	1426	0	2012-10-18 18:29:33.164482	2012-10-18 18:29:36.20271
156	1-156	41	73	9046	98	5000	4209	0	2012-10-18 18:29:33.87873	2012-10-18 18:29:36.724542
297	1-297	85	41	6856	32	5000	4924	0	2012-10-18 18:29:36.824476	2012-10-18 18:29:36.824476
279	1-279	32	32	9988	10	5000	3947	0	2012-10-18 18:29:36.324922	2012-10-18 18:29:36.491168
234	1-234	95	81	9364	6	5000	4294	0	2012-10-18 18:29:35.090787	2012-10-18 18:29:36.513363
216	1-216	76	10	5577	68	5000	2308	0	2012-10-18 18:29:34.779634	2012-10-18 18:29:36.513363
294	1-294	26	3	7991	42	5000	5000	0	2012-10-18 18:29:36.746629	\N
300	1-300	16	92	9094	77	5000	5000	0	2012-10-18 18:29:36.879832	\N
74	1-74	16	3	5188	81	5000	5000	0	2012-10-18 18:29:32.919455	\N
83	1-83	11	14	9816	36	5000	5000	0	2012-10-18 18:29:33.019829	\N
89	1-89	56	63	7433	87	5000	5000	0	2012-10-18 18:29:33.086521	\N
95	1-95	60	50	145	66	5000	5000	0	2012-10-18 18:29:33.153395	\N
101	1-101	59	74	9027	47	5000	5000	0	2012-10-18 18:29:33.22013	\N
104	1-104	40	83	7113	92	5000	5000	0	2012-10-18 18:29:33.25348	\N
116	1-116	33	41	5186	92	5000	5000	0	2012-10-18 18:29:33.387264	\N
161	1-161	83	37	2590	3	5000	4538	0	2012-10-18 18:29:33.934364	2012-10-18 18:29:35.359254
98	1-98	24	3	470	87	5000	2983	0	2012-10-18 18:29:33.186767	2012-10-18 18:29:35.359254
128	1-128	43	86	8841	81	5000	5000	0	2012-10-18 18:29:33.542934	\N
131	1-131	14	48	5958	20	5000	5000	0	2012-10-18 18:29:33.576594	\N
134	1-134	73	89	4075	87	5000	5000	0	2012-10-18 18:29:33.609808	\N
140	1-140	75	84	9530	66	5000	5000	0	2012-10-18 18:29:33.683059	\N
209	1-209	67	74	4972	69	5000	5000	0	2012-10-18 18:29:34.646432	\N
143	1-143	19	74	2999	47	5000	5000	0	2012-10-18 18:29:33.711782	\N
149	1-149	68	86	7736	87	5000	5000	0	2012-10-18 18:29:33.800776	\N
152	1-152	80	31	3856	56	5000	5000	0	2012-10-18 18:29:33.834141	\N
155	1-155	33	17	6342	60	5000	5000	0	2012-10-18 18:29:33.867645	\N
158	1-158	31	93	4989	66	5000	5000	0	2012-10-18 18:29:33.900981	\N
281	1-281	72	51	5561	20	5000	5000	0	2012-10-18 18:29:36.402473	\N
179	1-179	51	61	5398	90	5000	5000	0	2012-10-18 18:29:34.179284	\N
254	1-254	57	57	3743	36	5000	3976	0	2012-10-18 18:29:35.547872	2012-10-18 18:29:35.96972
182	1-182	88	42	5548	73	5000	5000	0	2012-10-18 18:29:34.212744	\N
197	1-197	36	4	8138	31	5000	5000	0	2012-10-18 18:29:34.435092	\N
200	1-200	62	73	5340	36	5000	5000	0	2012-10-18 18:29:34.479592	\N
173	1-173	9	72	3317	69	5000	1131	0	2012-10-18 18:29:34.101452	2012-10-18 18:29:34.49064
146	1-146	78	88	7949	25	5000	2505	0	2012-10-18 18:29:33.767404	2012-10-18 18:29:34.49064
80	1-80	10	23	1760	9	5000	3427	0	2012-10-18 18:29:32.986345	2012-10-18 18:29:36.20271
203	1-203	46	31	1678	47	5000	5000	0	2012-10-18 18:29:34.523976	\N
167	1-167	84	76	9892	12	5000	3432	0	2012-10-18 18:29:34.0012	2012-10-18 18:29:34.590776
125	1-125	71	52	4563	41	5000	611	0	2012-10-18 18:29:33.509408	2012-10-18 18:29:36.824476
266	1-266	32	64	8159	22	5000	4182	0	2012-10-18 18:29:35.825639	2012-10-18 18:29:35.858873
212	1-212	70	45	9236	78	5000	5000	0	2012-10-18 18:29:34.701878	\N
215	1-215	89	24	4970	22	5000	5000	0	2012-10-18 18:29:34.757474	\N
185	1-185	69	98	7435	22	5000	4647	0	2012-10-18 18:29:34.257247	2012-10-18 18:29:34.779634
77	1-77	14	22	6686	17	5000	4795	0	2012-10-18 18:29:32.952926	2012-10-18 18:29:34.779634
218	1-218	71	4	3929	3	5000	5000	0	2012-10-18 18:29:34.801842	\N
221	1-221	46	6	2893	47	5000	5000	0	2012-10-18 18:29:34.857469	\N
224	1-224	27	34	8783	60	5000	5000	0	2012-10-18 18:29:34.913105	\N
227	1-227	80	23	3772	25	5000	5000	0	2012-10-18 18:29:34.990668	\N
230	1-230	94	37	112	69	5000	5000	0	2012-10-18 18:29:35.024219	\N
248	1-248	40	51	5832	90	5000	5000	0	2012-10-18 18:29:35.381358	\N
122	1-122	7	30	4574	66	5000	1158	0	2012-10-18 18:29:33.453909	2012-10-18 18:29:35.124267
239	1-239	96	62	2318	17	5000	5000	0	2012-10-18 18:29:35.235167	\N
242	1-242	72	98	5308	55	5000	5000	0	2012-10-18 18:29:35.268584	\N
245	1-245	4	14	911	60	5000	5000	0	2012-10-18 18:29:35.336922	\N
269	1-269	18	3	7061	44	5000	5000	0	2012-10-18 18:29:35.914199	\N
236	1-236	59	74	5348	45	5000	1467	0	2012-10-18 18:29:35.157532	2012-10-18 18:29:35.692316
164	1-164	78	75	6410	45	5000	2520	0	2012-10-18 18:29:33.967845	2012-10-18 18:29:35.592175
257	1-257	87	76	9464	41	5000	5000	0	2012-10-18 18:29:35.61434	\N
260	1-260	8	78	8357	69	5000	5000	0	2012-10-18 18:29:35.681224	\N
206	1-206	93	44	6993	76	5000	563	0	2012-10-18 18:29:34.590776	2012-10-18 18:29:36.05069
191	1-191	48	49	7781	58	5000	2905	0	2012-10-18 18:29:34.346255	2012-10-18 18:29:36.05069
194	1-194	4	55	9691	25	5000	3933	0	2012-10-18 18:29:34.379685	2012-10-18 18:29:35.692316
188	1-188	11	65	6718	30	5000	3540	0	2012-10-18 18:29:34.301761	2012-10-18 18:29:36.20271
263	1-263	67	24	4247	3	5000	5000	0	2012-10-18 18:29:35.758602	\N
272	1-272	15	52	6325	60	5000	5000	0	2012-10-18 18:29:36.096037	\N
137	1-137	54	12	2248	70	5000	139	0	2012-10-18 18:29:33.643141	2012-10-18 18:29:36.147004
275	1-275	47	2	3152	92	5000	5000	0	2012-10-18 18:29:36.235863	\N
278	1-278	44	55	7706	25	5000	5000	4	2012-10-18 18:29:36.30278	\N
284	1-284	60	88	9884	20	5000	5000	0	2012-10-18 18:29:36.446967	\N
86	1-86	54	47	6361	81	5000	3493	0	2012-10-18 18:29:33.053363	2012-10-18 18:29:36.513363
176	1-176	74	35	4742	75	5000	4377	0	2012-10-18 18:29:34.145898	2012-10-18 18:29:36.513363
251	1-251	4	59	4926	17	5000	1060	0	2012-10-18 18:29:35.470189	2012-10-18 18:29:36.513363
76	1-76	44	62	77	46	5000	5000	0	2012-10-18 18:29:32.941839	\N
79	1-79	6	85	9679	67	5000	5000	0	2012-10-18 18:29:32.975172	\N
97	1-97	61	90	1538	18	5000	5000	0	2012-10-18 18:29:33.175635	\N
103	1-103	13	48	5994	37	5000	5000	0	2012-10-18 18:29:33.242396	\N
109	1-109	66	89	2272	93	5000	5000	0	2012-10-18 18:29:33.309228	\N
118	1-118	65	4	5899	37	5000	5000	0	2012-10-18 18:29:33.409404	\N
127	1-127	35	21	8405	54	5000	5000	0	2012-10-18 18:29:33.531838	\N
130	1-130	29	67	7293	54	5000	5000	0	2012-10-18 18:29:33.565326	\N
136	1-136	48	31	3275	23	5000	5000	0	2012-10-18 18:29:33.63202	\N
139	1-139	74	1	9351	34	5000	5000	0	2012-10-18 18:29:33.665384	\N
148	1-148	79	94	8534	34	5000	5000	0	2012-10-18 18:29:33.789628	\N
160	1-160	48	4	2303	79	5000	5000	0	2012-10-18 18:29:33.923222	\N
163	1-163	4	1	8116	71	5000	5000	0	2012-10-18 18:29:33.956601	\N
166	1-166	43	55	615	8	5000	2902	0	2012-10-18 18:29:33.990101	2012-10-18 18:29:33.990101
250	1-250	54	30	3035	79	5000	3164	0	2012-10-18 18:29:35.459005	2012-10-18 18:29:36.20271
175	1-175	86	84	2322	67	5000	5000	0	2012-10-18 18:29:34.123601	\N
178	1-178	54	94	2743	88	5000	5000	0	2012-10-18 18:29:34.168191	\N
100	1-100	62	6	6400	43	5000	4995	0	2012-10-18 18:29:33.209025	2012-10-18 18:29:34.235013
196	1-196	40	78	7288	64	5000	5000	0	2012-10-18 18:29:34.412969	\N
199	1-199	49	83	6151	93	5000	5000	0	2012-10-18 18:29:34.468404	\N
205	1-205	92	23	1463	88	5000	5000	0	2012-10-18 18:29:34.579617	\N
106	1-106	29	70	9658	72	5000	1571	0	2012-10-18 18:29:33.275847	2012-10-18 18:29:34.590776
265	1-265	65	23	8487	18	5000	5000	0	2012-10-18 18:29:35.814556	\N
211	1-211	91	75	9466	54	5000	5000	0	2012-10-18 18:29:34.679866	\N
217	1-217	16	42	5057	2	5000	5000	0	2012-10-18 18:29:34.790708	\N
190	1-190	54	61	7499	83	5000	1932	0	2012-10-18 18:29:34.335143	2012-10-18 18:29:34.835174
112	1-112	57	82	4897	28	5000	3171	0	2012-10-18 18:29:33.342566	2012-10-18 18:29:34.835174
232	1-232	82	74	6748	53	5000	2464	0	2012-10-18 18:29:35.057527	2012-10-18 18:29:35.057527
121	1-121	55	72	5468	64	5000	1960	0	2012-10-18 18:29:33.442771	2012-10-18 18:29:34.890838
226	1-226	76	90	6082	79	5000	5000	0	2012-10-18 18:29:34.968491	\N
181	1-181	47	53	7015	28	5000	3763	0	2012-10-18 18:29:34.201621	2012-10-18 18:29:35.057527
229	1-229	38	38	3432	72	5000	4230	0	2012-10-18 18:29:35.013069	2012-10-18 18:29:35.079708
124	1-124	52	34	5436	64	5000	4502	0	2012-10-18 18:29:33.476194	2012-10-18 18:29:35.124267
30	1-30	24	35	7233	49	5000	3000	0	2012-10-18 18:29:32.429477	2012-10-18 18:29:35.124267
238	1-238	37	24	8859	39	5000	5000	0	2012-10-18 18:29:35.212976	\N
244	1-244	85	83	5684	51	5000	5000	0	2012-10-18 18:29:35.312878	\N
262	1-262	87	86	6205	13	5000	1733	0	2012-10-18 18:29:35.736391	2012-10-18 18:29:35.736391
241	1-241	32	36	6182	26	5000	4254	0	2012-10-18 18:29:35.257418	2012-10-18 18:29:35.96972
193	1-193	5	87	5648	8	5000	4268	0	2012-10-18 18:29:34.368513	2012-10-18 18:29:35.359254
253	1-253	67	10	6018	64	5000	5000	0	2012-10-18 18:29:35.514665	\N
256	1-256	28	2	7757	29	5000	3032	0	2012-10-18 18:29:35.592175	2012-10-18 18:29:35.592175
151	1-151	70	13	8831	71	5000	2142	0	2012-10-18 18:29:33.823047	2012-10-18 18:29:35.659047
289	1-289	52	12	8566	34	5000	5000	0	2012-10-18 18:29:36.635705	\N
71	1-71	36	72	6483	55	5000	2787	0	2012-10-18 18:29:32.886129	2012-10-18 18:29:35.692316
187	1-187	89	49	9366	53	5000	4821	0	2012-10-18 18:29:34.290664	2012-10-18 18:29:35.692316
274	1-274	64	79	9659	23	5000	4275	0	2012-10-18 18:29:36.20271	2012-10-18 18:29:36.20271
172	1-172	44	2	9992	50	5000	4392	0	2012-10-18 18:29:34.079213	2012-10-18 18:29:35.96972
88	1-88	35	22	6040	37	5000	4377	0	2012-10-18 18:29:33.075408	2012-10-18 18:29:35.858873
214	1-214	48	37	2878	53	5000	1699	0	2012-10-18 18:29:34.735247	2012-10-18 18:29:35.858873
169	1-169	36	89	6448	63	5000	3362	0	2012-10-18 18:29:34.045653	2012-10-18 18:29:35.858873
115	1-115	60	94	1662	71	5000	3863	0	2012-10-18 18:29:33.375962	2012-10-18 18:29:35.96972
292	1-292	13	40	414	34	5000	5000	0	2012-10-18 18:29:36.713573	\N
280	1-280	66	12	6299	37	5000	5000	0	2012-10-18 18:29:36.369305	\N
277	1-277	79	75	3637	28	5000	3731	0	2012-10-18 18:29:36.291584	2012-10-18 18:29:36.291584
283	1-283	61	56	7474	53	5000	5000	0	2012-10-18 18:29:36.435859	\N
271	1-271	96	52	9717	26	5000	2088	0	2012-10-18 18:29:36.05069	2012-10-18 18:29:36.491168
133	1-133	44	25	6835	71	5000	2612	0	2012-10-18 18:29:33.598545	2012-10-18 18:29:36.491168
142	1-142	76	17	5510	13	5000	4353	0	2012-10-18 18:29:33.700622	2012-10-18 18:29:36.724542
145	1-145	77	10	9659	13	5000	2694	0	2012-10-18 18:29:33.756253	2012-10-18 18:29:36.491168
208	1-208	90	98	334	54	5000	584	0	2012-10-18 18:29:34.61325	2012-10-18 18:29:36.724542
282	1-282	56	68	9529	35	5000	4384	0	2012-10-18 18:29:36.413666	2012-10-18 18:29:36.513363
295	1-295	27	80	4775	48	5000	5000	0	2012-10-18 18:29:36.757828	\N
270	1-270	53	71	6790	27	5000	1986	0	2012-10-18 18:29:35.96972	2012-10-18 18:29:36.513363
170	1-170	38	41	4231	75	5000	1401	0	2012-10-18 18:29:34.056812	2012-10-18 18:29:36.513363
298	1-298	21	86	1215	72	5000	5000	0	2012-10-18 18:29:36.835444	\N
287	1-287	9	52	4312	58	5000	4821	0	2012-10-18 18:29:36.524428	2012-10-18 18:29:36.524428
154	1-154	28	58	3140	67	5000	3627	0	2012-10-18 18:29:33.856526	2012-10-18 18:29:36.524428
290	1-290	35	42	5840	20	5000	5000	0	2012-10-18 18:29:36.657914	\N
293	1-293	52	91	6877	17	5000	4202	0	2012-10-18 18:29:36.724542	2012-10-18 18:29:36.724542
296	1-296	18	85	1180	78	5000	5000	0	2012-10-18 18:29:36.802195	\N
299	1-299	45	27	9095	97	5000	5000	0	2012-10-18 18:29:36.846597	\N
\.


--
-- Data for Name: torderremoved; Type: TABLE DATA; Schema: public; Owner: olivier
--

COPY torderremoved (id, uuid, own, nr, qtt_requ, np, qtt_prov, qtt, start, created, updated) FROM stdin;
56	1-56	21	66	2060	70	5000	0	0	2012-10-18 18:29:32.719176	2012-10-18 18:29:33.453909
5	1-5	5	10	2288	9	5000	0	0	2012-10-18 18:29:32.093767	2012-10-18 18:29:33.689515
25	1-25	7	8	1505	34	5000	0	0	2012-10-18 18:29:32.37376	2012-10-18 18:29:33.990101
117	1-117	53	75	1079	32	5000	0	0	2012-10-18 18:29:33.398268	2012-10-18 18:29:34.056812
33	1-33	14	39	283	14	5000	0	0	2012-10-18 18:29:32.462955	2012-10-18 18:29:34.101452
102	1-102	60	12	1472	91	5000	0	0	2012-10-18 18:29:33.231253	2012-10-18 18:29:34.190539
24	1-24	21	43	1	42	5000	0	0	2012-10-18 18:29:32.362666	2012-10-18 18:29:34.235013
159	1-159	25	49	502	10	5000	0	0	2012-10-18 18:29:33.912179	2012-10-18 18:29:34.49064
91	1-91	58	69	2804	88	5000	0	0	2012-10-18 18:29:33.108763	2012-10-18 18:29:34.49064
201	1-201	75	71	3560	49	5000	0	0	2012-10-18 18:29:34.49064	2012-10-18 18:29:34.501828
113	1-113	67	46	1747	44	5000	0	0	2012-10-18 18:29:33.353691	2012-10-18 18:29:34.590776
207	1-207	8	8	1669	62	5000	0	0	2012-10-18 18:29:34.602128	2012-10-18 18:29:34.602128
202	1-202	60	17	159	71	5000	0	0	2012-10-18 18:29:34.501828	2012-10-18 18:29:34.779634
219	1-219	27	80	3721	61	5000	0	0	2012-10-18 18:29:34.835174	2012-10-18 18:29:34.835174
223	1-223	94	63	1108	54	5000	0	0	2012-10-18 18:29:34.890838	2012-10-18 18:29:34.890838
60	1-60	31	34	150	74	5000	0	0	2012-10-18 18:29:32.763655	2012-10-18 18:29:35.057527
233	1-233	33	72	286	96	5000	0	0	2012-10-18 18:29:35.079708	2012-10-18 18:29:35.079708
107	1-107	64	64	1209	30	5000	0	0	2012-10-18 18:29:33.286942	2012-10-18 18:29:35.124267
235	1-235	41	66	1954	59	5000	0	0	2012-10-18 18:29:35.124267	2012-10-18 18:29:35.124267
40	1-40	32	55	161	7	5000	0	0	2012-10-18 18:29:32.541067	2012-10-18 18:29:35.359254
247	1-247	41	7	1702	37	5000	0	0	2012-10-18 18:29:35.359254	2012-10-18 18:29:35.359254
93	1-93	59	20	631	14	5000	0	0	2012-10-18 18:29:33.131013	2012-10-18 18:29:35.470189
119	1-119	68	29	2558	75	5000	0	0	2012-10-18 18:29:33.420528	2012-10-18 18:29:35.592175
259	1-259	57	71	1609	13	5000	0	0	2012-10-18 18:29:35.659047	2012-10-18 18:29:35.659047
85	1-85	53	49	2164	72	5000	0	0	2012-10-18 18:29:33.042138	2012-10-18 18:29:35.692316
69	1-69	34	14	3114	74	5000	0	0	2012-10-18 18:29:32.863907	2012-10-18 18:29:35.692316
92	1-92	44	89	1740	55	5000	0	0	2012-10-18 18:29:33.119923	2012-10-18 18:29:35.692316
82	1-82	52	15	1930	86	5000	0	0	2012-10-18 18:29:33.008647	2012-10-18 18:29:35.736391
49	1-49	39	64	3672	63	5000	0	0	2012-10-18 18:29:32.64117	2012-10-18 18:29:35.858873
37	1-37	29	54	5800	53	5000	0	0	2012-10-18 18:29:32.507415	2012-10-18 18:29:35.858873
184	1-184	66	77	2330	64	5000	0	0	2012-10-18 18:29:34.246122	2012-10-18 18:29:35.858873
268	1-268	71	91	3154	54	5000	0	0	2012-10-18 18:29:35.869993	2012-10-18 18:29:35.869993
138	1-138	66	27	2552	80	5000	0	0	2012-10-18 18:29:33.654247	2012-10-18 18:29:35.96972
220	1-220	14	16	1543	2	5000	0	0	2012-10-18 18:29:34.846343	2012-10-18 18:29:35.96972
157	1-157	82	25	1344	46	5000	0	0	2012-10-18 18:29:33.889842	2012-10-18 18:29:36.05069
51	1-51	40	58	997	6	5000	0	0	2012-10-18 18:29:32.663419	2012-10-18 18:29:36.05069
110	1-110	3	11	5063	12	5000	0	0	2012-10-18 18:29:33.320317	2012-10-18 18:29:36.147004
94	1-94	59	50	586	67	5000	0	0	2012-10-18 18:29:33.142269	2012-10-18 18:29:36.20271
15	1-15	6	28	3753	27	5000	0	0	2012-10-18 18:29:32.260474	2012-10-18 18:29:36.291584
14	1-14	13	26	2844	25	5000	0	0	2012-10-18 18:29:32.249379	2012-10-18 18:29:36.491168
285	1-285	47	13	400	33	5000	0	0	2012-10-18 18:29:36.491168	2012-10-18 18:29:36.491168
39	1-39	31	6	4520	52	5000	0	0	2012-10-18 18:29:32.530048	2012-10-18 18:29:36.513363
57	1-57	6	71	4556	10	5000	0	0	2012-10-18 18:29:32.730254	2012-10-18 18:29:36.513363
286	1-286	80	75	2212	71	5000	0	0	2012-10-18 18:29:36.513363	2012-10-18 18:29:36.513363
249	1-249	58	67	3899	32	5000	0	0	2012-10-18 18:29:35.403674	2012-10-18 18:29:36.524428
171	1-171	84	54	5544	91	5000	0	0	2012-10-18 18:29:34.068285	2012-10-18 18:29:36.724542
165	1-165	28	32	991	52	5000	0	0	2012-10-18 18:29:33.978983	2012-10-18 18:29:36.824476
\.


--
-- Data for Name: towner; Type: TABLE DATA; Schema: public; Owner: olivier
--

COPY towner (id, name, created, updated) FROM stdin;
1	w72	2012-10-18 18:29:32.022375	\N
2	w19	2012-10-18 18:29:32.028248	\N
3	w97	2012-10-18 18:29:32.031691	\N
4	w33	2012-10-18 18:29:32.06063	\N
5	w44	2012-10-18 18:29:32.093767	\N
6	w80	2012-10-18 18:29:32.12708	\N
7	w82	2012-10-18 18:29:32.149455	\N
8	w87	2012-10-18 18:29:32.171539	\N
9	w85	2012-10-18 18:29:32.193604	\N
10	w8	2012-10-18 18:29:32.204785	\N
11	w36	2012-10-18 18:29:32.227094	\N
12	w12	2012-10-18 18:29:32.238221	\N
13	w13	2012-10-18 18:29:32.249379	\N
14	w78	2012-10-18 18:29:32.271741	\N
15	w90	2012-10-18 18:29:32.293929	\N
16	w63	2012-10-18 18:29:32.305055	\N
17	w76	2012-10-18 18:29:32.316208	\N
18	w22	2012-10-18 18:29:32.329302	\N
19	w5	2012-10-18 18:29:32.340386	\N
20	w89	2012-10-18 18:29:32.351541	\N
21	w100	2012-10-18 18:29:32.362666	\N
22	w31	2012-10-18 18:29:32.396136	\N
23	w84	2012-10-18 18:29:32.407208	\N
24	w94	2012-10-18 18:29:32.429477	\N
25	w59	2012-10-18 18:29:32.440683	\N
26	w51	2012-10-18 18:29:32.45195	\N
27	w70	2012-10-18 18:29:32.475066	\N
28	w64	2012-10-18 18:29:32.496335	\N
29	w49	2012-10-18 18:29:32.507415	\N
30	w71	2012-10-18 18:29:32.518573	\N
31	w35	2012-10-18 18:29:32.530048	\N
32	w92	2012-10-18 18:29:32.541067	\N
33	w38	2012-10-18 18:29:32.552344	\N
34	w55	2012-10-18 18:29:32.563123	\N
35	w3	2012-10-18 18:29:32.585501	\N
36	w48	2012-10-18 18:29:32.607796	\N
37	w53	2012-10-18 18:29:32.618866	\N
38	w11	2012-10-18 18:29:32.630072	\N
39	w91	2012-10-18 18:29:32.64117	\N
40	w74	2012-10-18 18:29:32.663419	\N
41	w4	2012-10-18 18:29:32.674586	\N
42	w60	2012-10-18 18:29:32.685707	\N
43	w68	2012-10-18 18:29:32.708002	\N
44	w65	2012-10-18 18:29:32.741422	\N
45	w54	2012-10-18 18:29:32.7748	\N
46	w16	2012-10-18 18:29:32.785919	\N
47	w81	2012-10-18 18:29:32.797056	\N
48	w88	2012-10-18 18:29:32.841588	\N
49	w99	2012-10-18 18:29:32.852727	\N
50	w50	2012-10-18 18:29:32.908387	\N
51	w14	2012-10-18 18:29:32.964118	\N
52	w42	2012-10-18 18:29:33.008647	\N
53	w26	2012-10-18 18:29:33.042138	\N
54	w95	2012-10-18 18:29:33.053363	\N
55	w62	2012-10-18 18:29:33.064261	\N
56	w37	2012-10-18 18:29:33.086521	\N
57	w45	2012-10-18 18:29:33.097671	\N
58	w73	2012-10-18 18:29:33.108763	\N
59	w69	2012-10-18 18:29:33.131013	\N
60	w52	2012-10-18 18:29:33.153395	\N
61	w96	2012-10-18 18:29:33.175635	\N
62	w18	2012-10-18 18:29:33.209025	\N
63	w2	2012-10-18 18:29:33.264615	\N
64	w1	2012-10-18 18:29:33.286942	\N
65	w29	2012-10-18 18:29:33.29806	\N
66	w43	2012-10-18 18:29:33.309228	\N
67	w79	2012-10-18 18:29:33.353691	\N
68	w57	2012-10-18 18:29:33.420528	\N
69	w83	2012-10-18 18:29:33.431693	\N
70	w98	2012-10-18 18:29:33.465029	\N
71	w17	2012-10-18 18:29:33.509408	\N
72	w32	2012-10-18 18:29:33.520682	\N
73	w21	2012-10-18 18:29:33.609808	\N
74	w30	2012-10-18 18:29:33.665384	\N
75	w25	2012-10-18 18:29:33.683059	\N
76	w9	2012-10-18 18:29:33.700622	\N
77	w66	2012-10-18 18:29:33.745094	\N
78	w86	2012-10-18 18:29:33.767404	\N
79	w77	2012-10-18 18:29:33.789628	\N
80	w28	2012-10-18 18:29:33.834141	\N
81	w58	2012-10-18 18:29:33.845359	\N
82	w47	2012-10-18 18:29:33.889842	\N
83	w34	2012-10-18 18:29:33.934364	\N
84	w75	2012-10-18 18:29:34.0012	\N
85	w67	2012-10-18 18:29:34.112507	\N
86	w40	2012-10-18 18:29:34.123601	\N
87	w6	2012-10-18 18:29:34.190539	\N
88	w24	2012-10-18 18:29:34.212744	\N
89	w7	2012-10-18 18:29:34.290664	\N
90	w41	2012-10-18 18:29:34.357413	\N
91	w46	2012-10-18 18:29:34.39077	\N
92	w56	2012-10-18 18:29:34.579617	\N
93	w27	2012-10-18 18:29:34.590776	\N
94	w23	2012-10-18 18:29:34.890838	\N
95	w10	2012-10-18 18:29:35.090787	\N
96	w61	2012-10-18 18:29:35.235167	\N
97	w20	2012-10-18 18:29:35.858873	\N
\.


--
-- Data for Name: tquality; Type: TABLE DATA; Schema: public; Owner: olivier
--

COPY tquality (id, name, idd, depository, qtt, created, updated) FROM stdin;
1	user0/q9	1	user0	5000	2012-10-18 18:29:32.022375	2012-10-18 18:29:32.022375
4	user0/q6	1	user0	0	2012-10-18 18:29:32.028248	\N
36	user2/q23	3	user2	25000	2012-10-18 18:29:32.316208	2012-10-18 18:29:35.547872
29	user0/q14	1	user0	10000	2012-10-18 18:29:32.271741	2012-10-18 18:29:35.592175
90	user2/q31	3	user2	10000	2012-10-18 18:29:33.175635	2012-10-18 18:29:35.381358
82	user1/q16	2	user1	10000	2012-10-18 18:29:32.93059	2012-10-18 18:29:33.945526
13	user0/q7	1	user0	25000	2012-10-18 18:29:32.149455	2012-10-18 18:29:35.736391
15	user2/q4	3	user2	5000	2012-10-18 18:29:32.171539	2012-10-18 18:29:32.171539
42	user1/q29	2	user1	10000	2012-10-18 18:29:32.362666	2012-10-18 18:29:36.746629
63	user0/q32	1	user0	10000	2012-10-18 18:29:32.64117	2012-10-18 18:29:34.045653
56	user2/q6	3	user2	10000	2012-10-18 18:29:32.552344	2012-10-18 18:29:33.834141
46	user0/q22	1	user0	20000	2012-10-18 18:29:32.407208	2012-10-18 18:29:33.889842
24	user1/q23	2	user1	0	2012-10-18 18:29:32.238221	\N
89	user1/q14	2	user1	5000	2012-10-18 18:29:33.119923	2012-10-18 18:29:34.713125
87	user2/q5	3	user2	20000	2012-10-18 18:29:33.086521	2012-10-18 18:29:33.800776
18	user0/q19	1	user0	20000	2012-10-18 18:29:32.204785	2012-10-18 18:29:35.814556
78	user2/q3	3	user2	10000	2012-10-18 18:29:32.830445	2012-10-18 18:29:36.802195
28	user0/q2	1	user0	15000	2012-10-18 18:29:32.260474	2012-10-18 18:29:36.291584
40	user2/q0	3	user2	0	2012-10-18 18:29:32.340386	\N
6	user1/q31	2	user1	25000	2012-10-18 18:29:32.031691	2012-10-18 18:29:35.246301
81	user2/q16	3	user2	15000	2012-10-18 18:29:32.919455	2012-10-18 18:29:33.542934
32	user1/q4	2	user1	20000	2012-10-18 18:29:32.293929	2012-10-18 18:29:36.824476
34	user0/q0	1	user0	30000	2012-10-18 18:29:32.305055	2012-10-18 18:29:36.713573
19	user1/q12	2	user1	15000	2012-10-18 18:29:32.204785	2012-10-18 18:29:36.26922
3	user2/q25	3	user2	20000	2012-10-18 18:29:32.028248	2012-10-18 18:29:35.758602
58	user2/q20	3	user2	10000	2012-10-18 18:29:32.574345	2012-10-18 18:29:36.524428
77	user1/q25	2	user1	30000	2012-10-18 18:29:32.830445	2012-10-18 18:29:36.879832
67	user0/q17	1	user0	20000	2012-10-18 18:29:32.685707	2012-10-18 18:29:34.123601
43	user0/q21	1	user0	5000	2012-10-18 18:29:32.362666	2012-10-18 18:29:33.209025
5	user1/q8	2	user1	25000	2012-10-18 18:29:32.031691	2012-10-18 18:29:35.179732
17	user2/q29	3	user2	20000	2012-10-18 18:29:32.193604	2012-10-18 18:29:36.724542
83	user0/q20	1	user0	5000	2012-10-18 18:29:32.93059	2012-10-18 18:29:34.335143
41	user2/q11	3	user2	15000	2012-10-18 18:29:32.351541	2012-10-18 18:29:35.61434
14	user1/q15	2	user1	20000	2012-10-18 18:29:32.149455	2012-10-18 18:29:34.012323
21	user1/q27	2	user1	10000	2012-10-18 18:29:32.227094	2012-10-18 18:29:32.563123
22	user2/q32	3	user2	15000	2012-10-18 18:29:32.227094	2012-10-18 18:29:35.825639
33	user1/q22	2	user1	5000	2012-10-18 18:29:32.293929	2012-10-18 18:29:36.491168
31	user2/q18	3	user2	10000	2012-10-18 18:29:32.282842	2012-10-18 18:29:34.435092
66	user2/q24	3	user2	25000	2012-10-18 18:29:32.685707	2012-10-18 18:29:33.900981
26	user0/q28	1	user0	10000	2012-10-18 18:29:32.249379	2012-10-18 18:29:36.05069
50	user0/q24	1	user0	10000	2012-10-18 18:29:32.440683	2012-10-18 18:29:34.079213
55	user2/q7	3	user2	20000	2012-10-18 18:29:32.541067	2012-10-18 18:29:35.268584
10	user1/q2	2	user1	35000	2012-10-18 18:29:32.093767	2012-10-18 18:29:36.324922
7	user0/q1	1	user0	20000	2012-10-18 18:29:32.06063	2012-10-18 18:29:32.674586
70	user2/q30	3	user2	10000	2012-10-18 18:29:32.719176	2012-10-18 18:29:33.643141
23	user0/q4	1	user0	15000	2012-10-18 18:29:32.238221	2012-10-18 18:29:36.20271
47	user2/q2	3	user2	35000	2012-10-18 18:29:32.418376	2012-10-18 18:29:34.857469
64	user0/q13	1	user0	30000	2012-10-18 18:29:32.64117	2012-10-18 18:29:35.514665
37	user0/q10	1	user0	25000	2012-10-18 18:29:32.316208	2012-10-18 18:29:36.369305
80	user1/q10	2	user1	10000	2012-10-18 18:29:32.874962	2012-10-18 18:29:34.357413
39	user0/q26	1	user0	15000	2012-10-18 18:29:32.340386	2012-10-18 18:29:35.212976
76	user2/q10	3	user2	5000	2012-10-18 18:29:32.819261	2012-10-18 18:29:34.590776
74	user1/q17	2	user1	10000	2012-10-18 18:29:32.763655	2012-10-18 18:29:32.863907
52	user1/q11	2	user1	15000	2012-10-18 18:29:32.496335	2012-10-18 18:29:33.978983
69	user2/q15	3	user2	20000	2012-10-18 18:29:32.708002	2012-10-18 18:29:35.681224
57	user1/q21	2	user1	35000	2012-10-18 18:29:32.552344	2012-10-18 18:29:35.348152
38	user1/q24	2	user1	10000	2012-10-18 18:29:32.329302	2012-10-18 18:29:34.457281
84	user0/q27	1	user0	0	2012-10-18 18:29:32.964118	\N
61	user1/q18	2	user1	10000	2012-10-18 18:29:32.630072	2012-10-18 18:29:34.835174
85	user1/q7	2	user1	0	2012-10-18 18:29:32.975172	\N
9	user2/q13	3	user2	10000	2012-10-18 18:29:32.093767	2012-10-18 18:29:32.986345
94	user1/q30	2	user1	5000	2012-10-18 18:29:33.375962	2012-10-18 18:29:35.04637
86	user0/q15	1	user0	5000	2012-10-18 18:29:33.008647	2012-10-18 18:29:33.008647
88	user0/q5	1	user0	15000	2012-10-18 18:29:33.108763	2012-10-18 18:29:34.579617
16	user1/q3	2	user1	20000	2012-10-18 18:29:32.193604	2012-10-18 18:29:36.580013
92	user2/q26	3	user2	15000	2012-10-18 18:29:33.25348	2012-10-18 18:29:36.235863
35	user1/q13	2	user1	30000	2012-10-18 18:29:32.305055	2012-10-18 18:29:36.413666
54	user0/q29	1	user0	30000	2012-10-18 18:29:32.507415	2012-10-18 18:29:35.869993
49	user1/q6	2	user1	15000	2012-10-18 18:29:32.429477	2012-10-18 18:29:35.692316
62	user1/q5	2	user1	5000	2012-10-18 18:29:32.630072	2012-10-18 18:29:34.602128
91	user1/q26	2	user1	10000	2012-10-18 18:29:33.231253	2012-10-18 18:29:34.068285
20	user2/q21	3	user2	25000	2012-10-18 18:29:32.216014	2012-10-18 18:29:36.657914
93	user0/q23	1	user0	10000	2012-10-18 18:29:33.309228	2012-10-18 18:29:34.468404
60	user2/q1	3	user2	25000	2012-10-18 18:29:32.618866	2012-10-18 18:29:36.096037
79	user0/q11	1	user0	20000	2012-10-18 18:29:32.874962	2012-10-18 18:29:35.459005
59	user0/q30	1	user0	15000	2012-10-18 18:29:32.607796	2012-10-18 18:29:35.124267
12	user2/q28	3	user2	10000	2012-10-18 18:29:32.12708	2012-10-18 18:29:34.0012
75	user2/q17	3	user2	20000	2012-10-18 18:29:32.819261	2012-10-18 18:29:34.145898
73	user2/q9	3	user2	10000	2012-10-18 18:29:32.75255	2012-10-18 18:29:34.212744
30	user2/q27	3	user2	15000	2012-10-18 18:29:32.282842	2012-10-18 18:29:34.301761
8	user0/q8	1	user0	15000	2012-10-18 18:29:32.06063	2012-10-18 18:29:34.368513
27	user1/q0	2	user1	30000	2012-10-18 18:29:32.260474	2012-10-18 18:29:36.147004
65	user1/q28	2	user1	15000	2012-10-18 18:29:32.652343	2012-10-18 18:29:34.668688
44	user2/q8	3	user2	25000	2012-10-18 18:29:32.384932	2012-10-18 18:29:35.914199
68	user1/q1	2	user1	20000	2012-10-18 18:29:32.696837	2012-10-18 18:29:34.779634
2	user0/q18	1	user0	10000	2012-10-18 18:29:32.022375	2012-10-18 18:29:34.846343
45	user2/q19	3	user2	10000	2012-10-18 18:29:32.384932	2012-10-18 18:29:35.157532
53	user0/q25	1	user0	25000	2012-10-18 18:29:32.507415	2012-10-18 18:29:36.435859
48	user0/q31	1	user0	5000	2012-10-18 18:29:32.418376	2012-10-18 18:29:36.757828
72	user0/q16	1	user0	25000	2012-10-18 18:29:32.741422	2012-10-18 18:29:36.835444
51	user0/q12	1	user0	5000	2012-10-18 18:29:32.45195	2012-10-18 18:29:35.312878
71	user0/q3	1	user0	30000	2012-10-18 18:29:32.730254	2012-10-18 18:29:36.513363
95	user1/q19	2	user1	15000	2012-10-18 18:29:33.431693	2012-10-18 18:29:34.935323
98	user1/q9	2	user1	10000	2012-10-18 18:29:33.87873	2012-10-18 18:29:35.001943
96	user2/q12	3	user2	5000	2012-10-18 18:29:33.431693	2012-10-18 18:29:35.079708
11	user1/q32	2	user1	25000	2012-10-18 18:29:32.12708	2012-10-18 18:29:35.792115
97	user2/q22	3	user2	5000	2012-10-18 18:29:33.77853	2012-10-18 18:29:36.846597
25	user2/q14	3	user2	25000	2012-10-18 18:29:32.249379	2012-10-18 18:29:36.30278
\.


--
-- Data for Name: tquote; Type: TABLE DATA; Schema: public; Owner: olivier
--

COPY tquote (id, own, nr, qtt_requ, np, qtt_prov, qtt_in, qtt_out, flows, created, removed) FROM stdin;
\.


--
-- Data for Name: tquoteremoved; Type: TABLE DATA; Schema: public; Owner: olivier
--

COPY tquoteremoved (id, own, nr, qtt_requ, np, qtt_prov, qtt_in, qtt_out, flows, created, removed) FROM stdin;
\.


--
-- Data for Name: treltried; Type: TABLE DATA; Schema: public; Owner: olivier
--

COPY treltried (np, nr, cnt) FROM stdin;
70	66	2
74	14	3
45	74	3
9	10	2
29	9	2
44	45	2
37	22	2
74	34	2
10	12	2
34	8	2
19	34	2
18	19	2
53	74	2
38	96	2
8	55	2
32	75	3
68	14	4
73	68	4
39	69	2
14	39	2
18	68	2
35	18	3
53	37	3
72	38	2
11	65	3
89	53	6
91	12	2
65	91	2
43	6	2
42	43	2
57	42	2
56	57	2
6	56	2
10	49	2
98	73	4
63	89	3
96	72	2
19	63	4
69	72	3
88	69	2
25	88	2
49	71	4
27	28	4
64	34	2
30	64	3
66	30	3
12	76	2
72	70	3
9	23	2
44	46	2
54	91	2
8	62	2
62	8	2
22	98	3
17	22	3
71	17	3
54	98	3
83	61	2
82	83	2
28	82	2
53	49	2
35	59	5
61	80	2
16	17	4
2	16	4
55	89	4
72	55	2
64	72	3
54	63	2
28	53	2
26	52	4
34	35	4
25	55	4
49	35	4
66	67	2
59	66	3
50	2	2
80	27	3
7	55	2
50	9	2
3	37	2
87	3	2
8	87	2
7	8	2
37	7	3
67	50	2
20	2	2
14	20	2
79	80	2
11	13	2
75	29	3
45	75	2
59	45	3
11	34	2
12	11	5
29	2	2
71	13	3
13	71	2
72	49	5
55	72	4
57	79	2
36	57	2
14	49	3
15	12	2
86	15	2
13	86	2
94	50	2
63	64	3
98	19	2
53	54	3
71	94	2
77	19	3
64	77	3
22	64	2
26	36	2
91	54	3
70	12	3
25	26	5
46	25	3
71	25	4
65	32	3
44	25	4
76	44	6
49	76	5
58	49	3
6	58	2
27	70	2
30	65	2
79	30	2
23	79	2
28	75	2
47	10	2
81	47	2
6	81	2
52	6	3
68	10	3
35	68	2
75	35	2
27	71	4
59	27	6
17	59	6
46	17	3
52	46	4
75	41	5
71	75	4
41	52	6
32	33	3
10	32	2
13	10	4
33	13	3
10	71	5
32	41	2
67	58	3
32	67	3
58	52	2
13	17	2
14	13	2
17	91	2
52	32	5
\.


--
-- Data for Name: tuser; Type: TABLE DATA; Schema: public; Owner: olivier
--

COPY tuser (id, name, spent, quota, last_in, created, updated) FROM stdin;
4	user3	0	0	\N	2012-10-18 18:29:11.41629	\N
5	user4	0	0	\N	2012-10-18 18:29:11.427327	\N
6	user5	0	0	\N	2012-10-18 18:29:11.438387	\N
7	user6	0	0	\N	2012-10-18 18:29:11.449456	\N
8	user7	0	0	\N	2012-10-18 18:29:11.460456	\N
9	user8	0	0	\N	2012-10-18 18:29:11.471637	\N
10	user9	0	0	\N	2012-10-18 18:29:11.482551	\N
1	user0	241992	0	2012-10-18 18:29:36.835444	2012-10-18 18:29:11.36831	2012-10-18 18:29:36.835444
3	user2	93647	0	2012-10-18 18:29:36.846597	2012-10-18 18:29:11.405176	2012-10-18 18:29:36.846597
2	user1	183641	0	2012-10-18 18:29:36.879832	2012-10-18 18:29:11.394221	2012-10-18 18:29:36.879832
\.


--
-- Name: tconst_pkey; Type: CONSTRAINT; Schema: public; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY tconst
    ADD CONSTRAINT tconst_pkey PRIMARY KEY (name);


--
-- Name: tmarket_id_key; Type: CONSTRAINT; Schema: public; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY tmarket
    ADD CONSTRAINT tmarket_id_key UNIQUE (id);


--
-- Name: tmvt_id_key; Type: CONSTRAINT; Schema: public; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY tmvt
    ADD CONSTRAINT tmvt_id_key UNIQUE (id);


--
-- Name: tmvt_uuid_key; Type: CONSTRAINT; Schema: public; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY tmvt
    ADD CONSTRAINT tmvt_uuid_key UNIQUE (uuid);


--
-- Name: tmvtremoved_uuid_key; Type: CONSTRAINT; Schema: public; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY tmvtremoved
    ADD CONSTRAINT tmvtremoved_uuid_key UNIQUE (uuid);


--
-- Name: torder_pkey; Type: CONSTRAINT; Schema: public; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY torder
    ADD CONSTRAINT torder_pkey PRIMARY KEY (id);


--
-- Name: torder_uuid_key; Type: CONSTRAINT; Schema: public; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY torder
    ADD CONSTRAINT torder_uuid_key UNIQUE (uuid);


--
-- Name: torderremoved_pkey; Type: CONSTRAINT; Schema: public; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY torderremoved
    ADD CONSTRAINT torderremoved_pkey PRIMARY KEY (uuid);


--
-- Name: towner_name_key; Type: CONSTRAINT; Schema: public; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY towner
    ADD CONSTRAINT towner_name_key UNIQUE (name);


--
-- Name: towner_pkey; Type: CONSTRAINT; Schema: public; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY towner
    ADD CONSTRAINT towner_pkey PRIMARY KEY (id);


--
-- Name: tquality_name_key; Type: CONSTRAINT; Schema: public; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY tquality
    ADD CONSTRAINT tquality_name_key UNIQUE (name);


--
-- Name: tquality_pkey; Type: CONSTRAINT; Schema: public; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY tquality
    ADD CONSTRAINT tquality_pkey PRIMARY KEY (id);


--
-- Name: tquote_pkey; Type: CONSTRAINT; Schema: public; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY tquote
    ADD CONSTRAINT tquote_pkey PRIMARY KEY (id);


--
-- Name: treltried_pkey; Type: CONSTRAINT; Schema: public; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY treltried
    ADD CONSTRAINT treltried_pkey PRIMARY KEY (np, nr);


--
-- Name: tuser_id_key; Type: CONSTRAINT; Schema: public; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY tuser
    ADD CONSTRAINT tuser_id_key UNIQUE (id);


--
-- Name: tuser_pkey; Type: CONSTRAINT; Schema: public; Owner: olivier; Tablespace: 
--

ALTER TABLE ONLY tuser
    ADD CONSTRAINT tuser_pkey PRIMARY KEY (name);


--
-- Name: tmvt_did_idx; Type: INDEX; Schema: public; Owner: olivier; Tablespace: 
--

CREATE INDEX tmvt_did_idx ON tmvt USING btree (grp);


--
-- Name: tmvt_nat_idx; Type: INDEX; Schema: public; Owner: olivier; Tablespace: 
--

CREATE INDEX tmvt_nat_idx ON tmvt USING btree (nat);


--
-- Name: tmvt_own_dst_idx; Type: INDEX; Schema: public; Owner: olivier; Tablespace: 
--

CREATE INDEX tmvt_own_dst_idx ON tmvt USING btree (own_dst);


--
-- Name: tmvt_own_src_idx; Type: INDEX; Schema: public; Owner: olivier; Tablespace: 
--

CREATE INDEX tmvt_own_src_idx ON tmvt USING btree (own_src);


--
-- Name: torder_np_idx; Type: INDEX; Schema: public; Owner: olivier; Tablespace: 
--

CREATE INDEX torder_np_idx ON torder USING btree (np);


--
-- Name: torder_nr_idx; Type: INDEX; Schema: public; Owner: olivier; Tablespace: 
--

CREATE INDEX torder_nr_idx ON torder USING btree (nr);


--
-- Name: towner_name_idx; Type: INDEX; Schema: public; Owner: olivier; Tablespace: 
--

CREATE INDEX towner_name_idx ON towner USING btree (name);


--
-- Name: tquality_name_idx; Type: INDEX; Schema: public; Owner: olivier; Tablespace: 
--

CREATE INDEX tquality_name_idx ON tquality USING btree (name);


--
-- Name: _RETURN; Type: RULE; Schema: public; Owner: olivier
--

CREATE RULE "_RETURN" AS ON SELECT TO vstat DO INSTEAD SELECT q.name, (sum(d.qtt) - (q.qtt)::numeric) AS delta, q.qtt AS qtt_quality, sum(d.qtt) AS qtt_detail FROM ((SELECT vorderverif.np AS nat, vorderverif.qtt FROM vorderverif UNION ALL SELECT vmvtverif.nat, vmvtverif.qtt FROM vmvtverif) d JOIN tquality q ON ((d.nat = q.id))) GROUP BY q.id ORDER BY q.name;
ALTER VIEW vstat SET ();


--
-- Name: trig_befa_towner; Type: TRIGGER; Schema: public; Owner: olivier
--

CREATE TRIGGER trig_befa_towner BEFORE INSERT OR UPDATE ON towner FOR EACH ROW EXECUTE PROCEDURE ftime_updated();


--
-- Name: trig_befa_tquality; Type: TRIGGER; Schema: public; Owner: olivier
--

CREATE TRIGGER trig_befa_tquality BEFORE INSERT OR UPDATE ON tquality FOR EACH ROW EXECUTE PROCEDURE ftime_updated();


--
-- Name: trig_befa_tuser; Type: TRIGGER; Schema: public; Owner: olivier
--

CREATE TRIGGER trig_befa_tuser BEFORE INSERT OR UPDATE ON tuser FOR EACH ROW EXECUTE PROCEDURE ftime_updated();


--
-- Name: creltried_np; Type: FK CONSTRAINT; Schema: public; Owner: olivier
--

ALTER TABLE ONLY treltried
    ADD CONSTRAINT creltried_np FOREIGN KEY (np) REFERENCES tquality(id);


--
-- Name: creltried_nr; Type: FK CONSTRAINT; Schema: public; Owner: olivier
--

ALTER TABLE ONLY treltried
    ADD CONSTRAINT creltried_nr FOREIGN KEY (nr) REFERENCES tquality(id);


--
-- Name: ctmvt_nat; Type: FK CONSTRAINT; Schema: public; Owner: olivier
--

ALTER TABLE ONLY tmvt
    ADD CONSTRAINT ctmvt_nat FOREIGN KEY (nat) REFERENCES tquality(id);


--
-- Name: ctmvt_own_dst; Type: FK CONSTRAINT; Schema: public; Owner: olivier
--

ALTER TABLE ONLY tmvt
    ADD CONSTRAINT ctmvt_own_dst FOREIGN KEY (own_dst) REFERENCES towner(id);


--
-- Name: ctmvt_own_src; Type: FK CONSTRAINT; Schema: public; Owner: olivier
--

ALTER TABLE ONLY tmvt
    ADD CONSTRAINT ctmvt_own_src FOREIGN KEY (own_src) REFERENCES towner(id);


--
-- Name: ctorder_np; Type: FK CONSTRAINT; Schema: public; Owner: olivier
--

ALTER TABLE ONLY torder
    ADD CONSTRAINT ctorder_np FOREIGN KEY (np) REFERENCES tquality(id);


--
-- Name: ctorder_nr; Type: FK CONSTRAINT; Schema: public; Owner: olivier
--

ALTER TABLE ONLY torder
    ADD CONSTRAINT ctorder_nr FOREIGN KEY (nr) REFERENCES tquality(id);


--
-- Name: ctorder_own; Type: FK CONSTRAINT; Schema: public; Owner: olivier
--

ALTER TABLE ONLY torder
    ADD CONSTRAINT ctorder_own FOREIGN KEY (own) REFERENCES towner(id);


--
-- Name: ctquality_depository; Type: FK CONSTRAINT; Schema: public; Owner: olivier
--

ALTER TABLE ONLY tquality
    ADD CONSTRAINT ctquality_depository FOREIGN KEY (depository) REFERENCES tuser(name);


--
-- Name: ctquality_idd; Type: FK CONSTRAINT; Schema: public; Owner: olivier
--

ALTER TABLE ONLY tquality
    ADD CONSTRAINT ctquality_idd FOREIGN KEY (idd) REFERENCES tuser(id);


--
-- Name: tmvtremoved_nat_fkey; Type: FK CONSTRAINT; Schema: public; Owner: olivier
--

ALTER TABLE ONLY tmvtremoved
    ADD CONSTRAINT tmvtremoved_nat_fkey FOREIGN KEY (nat) REFERENCES tquality(id);


--
-- Name: tmvtremoved_own_dst_fkey; Type: FK CONSTRAINT; Schema: public; Owner: olivier
--

ALTER TABLE ONLY tmvtremoved
    ADD CONSTRAINT tmvtremoved_own_dst_fkey FOREIGN KEY (own_dst) REFERENCES towner(id);


--
-- Name: tmvtremoved_own_src_fkey; Type: FK CONSTRAINT; Schema: public; Owner: olivier
--

ALTER TABLE ONLY tmvtremoved
    ADD CONSTRAINT tmvtremoved_own_src_fkey FOREIGN KEY (own_src) REFERENCES towner(id);


--
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- Name: fchangestatemarket(boolean); Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON FUNCTION fchangestatemarket(_execute boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION fchangestatemarket(_execute boolean) FROM olivier;
GRANT ALL ON FUNCTION fchangestatemarket(_execute boolean) TO olivier;
GRANT ALL ON FUNCTION fchangestatemarket(_execute boolean) TO PUBLIC;
GRANT ALL ON FUNCTION fchangestatemarket(_execute boolean) TO admin;


--
-- Name: fcreateuser(text); Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON FUNCTION fcreateuser(_name text) FROM PUBLIC;
REVOKE ALL ON FUNCTION fcreateuser(_name text) FROM olivier;
GRANT ALL ON FUNCTION fcreateuser(_name text) TO olivier;
GRANT ALL ON FUNCTION fcreateuser(_name text) TO PUBLIC;
GRANT ALL ON FUNCTION fcreateuser(_name text) TO admin;


--
-- Name: fexecquote(text, integer); Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON FUNCTION fexecquote(_owner text, _idquote integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION fexecquote(_owner text, _idquote integer) FROM olivier;
GRANT ALL ON FUNCTION fexecquote(_owner text, _idquote integer) TO olivier;
GRANT ALL ON FUNCTION fexecquote(_owner text, _idquote integer) TO PUBLIC;
GRANT ALL ON FUNCTION fexecquote(_owner text, _idquote integer) TO client_opened_role;


--
-- Name: fgeterrs(boolean); Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON FUNCTION fgeterrs(_details boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION fgeterrs(_details boolean) FROM olivier;
GRANT ALL ON FUNCTION fgeterrs(_details boolean) TO olivier;
GRANT ALL ON FUNCTION fgeterrs(_details boolean) TO PUBLIC;
GRANT ALL ON FUNCTION fgeterrs(_details boolean) TO admin;


--
-- Name: fgetprequote(text, text, bigint, text); Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON FUNCTION fgetprequote(_owner text, _qualityprovided text, _qttprovided bigint, _qualityrequired text) FROM PUBLIC;
REVOKE ALL ON FUNCTION fgetprequote(_owner text, _qualityprovided text, _qttprovided bigint, _qualityrequired text) FROM olivier;
GRANT ALL ON FUNCTION fgetprequote(_owner text, _qualityprovided text, _qttprovided bigint, _qualityrequired text) TO olivier;
GRANT ALL ON FUNCTION fgetprequote(_owner text, _qualityprovided text, _qttprovided bigint, _qualityrequired text) TO PUBLIC;
GRANT ALL ON FUNCTION fgetprequote(_owner text, _qualityprovided text, _qttprovided bigint, _qualityrequired text) TO client_opened_role;


--
-- Name: tquote; Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON TABLE tquote FROM PUBLIC;
REVOKE ALL ON TABLE tquote FROM olivier;
GRANT ALL ON TABLE tquote TO olivier;
GRANT SELECT ON TABLE tquote TO client_opened_role;
GRANT SELECT ON TABLE tquote TO client_stopping_role;
GRANT SELECT ON TABLE tquote TO admin;


--
-- Name: fgetquote(text, text, bigint, bigint, text); Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON FUNCTION fgetquote(_owner text, _qualityprovided text, _qttprovided bigint, _qttrequired bigint, _qualityrequired text) FROM PUBLIC;
REVOKE ALL ON FUNCTION fgetquote(_owner text, _qualityprovided text, _qttprovided bigint, _qttrequired bigint, _qualityrequired text) FROM olivier;
GRANT ALL ON FUNCTION fgetquote(_owner text, _qualityprovided text, _qttprovided bigint, _qttrequired bigint, _qualityrequired text) TO olivier;
GRANT ALL ON FUNCTION fgetquote(_owner text, _qualityprovided text, _qttprovided bigint, _qttrequired bigint, _qualityrequired text) TO PUBLIC;
GRANT ALL ON FUNCTION fgetquote(_owner text, _qualityprovided text, _qttprovided bigint, _qttrequired bigint, _qualityrequired text) TO client_opened_role;


--
-- Name: fgetstats(boolean); Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON FUNCTION fgetstats(_details boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION fgetstats(_details boolean) FROM olivier;
GRANT ALL ON FUNCTION fgetstats(_details boolean) TO olivier;
GRANT ALL ON FUNCTION fgetstats(_details boolean) TO PUBLIC;
GRANT ALL ON FUNCTION fgetstats(_details boolean) TO admin;


--
-- Name: torder; Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON TABLE torder FROM PUBLIC;
REVOKE ALL ON TABLE torder FROM olivier;
GRANT ALL ON TABLE torder TO olivier;
GRANT SELECT ON TABLE torder TO client_opened_role;
GRANT SELECT ON TABLE torder TO client_stopping_role;
GRANT SELECT ON TABLE torder TO admin;


--
-- Name: finsertorder(text, text, bigint, bigint, text); Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON FUNCTION finsertorder(_owner text, _qualityprovided text, _qttprovided bigint, _qttrequired bigint, _qualityrequired text) FROM PUBLIC;
REVOKE ALL ON FUNCTION finsertorder(_owner text, _qualityprovided text, _qttprovided bigint, _qttrequired bigint, _qualityrequired text) FROM olivier;
GRANT ALL ON FUNCTION finsertorder(_owner text, _qualityprovided text, _qttprovided bigint, _qttrequired bigint, _qualityrequired text) TO olivier;
GRANT ALL ON FUNCTION finsertorder(_owner text, _qualityprovided text, _qttprovided bigint, _qttrequired bigint, _qualityrequired text) TO PUBLIC;
GRANT ALL ON FUNCTION finsertorder(_owner text, _qualityprovided text, _qttprovided bigint, _qttrequired bigint, _qualityrequired text) TO client_opened_role;


--
-- Name: fremovemvt(text); Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON FUNCTION fremovemvt(_uuid text) FROM PUBLIC;
REVOKE ALL ON FUNCTION fremovemvt(_uuid text) FROM olivier;
GRANT ALL ON FUNCTION fremovemvt(_uuid text) TO olivier;
GRANT ALL ON FUNCTION fremovemvt(_uuid text) TO PUBLIC;
GRANT ALL ON FUNCTION fremovemvt(_uuid text) TO client_opened_role;
GRANT ALL ON FUNCTION fremovemvt(_uuid text) TO client_stopping_role;


--
-- Name: towner; Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON TABLE towner FROM PUBLIC;
REVOKE ALL ON TABLE towner FROM olivier;
GRANT ALL ON TABLE towner TO olivier;
GRANT SELECT ON TABLE towner TO client_opened_role;
GRANT SELECT ON TABLE towner TO client_stopping_role;
GRANT SELECT ON TABLE towner TO admin;


--
-- Name: tquality; Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON TABLE tquality FROM PUBLIC;
REVOKE ALL ON TABLE tquality FROM olivier;
GRANT ALL ON TABLE tquality TO olivier;
GRANT SELECT ON TABLE tquality TO client_opened_role;
GRANT SELECT ON TABLE tquality TO client_stopping_role;
GRANT SELECT ON TABLE tquality TO admin;


--
-- Name: vorder; Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON TABLE vorder FROM PUBLIC;
REVOKE ALL ON TABLE vorder FROM olivier;
GRANT ALL ON TABLE vorder TO olivier;
GRANT SELECT ON TABLE vorder TO client_opened_role;
GRANT SELECT ON TABLE vorder TO client_stopping_role;
GRANT SELECT ON TABLE vorder TO admin;


--
-- Name: fremoveorder(text); Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON FUNCTION fremoveorder(_uuid text) FROM PUBLIC;
REVOKE ALL ON FUNCTION fremoveorder(_uuid text) FROM olivier;
GRANT ALL ON FUNCTION fremoveorder(_uuid text) TO olivier;
GRANT ALL ON FUNCTION fremoveorder(_uuid text) TO PUBLIC;
GRANT ALL ON FUNCTION fremoveorder(_uuid text) TO client_opened_role;
GRANT ALL ON FUNCTION fremoveorder(_uuid text) TO client_stopping_role;


--
-- Name: tmvt; Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON TABLE tmvt FROM PUBLIC;
REVOKE ALL ON TABLE tmvt FROM olivier;
GRANT ALL ON TABLE tmvt TO olivier;
GRANT SELECT ON TABLE tmvt TO client_opened_role;
GRANT SELECT ON TABLE tmvt TO client_stopping_role;
GRANT SELECT ON TABLE tmvt TO admin;


--
-- Name: tconst; Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON TABLE tconst FROM PUBLIC;
REVOKE ALL ON TABLE tconst FROM olivier;
GRANT ALL ON TABLE tconst TO olivier;
GRANT SELECT ON TABLE tconst TO client_opened_role;
GRANT SELECT ON TABLE tconst TO client_stopping_role;
GRANT SELECT ON TABLE tconst TO admin;


--
-- Name: tmarket; Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON TABLE tmarket FROM PUBLIC;
REVOKE ALL ON TABLE tmarket FROM olivier;
GRANT ALL ON TABLE tmarket TO olivier;
GRANT SELECT ON TABLE tmarket TO client_opened_role;
GRANT SELECT ON TABLE tmarket TO client_stopping_role;
GRANT SELECT ON TABLE tmarket TO admin;


--
-- Name: tmvtremoved; Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON TABLE tmvtremoved FROM PUBLIC;
REVOKE ALL ON TABLE tmvtremoved FROM olivier;
GRANT ALL ON TABLE tmvtremoved TO olivier;
GRANT SELECT ON TABLE tmvtremoved TO client_opened_role;
GRANT SELECT ON TABLE tmvtremoved TO client_stopping_role;
GRANT SELECT ON TABLE tmvtremoved TO admin;


--
-- Name: torderremoved; Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON TABLE torderremoved FROM PUBLIC;
REVOKE ALL ON TABLE torderremoved FROM olivier;
GRANT ALL ON TABLE torderremoved TO olivier;
GRANT SELECT ON TABLE torderremoved TO client_opened_role;
GRANT SELECT ON TABLE torderremoved TO client_stopping_role;
GRANT SELECT ON TABLE torderremoved TO admin;


--
-- Name: tquoteremoved; Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON TABLE tquoteremoved FROM PUBLIC;
REVOKE ALL ON TABLE tquoteremoved FROM olivier;
GRANT ALL ON TABLE tquoteremoved TO olivier;
GRANT SELECT ON TABLE tquoteremoved TO client_opened_role;
GRANT SELECT ON TABLE tquoteremoved TO client_stopping_role;
GRANT SELECT ON TABLE tquoteremoved TO admin;


--
-- Name: tuser; Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON TABLE tuser FROM PUBLIC;
REVOKE ALL ON TABLE tuser FROM olivier;
GRANT ALL ON TABLE tuser TO olivier;
GRANT SELECT ON TABLE tuser TO client_opened_role;
GRANT SELECT ON TABLE tuser TO client_stopping_role;
GRANT SELECT ON TABLE tuser TO admin;


--
-- Name: vmarkethistory; Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON TABLE vmarkethistory FROM PUBLIC;
REVOKE ALL ON TABLE vmarkethistory FROM olivier;
GRANT ALL ON TABLE vmarkethistory TO olivier;
GRANT SELECT ON TABLE vmarkethistory TO client_opened_role;
GRANT SELECT ON TABLE vmarkethistory TO client_stopping_role;
GRANT SELECT ON TABLE vmarkethistory TO admin;


--
-- Name: vmarket; Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON TABLE vmarket FROM PUBLIC;
REVOKE ALL ON TABLE vmarket FROM olivier;
GRANT ALL ON TABLE vmarket TO olivier;
GRANT SELECT ON TABLE vmarket TO client_opened_role;
GRANT SELECT ON TABLE vmarket TO client_stopping_role;
GRANT SELECT ON TABLE vmarket TO admin;


--
-- Name: vmvt; Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON TABLE vmvt FROM PUBLIC;
REVOKE ALL ON TABLE vmvt FROM olivier;
GRANT ALL ON TABLE vmvt TO olivier;
GRANT SELECT ON TABLE vmvt TO client_opened_role;
GRANT SELECT ON TABLE vmvt TO client_stopping_role;
GRANT SELECT ON TABLE vmvt TO admin;


--
-- Name: vmvtverif; Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON TABLE vmvtverif FROM PUBLIC;
REVOKE ALL ON TABLE vmvtverif FROM olivier;
GRANT ALL ON TABLE vmvtverif TO olivier;
GRANT SELECT ON TABLE vmvtverif TO client_opened_role;
GRANT SELECT ON TABLE vmvtverif TO client_stopping_role;
GRANT SELECT ON TABLE vmvtverif TO admin;


--
-- Name: vorderremoved; Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON TABLE vorderremoved FROM PUBLIC;
REVOKE ALL ON TABLE vorderremoved FROM olivier;
GRANT ALL ON TABLE vorderremoved TO olivier;
GRANT SELECT ON TABLE vorderremoved TO client_opened_role;
GRANT SELECT ON TABLE vorderremoved TO client_stopping_role;
GRANT SELECT ON TABLE vorderremoved TO admin;


--
-- Name: vorderverif; Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON TABLE vorderverif FROM PUBLIC;
REVOKE ALL ON TABLE vorderverif FROM olivier;
GRANT ALL ON TABLE vorderverif TO olivier;
GRANT SELECT ON TABLE vorderverif TO client_opened_role;
GRANT SELECT ON TABLE vorderverif TO client_stopping_role;
GRANT SELECT ON TABLE vorderverif TO admin;


--
-- Name: vstat; Type: ACL; Schema: public; Owner: olivier
--

REVOKE ALL ON TABLE vstat FROM PUBLIC;
REVOKE ALL ON TABLE vstat FROM olivier;
GRANT ALL ON TABLE vstat TO olivier;
GRANT SELECT ON TABLE vstat TO client_opened_role;
GRANT SELECT ON TABLE vstat TO client_stopping_role;
GRANT SELECT ON TABLE vstat TO admin;


--
-- PostgreSQL database dump complete
--

