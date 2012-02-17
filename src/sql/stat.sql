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
CREATE OR REPLACE FUNCTION fgetconnected() RETURNS SETOF int8[] AS $$
DECLARE 
	_obCMAXCYCLE int := fgetconst('obCMAXCYCLE');
	_MAX_REFUSED int := fgetconst('MAX_REFUSED');
BEGIN
	RETURN QUERY
		WITH RECURSIVE search_forward(id,np,pat,depthf,b,refused) AS (
			-- all valid orders
			SELECT b.id, b.np,array[]::int8[],0,false,b.refused
				FROM torder b
				WHERE 	b.qtt > 0  AND flow_maxdimrefused(b.refused,_MAX_REFUSED)
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
			select m,generate_subscripts(m,1) as id from fgetconnected() c(m)
			) a
		) b group by x order by x desc;
END;
$$ LANGUAGE PLPGSQL;

/* list of path that do not contain array */ 
CREATE OR REPLACE FUNCTION fgetconl(_lid int8[]) RETURNS SETOF int8[] AS $$
BEGIN
	RAISE INFO 'list of path than do not contain %',_lid;
	RETURN QUERY SELECT pat FROM fgetconnected() a(pat) where NOT _lid <@ pat;
END;
$$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION fgetconll() RETURNS int8[] AS $$
DECLARE
	_res int[];
	_iter record;
	_cnt int :=0;
BEGIN
	RAISE INFO 'intersection all cycles (int8->int!!)';
	FOR _iter IN SELECT pat FROM fgetconnected() a(pat) LOOP
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

