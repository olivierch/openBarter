
--------------------------------------------------------------------------------
-- prequote -- err_offset -30
--------------------------------------------------------------------------------
CREATE FUNCTION fsubmitprequote(_own text,_qua_requ text,_pos_requ point,_qua_prov text,_pos_prov point,_dist float8)
	RETURNS yerrororder AS $$
DECLARE
	_r			yerrororder%rowtype;
	_s 			tstack%rowtype;

BEGIN
	-- ORDER_BEST 2 NOQTTLIMIT 4 IGNOREOMEGA 8 PREQUOTE 64
	_s := ROW(NULL,NULL,_own,NULL,2 | 4 | 8 | 64,_qua_requ,NULL,_pos_requ,_qua_prov,NULL,NULL,_pos_prov,_dist,NULL,NULL,NULL,NULL,NULL)::tstack;
	_r := fprocessprequote('submitted',_s);
	RETURN _r;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
-- GRANT EXECUTE ON FUNCTION  fsubmitprequote(text,text,point,text,point,float8) TO role_co;

--------------------------------------------------------------------------------
CREATE FUNCTION fprocessprequote(_state eorderstate, _s tstack)
	RETURNS yerrororder AS $$
DECLARE
	_r			yerrororder;
	_wid		int;
	_o          yorder;
	_tx 		text;
BEGIN
	_r := ROW(_s.id,0,NULL);

    CASE
    	WHEN (_state = 'submitted') THEN -- before stack insertion

		    _r := fcheckquaown(_r,_s.own,_s.qua_requ,_s.pos_requ,_s.qua_prov,_s.pos_prov,_s.dist);
		    if(_r.code !=0) THEN
				_r.code := _r.code -1000;
		        RETURN _r;
		    END IF;

    		IF (NOT fchecknameowner(_s.own,session_user)) THEN
				_r.code := -1001;
				_r.reason := 'illegal owner name';
				RETURN _r;
    		END IF;

			_r := fpushorder(_r,_s);
			
			RETURN _r;

    	WHEN (_state = 'pending') THEN -- execution

    		_wid := fgetowner(_s.own);

	        _s.oid := _s.id;
	        IF(_s.qtt_requ IS NULL) THEN _s.qtt_requ := 1; END IF;
	        IF(_s.qtt_prov IS NULL) THEN _s.qtt_prov := 1; END IF;
	        IF(_s.qtt IS NULL) THEN _s.qtt := 0; END IF;

	        _o := ROW(_s.type,_s.id,_wid,_s.oid,_s.qtt_requ,_s.qua_requ,_s.qtt_prov,_s.qua_prov,_s.qtt,
	                    box(_s.pos_requ,_s.pos_requ),box(_s.pos_prov,_s.pos_prov),
	                    _s.dist,earth_get_square(_s.pos_prov,_s.dist))::yorder;

	        _tx := fproducequote(_o,_s,true);

	        RETURN _r;

	    WHEN (_state = 'aborted') THEN -- failure on stack output
	    	return _r;

    	ELSE

    		RAISE EXCEPTION 'Should not reach this point';

    END CASE;
    
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;


--------------------------------------------------------------------------------
-- quote all forms -- err_offset -40
-- type & ~3 == 0 
--------------------------------------------------------------------------------
CREATE FUNCTION fsubmitquote(_type dtypeorder,_own text,_qua_requ text,_qtt_requ int8,_pos_requ point,_qua_prov text,_qtt_prov int8,_qtt int8,_pos_prov point,_dist float8)
	RETURNS yerrororder AS $$
DECLARE
	_r			yerrororder%rowtype;
	_s 			tstack%rowtype;
	_otype		int;

