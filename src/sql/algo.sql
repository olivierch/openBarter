
--------------------------------------------------------------------------------
/* function fcreate_tmp

It is the central query of openbarter

for an order O fcreate_tmp creates a temporary table _tmp of objects.
Each object represents a possible chain of orders - a 'flow' - going to O. 

The table has columns
	debut 	the first order of the path
	path	the path
	fin		the end of the path (O)
	depth	the exploration depth
	cycle	a boolean true when the path contains the new order

The number of paths fetched is limited to MAXPATHFETCHED
Among those objects representing chains of orders, 
only those making a potential exchange (draft) are recorded.

*/
--------------------------------------------------------------------------------
/*
CREATE VIEW vorderinsert AS
	SELECT id,yorder_get(id,own,nr,qtt_requ,np,qtt_prov,qtt) as ord,np,nr
	FROM torder ORDER BY ((qtt_prov::double precision)/(qtt_requ::double precision)) DESC; */
	
--------------------------------------------------------------------------------
CREATE FUNCTION fcreate_tmp(_ord yorder) RETURNS int AS $$
DECLARE 
	_MAXPATHFETCHED	 int := fgetconst('MAXPATHFETCHED');  
	_MAXCYCLE 	int := fgetconst('MAXCYCLE');
	_cnt int;
BEGIN
	/* the statement LIMIT would not avoid deep exploration if the condition
	was specified  on Z in the search_backward WHERE condition */
	-- fails when qua_prov == qua_requ 
	IF((_ord).qua_prov = (_ord).qua_requ) THEN
		RAISE EXCEPTION 'quality provided and required are the same: %',_ord;
	END IF;
	CREATE TEMPORARY TABLE _tmp ON COMMIT DROP AS (
		SELECT yflow_finish(Z.debut,Z.path,Z.fin) as cycle FROM (
			WITH RECURSIVE search_backward(debut,path,fin,depth,cycle) AS(
					SELECT _ord,yflow_init(_ord),
						_ord,1,false 
					-- FROM torder WHERE (ord).id= _ordid
				UNION ALL
					SELECT X.ord,yflow_grow_backward(X.ord,Y.debut,Y.path),
						Y.fin,Y.depth+1,yflow_contains_oid((X.ord).oid,Y.path)
					FROM torder X,search_backward Y
					WHERE yflow_match(X.ord,Y.debut) -- (X.ord).qua_prov=(Y.debut).qua_requ 
						AND ((X.duration IS NULL) OR ((X.created + X.duration) > clock_timestamp()))  
						AND Y.depth < _MAXCYCLE 
						AND NOT cycle 
						AND (X.ord).carre_prov @> (Y.debut).pos_requ -- use if gist(carre_prov)
						AND NOT yflow_contains_oid((X.ord).oid,Y.path) 
			) SELECT debut,path,fin from search_backward 
			LIMIT _MAXPATHFETCHED
		) Z WHERE /* (Z.fin).qua_prov=(Z.debut).qua_requ 
				AND */ yflow_match(Z.fin,Z.debut) -- it is a cycle
				AND yflow_is_draft(yflow_finish(Z.debut,Z.path,Z.fin)) -- and a draft
	);
	RETURN 0;
	
END;
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
-- order unstacked and inserted into torder
/* if the referenced oid is found,
	the order is inserted, and the process is loached
else a movement is created
*/
--------------------------------------------------------------------------------

CREATE TYPE yresflow AS (
    mvts int[], -- list of id des mvts
    qtts int8[], -- value.qtt moved
    nats text[], -- value.nat moved
    grp  int,
    owns text[],
    usrs text[],
    ords yorder[]
);

--------------------------------------------------------------------------------

CREATE FUNCTION insertorder(_owner dtext,_o yorder,_usr dtext,_created timestamp,_duration interval) 
	RETURNS int AS $$
DECLARE

	_fmvtids	int[];
	_cyclemax 	yflow;
    _res        int8[];
	_MAXMVTPERTRANS 	int := fgetconst('MAXMVTPERTRANS');
	_nbmvts		int := 0;
	
	_qtt_give   int8 := 0;
	_qtt_reci   int8 := 0;
	_cnt        int;
	_resflow    yresflow;
