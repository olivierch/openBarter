-- set schema 't';

-- init->close->prepare->open->close->prepare->open ...
create type ymarketaction AS ENUM ('init','close','prepare','open');
create table tmarket ( 
    id serial UNIQUE not NULL,
    sess	int not NULL,
    action ymarketaction NOT NULL,
    created timestamp not NULL
);
-- a sequence tmarket_id_seq created

CREATE VIEW vmarket AS SELECT
 	sess AS market_session,
 	created,
 	CASE WHEN action IN ('init','open') THEN 'OPENED' ELSE  'CLOSED' 
	END AS state
	FROM tmarket ORDER BY ID DESC LIMIT 1; 
	
--------------------------------------------------------------------------------
CREATE FUNCTION fcreateuser(_name text) RETURNS void AS $$
DECLARE
	_user	tuser%rowtype;
	_super	bool;
BEGIN
	IF( _name IN ('admin','market','client')) THEN
		RAISE WARNING 'The name % is not allowed',_name;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	SELECT * INTO _user FROM tuser WHERE name=_name;
	IF NOT FOUND THEN
		INSERT INTO tuser (name) VALUES (_name);
		SELECT rolsuper INTO _super FROM pg_authid where rolname=_name;
		IF NOT FOUND THEN
			EXECUTE 'CREATE ROLE ' || _name;
			EXECUTE 'ALTER ROLE ' || _name || ' NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION'; 
			EXECUTE 'ALTER ROLE ' || _name || ' LOGIN CONNECTION LIMIT 1';
		ELSE
			IF(_super) THEN
				RAISE INFO 'The role % is a super user: unchanged.',_name;
			ELSE
				RAISE WARNING 'The user is not found but a role % already exists.',_name;
				RAISE EXCEPTION USING ERRCODE='YU001';				
			END IF;
		END IF;
	ELSE
		RAISE WARNING 'The user % exists.',_name;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	RETURN;
		
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE INFO 'ABORTED';
	RETURN; 
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fcreateuser(text)  TO admin;

--------------------------------------------------------------------------------
CREATE FUNCTION fclose() RETURNS tmarket AS $$
DECLARE
	_hm tmarket%rowtype;
BEGIN
	SELECT * INTO _hm FROM tmarket ORDER BY id DESC LIMIT 1;
	IF(NOT _hm.action IN ('init','open') ) THEN
		RAISE WARNING 'The last action on the market is % ; it should be open or init',_hm.action;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	-- revoke insertion and quotation from client
	REVOKE EXECUTE ON FUNCTION finsertorder(text,text,int8,int8,text,int) FROM market;
	REVOKE EXECUTE ON FUNCTION fgetquote(text,text) FROM market;
		
	SELECT * INTO _hm FROM fchangestatemarket('close');
	RETURN _hm;
	
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE INFO 'ABORTED';
	RETURN _hm; 
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fclose()  TO admin;
--
-- close client access 
-- aborts when some tables are not empty
--------------------------------------------------------------------------------
CREATE FUNCTION fprepare() RETURNS tmarket AS $$
DECLARE
	_hm tmarket%rowtype;
	_cnt int;
BEGIN
	SELECT * INTO _hm FROM tmarket ORDER BY id DESC LIMIT 1;
	IF(NOT _hm.action ='close' ) THEN
		RAISE WARNING 'The state of the market is % ; it should be closed',_hm.action;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	SELECT count(*) INTO _cnt FROM tmvt;
	IF(_cnt != 0) THEN
		RAISE WARNING 'The table tmvt should be empty. It contains % records',_cnt;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	SELECT count(*) INTO _cnt FROM torder;
	IF(_cnt != 0) THEN
		RAISE WARNING 'The table torder should be empty. It contains % records',_cnt;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	SELECT * INTO _hm FROM fchangestatemarket('prepare');
		
	REVOKE market FROM client;
	RETURN _hm;
	
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE INFO 'ABORTED';
	RETURN _hm; 
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fprepare()  TO admin;


--------------------------------------------------------------------------------
CREATE FUNCTION fopen() RETURNS tmarket AS $$
DECLARE
	_hm tmarket%rowtype;
	_cnt int;
BEGIN
	SELECT * INTO _hm FROM tmarket ORDER BY id DESC LIMIT 1;
	IF(NOT _hm.action ='prepare' ) THEN
		RAISE WARNING 'The state of the market is % ; it should be prepare',_hm.action;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	TRUNCATE tmvt;
	PERFORM setval('tmvt_id_seq',1,false);	
	TRUNCATE torder CASCADE;
	PERFORM setval('torder_id_seq',1,false);
	TRUNCATE towner CASCADE;
	PERFORM setval('towner_id_seq',1,false);
	TRUNCATE tquality CASCADE;
	PERFORM setval('tquality_id_seq',1,false);
	TRUNCATE towner CASCADE;
	PERFORM setval('towner_id_seq',1,false);
		
	TRUNCATE torderempty;
	
	VACUUM FULL ANALYZE;
	
	_hm := fchangestatemarket('open');
	
	GRANT EXECUTE ON FUNCTION finsertorder(text,text,int8,int8,text,int) TO market;
	GRANT EXECUTE ON FUNCTION fgetquote(text,text) TO market;
	GRANT market TO client;
	RETURN _hm;
	
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE INFO 'ABORTED';
	RETURN _hm; 
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fopen()  TO admin;


--------------------------------------------------------------------------------
CREATE FUNCTION fchangestatemarket(action ymarketaction) RETURNS tmarket AS $$
DECLARE
	_session int;
	_hm tmarket%rowtype;
BEGIN
	SELECT sess INTO _session FROM tmarket ORDER BY id DESC LIMIT 1;
	IF(NOT FOUND) THEN --init
		_session = 1;
		INSERT INTO tconst (name,value) VALUES ('MARKET_SESSION',1);
		INSERT INTO tconst (name,value) VALUES ('MARKET_OPENED',1);
	ELSE
		IF(action = 'open') THEN
			_session := _session +1;
			UPDATE tconst SET value = 1 WHERE name='MARKET_OPENED';
		ELSE
			IF(action = 'close') THEN
				UPDATE tconst SET value = 0 WHERE name='MARKET_OPENED';
			END IF;			
		END IF;
	END IF;
	
	INSERT INTO tmarket (sess,action,created) VALUES (_session,action,statement_timestamp()) RETURNING * INTO _hm;
	UPDATE tconst SET value = _hm.sess WHERE name='MARKET_SESSION';
	RETURN _hm; 
END;
$$ LANGUAGE PLPGSQL;
SELECT id,sess,action from fchangestatemarket('init'); 
-- not the field created

--------------------------------------------------------------------------------
CREATE FUNCTION fgetuuid(_id int) RETURNS text AS $$ 
DECLARE
	_session	int;
BEGIN
	SELECT value INTO _session FROM tconst WHERE name='MARKET_SESSION';
	RETURN _session::text || '-' || _id::text; 
END;
$$ LANGUAGE PLPGSQL;



