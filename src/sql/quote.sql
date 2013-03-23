
--------------------------------------------------------------------------------
-- check parameters of a quote
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION 
	fcheckquote(_type dtypeorder,_own text,_qua_requ text,_qtt_requ int8,_qua_prov text,_qtt_prov int8,_qtt int8)
	RETURNS yressubmit AS $$	
DECLARE
	_r			 yressubmit%rowtype;
BEGIN
	_r.diag := 0;

	IF(_qua_requ = _qua_prov) THEN
		_r.diag := -1;
		RETURN _r;
	END IF;
			
	IF( 
		(((_qtt_requ IS NOT NULL) OR (_qtt_requ IS NOT NULL)) AND ((_qtt_requ <=0) OR (_qtt_prov <= 0)))
	 OR ((_qtt      IS NOT NULL) AND (_qtt <= 0)) 
	 ) THEN
		_r.diag := -2;
		RETURN _r;
	END IF;
	
	IF(NOT (0 < _type AND _type <4)) THEN
		_r.diag := -3;
		RETURN _r;
	END IF;

	RETURN _r;
END; 
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
-- prequote
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION 
	fsubmitprequote(_type dtypeorder,_own text,_qua_requ text,_qua_prov text)
	RETURNS yressubmit AS $$	
DECLARE
	_r			 yressubmit%rowtype;
BEGIN
	_r := fcheckquote(_type,_own,_qua_requ,NULL,_qua_prov,NULL,NULL);
	IF(_r.diag != 0) THEN
		RETURN _r;
	END IF;	
	-- NOQTTLIMIT 4 IGNOREOMEGA 8 PREQUOTE 64
	_r.id := fsubmitorder((_type & 3) | 4 | 8 | 64,_own,NULL,_qua_requ,1,_qua_prov,1,1,NULL);
	
	RETURN _r;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fsubmitprequote(dtypeorder,text,text,text) TO role_co;

--------------------------------------------------------------------------------
-- quote first form
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION 
	fsubmitquote(_type dtypeorder,_own text,_qua_requ text,_qua_prov text)
	RETURNS yressubmit AS $$	
DECLARE
	_r			 yressubmit%rowtype;
BEGIN
	_r := fcheckquote(_type,_own,_qua_requ,NULL,_qua_prov,NULL,NULL);
	IF(_r.diag != 0) THEN
		RETURN _r;
	END IF;	
	-- NOQTTLIMIT 4 IGNOREOMEGA 8 QUOTE 128
	_r.id := fsubmitorder((_type & 3) | 4 | 8 | 128,_own,NULL,_qua_requ,1,_qua_prov,1,1,NULL);
	
	RETURN _r;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fsubmitquote(dtypeorder,text,text,text) TO role_co;

--------------------------------------------------------------------------------
-- quote second form
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION 
	fsubmitquote(_type dtypeorder,_own text,_qua_requ text,_qtt_requ int8,_qua_prov text,_qtt_prov int8)
	RETURNS yressubmit AS $$	
DECLARE
	_r			 yressubmit%rowtype;
BEGIN
	_r := fcheckquote(_type,_own,_qua_requ,_qtt_requ,_qua_prov,_qtt_prov,NULL);
	IF(_r.diag != 0) THEN
		RETURN _r;
	END IF;
	--  NOQTTLIMIT 4 QUOTE 128
	_r.id := fsubmitorder((_type & 3) | 4 | 128,_own,NULL,_qua_requ,_qtt_requ,_qua_prov,_qtt_prov,0,NULL);
	
	RETURN _r;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fsubmitquote(dtypeorder,text,text,int8,text,int8) TO role_co;

--------------------------------------------------------------------------------
-- quote third form
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION 
	fsubmitquote(_type dtypeorder,_own text,_qua_requ text,_qtt_requ int8,_qua_prov text,_qtt_prov int8,_qtt int8)
	RETURNS yressubmit AS $$	
DECLARE
	_r			 yressubmit%rowtype;
BEGIN
	_r := fcheckquote(_type,_own,_qua_requ,_qtt_requ,_qua_prov,_qtt_prov,_qtt);
	IF(_r.diag != 0) THEN
		RETURN _r;
	END IF;
	-- QUOTE 128	
	_r.id := fsubmitorder((_type & 3) | 128,_own,NULL,_qua_requ,_qtt_requ,_qua_prov,_qtt_prov,_qtt,NULL);
	
	RETURN _r;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fsubmitquote(dtypeorder,text,text,int8,text,int8,int8) TO role_co;