BEGIN

    lock table torder in share update exclusive mode NOWAIT;
    -- immediatly aborts the order if the lock cannot be acquired
	
	INSERT INTO torder(usr,own,ord,created,updated,duration) VALUES (_usr,_owner,_o,_created,NULL,_duration);

	_fmvtids := ARRAY[]::int[];
	
	-- _time_begin := clock_timestamp();
	
	_cnt := fcreate_tmp(_o);
    -- RAISE WARNING 'insertbarter A % %',_o,_cnt;
	LOOP	
		SELECT yflow_max(cycle) INTO _cyclemax FROM _tmp WHERE yflow_is_draft(cycle);	
		IF(NOT yflow_is_draft(_cyclemax)) THEN
			EXIT; -- from LOOP
		END IF;
        -- RAISE WARNING 'insertbarter B %',_cyclemax;
		_nbmvts := _nbmvts + yflow_dim(_cyclemax);
		IF(_nbmvts > _MAXMVTPERTRANS) THEN
			EXIT; 
		END IF;	

		_resflow := fexecute_flow(_cyclemax);
		
		_cnt := foncreatecycle(_o,_resflow);
	
		_fmvtids := _fmvtids || _resflow.mvts;
		
		_res := yflow_qtts(_cyclemax);
		_qtt_reci := _qtt_reci + _res[1];
		_qtt_give := _qtt_give + _res[2];
	
		UPDATE _tmp SET cycle = yflow_reduce(cycle,_cyclemax,false);
		DELETE FROM _tmp WHERE NOT yflow_is_draft(cycle);
	END LOOP;
	-- RAISE WARNING 'insertbarter C % % % % %',_qtt_give,_qtt_reci,_o.qtt_prov,_o.qtt_requ,_fmvtids;

	IF (	(_qtt_give != 0) AND ((_o.type & 3) = 1) -- ORDER_LIMIT
	AND	((_qtt_give::double precision)	/(_qtt_reci::double precision)) > 
		((_o.qtt_prov::double precision)	/(_o.qtt_requ::double precision))
	) THEN
		RAISE EXCEPTION 'pb: Omega of the flows obtained is not limited by the order limit' 
			USING ERRCODE='YA003';
	END IF;
	-- set the number of movements in this transaction
	-- UPDATE tmvt SET nbt= array_length(_fmvtids,1) WHERE id = ANY (_fmvtids);
	
	RETURN 0;

END; 
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
CREATE FUNCTION foncreatecycle(_orig yorder,_r yresflow) RETURNS int AS $$
DECLARE

	_usr_src    text;
	_cnt    int;
	_i      int;
    _nbcommit int;
    _iprev  int;
    _inext  int;
    _o      yorder;
BEGIN

    _nbcommit := array_length(_r.ords,1);
    _i := _nbcommit;
    _iprev := _i -1;
    FOR _inext IN 1.._nbcommit LOOP

        _usr_src := _r.usrs[_i];
        _o := _r.ords[_i];

        INSERT INTO tmsg (typ,jso,usr,created) VALUES (
            'exchange',
            row_to_json(ROW(
                _r.mvts[_i],
                _r.grp,
                ROW( -- order
                    _o.id,
                    _o.qtt_prov,
                    _o.qtt_requ, 
                    CASE WHEN _o.type&3 =1 THEN 'limit' ELSE 'best' END
                    )::yj_ω,
                ROW( -- stock
                    _o.oid,
                    _o.qtt,
                    _r.nats[_i], 
                    _r.owns[_i],
                    _r.usrs[_i]
                    )::yj_stock,
                ROW( -- mvt_from
                    _r.mvts[_i],
                    _r.qtts[_i],
                    _r.nats[_i],
                    _r.owns[_inext],
                    _r.usrs[_inext]
                    )::yj_stock,
                ROW( --mvt_to
                    _r.mvts[_iprev],
                    _r.qtts[_iprev],
                    _r.nats[_iprev],
                    _r.owns[_iprev],
                    _r.usrs[_iprev]
                    )::yj_stock,
                _orig.id -- orig
                )::yj_mvt),
            _usr_src,statement_timestamp());

        _iprev := _i;
        _i := _inext;

    END LOOP;

    RETURN 0; 
END; 
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
/* fexecute_flow used for a barter
from a flow representing a draft, for each order:
	inserts a new movement
	updates the order book
*/
--------------------------------------------------------------------------------

CREATE FUNCTION fexecute_flow(_flw yflow) RETURNS  yresflow AS $$
DECLARE
	_i			int;
	_next_i		int;
	_prev_i     int;
	_nbcommit	int;
	
	_first_mvt  int;
	_exhausted	boolean;
	_mvtexhausted boolean;
	_cntExhausted int;
	_mvt_id		int;

	_cnt 		int;
	_resflow    yresflow;
	--_mvts       int[];
	--_oids       int[];
	_qtt		int8;
	_flowr		int8;
	_qttmin		int8;
	_qttmax		int8;
	_o			yorder;
	_usr		text;
	_usrnext	text;
	-- _own		text;
	-- _ownnext	text;
	-- _idownnext	int;
	-- _pidnext 	int;
	_or			torder%rowtype;
	_mat		int8[][];
	_om_exp     double precision;
	_om_rea     double precision;