BEGIN
	_otype := (_type & 3) | 128; -- QUOTE 128

	IF((_qtt IS NULL) AND (_qtt_requ IS NULL) AND (_qtt_prov IS NULL) ) THEN -- quote first form
	    _otype := _otype | 4 | 8; -- NOQTTLIMIT 4 IGNOREOMEGA 8
	ELSIF((_qtt IS NULL) AND (_qtt_requ >0) AND (_qtt_prov >0) ) THEN -- quote second form
	    _otype := _otype | 4 ; --  NOQTTLIMIT 4
	ELSIF((_qtt > 0) AND (_qtt_requ >0) AND (_qtt_prov >0) ) THEN -- quote third form	
	    _otype := _otype ;
	ELSE 
	    _otype := _otype | 32; -- bit d'erreur inséré
	END IF;

	_s := ROW(NULL,NULL,_own,NULL,_otype,_qua_requ,_qtt_requ,_pos_requ,_qua_prov,_qtt_prov,_qtt,_pos_prov,_dist,NULL,NULL,NULL,NULL,NULL)::tstack;
	_r := fprocessquote('submitted',_s);
	RETURN _r;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
-- GRANT EXECUTE ON FUNCTION  fsubmitquote(dtypeorder,text,text,int8,point,text,int8,int8,point,float8) TO role_co;
--------------------------------------------------------------------------------
CREATE FUNCTION fsubmitlquote(_own text,_qua_requ text,_qtt_requ int8,_qua_prov text,_qtt_prov int8)
	RETURNS yerrororder AS $$
DECLARE
	_r			yerrororder%rowtype;
	_s 			tstack%rowtype;
	_otype		int;

BEGIN
	_r := ROW(NULL,0,NULL);
	_otype := 2 | 128; -- Best 2 QUOTE 128 

	IF(NOT((_qtt_requ >0) AND (_qtt_prov >0)) ) THEN -- quote third form	
	    _r.code := -2000;
	    _r.reason := 'quantities required';
	    return _r;
	END IF;

	_s := ROW(NULL,NULL,_own,NULL,_otype,_qua_requ,_qtt_requ,'(0,0)'::point,_qua_prov,_qtt_prov,_qtt_prov,'(0,0)'::point,0,NULL,NULL,NULL,NULL,NULL)::tstack;
	_r := fprocessquote('submitted',_s);
	RETURN _r;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fsubmitlquote(text,text,int8,text,int8) TO role_co;


--------------------------------------------------------------------------------
CREATE FUNCTION fprocessquote(_state eorderstate, _s tstack)
	RETURNS yerrororder AS $$
DECLARE
	_r			yerrororder;
	_wid		int;
	_o          yorder;
	_tx 		text;
BEGIN
	_r := ROW(_s.id,0,NULL);
    CASE
    	WHEN (_state = 'submitted') THEN -- before stack insertion

		    _r := fcheckquaown(_r,_s.own,_s.qua_requ,_s.pos_requ,_s.qua_prov,_s.pos_prov,_s.dist);
		    if(_r.code !=0) THEN
		    	_r.code := _r.code - 1100;
		        RETURN _r;
		    END IF;

		    IF ((_s.type & 32)=32) THEN -- error detected in submit
			    _r.code := -1110;
			    _r.reason := 'Illegal parameters for a quote';
			    return _r;
			END IF;

			_r := fpushorder(_r,_s);
			RETURN _r;

    	WHEN (_state = 'pending') THEN -- execution

    		_wid := fgetowner(_s.own);

	        _s.oid := _s.id;
	        IF(_s.qtt_requ IS NULL) THEN _s.qtt_requ := 1; END IF;
	        IF(_s.qtt_prov IS NULL) THEN _s.qtt_prov := 1; END IF;
	        IF(_s.qtt IS NULL) THEN _s.qtt := 0; END IF;

	        _o := ROW(_s.type,_s.id,_wid,_s.oid,_s.qtt_requ,_s.qua_requ,_s.qtt_prov,_s.qua_prov,_s.qtt,
	                    box(_s.pos_requ,_s.pos_requ),box(_s.pos_prov,_s.pos_prov),
	                    _s.dist,earth_get_square(_s.pos_prov,_s.dist))::yorder;
	        _tx := fproducequote(_o,_s,true);

	        RETURN _r;
	        
	    WHEN (_state = 'aborted') THEN -- failure on stack output
	    	return _r;

    	ELSE

    		RAISE EXCEPTION 'Should not reach this point';

    END CASE;
    
