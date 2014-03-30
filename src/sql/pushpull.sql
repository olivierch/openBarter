INSERT INTO tvar(name,value) VALUES 
	('STACK_TOP',0),
	('STACK_EXECUTED',0);  -- last primitive executed
--------------------------------------------------------------------------------
CREATE FUNCTION  fstackdone()
	RETURNS boolean AS $$
DECLARE
	_top	int;
	_exe	int;
BEGIN
	SELECT value INTO _top FROM tvar WHERE name = 'STACK_TOP';
	SELECT value INTO _exe FROM tvar WHERE name = 'STACK_EXECUTED';
	RETURN (_top = _exe);
END; 
$$ LANGUAGE PLPGSQL set search_path to market;
--------------------------------------------------------------------------------
CREATE FUNCTION  fpushprimitive(_r yj_error,_kind eprimitivetype,_jso json)
	RETURNS yj_primitive AS $$	
DECLARE
	_tid		int;
	_ir 		int;
BEGIN
	IF (_r.code!=0) THEN
		RAISE EXCEPTION 'Primitive cannot be pushed due to error %: %',_r.code,_r.reason;
	END IF; 
    -- id,usr,kind,jso,submitted
    INSERT INTO tstack(usr,kind,jso,submitted)
    VALUES (session_user,_kind,_jso,statement_timestamp())
    RETURNING id into _tid;

    UPDATE tvar SET value=_tid WHERE name = 'STACK_TOP';

	RETURN ROW(_tid,_r,_jso,NULL,NULL)::yj_primitive;
END; 
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
CREATE FUNCTION consumestack() RETURNS int AS $$
/*
 * This code is executed by the bg_orker doing following:
 	while(true)
 		dowait := market.worker2()
 		if (dowait):
 			wait(dowait) -- milliseconds
*/
DECLARE
	_s			tstack%rowtype;
	_res 		yj_primitive;
	_cnt 		int;
	_txt		text;
	_detail		text;
	_ctx 		text;
BEGIN
	DELETE FROM tstack 
		WHERE id IN (SELECT id FROM tstack ORDER BY id ASC LIMIT 1) 
	RETURNING * INTO _s;

	IF(NOT FOUND) THEN
		RETURN 20; -- OB_DOWAIT 20 milliseconds
	END IF;

	_res := fprocessprimitive('execute',_s);

    INSERT INTO tmsg (usr,typ,jso,created) 
        VALUES (_s.usr,'response',row_to_json(_res),statement_timestamp());

    UPDATE tvar SET value=_s.id WHERE name = 'STACK_EXECUTED';

	RETURN 0;

EXCEPTION WHEN OTHERS THEN
		GET STACKED DIAGNOSTICS 
			_txt = MESSAGE_TEXT,
			_detail = PG_EXCEPTION_DETAIL,
			_ctx = PG_EXCEPTION_CONTEXT;

		RAISE WARNING 'market.consumestack() failed:''%'' ''%'' ''%''',_txt,_detail,_ctx;
	RETURN 0;

END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER set search_path = market;
GRANT EXECUTE ON FUNCTION  consumestack() TO role_bo;


CREATE TABLE tmsgack (LIKE tmsg);
SELECT _grant_read('tmsgack');
--------------------------------------------------------------------------------
CREATE FUNCTION ackmsg(_id int,_date date) RETURNS int AS $$
DECLARE
	_cnt    int;
BEGIN
	WITH t AS (
		DELETE FROM tmsg WHERE id = _id and (created::date) = _date AND usr=session_user 
		RETURNING * 
	) INSERT INTO tmsgack SELECT * FROM t ;
	GET DIAGNOSTICS _cnt = ROW_COUNT;

	IF( _cnt = 0 ) THEN
		WITH t AS (
			DELETE FROM tmsgdaysbefore WHERE id = _id and (created::date) = _date AND usr=session_user 
			RETURNING * 
		) INSERT INTO tmsgack SELECT * FROM t ;
		GET DIAGNOSTICS _cnt = ROW_COUNT;

		IF( _cnt = 0 ) THEN
			RAISE INFO 'The message could not be found';
		END IF;
	END IF;
	
	RETURN _cnt;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  ackmsg(int,date) TO role_com;
