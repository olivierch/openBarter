
/*-------------------------------------------------------------------------------
-- QUOTA MANAGEMENT

for long functions, the time spent to execute it is added to the time used by the user. 
When the time spent reaches a limit, these functions become forbidden for this user.

if this time is greater than a quota defined for this user at the beginning of the function, 
the function is aborted.
The time spent is cleared when the market starts. 

The quota management can be disabled by resetting the quota of users globally or for each user.

-------------------------------------------------------------------------------*/
create function fverifyquota() RETURNS int AS $$
DECLARE 
	_u	tuser%rowtype;
BEGIN
	SELECT * INTO _u FROM tuser WHERE name = session_user;
	IF(_u.id is NULL) THEN
		RAISE WARNING 'the user % is undefined',session_user;
		RAISE EXCEPTION USING ERRCODE='YA005';
	END IF;
	UPDATE tuser SET last_in = statement_timestamp() WHERE name = session_user;
	IF(_u.quota = 0 ) THEN
		RETURN _u.id;
	END IF;

	IF(_u.quota < _u.spent) THEN
		RAISE WARNING 'the quota is reached for the user %',session_user;
		RAISE EXCEPTION USING ERRCODE='YU003';
	END IF;
	RETURN _u.id;

END;		
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
-- 
--------------------------------------------------------------------------------
create function fspendquota(_time_begin timestamp) RETURNS bool AS $$
DECLARE 
	_t2	timestamp;
BEGIN
	_t2 := clock_timestamp();
	UPDATE tuser SET spent = spent + extract (microseconds from (_t2-_time_begin)) WHERE name = session_user;
	RETURN true;
END;		
$$ LANGUAGE PLPGSQL;