--------------------------------------------------------------------------------
-- quote execution at the output of the stack
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fproducequote(_MAXMVTPERTRANS int,_t tstack,_o yorder) RETURNS yresorder AS $$
DECLARE
	_ro		    yresorder%rowtype;
	_time_begin	timestamp;
	_cnt		int;
	_cyclemax 	yflow;
	_cycle		yflow;
	_res	    int8[];
	_firstloop		boolean := true;
	_mid		int;
	_nbmvts		int;
	_wid		int;
	
BEGIN

	_wid := fgetowner(_t.own);
	
	_ro := fcheckorder(_wid,_t);
	
	IF(_ro.err != 0) THEN RETURN _ro; END IF;

	_o := _ro.ord;
	_cnt := fcreate_tmp(_o);
	_nbmvts := 0;
	_ro.json := '';
	
	LOOP
		SELECT yflow_max(cycle) INTO _cyclemax FROM _tmp WHERE yflow_is_draft(cycle);
		
		IF(NOT yflow_is_draft(_cyclemax)) THEN
			EXIT; -- from LOOP
		END IF;	
		
		_nbmvts := _nbmvts + yflow_dim(_cyclemax);
		IF(_nbmvts > _MAXMVTPERTRANS) THEN
			EXIT; 
		END IF;	
		
		IF(NOT _firstloop) THEN
			_ro.json := _ro.json || ',' || chr(10); -- ,\n
		END IF;
		
		_res := yflow_qtts(_cyclemax);
		-- _res = [qtt_in,qtt_out,qtt_requ,qtt_prov,qtt]
		
		_ro.json := _ro.json || yflow_to_jsona(_cyclemax);

		IF(_firstloop) THEN
			_ro.qtt_requ := _res[3]; -- qtt_requ
			_ro.qtt_prov := _res[4]; -- qtt_prov
		END IF;
		
		_ro.qtt_reci := _ro.qtt_reci + _res[1];
		_ro.qtt_give := _ro.qtt_give + _res[2];
		
		IF(_o.type & 4 = 4) THEN -- NOLIMITQTT
			_ro.qtt	:= _ro.qtt + _res[5]; -- qtt
		ELSE
			IF(_firstloop) THEN
				_ro.qtt		 := _res[5]; -- qtt
			END IF;
		END IF;
				
/* 	node having IGNOREOMEGA:
		- omega is set to _ro.qtt_requ,_ro.qtt_prov
		- IGNOREOMEGA is reset
	
	for all updates, yflow_reduce is applied except for node with NOQTTLIMIT
*/
		UPDATE _tmp SET cycle = yflow_reduce(cycle,_cyclemax,true);  -- reset IGNOREOMEGA
		
		_firstloop := false;	
		DELETE FROM _tmp WHERE NOT yflow_is_draft(cycle);
		
	END LOOP;

	IF (	(_ro.qtt_requ != 0) 
		AND ((_o.type & 3) = 1) -- ORDER_LIMIT
		AND	((_ro.qtt_give::double precision)	/(_ro.qtt_reci::double precision)) > 
			((_ro.qtt_prov::double precision)	/(_ro.qtt_requ::double precision))
	) THEN	
		RAISE EXCEPTION 'pq: Omega of the flows obtained is not limited by the order limit' USING ERRCODE='YA003';
	END IF;
	
	_ro.json :='{"qtt_requ":' || _ro.qtt_requ || ',"qtt_prov":' || _ro.qtt_prov || ',"qtt":' || _ro.qtt  || 
		',"qtt_reci":' || _ro.qtt_reci || ',"qtt_give":' || _ro.qtt_give || 
		',"paths":[' || chr(10) || _ro.json || chr(10) ||']}';
	
	INSERT INTO tmvt (	type,json,nbc,nbt,grp,xid,    usr,xoid, own_src,own_dst,
						qtt,nat,ack,exhausted,refused,order_created,created
					 ) 
		VALUES       (	_o.type,_ro.json,1,  1,NULL,_o.id,_t.usr,_o.oid,_t.own,_t.own,
						_ro.qtt,_t.qua_prov,false,false,_ro.err,_t.created,statement_timestamp()
					 )
		RETURNING id INTO _mid;
	UPDATE tmvt SET grp = _mid WHERE id = _mid;
	
	RETURN _ro;