BEGIN

	_nbcommit := yflow_dim(_flw);
	
	-- sanity check
	IF( _nbcommit <2 ) THEN
		RAISE EXCEPTION 'the flow should be draft:_nbcommit = %',_nbcommit 
			USING ERRCODE='YA003';
	END IF;
	
	_first_mvt := NULL;
	_exhausted := false;
	-- _resx.nbc := _nbcommit;	
	_resflow.mvts := ARRAY[]::int[];
	_resflow.qtts := ARRAY[]::int8[];
	_resflow.nats := ARRAY[]::text[];
	_resflow.owns := ARRAY[]::text[];
	_resflow.usrs := ARRAY[]::text[];
	_resflow.ords := ARRAY[]::yorder[];

	_mat := yflow_to_matrix(_flw);
	
	_i := _nbcommit;
	_prev_i := _i - 1;
	FOR _next_i IN 1 .. _nbcommit LOOP
		------------------------------------------------------------------------
		_o.id   := _mat[_i][1];
		_o.own	:= _mat[_i][2];
		_o.oid	:= _mat[_i][3];
		_o.qtt  := _mat[_i][6];
		_flowr  := _mat[_i][7]; 
		
		-- _idownnext := _mat[_next_i][2];	
		-- _pidnext   := _mat[_next_i][3];
		
		-- sanity check
		SELECT count(*),min((ord).qtt),max((ord).qtt) INTO _cnt,_qttmin,_qttmax 
			FROM torder WHERE (ord).oid = _o.oid;
			
		IF(_cnt = 0) THEN
			RAISE EXCEPTION 'the stock % expected does not exist',_o.oid  USING ERRCODE='YU002';
		END IF;
		
		IF( _qttmin != _qttmax ) THEN
			RAISE EXCEPTION 'the value of stock % is not the same value for all orders',_o.oid  USING ERRCODE='YU002';
		END IF;
		
		_cntExhausted := 0;
		_mvtexhausted := false;
		IF( _qttmin < _flowr ) THEN
			RAISE EXCEPTION 'the stock % is smaller than the flow (% < %)',_o.oid,_qttmin,_flowr  USING ERRCODE='YU002';
		ELSIF (_qttmin = _flowr) THEN
			_cntExhausted := _cnt;
			_exhausted := true;
			_mvtexhausted := true;
		END IF;
			
		-- update all stocks of the order book
		UPDATE torder SET ord.qtt = (ord).qtt - _flowr ,updated = statement_timestamp()
			WHERE (ord).oid = _o.oid; 
		GET DIAGNOSTICS _cnt = ROW_COUNT;
		IF(_cnt = 0) THEN
			RAISE EXCEPTION 'no orders with the stock % exist',_o.oid  USING ERRCODE='YU002';
		END IF;

        
		SELECT * INTO _or FROM torder WHERE (ord).id = _o.id LIMIT 1; -- child order
		-- RAISE WARNING 'ici %',_or.ord;
		_om_exp	:= (((_or.ord).qtt_prov)::double precision) / (((_or.ord).qtt_requ)::double precision);
		_om_rea := ((_flowr)::double precision) / ((_mat[_prev_i][7])::double precision);
		
		/*
		SELECT name INTO STRICT _ownnext 	FROM towner WHERE id=_idownnext;
		SELECT name INTO STRICT _own 		FROM towner WHERE id=_o.own;
		SELECT usr  INTO STRICT _usrnext    FROM torder WHERE (ord).id=_pidnext;

		INSERT INTO tmvt (nbc,nbt,grp,
						xid,usr_src,usr_dst,xoid,own_src,own_dst,qtt,nat,ack,
						exhausted,order_created,created,om_exp,om_rea) 
			VALUES(_nbcommit,1,_first_mvt,
						_o.id,_or.usr,_usrnext,_o.oid,_own,_ownnext,_flowr,(_or.ord).qua_prov,_cycleack,
						_mvtexhausted,_or.created,statement_timestamp(),_om_exp,_om_rea)
			RETURNING id INTO _mvt_id;
		*/
		SELECT nextval('tmvt_id_seq') INTO _mvt_id;

		IF(_first_mvt IS NULL) THEN
			_first_mvt := _mvt_id;
			_resflow.grp := _mvt_id;
			-- _resx.first_mvt := _mvt_id;
			-- UPDATE tmvt SET grp = _first_mvt WHERE id = _first_mvt;
		END IF;
		
		_resflow.mvts := array_append(_resflow.mvts,_mvt_id);
		_resflow.qtts := array_append(_resflow.qtts,_flowr);
		_resflow.nats := array_append(_resflow.nats,(_or.ord).qua_prov);
		_resflow.owns := array_append(_resflow.owns,_or.own::text);
		_resflow.usrs := array_append(_resflow.usrs,_or.usr::text);
		_resflow.ords := array_append(_resflow.ords,_or.ord);

        _prev_i := _i;
		_i := _next_i;
		------------------------------------------------------------------------
	END LOOP;

	IF( NOT _exhausted ) THEN
		--  some order should be exhausted 
		RAISE EXCEPTION 'the cycle should exhaust some order' 
			USING ERRCODE='YA003';
	END IF;
	

	RETURN _resflow;
