
--------------------------------------------------------------------------------
-- check params
-- code in [-9,0]
--------------------------------------------------------------------------------
CREATE FUNCTION 
	fcheckquaown(_r yj_error,_own dtext,_qua_requ dtext,_pos_requ point,_qua_prov dtext,_pos_prov point,_dist float8)
	RETURNS yj_error AS $$
DECLARE
	_r			yj_error;
	_i 			int;
BEGIN
    IF(NOT ((yflow_checktxt(_own)&1)=1)) THEN
    	_r.reason := '_own is empty string';
    	_r.code := -1;
	    RETURN _r;
    END IF;
    IF(_qua_prov IS NULL) THEN
	    --IF (NOT yflow_quacheck(_qua_requ,1)) THEN
	    IF(NOT ((yflow_checktxt(_qua_requ)&1)=1)) THEN
	    	_r.reason := '_qua_requ is empty string';
	    	_r.code := -2;
	    	RETURN _r;
	    END IF;
    ELSE
        _i = yflow_checkquaownpos(_own,_qua_requ,_pos_requ,_qua_prov,_pos_prov,_dist);
        IF (_i != 0) THEN 
        	_r.reason := 'rejected by yflow_checkquaownpos';
        	_r.code := _i; -- -9<=i<=-5
            return _r;
        END IF;
    END IF;
    
    RETURN _r;
END; 
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
CREATE FUNCTION  fcheckquaprovusr(_r yj_error,_qua_prov dtext,_usr dtext) RETURNS yj_error AS $$
DECLARE
	_QUAPROVUSR boolean := fgetconst('QUAPROVUSR')=1;
	_p int;
	_suffix	text;
BEGIN
	IF (NOT _QUAPROVUSR) THEN 
		RETURN _r;
	END IF;
	_p := position('@' IN _qua_prov);
	IF (_p = 0) THEN
		-- without prefix, it should be a currency
		SELECT count(*) INTO _p FROM tcurrency WHERE _qua_prov = name;
		IF (_p = 1) THEN 
			RETURN _r;
		ELSE
			_r.code := -12;
			_r.reason := 'the quality provided that is not a currency must be prefixed';			
			RETURN _r;
		END IF;
	END IF;

	-- with prefix
	IF (char_length(substring(_qua_prov FROM 1 FOR (_p-1))) <1) THEN
		_r.code := -13;
		_r.reason := 'the prefix of the quality provided cannot be empty';			
		RETURN _r;
	END IF;

	_suffix := substring(_qua_prov FROM (_p+1));
	_suffix := replace(_suffix,'.','_'); 	-- change . to _

	-- it must be the username
	IF ( _suffix!= _usr) THEN
		_r.code := -14;
		_r.reason := 'the prefix of the quality provided must by the user name';			
		RETURN _r;
	END IF;

	RETURN _r;
END; 
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
CREATE FUNCTION fchecknameowner(_r yj_error,_name dtext,_usr dtext) RETURNS yj_error AS $$
DECLARE
	_p 			int;
	_OWNUSR 	boolean := fgetconst('OWNUSR')=1;
	_suffix 	text;
BEGIN
	IF (NOT _OWNUSR) THEN
		RETURN _r;
	END IF;
	_p := position('@' IN _name);
	IF (char_length(substring(_name FROM 1 FOR (_p-1))) <1) THEN
		_r.code := -20;
		_r.reason := 'the owner name has an empty prefix';			
		RETURN _r;
	END IF;
	_suffix := substring(_name FROM (_p+1));
	SELECT count(*) INTO _p FROM townauth WHERE _suffix = name;
	IF (_p = 1) THEN
		RETURN _r; --well known auth provider
	END IF;
	-- change . to _
	_suffix := replace(_suffix,'.','_');
	IF ( _suffix= _usr) THEN
		RETURN _r; -- owners name suffixed by users name
	END IF;
	_r.code := -21;
	_r.reason := 'if the owner name is not prefixed by a well know provider, it must be prefixed by user name';			
	RETURN _r;