END;
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
/*
CREATE TYPE yquotebarter AS (
    type int,
    qua_requ text,
    qtt_requ int,
    qua_prov text,
    qtt_prov int,
    qtt int
); */
CREATE TYPE yr_quote AS (
    qtt_reci int8,
    qtt_give int8
);
--------------------------------------------------------------------------------
-- quote execution at the output of the stack
--------------------------------------------------------------------------------
CREATE FUNCTION fproducequote(_ord yorder,_isquote boolean,_isnoqttlimit boolean,_islimit boolean,_isignoreomega boolean) 
/*
	_isquote := true; -- (_t.type & 128) = 128
		it can be a quote or a prequote
	_isnoqttlimit := false; -- (_t.type & 4) = 4
		when true the quantity provided is not limited by the stock available
	_islimit:= (_t.jso->'type')='limit'; -- (_t.type & 3) = 1
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
		/*
		IF(NOT _firstloop) THEN
			_paths := _paths || ',' || chr(10); -- ,\n
		END IF;
		*/
		_res := yflow_qtts(_cyclemax);
		-- _res = [qtt_in,qtt_out,qtt_requ,qtt_prov,qtt]
		-- _res = [x[f->dim-2].flowr,x[f->dim-1].flowr,x[f->dim-1].qtt_requ,x[f->dim-1].qtt_prov,x[f->dim-1].qtt]
		
		_qtt_reci := _qtt_reci + _res[1];
		_qtt_give := _qtt_give + _res[2];
				
		-- _paths := _paths || yflow_to_jsona(_cyclemax);

		-- for a QUOTE, set _ro.qtt_requ,_ro.qtt_prov,_ro.qtt
		IF(_isquote) THEN -- QUOTE
			IF(_firstloop) THEN
				_qtt_requ := _res[3]; -- qtt_requ
				_qtt_prov := _res[4]; -- qtt_prov
			END IF;
		
			IF(_isnoqttlimit) THEN -- NOLIMITQTT
				_qtt	:= _qtt + _res[5]; -- qtt
			ELSE
				IF(_firstloop) THEN
					_qtt		 := _res[5]; -- qtt
				END IF;
			END IF;
		END IF;
		-- for a PREQUOTE they remain 0
				
/* 	if _setOmega, for all remaining orders:
		- omega is set to _ro.qtt_requ,_ro.qtt_prov
		- IGNOREOMEGA is reset
	
	for all updates, yflow_reduce is applied except for node with NOQTTLIMIT
*/
		_freezeOmega := _firstloop AND _isignoreomega AND _isquote; --((_t.type & (8|128)) = (8|128));
		UPDATE _tmp SET cycle = yflow_reduce(cycle,_cyclemax,_freezeOmega);
		_firstloop := false;
			
		DELETE FROM _tmp WHERE NOT yflow_is_draft(cycle);
		
	END LOOP;

	IF (	(_qtt_requ != 0) 
		AND _islimit AND _isquote
		AND	((_qtt_give::double precision)	/(_qtt_reci::double precision)) > 
			((_qtt_prov::double precision)	/(_qtt_requ::double precision))
	) THEN	
		RAISE EXCEPTION 'pq: Omega of the flows obtained is not limited by the order limit' USING ERRCODE='YA003';
	END IF;
/*
	_paths := '{"qtt_reci":' || _qtt_reci || ',"qtt_give":' || _qtt_give || 
		',"paths":[' || chr(10) || _paths || chr(10) ||']}';
			
	IF((_t.type & (128)) = 128) THEN
	    _barter := row_to_json(ROW(_t.type&(~3),_t.qua_requ,_qtt_requ,_t.qua_prov,_qtt_prov,_qtt)::yquotebarter);
        _paths := '{"object":' || row_to_json(_t)::text || ',"quoted":' || _barter || ',"result":' || _paths || '}';
	ELSE	-- prequote	
        _paths := '{"object":' || row_to_json(_t)::text || ',"result":' || _paths || '}';
	END IF;	*/
	_resjso := row_to_json(ROW(_qtt_reci,_qtt_give)::yr_quote);
	
	RETURN _resjso;

END; 
$$ LANGUAGE PLPGSQL;
