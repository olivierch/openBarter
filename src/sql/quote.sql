
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fproducequote(_MAXMVTPERTRANS int,_t tstack,_o yorder) RETURNS yresorder AS $$
DECLARE
	_ro		    yresorder%rowtype;
	_time_begin	timestamp;
	_cnt		int;
	_cyclemax 	yflow;
	_cycle		yflow;
	_res	    int8[];
	_begin		boolean := true;
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
	
	_time_begin := clock_timestamp();
	_o.type := _t.type;
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
		
		IF(NOT _begin) THEN
			_ro.json := _ro.json || ',' || chr(10); -- ,\n
		END IF;
		
		_res := yflow_qtts(_cyclemax);
		-- _res = [qtt_in,qtt_out,qtt_requ,qtt_prov,qtt]
		
		_ro.json := _ro.json || yflow_to_jsona(_cyclemax);
		-- RAISE WARNING '_res % %',_res,yflow_to_jsona(_cyclemax);
/*
		IF (_begin ) THEN
			IF((_t.type & 8) = 8) THEN-- _begin AND IGNOREOMEGA
				_ro.qtt_requ  := _res[3]; -- qtt_requ
				_ro.qtt_prov  := _res[4]; -- qtt_prov
			ELSE
				_ro.qtt_requ  := _o.qtt_requ;
				_ro.qtt_prov  := _o.qtt_prov;
			END IF;
		END IF;
*/
		IF(_begin) THEN
			_ro.qtt_requ := _res[3]; -- qtt_requ
			_ro.qtt_prov := _res[4]; -- qtt_prov
		END IF;
		
		_ro.qtt_reci := _ro.qtt_reci + _res[1];
		_ro.qtt_give := _ro.qtt_give + _res[2];
		
		IF(_o.type & 4 = 4) THEN -- NOLIMITQTT
			_ro.qtt	:= _ro.qtt + _res[5]; -- qtt
		ELSE
			IF(_begin) THEN
				_ro.qtt		 := _res[5]; -- qtt
			END IF;
		END IF;


					
/* 	node having IGNOREOMEGA:
		- omega is set to _ro.qtt_requ,_ro.qtt_prov
		- IGNOREOMEGA is reset
	
	for all updates, yflow_reduce is applied except for node with NOQTTLIMIT
*/
		UPDATE _tmp SET cycle = yflow_reduce(cycle,_cyclemax);  -- reset IGNOREOMEGA
		_begin := false;	
		DELETE FROM _tmp WHERE NOT yflow_is_draft(cycle);
	END LOOP;

	IF (	(_ro.qtt_requ != 0) AND ((_o.type & 3) = 1) -- ORDER_LIMIT
	-- AND ((_o.type & 8) != 8) -- not IGNOREOMEGA
	AND	((_ro.qtt_give::double precision)	/(_ro.qtt_reci::double precision)) > 
		((_ro.qtt_prov::double precision)	/(_ro.qtt_requ::double precision))
	) THEN	
		RAISE EXCEPTION 'pq: Omega of the flows obtained is not limited by the order limit' USING ERRCODE='YA003';
	END IF;
	_ro.json :='{"qtt_requ":' || _ro.qtt_requ || ',"qtt_prov":' || _ro.qtt_prov || ',"qtt":' || _ro.qtt  || ',"qtt_reci":' || _ro.qtt_reci || ',"qtt_give":' || _ro.qtt_give || ',"paths":[' || chr(10) || _ro.json || chr(10) ||']}';
	
	INSERT INTO tmvt (	type,json,nbc,nbt,grp,xid,    usr,xoid, own_src,own_dst,
						qtt,nat,ack,exhausted,refused,order_created,created
					 ) 
		VALUES       (	_t.type,_ro.json,1,  1,NULL,_o.id,_t.usr,_o.oid,_t.own,_t.own,
						_ro.qtt,_t.qua_prov,false,false,_ro.err,_t.created,statement_timestamp()
					 )
		RETURNING id INTO _mid;
	UPDATE tmvt SET grp = _mid WHERE id = _mid;
	
	RETURN _ro;

END; 
$$ LANGUAGE PLPGSQL;