END;
$$ LANGUAGE PLPGSQL;

-------------------------------------------------------------------------------- 
-- order primitive  
--------------------------------------------------------------------------------
CREATE TYPE yp_order AS (
	kind	eprimitivetype,
	type eordertype,
	owner dtext,
	qua_requ  dtext,
	qtt_requ  dqtt,
	qua_prov  dtext,
	qtt_prov  dqtt
);
CREATE FUNCTION fsubmitorder(_type eordertype,_owner dtext,_qua_requ dtext,_qtt_requ dqtt,_qua_prov dtext,_qtt_prov dqtt)
	RETURNS yerrorprim AS $$
DECLARE
	_res 		yj_primitive;
	_prim 		yp_order;
BEGIN
	_prim := ROW('order',_type,_owner,_qua_requ,_qtt_requ,_qua_prov,_qtt_prov)::yp_order;
	_res := fprocessorder('submit',NULL,_prim);
	RETURN ROW(_res.id,_res.error)::yerrorprim;
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER  set search_path = market,public;
GRANT EXECUTE ON FUNCTION fsubmitorder(eordertype,dtext,dtext,dqtt,dtext,dqtt) TO role_co;

--------------------------------------------------------------------------------
CREATE FUNCTION fprocessorder(_phase eprimphase, _t tstack,_s yp_order)
	RETURNS yj_primitive AS $$
DECLARE
	_r			yj_error;
	_res	    yj_primitive; 
	_wid		int;
	_ir 		int;
	_o          yorder;
BEGIN
	_r := ROW(0,NULL)::yj_error; -- code,reason	
    CASE
    	
		WHEN (_phase = 'submit') THEN 

    		_r := fchecknameowner(_r,_s.owner,session_user);
    		IF (_r.code!=0) THEN
				RETURN ROW(NULL,_r,NULL,NULL,NULL)::yj_primitive;
    		END IF;
    		_r := fcheckquaprovusr(_r,_s.qua_prov,session_user);
    		IF (_r.code!=0) THEN
				RETURN ROW(NULL,_r,NULL,NULL,NULL)::yj_primitive;
    		END IF; 

			_res := fpushprimitive(_r,'order',row_to_json(_s));
			RETURN _res;

    	WHEN (_phase = 'execute') THEN 
			/*
	        IF(	
	        	(_s.duration IS NOT NULL) AND (_s.submitted + _s.duration) < clock_timestamp()
	        	) THEN
		        _r.reason := 'barter order - the order is too old';
		        _r.code := -19; 
	        END IF;	*/	
			_wid := fgetowner(_s.owner);

	        _o := ROW(CASE WHEN _s.type='limit' THEN 1 ELSE 2 END,
	        		_t.id,_wid,_t.id,
	        		_s.qtt_requ,_s.qua_requ,_s.qtt_prov,_s.qua_prov,_s.qtt_prov,
	                    box('(0,0)'::point,'(0,0)'::point),box('(0,0)'::point,'(0,0)'::point),
	                    0.0,earth_get_square('(0,0)'::point,0.0)
	              )::yorder;

	        _ir := insertorder(_s.owner,_o,_t.usr,_t.submitted,'1 day');
        
	        RETURN ROW(_t.id,NULL,_t.jso,
				row_to_json(ROW(_o.id,_o.qtt,_o.qua_prov,_s.owner,_t.usr)::yj_stock),
				NULL
	        	)::yj_primitive;

    	ELSE
    		RAISE EXCEPTION 'Should not reach this point';
    END CASE;

    
