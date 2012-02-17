
--------------------------------------------------------------------------------
-- error reported to the client only
-- OK tested
create function fuser(_she text,_quota int8) RETURNS void AS $$
BEGIN
	LOOP
		UPDATE tuser SET quota = _quota WHERE name = _she;
		IF FOUND THEN
			RAISE INFO 'user "%" updated',_she;
			RETURN;
		END IF;
			
		BEGIN
			EXECUTE 'CREATE ROLE ' || _she || ' WITH LOGIN CONNECTION LIMIT 1 IN ROLE client';
			INSERT INTO tuser (name,quota,last_in) VALUES (_she,_quota,NULL);
			RAISE INFO 'tuser and role % are created',_she;
			RETURN;
			
		EXCEPTION 
			WHEN duplicate_object THEN
				RAISE NOTICE 'ERROR the role already "%" exists while the tuser does not.',_she;
				RAISE NOTICE 'You should add the tuser.name=% first.',_she;
				RAISE EXCEPTION USING ERRCODE='YU001';
				RETURN; 
			WHEN unique_violation THEN
				RAISE NOTICE 'ERROR the role "%" does nt exists while the tuser exists.',_she;
				RAISE NOTICE 'You should delete the tuser.name=% first.',_she;
				RAISE EXCEPTION USING ERRCODE='YU001';
				RETURN; 
		END;
	END LOOP;
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE NOTICE 'ABORTED';
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fuser(text,int8) TO market;

--------------------------------------------------------------------------------
create or replace function fspendquota(_time_begin timestamp) RETURNS bool AS $$
DECLARE
	_millisec int8;
BEGIN
	_millisec := CAST(EXTRACT(milliseconds FROM (clock_timestamp() - _time_begin)) AS INT8);
	UPDATE tuser SET spent = spent+_millisec WHERE name=current_user;
	IF NOT FOUND THEN
		RAISE NOTICE 'user "%" does not exist',current_user;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	RETURN true;
END;		
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
/*	bool fconnect(_she txt)
returns false if one of these conditions occur:
	she is not recorded, 
	she has a quota and it it consumed,
or true otherwise.
*/
create or replace function fconnect(verifyquota bool) RETURNS int8 AS $$
DECLARE
	_user tuser%rowtype;
BEGIN
	UPDATE tuser SET last_in=clock_timestamp() WHERE name=current_user RETURNING * INTO _user;
	IF NOT FOUND THEN
		RAISE NOTICE 'user "%" does not exist',current_user;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	IF (verifyquota AND NOT(_user.quota = 0 OR _user.spent<=_user.quota)) THEN
		RAISE NOTICE 'quota reached for user "%" ',current_user;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;

	RETURN _user.id;
END;		
$$ LANGUAGE PLPGSQL;