END;
$$ LANGUAGE PLPGSQL;

CREATE TYPE yr_quote AS (
    qtt_reci int8,
    qtt_give int8
);
--------------------------------------------------------------------------------
-- quote execution at the output of the stack
--------------------------------------------------------------------------------
CREATE FUNCTION fproducequote(_ord yorder,_isquote boolean,_isnoqttlimit boolean,_islimit boolean,_isignoreomega boolean) 
/*
	_isquote := true; 
		it can be a quote or a prequote
	_isnoqttlimit := false; 
		when true the quantity provided is not limited by the stock available
	_islimit:= (_t.jso->'type')='limit'; 
		type of the quoted order
	_isignoreomega := -- (_t.type & 8) = 8
*/
	RETURNS json AS $$
DECLARE
	_cnt		int;
	_cyclemax 	yflow;
	_cycle		yflow;
	_res	    int8[];
	_firstloop		boolean := true;
	_freezeOmega boolean;
	_mid		int;
	_nbmvts		int;
	_wid		int;
	_MAXMVTPERTRANS 	int := fgetconst('MAXMVTPERTRANS');
	_barter     text;
	_paths      text;
	
	_qtt_reci   int8 := 0;
	_qtt_give   int8 := 0;
	_qtt_prov   int8 := 0;
	_qtt_requ   int8 := 0;
	_qtt        int8 := 0;

	_resjso json;
	
BEGIN
	_cnt := fcreate_tmp(_ord);
	_nbmvts := 0;
	_paths := '';
	
	LOOP
		SELECT yflow_max(cycle) INTO _cyclemax FROM _tmp WHERE yflow_is_draft(cycle);
		
		IF(NOT yflow_is_draft(_cyclemax)) THEN
			EXIT; -- from LOOP
		END IF;	
		
		_nbmvts := _nbmvts + yflow_dim(_cyclemax);
		IF(_nbmvts > _MAXMVTPERTRANS) THEN
			EXIT; 
		END IF;	

		_res := yflow_qtts(_cyclemax);

		_qtt_reci := _qtt_reci + _res[1];
		_qtt_give := _qtt_give + _res[2];

		IF(_isquote) THEN 
			IF(_firstloop) THEN
				_qtt_requ := _res[3]; 
				_qtt_prov := _res[4]; 
			END IF;
		
			IF(_isnoqttlimit) THEN 
				_qtt	:= _qtt + _res[5]; 
			ELSE
				IF(_firstloop) THEN
					_qtt		 := _res[5]; 
				END IF;
			END IF;
		END IF;
		-- for a PREQUOTE they remain 0

		_freezeOmega := _firstloop AND _isignoreomega AND _isquote;
				
		/* 	yflow_reduce:
			for all orders except for node with NOQTTLIMIT:
				qtt = qtt -flowr 
			for the last order, if is IGNOREOMEGA:
				- omega is set:
					_cycle[last].qtt_requ,_cycle[last].qtt_prov 
						:= _cyclemax[last].qtt_requ,_cyclemax[last].qtt_prov
				- if _freezeOmega the IGNOREOMEGA is reset 
		*/	 
		UPDATE _tmp SET cycle = yflow_reduce(cycle,_cyclemax,_freezeOmega);
			
		DELETE FROM _tmp WHERE NOT yflow_is_draft(cycle);
		_firstloop := false;
		
	END LOOP;

	IF (	(_qtt_requ != 0) 
		AND _islimit AND _isquote
		AND	((_qtt_give::double precision)	/(_qtt_reci::double precision)) > 
			((_qtt_prov::double precision)	/(_qtt_requ::double precision))
	) THEN	
		RAISE EXCEPTION 'pq: Omega of the flows obtained is not limited by the order limit' USING ERRCODE='YA003';
	END IF;

	_resjso := row_to_json(ROW(_qtt_reci,_qtt_give)::yr_quote);
	
	RETURN _resjso;

END; 
$$ LANGUAGE PLPGSQL;







