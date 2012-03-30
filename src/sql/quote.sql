-- set schema 't';

--------------------------------------------------------------------------------
CREATE FUNCTION 
	fget_quality(_quality_name text) 
	RETURNS int AS $$
DECLARE 
	_id int;
BEGIN
	SELECT id INTO _id FROM tquality WHERE name = _quality_name;
	IF NOT FOUND THEN
		RAISE WARNING 'The quality "%" is undefined',_quality_name;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	RETURN _id;
END;
$$ LANGUAGE PLPGSQL;
	
--------------------------------------------------------------------------------
-- fgetquote
--------------------------------------------------------------------------------
-- PUBLIC
/* usage: 
	nb_draft int = fgetquote(_qualityprovided text,_qualityrequired text)
		
	action:
		read omegas.
		if _qualityprovided or _qualityrequired do not exist, the function exists
	
	returns list of
		_qtt_prov,_qtt_requ

*/
--------------------------------------------------------------------------------
CREATE FUNCTION 
	fgetquote(_owner text,_qualityprovided text,_qualityrequired text) 
	RETURNS TABLE(_dim int,_qtt_prov int8,_qtt_requ int8 ) AS $$
	
DECLARE
	_np	int;
	_nr	int;
	_time_begin timestamp;
	_uid	int;
	_wid	int;
BEGIN
	_uid := fconnect(true);
	_time_begin := clock_timestamp();
	
	-- qualities are red
	_np := fget_quality(_qualityprovided); 
	_nr := fget_quality(_qualityrequired);
	-- RAISE INFO '_np=%,_nr=%' , _np,_nr;

	SELECT id INTO _wid FROM towner WHERE name = _owner;
	IF NOT FOUND THEN
		_wid := 0;
	END IF;
		
	FOR _dim,_qtt_prov,_qtt_requ IN SELECT * FROM fgetquote_int(_wid,_np,_nr) LOOP
		RETURN NEXT;
	END LOOP;
	
	perform fspendquota(_time_begin);
	
	RETURN;
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE INFO 'ABORTED';
	RETURN;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fgetquote(text,text,text) TO market;
/*
CREATE VIEW vorder_int AS
	SELECT id,yorder_get(id,own,nr,qtt_requ,np,qtt_prov,qtt) as ord,np,nr FROM torder;
*/
CREATE FUNCTION fgetquote_int(_wid int,_np int,_nr int) RETURNS TABLE(_dim int,_qtt_prov int8,_qtt_requ int8) AS $$
DECLARE 
	_patmax	yflow;
	_res	int8[];
	_cnt int;
	_start timestamp;
BEGIN
	_cnt := fcreate_tmp(0,yorder_get(0,_wid,_nr,1,_np,1,1),_np,_nr);
	
/*	DROP TABLE IF EXISTS _tmp_quote;
	CREATE TABLE _tmp_quote AS (SELECT * FROM _tmp);
*/
	IF(_cnt=0) THEN
		RETURN;
	END IF;
	_cnt :=0;
	LOOP	
		_cnt := _cnt+1;
		SELECT yflow_max(pat) INTO _patmax FROM _tmp;
		IF (yflow_status(_patmax)!=3) THEN
			EXIT; -- from LOOP
		END IF;
/*
		IF(_cnt = 1) THEN
			RAISE NOTICE 'get max = %',yflow_show(_patmax);
		END IF;
*/
		-- RAISE NOTICE 'get max = %',yflow_show(_patmax);
		-- RETURN;
		----------------------------------------------------------------
		_res := yflow_qtts(_patmax);
		_qtt_prov := _res[1];
		_qtt_requ := _res[2];
		_dim 	:= _res[3];
		-- RAISE NOTICE 'maxflow %' ,yflow_show(_patmax);
		RETURN NEXT;
		----------------------------------------------------------------
		UPDATE _tmp SET pat = yflow_reduce(pat,_patmax);

	END LOOP;
	
	DROP TABLE _tmp;
	RETURN;
END; 
$$ LANGUAGE PLPGSQL;

	
--------------------------------------------------------------------------------
-- fgetquote
--------------------------------------------------------------------------------
-- PUBLIC
/* usage: 
	nb_draft int = fgetquoteorder(_owner text,_qualityprovided text,_qttprovided int8,_qttrequired int8,_qualityrequired text)
		
	action:
		read omegas.
		if _qualityprovided or _qualityrequired do not exist, the function exists
	
	returns list of
		_qtt_prov,_qtt_requ

*/
--------------------------------------------------------------------------------

CREATE FUNCTION 
	fgetquoteorder(_owner text,_qualityprovided text,_qttprovided int8,_qttrequired int8,_qualityrequired text) 
	RETURNS TABLE(_dim int,_qtt_prov int8,_qtt_requ int8 ) AS $$
	
DECLARE
	_np	int;
	_nr	int;
	_time_begin timestamp;
	_uid	int;
	_wid	int;
	_pivot torder%rowtype;
BEGIN
	_uid := fconnect(true);
	_time_begin := clock_timestamp();
	
	SELECT id INTO _wid FROM towner WHERE name = _owner;
	IF NOT FOUND THEN
		_wid := 0;
	END IF;
	
	-- qualities are red
	_pivot.np := fget_quality(_qualityprovided); 
	_pivot.nr := fget_quality(_qualityrequired);
	-- _pivot.id  := 0;
	_pivot.own := _wid;
	_pivot.qtt_requ := _qttrequired;
	_pivot.qtt_prov := _qttprovided;
	_pivot.qtt := _qttprovided;
		
	FOR _dim,_qtt_prov,_qtt_requ IN SELECT _zdim,_zqtt_prov,_zqtt_requ  FROM finsert_order_int(_pivot,FALSE) LOOP
		RETURN NEXT;
	END LOOP;
	
	perform fspendquota(_time_begin);
	
	RETURN;
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE INFO 'ABORTED';
	RETURN;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fgetquoteorder(text,text,int8,int8,text) TO market;
/*
select sum(_qtt_prov),sum(_qtt_requ),sum(_qtt_prov)/sum(_qtt_requ) from fgetquote('1','q3','q2');
select sum(_qtt_prov),sum(_qtt_requ),sum(_qtt_prov)/sum(_qtt_requ) from fgetquoteorder('1','q3',5429898,4904876,'q2');

sum_qtt_prov(path)
sum_qtt_requ(path)
*/

