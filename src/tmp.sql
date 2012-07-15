--------------------------------------------------------------------------------
-- tquote
--------------------------------------------------------------------------------
CREATE TABLE tquote (
    id serial UNIQUE not NULL,
    
    own int NOT NULL,
    nr int NOT NULL,
    qtt_requ int8,
    np int NOT NULL,
    qtt_prov int8,
    
    qtt_in int8,
    qtt_out int8,
    flows yflow[],
    
    created timestamp not NULL,
    removed timestamp default NULL,    
    PRIMARY KEY (id)
);
SELECT _grant_read('tquote');
-- SELECT _reference_time('tquote');
-- TODO truncate at market opening

CREATE TABLE tquoteremoved (
    id int NOT NULL,
    
    own int NOT NULL,
    nr int NOT NULL,
    qtt_requ int8,
    np int NOT NULL,
    qtt_prov int8,
    
    qtt_in int8,
    qtt_out int8,
    flows yflow[],
    
    created timestamp,
    removed timestamp
);




--------------------------------------------------------------------------------
-- (id,own,qtt_in,qtt_out,flows) = fgetquote(owner,qltprovided,qttprovided,qttrequired,qltprovided)
/* if qttrequired == 0, 
	qtt_in is the minimum quantity received for a given qtt_out provided
	id == 0 (the quote is not recorded)
   else
   	(qtt_in,qtt_out) is the execution result of an order (qttprovided,qttprovided)
   
   if (id!=0) the quote is recorded
*/
--------------------------------------------------------------------------------
CREATE FUNCTION 
	fgetquote(_owner text,_qualityprovided text,_qttprovided int8,_qttrequired int8,_qualityrequired text) 
	RETURNS tquote AS $$
	
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
	 
	IF(_qttrequired = 0) THEN -- lastignore == true
		_pivot.qtt_requ := 0; -- omega is undefined
		_pivot.qtt_prov := 0; 
		_pivot.qtt := _qttprovided;
	ELSE
		_pivot.qtt_requ := _qttrequired; 
		_pivot.qtt_prov := _qttprovided; 
		_pivot.qtt := _qttprovided;
	END IF;
	
	_r.id 		:= 0;
	_r.own 		:= _pivot.own;
	_r.flows 	:= ARRAY[];
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
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fgetquote(text,text,int8,int8,text) TO client_opened_role;
--------------------------------------------------------------------------------
-- 
--------------------------------------------------------------------------------
-- torder id,uuid,yorder,created,updated
-- yorder: qtt,nr,np,qtt_prov,qtt_requ,own
CREATE FUNCTION 
	fexecquote(_owner text,_idquote int)
	RETURNS tquote AS $$
	
DECLARE
	_wid		int;
	_o		torder%rowtype;
	_start		int8;
	_idpivot	int;
	_idd		int;
	_expected	tquote%rowtype;
	_q		tquote%rowtype;
	_pivot		torder%rowtype;

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
	
	-- _q.qtt_requ != 0		
	_qtt_requ := _q.qtt_requ;
	_qtt_prov := _q.qtt_prov;

			
	INSERT INTO torder (uuid,qtt,nr,np,qtt_prov,qtt_requ,own,created,updated) 
		VALUES ('',_qtt_prov,_q.nr,_q.np,_qtt_prov,_qtt_requ,_q.own,statement_timestamp(),NULL)
		RETURNING id INTO _idpivot;
	_yuuid := fgetuuid(_idpivot);
	_start := fget_treltried(_q.np,_q.nr);
	UPDATE torder SET uuid = _yuuid,start = _start WHERE id=_idpivot RETURNING * INTO _o;
	
	_q.id      := _o.id;
	_q.qtt_in  := 0;
	_q.qtt_out := 0;
	_q.flows   := ARRAY[];
	
	FOR _ypatmax IN SELECT _patmax  FROM finsertflows(_o) LOOP
		_first_mvt := fexecute_flow(_ypatmax);
		_res := yflow_qtts(_ypatmax);
		_q.qtt_in  := _q.qtt_in  + _res[1];
		_q.qtt_out := _q.qtt_out + _res[2];
		_q.flows := array_append(_q.flows,_ypatmax);
	END LOOP;
	
	
	IF (	(_q.qtt_in = 0) OR (_qtt_requ = 0) OR
		((_q.qtt_out::double precision)	/(_q.qtt_in::double precision)) > 
		((_qtt_prov::double precision)	/(_qtt_requ::double precision))
	) THEN
		RAISE NOTICE 'Omega of the flows obtained is not limited by the order';
		RAISE EXCEPTION USING ERRCODE='YA003';
	END IF;
	
	PERFORM fremovequote_int(_idquote);	
	PERFORM finvalidate_treltried();
	
	RETURN _q;
	
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	PERFORM fremovequote_int(_idquote); 
	RAISE INFO 'Abort; Quote removed';
	RETURN _q; 

END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fexecquote(text,int) TO client_opened_role;


--------------------------------------------------------------------------------
CREATE FUNCTION  fremovequote_int(_idquote int) RETURNS void AS $$
BEGIN		
	WITH a AS (DELETE FROM tquote o WHERE o.id=_idquote RETURNING *) 
	INSERT INTO tquoteremoved 
		SELECT id,own,qtt_prov,qtt_requ,flows,created,statement_timestamp() 
	FROM a;					
END;
$$ LANGUAGE PLPGSQL;