END;
$$ LANGUAGE PLPGSQL;
-------------------------------------------------------------------------------- 
-- child order primitive
--------------------------------------------------------------------------------
CREATE TYPE yp_childorder AS (
	kind	eprimitivetype,
	owner 	dtext,
	qua_requ  dtext,
	qtt_requ  dqtt,
	stock_id int
);
CREATE FUNCTION  fsubmitchildorder(_owner dtext,_qua_requ dtext,_qtt_requ dqtt,_stock_id int)
	RETURNS yerrorprim AS $$
DECLARE
	_res		yj_primitive;
	_prim 		yp_childorder;
BEGIN
	
	_prim := ROW('childorder',_owner,_qua_requ,_qtt_requ,_stock_id)::yp_childorder;
	_res := fprocesschildorder('submit',NULL,_prim);
	RETURN ROW(_res.id,_res.error)::yerrorprim;
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER set search_path = market,public;
GRANT EXECUTE ON FUNCTION fsubmitchildorder(dtext,dtext,dqtt,int) TO role_co;

--------------------------------------------------------------------------------
CREATE FUNCTION fprocesschildorder(_phase eprimphase, _t tstack,_s yp_childorder)
	RETURNS yj_primitive AS $$
DECLARE
	_r			yj_error;
	_res	    yj_primitive; 
	_wid		int;
	_otype		int;
	_ir 		int;
	_o          yorder;
	_op         torder%rowtype;
	_sp 		tstack%rowtype;
BEGIN
	_r := ROW(0,NULL)::yj_error; -- code,reason
    CASE
    
    	WHEN (_phase = 'submit') THEN 

    		_r := fchecknameowner(_r,_s.owner,session_user);
    		IF (_r.code!=0) THEN
				RETURN ROW(NULL,_r,NULL,NULL,NULL)::yj_primitive;
    		END IF;
    		_r := fcheckquaprovusr(_r,_s.qua_requ,session_user);
    		IF (_r.code!=0) THEN
				RETURN ROW(NULL,_r,NULL,NULL,NULL)::yj_primitive;
    		END IF;

			_wid := fgetowner(_s.owner);
			SELECT * INTO _op FROM torder WHERE 
				(ord).id = _s.stock_id AND usr = session_user AND (ord).own = _wid;
			IF (NOT FOUND) THEN
				/* could be found in the stack */
				SELECT * INTO _sp FROM tstack WHERE 
					id = _s.stock_id AND usr = session_user AND _s.owner = jso->'owner' AND kind='order';
				IF (NOT FOUND) THEN
					_r.code := -200;
					_r.reason := 'the order was not found for this user and owner';
					RETURN ROW(NULL,_r,NULL,NULL,NULL)::yj_primitive;
				END IF;
			END IF; 

			_res := fpushprimitive(_r,'childorder',row_to_json(_s));
			RETURN _res;

    	WHEN (_phase = 'execute') THEN 
	
			_wid := fgetowner(_s.owner);
			SELECT * INTO _op FROM torder WHERE 
				(ord).id = _s.stock_id AND usr = session_user AND (ord).own = _wid;
			IF (NOT FOUND) THEN
					_r.code := -201;
					_r.reason := 'the stock is not in the order book';
					RETURN ROW(_t.id,_r,_t.jso,NULL,NULL)::yj_primitive;
			END IF;
	        _o := _op.ord;
	        _o.id := _id;
	        _o.qua_requ := _s.qua_requ;
	        _o.qtt_requ := _s.qtt_requ;

	        _ir := insertorder(_s.owner,_o,_s.usr,_s.submitted,_op.duration);
        
	        RETURN ROW(_t.id,NULL,_t.jso,NULL,NULL)::yj_primitive;

    	ELSE
    		RAISE EXCEPTION 'Should not reach this point';
    END CASE;

    
END;
$$ LANGUAGE PLPGSQL;

-------------------------------------------------------------------------------- 
-- rm primitive 
--------------------------------------------------------------------------------
CREATE TYPE yp_rmorder AS (
	kind	eprimitivetype,
	owner 	dtext,
	stock_id int
);
CREATE FUNCTION  fsubmitrmorder(_owner dtext,_stock_id int)
	RETURNS yerrorprim AS $$
