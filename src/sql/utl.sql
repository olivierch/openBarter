SET client_min_messages = warning;
\set ECHO none

--------------------------------------------------------------------------------
/*
create table tsave_tmp(
	n	int,
	id 	int,
	ord	yorder,
	nr	int,
	pat	yflow
);
--------------------------------------------------------------------------------
-- common to insertorder() and getquote() 
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
*/



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

--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fomega(pat yflow) RETURNS float8 AS $$
DECLARE
	_f float8[];
BEGIN
	_f := yflow_qtts(pat)::float8[];
	-- qtt_prov/qtt_requ
	RETURN (_f[1])/(_f[2]);
END;
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
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

\set ECHO all
 RESET client_min_messages;

