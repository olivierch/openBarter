
--------------------------------------------------------------------------------
-- check params of quote
--------------------------------------------------------------------------------
CREATE FUNCTION 
	fcheckquaown(_own text,_qua_requ text,_qua_prov text)
	RETURNS yressubmit AS $$	
DECLARE
	_r			 yressubmit%rowtype;
BEGIN
    _r.id := 0;
    _r.diag := 0;
    
	IF(NOT((fchecktxt(_qua_prov)=0) AND (fchecktxt(_qua_requ)=0) AND (fchecktxt(_own)=0))) THEN 
		_r.diag := -1;
		RETURN _r;
	END IF;	
    IF(_qua_prov = _qua_requ) THEN
	    _r.diag := -1;
	    RETURN _r;
    END IF;
    
    RETURN _r;
END; 
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
-- prequote
--------------------------------------------------------------------------------
CREATE FUNCTION 
	fsubmitprequote(_own text,_qua_requ text,_qua_prov text)
	RETURNS yressubmit AS $$	
DECLARE
	_r			 yressubmit%rowtype;
BEGIN
    _r := fcheckquaown(_own,_qua_requ,_qua_prov);
    if(_r.diag !=0) THEN
        return _r;
    END IF;
	
	-- ORDER_BEST 2 NOQTTLIMIT 4 IGNOREOMEGA 8 PREQUOTE 64
	_r.id := fsubmitorder(2 | 4 | 8 | 64,_own,NULL,_qua_requ,NULL,_qua_prov,NULL,NULL,NULL);
	_r.diag = 0;
	
	RETURN _r;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fsubmitprequote(text,text,text) TO role_co;

--------------------------------------------------------------------------------
-- all forms
--------------------------------------------------------------------------------
CREATE FUNCTION 
	fsubmitquote(_type dtypeorder,_own text,_qua_requ text,_qtt_requ int8,_qua_prov text,_qtt_prov int8,_qtt int8)
	RETURNS yressubmit AS $$	
DECLARE
	_r			 yressubmit%rowtype;
	_otype      int;
BEGIN
    _r := fcheckquaown(_own,_qua_requ,_qua_prov);
    if(_r.diag !=0) THEN
        return _r;
    END IF;
	
	_otype := _type & 3;
	
	IF((_qtt IS NULL) AND (_qtt_requ IS NULL) AND (_qtt_prov IS NULL)) THEN -- quote first form
	    _otype := _otype | 4 | 8 | 128; -- NOQTTLIMIT 4 IGNOREOMEGA 8 QUOTE 128
	ELSIF((_qtt IS NULL) AND (_qtt_requ >0) AND (_qtt_prov >0)) THEN -- quote second form
	    _otype := _otype | 4 | 128; --  NOQTTLIMIT 4 QUOTE 128
	ELSIF((_qtt > 0) AND (_qtt_requ >0) AND (_qtt_prov >0) ) THEN -- quote third form	
	    _otype := _otype | 128; --  QUOTE 128
	ELSE 
	    _r.diag := -2;
	    RETURN _r;
	END IF;
	
	_r.id := fsubmitorder(_otype,_own,NULL,_qua_requ,_qtt_requ,_qua_prov,_qtt_prov,_qtt,NULL);
	_r.diag = 0;
	RETURN _r;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fsubmitquote(dtypeorder,text,text,int8,text,int8,int8) TO role_co;

--------------------------------------------------------------------------------
-- quote first form -shortcut
--------------------------------------------------------------------------------
CREATE FUNCTION 
	fsubmitquote(_type dtypeorder,_own text,_qua_requ text,_qua_prov text)
	RETURNS yressubmit AS $$
DECLARE
	_r			 yressubmit%rowtype;	
BEGIN
	_r := fsubmitquote(_type,_own,_qua_requ,NULL,_qua_prov,NULL,NULL);
	RETURN _r; 
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fsubmitquote(dtypeorder,text,text,text) TO role_co;

--------------------------------------------------------------------------------
-- quote second form -shortcut
--------------------------------------------------------------------------------
CREATE FUNCTION 
	fsubmitquote(_type dtypeorder,_own text,_qua_requ text,_qtt_requ int8,_qua_prov text,_qtt_prov int8)
	RETURNS yressubmit AS $$	
DECLARE
	_r			 yressubmit%rowtype;	
BEGIN
	_r := fsubmitquote(_type,_own,_qua_requ,_qtt_requ,_qua_prov,_qtt_prov,NULL);
	RETURN _r; 
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fsubmitquote(dtypeorder,text,text,int8,text,int8) TO role_co;


--------------------------------------------------------------------------------
-- quote execution at the output of the stack
--------------------------------------------------------------------------------
CREATE FUNCTION fproducequote(_ro yresorder,_t tstack,_record boolean) RETURNS yresorder AS $$
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
	_give       text;
	