DECLARE
	_res		yj_primitive;
	_prim 		yp_rmorder;
BEGIN
	
	_prim := ROW('rmorder',_owner,_stock_id)::yp_rmorder;
	_res := fprocessrmorder('submit',NULL,_prim);
	RETURN ROW(_res.id,_res.error)::yerrorprim;
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER set search_path = market,public;
GRANT EXECUTE ON FUNCTION fsubmitrmorder(dtext,int) TO role_co,role_bo;

--------------------------------------------------------------------------------
CREATE FUNCTION fprocessrmorder(_phase eprimphase, _t tstack,_s yp_rmorder)
	RETURNS yj_primitive AS $$
DECLARE
	_r			yj_error;
	_res	    yj_primitive;
	_wid		int;
	_otype		int;
	_ir 		int;
	_o          yorder;
	_opy		yorder; -- parent_order
	_op         torder%rowtype;
	_te 		text;
	_pusr		text;
	_sp 		tstack%rowtype;
BEGIN
	_r := ROW(0,NULL)::yj_error; -- code,reason
    CASE
    
    	WHEN (_phase = 'submit') THEN 

    		_r := fchecknameowner(_r,_s.owner,session_user);
    		IF (_r.code!=0) THEN
				RETURN ROW(NULL,_r,NULL,NULL,NULL)::yj_primitive;
    		END IF;

			_wid := fgetowner(_s.owner);
			SELECT * INTO _op FROM torder WHERE 
				(ord).id = _s.stock_id AND usr = session_user AND (ord).own = _wid AND (ord).id=(ord).oid;
			IF (NOT FOUND) THEN
				/* could be found in the stack */
				SELECT * INTO _sp FROM tstack WHERE 
					id = _s.stock_id AND usr = session_user AND _s.owner = jso->'owner' AND kind='order' AND (ord).id=(ord).oid;
				IF (NOT FOUND) THEN
					_r.code := -300;
					_r.reason := 'the order was not found for this user and owner';
					RETURN ROW(NULL,_r,NULL,NULL,NULL)::yj_primitive;
				END IF;
			END IF; 

			_res := fpushprimitive(_r,'rmorder',row_to_json(_s));
			RETURN _res;

    	WHEN (_phase = 'execute') THEN 
	
			_wid := fgetowner(_s.owner);
			SELECT * INTO _op FROM torder WHERE 
				(ord).id = _s.stock_id AND usr = session_user AND (ord).own = _wid AND (ord).id=(ord).oid;
			IF (NOT FOUND) THEN
					_r.code := -301;
					_r.reason := 'the stock is not in the order book';
					RETURN ROW(_t.id,_r,_t.json,NULL,NULL)::yj_primitive;
			END IF;

		    -- delete order and sub-orders from the book
		    DELETE FROM torder o WHERE (o.ord).oid = _yo.oid;
        
        	-- id,error,primitive,result
	        RETURN ROW(_t.id,NULL,_t.json,
	        	ROW((_op.ord).id,(_op.ord).qtt,(_op.ord).qua_prov,_s.owner,_op.usr)::yj_stock,
	        	ROW((_op.ord).qua_prov,(_op.ord).qtt)::yj_value
	        	)::yj_primitive;

    	ELSE
    		RAISE EXCEPTION 'Should not reach this point';
    END CASE;

    
END;
$$ LANGUAGE PLPGSQL;
-------------------------------------------------------------------------------- 
-- quote 
--------------------------------------------------------------------------------
CREATE FUNCTION fsubmitquote(_type eordertype,_owner dtext,_qua_requ dtext,_qtt_requ dqtt,_qua_prov dtext,_qtt_prov dqtt)
	RETURNS yerrorprim AS $$
DECLARE
	_res		yj_primitive;
	_prim 		yp_order;
