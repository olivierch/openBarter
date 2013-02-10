
--------------------------------------------------------------------------------
CREATE FUNCTION fproducequote(_o yorder) RETURNS yresorder AS $$
DECLARE
	_ro		    yresorder%rowtype;
	_time_begin	timestamp;
	_cnt		int;
	_cyclemax 	yflow;
	_cycle		yflow;
	_res	    int8[];
	_begin		boolean := true;
	
BEGIN

	_ro.ord 		:= _o;
	_ro.qtt_prov 	:= 0;
	_ro.qtt_requ 	:= 0;
	_ro.qtt			:= 0;
	_ro.err			:= 0;
	_ro.json		:= NULL;
	
	_time_begin := clock_timestamp();
	
	_o.type := _o.type & 12; -- NOQTTLIMIT IGNOREOMEGA
	_cnt := fcreate_tmp(_o);
	
	LOOP
		SELECT yflow_max(cycle) INTO _cyclemax FROM _tmp WHERE yflow_is_draft(cycle);
		
		IF(NOT yflow_is_draft(_cyclemax)) THEN
			EXIT; -- from LOOP
		END IF;	
	
		_res := yflow_qtts(_cyclemax);
		IF (_begin) THEN
			_ro.qtt_requ  := _res[1];
			_ro.qtt_prov  := _res[2];
			_ro.qtt		  := _res[2];
		ELSE
			_ro.qtt		  := _res[2];
		END IF;
					
/* 	the first update, last node of each cycle are updated:
		- omega is set to _ro.qtt_requ,_ro.qtt_prov
		- type: NOQTTLIMIT is set, IGNOREOMEGA is reset
	
	for all updates, yflow_reduce is applied except on the first node
*/
		UPDATE _tmp SET cycle = yflow_reducequote(_begin,cycle,_cyclemax);
		_begin := false;	
		DELETE FROM _tmp WHERE NOT yflow_is_draft(cycle);
	END LOOP;
	
	IF (	(_ro.qtt_in != 0) AND ((_o.type & 3) = 1) -- ORDER_LIMIT
	AND	((_ro.qtt_out::double precision)	/(_ro.qtt_in::double precision)) > 
		((_o.qtt_prov::double precision)	/(_o.qtt_requ::double precision))
	) THEN
		RAISE EXCEPTION 'Omega of the flows obtained is not limited by the order limit' USING ERRCODE='YA003';
	END IF;

	
	RETURN _ro;

END; 
$$ LANGUAGE PLPGSQL;