BEGIN
	_cnt := fcreate_tmp(_ro.ord);
	_nbmvts := 0;
	_ro.json := '';
	_give := '';
	
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
		-- _res = [x[f->dim-2].flowr,x[f->dim-1].flowr,x[f->dim-1].qtt_requ,x[f->dim-1].qtt_prov,x[f->dim-1].qtt]
		
		_ro.qtt_reci := _ro.qtt_reci + _res[1];
		_ro.qtt_give := _ro.qtt_give + _res[2];
				
		_ro.json := _ro.json || yflow_to_jsona(_cyclemax);

		-- for a QUOTE, set _ro.qtt_requ,_ro.qtt_prov,_ro.qtt
		IF((_t.type & 128) = 128) THEN -- QUOTE
			IF(_firstloop) THEN
				_ro.qtt_requ := _res[3]; -- qtt_requ
				_ro.qtt_prov := _res[4]; -- qtt_prov
			END IF;
		
			IF((_t.type & 4) = 4) THEN -- NOLIMITQTT
				_ro.qtt	:= _ro.qtt + _res[5]; -- qtt
			ELSE
				IF(_firstloop) THEN
					_ro.qtt		 := _res[5]; -- qtt
				END IF;
			END IF;
		END IF;
		-- for a PREQUOTE they remain 0
				
/* 	if _setOmega, for all remaining orders:
		- omega is set to _ro.qtt_requ,_ro.qtt_prov
		- IGNOREOMEGA is reset
	
	for all updates, yflow_reduce is applied except for node with NOQTTLIMIT
*/
		_freezeOmega := _firstloop AND ((_t.type & (8|128)) = (8|128));
		UPDATE _tmp SET cycle = yflow_reduce(cycle,_cyclemax,_freezeOmega);
		_firstloop := false;
			
		DELETE FROM _tmp WHERE NOT yflow_is_draft(cycle);
		
	END LOOP;

	IF (	(_ro.qtt_requ != 0) 
		AND ((_t.type & 3) = 1) -- ORDER_LIMIT
		AND ((_t.type & (128)) = (128)) -- QUOTE
		AND	((_ro.qtt_give::double precision)	/(_ro.qtt_reci::double precision)) > 
			((_ro.qtt_prov::double precision)	/(_ro.qtt_requ::double precision))
	) THEN	
		RAISE EXCEPTION 'pq: Omega of the flows obtained is not limited by the order limit' USING ERRCODE='YA003';
	END IF;
	
	_ro.json :='{"qtt_requ":' || _ro.qtt_requ || ',"qtt_prov":' || _ro.qtt_prov || ',"qtt":' || _ro.qtt  || 
		',"qtt_reci":' || _ro.qtt_reci || ',"qtt_give":' || _ro.qtt_give || 
		',"paths":[' || chr(10) || _ro.json || chr(10) ||']}';
	_ro.err := 1;
		
	IF(_record) THEN
	    INSERT INTO tmvt (	type,json,xid,    usr,xoid, 
						    refused,order_created,created
					     ) 
		    VALUES       (	_t.type,_ro.json,_t.id,_t.usr,(_ro.ord).oid,
						    _ro.err,_t.created,statement_timestamp()
					     )
		    RETURNING id INTO _mid;
	    UPDATE tmvt SET grp = _mid WHERE id = _mid;
	END IF;
	
	RETURN _ro;

END; 
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
-- obtain quote directly TODO
--------------------------------------------------------------------------------
CREATE FUNCTION 
	fgetquote(_type dtypeorder,_own text,_qua_requ text,_qtt_requ int8,_qua_prov text,_qtt_prov int8,_qtt int8)
	RETURNS yresorder AS $$	
DECLARE
    _rs			 yressubmit%rowtype;
	_r			 yresorder%rowtype;
	_ty           int;
	_t           tstack%rowtype;
BEGIN
	_rs := fcheckquote(_type & 3,_own,_qua_requ,_qtt_requ,_qua_prov,_qtt_prov,_qtt);
	IF(_rs.diag != 0) THEN
	    _r.err := _rs.diag;
		RETURN _r;
	END IF;
	_ty := _type & ~3;

	IF(
	    (_ty = (4 | 8 | 64))  OR (_ty = (4 | 8 | 128)) 
	) THEN 
	    _qtt_requ := 1;
	    _qtt_prov := 1;
	    _qtt := 1;
	ELSIF(
	    (_ty = (4 | 128)) AND (_qtt_requ IS NOT NULL) AND (_qtt_prov IS NOT NULL)
	) THEN
	    _qtt := 0;
	ELSIF(
	    (_ty = (128)) AND (_qtt_requ IS NOT NULL) AND (_qtt_prov IS NOT NULL) AND (_qtt_prov IS NOT NULL)
	) THEN
	    _t.oid := 0; -- rien dutout
	ELSE
	    _r.err := -100;
	    RETURN _r;	
	END IF;

    _t.id  := 0;
	_t.usr := session_user;
	_t.own := _own;
	_t.oid := NULL;
	_t.type := _type;
	_t.qua_requ := _qua_requ;
	_t.qtt_requ := _qtt_requ;
	_t.qua_prov := _qua_prov;
	_t.qtt_prov := _qtt_prov;
	_t.qtt := _qtt;
	_t.duration := NULL;
	_t.created := NULL;
	
	_r := fproducequote(_t,false);	
	RETURN _r;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fgetquote(dtypeorder,text,text,int8,text,int8,int8) TO role_co;