END; 
$$ LANGUAGE PLPGSQL;


--------------------------------------------------------------------------------
-- prequote execution at the output of the stack
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fproduceprequote(_MAXMVTPERTRANS int,_t tstack,_o yorder) RETURNS yresorder AS $$
DECLARE
	_ro		    yresorder%rowtype;
	_time_begin	timestamp;
	_cnt		int;
	_cyclemax 	yflow;
	_cycle		yflow;
	_res	    int8[];
	_firstloop		boolean := true;
	_mid		int;
	_nbmvts		int;
	
BEGIN

	_ro.ord 		:= _o;
	_ro.ordp		:= NULL;
	_ro.qtt_prov 	:= 0;
	_ro.qtt_requ 	:= 0;
	_ro.qtt			:= 0;
	_ro.qtt_give	:= 0;
	_ro.qtt_reci	:= 0;
	_ro.err			:= 0;
	_ro.json		:= '';
	
	-- _o.type == _t.type
	_cnt := fcreate_tmp(_o);
	_nbmvts := 0;
	
	LOOP
		SELECT yflow_max(cycle) INTO _cyclemax FROM _tmp WHERE yflow_is_draft(cycle);
		
		IF(NOT yflow_is_draft(_cyclemax)) THEN
			EXIT; -- from LOOP
		END IF;	
		
		_nbmvts := _nbmvts + yflow_dim(_cyclemax);
		IF(_nbmvts > _MAXMVTPERTRANS) THEN
			EXIT; 
		END IF;	
		
		IF(NOT _firstloop) THEN
			_ro.json := _ro.json || ',' || chr(10); -- ,\n
		END IF;
		
		_res := yflow_qtts(_cyclemax);
		-- _res = [qtt_in,qtt_out,qtt_requ,qtt_prov,qtt]
		
		_ro.json := _ro.json || yflow_to_jsona(_cyclemax);

		IF(_firstloop) THEN
			_ro.qtt_requ := _res[3]; -- qtt_requ
			_ro.qtt_prov := _res[4]; -- qtt_prov
		END IF;
		
		_ro.qtt_reci := _ro.qtt_reci + _res[1];
		_ro.qtt_give := _ro.qtt_give + _res[2];
		
		IF(_o.type & 4 = 4) THEN -- NOLIMITQTT
			_ro.qtt	:= _ro.qtt + _res[5]; -- qtt
		ELSE
			IF(_firstloop) THEN
				_ro.qtt		 := _res[5]; -- qtt
			END IF;
		END IF;
				
/* 	node having IGNOREOMEGA:
		- omega is set to _ro.qtt_requ,_ro.qtt_prov
		- IGNOREOMEGA is reset
	
	for all updates, yflow_reduce is applied except for node with NOQTTLIMIT
*/
		UPDATE _tmp SET cycle = yflow_reduce(cycle,_cyclemax,true);  -- reset IGNOREOMEGA
		
		_firstloop := false;	
		DELETE FROM _tmp WHERE NOT yflow_is_draft(cycle);
		
	END LOOP;
	
	_ro.json :='{"qtt_requ":' || _ro.qtt_requ || ',"qtt_prov":' || _ro.qtt_prov || ',"qtt":' || _ro.qtt  || 
		',"qtt_reci":' || _ro.qtt_reci || ',"qtt_give":' || _ro.qtt_give || 
		',"paths":[' || chr(10) || _ro.json || chr(10) ||']}';
	
	INSERT INTO tmvt (	type,json,nbc,nbt,grp,xid,    usr,xoid, own_src,own_dst,
						qtt,nat,ack,exhausted,refused,order_created,created
					 ) 
		VALUES       (	_o.type,_ro.json,1,  1,NULL,_o.id,_t.usr,_o.oid,_t.own,_t.own,
						_ro.qtt,_t.qua_prov,false,false,_ro.err,_t.created,statement_timestamp()
					 )
		RETURNING id INTO _mid;
	UPDATE tmvt SET grp = _mid WHERE id = _mid;
	
	RETURN _ro;

END; 
$$ LANGUAGE PLPGSQL;