BEGIN
	
	_prim := ROW('quote',_type,_owner,_qua_requ,_qtt_requ,_qua_prov,_qtt_prov)::yp_order;
	_res := fprocessquote('submit',NULL,_prim);
	RETURN ROW(_res.id,_res.error)::yerrorprim;
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER set search_path = market,public;
GRANT EXECUTE ON FUNCTION fsubmitquote(eordertype,dtext,dtext,dqtt,dtext,dqtt) TO role_co;

--------------------------------------------------------------------------------
CREATE FUNCTION fprocessquote(_phase eprimphase, _t tstack,_s yp_order)
	RETURNS yj_primitive AS $$
DECLARE
	_r			yj_error;
	_res	    yj_primitive;
	_wid		int;
	_ir 		int;
	_o          yorder;
	_type 		int;
	_json_res	json;
BEGIN
	_r := ROW(0,NULL)::yj_error; -- code,reason
    CASE
    
    	WHEN (_phase = 'submit') THEN 

    		_r := fchecknameowner(_r,_s.owner,session_user);
    		IF (_r.code!=0) THEN
				RETURN ROW(NULL,_r,NULL,NULL,NULL)::yj_primitive;
    		END IF;
    		_r := fcheckquaprovusr(_r,_s.qua_prov,session_user);
    		IF (_r.code!=0) THEN
				RETURN ROW(NULL,_r,NULL,NULL,NULL)::yj_primitive;
    		END IF; 

			_res := fpushprimitive(_r,'quote',row_to_json(_s));
			RETURN _res;

    	WHEN (_phase = 'execute') THEN 

			_wid := fgetowner(_s.owner);
			_type := CASE WHEN _s.type='limit' THEN 1 ELSE 2 END;
	        _o := ROW( _type,
	        		_s.id,_wid,_s.id,
	        		_s.qtt_requ,_s.qua_requ,_s.qtt_prov,_s.qua_prov,_s.qtt_prov,
	                    box('(0,0)'::point,'(0,0)'::point),box('(0,0)'::point,'(0,0)'::point),
	                    _s.dist,earth_get_square(box('(0,0)'::point,0.0))
	             )::yorder;

/*fproducequote(_ord yorder,_isquote boolean,_isnoqttlimit boolean,_islimit boolean,_isignoreomega boolean) 
*/
	        _json_res := fproducequote(_o,true,false,_s.type='limit',false);
        
	        RETURN ROW(_t.id,NULL,_t.json,_tx,NULL,NULL)::yj_primitive;

    	ELSE
    		RAISE EXCEPTION 'Should not reach this point';
    END CASE;

    
END;
$$ LANGUAGE PLPGSQL;

-------------------------------------------------------------------------------- 
-- primitive processing  
--------------------------------------------------------------------------------
CREATE FUNCTION fprocessprimitive(_phase eprimphase, _s tstack)
	RETURNS yj_primitive AS $$
DECLARE
	_res 		yj_primitive;
	_kind		eprimitivetype;
BEGIN
	_kind := _s.kind;

	CASE
		WHEN (_kind = 'order' ) THEN
			_res := fprocessorder(_phase,_s,json_populate_record(NULL::yp_order,_s.jso));
		WHEN (_kind = 'childorder' ) THEN
			_res := fprocesschildorder(_phase,_s,json_populate_record(NULL::yp_childorder,_s.jso));
		WHEN (_kind = 'rmorder' ) THEN
			_res := fprocessrmorder(_phase,_s,json_populate_record(NULL::yp_rmorder,_s.jso));
		WHEN (_kind = 'quote' ) THEN
			_res := fprocessquote(_phase,_s,json_populate_record(NULL::yp_order,_s.jso));
		ELSE
			RAISE EXCEPTION 'Should not reach this point';
	END CASE;

	RETURN _res; 
END;
$$ LANGUAGE PLPGSQL;





