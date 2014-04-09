/*
--------------------------------------------------------------------------------
-- stack primitive management
-------------------------------------------------------------------------------- 

The stack is a FIFO (first in first out) used to submit primitives and execute
them in the order of submission.

*/

create table tstack ( 
    id 			serial UNIQUE not NULL,
    usr 		dtext,
    kind 		eprimitivetype,
    jso 		json,
    submitted 	timestamp not NULL,
    PRIMARY KEY (id)
);

comment on table tstack 			is 'Records the stack of primitives';
comment on column tstack.id 		is 'id of this primitive. For an order, it''s it is also the id of the order';
comment on column tstack.usr 		is 'user submitting the primitive';
comment on column tstack.kind 		is 'type of primitive';
comment on column tstack.jso 		is 'representation of the primitive';
comment on column tstack.submitted 	is 'timestamp when the primitive was successfully submitted';

alter sequence tstack_id_seq owned by tstack.id;

GRANT SELECT ON tstack TO role_com;
GRANT SELECT ON tstack_id_seq TO role_com;


INSERT INTO tvar(name,value) VALUES 
	('STACK_TOP',0),		-- last primitive submitted
	('STACK_EXECUTED',0); 	-- last primitive executed

/*
--------------------------------------------------------------------------------
fstackdone returns true when the stack is empty
*/
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
/*
--------------------------------------------------------------------------------
fpushprimitive is used for submission of a primitive recording it's type, parameters
and the name of the user that submit it.
*/
CREATE FUNCTION  fpushprimitive(_r yj_error,_kind eprimitivetype,_jso json)
	RETURNS yj_primitive AS $$	
DECLARE
	_tid		int;
	_ir 		int;
BEGIN
	IF (_r.code!=0) THEN
		RAISE EXCEPTION 'Primitive cannot be pushed due to error %: %',_r.code,_r.reason;
	END IF; 

    INSERT INTO tstack(usr,kind,jso,submitted)
    	VALUES (session_user,_kind,_jso,statement_timestamp())
    RETURNING id into _tid;

    UPDATE tvar SET value=_tid WHERE name = 'STACK_TOP';

	RETURN ROW(_tid,_r,_jso,NULL,NULL)::yj_primitive;
END; 
$$ LANGUAGE PLPGSQL;
/*
--------------------------------------------------------------------------------
-- consumestack()
--------------------------------------------------------------------------------

consumestack() is processed by postgres in background using a background_worker called 
BGW_CONSUMESTACK (see src/worker_ob.c). 

It consumes the stack of primitives executing each primitive in the order of submission.
Each primitive is wrapped in a single transaction by the background_worker.

*/
CREATE FUNCTION consumestack() RETURNS int AS $$
/*
 * This code is executed by BGW_CONSUMESTACK doing following:
 	while(true)
 		dowait := market.consumestack()
 		if (dowait):
 			waits for dowait milliseconds
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

	IF(NOT FOUND) THEN -- if the stack is empty
		RETURN 20; -- waits for 20 milliseconds
	END IF;

	-- else, process it
	_res := fprocessprimitive(_s);

	-- and records the result in tmsg
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
		RAISE WARNING 'for fprocessprimitive(%)',_s;
		
	RETURN 0;

END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER set search_path = market;
GRANT EXECUTE ON FUNCTION  consumestack() TO role_bo;
/*
--------------------------------------------------------------------------------
-- message acknowledgement
--------------------------------------------------------------------------------

The execution result of a primitive submitted by a user is stores in tmsg or tmsgdaysbefore.
ackmsg(_id,_date) is called by this user to acknowledge this message. 
*/

CREATE TABLE tmsgack (LIKE tmsg);
GRANT SELECT ON tmsgack TO role_com;
--------------------------------------------------------------------------------
CREATE FUNCTION ackmsg(_id int,_date date) RETURNS int AS $$
/*
If found in tmsg or tmsgdaysbefore 
the message is archived and returns 1. Otherwise, returns 0 
*/
DECLARE
	_cnt    int;
BEGIN
	WITH t AS (
		DELETE FROM tmsg 
			WHERE id = _id and (created::date) = _date AND usr=session_user 
		RETURNING * 
	) INSERT INTO tmsgack SELECT * FROM t ;
	GET DIAGNOSTICS _cnt = ROW_COUNT;

	IF( _cnt = 0 ) THEN
		WITH t AS (
			DELETE FROM tmsgdaysbefore 
				WHERE id = _id and (created::date) = _date AND usr=session_user 
			RETURNING * 
		) INSERT INTO tmsgack SELECT * FROM t ;
		GET DIAGNOSTICS _cnt = ROW_COUNT;

		IF( _cnt = 0 ) THEN
			RAISE INFO 'The message could not be found';
			RETURN 0;

		ELSIF(_cnt = 1) THEN
			RETURN 1;

		ELSE
			RAISE EXCEPTION 'Error';
		END IF;

	ELSIF(_cnt = 1) THEN
		RETURN 1;

	ELSE
		RAISE EXCEPTION 'Error';
		
	END IF;
	
	RETURN _cnt;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION ackmsg(int,date) TO role_com;
