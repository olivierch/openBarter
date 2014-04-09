\set ECHO none
\set ON_ERROR_STOP on

/* script executed for the whole cluster */

SET client_min_messages = warning;
SET log_error_verbosity = terse;
BEGIN;
/* flowf extension */

-- drop extension if exists btree_gin cascade;
-- create extension btree_gin with version '1.0';

DROP EXTENSION IF EXISTS flowf;
CREATE EXTENSION flowf WITH VERSION '0.1';
--------------------------------------------------------------------------------

CREATE FUNCTION _create_role(_role text) RETURNS int AS $$
BEGIN
	BEGIN 
		EXECUTE 'CREATE ROLE ' || _role; 
	EXCEPTION WHEN duplicate_object THEN
		NULL;	
	END;
	EXECUTE 'ALTER ROLE ' || _role || ' NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION';	
	RETURN 0;
END; 
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
/* definition of roles

	-- role_com ----> role_co --------->role_client---->clientA
	             |                                  \-->clientB 
	             |\-> role_co_closed
	             |
	              \-> role_bo---->user_bo
	
	access by clients can be disabled/enabled with a single command:
		REVOKE role_co FROM role_client
		GRANT role_co TO role_client

	opening/closing of market is performed by switching role_client
	between role_co and role_co_closed
		
	same thing for role batch with role_bo:
		REVOKE role_bo FROM user_bo
		GRANT role_bo TO user_bo
*/
--------------------------------------------------------------------------------
select _create_role('prod'); -- owner of market objects
ALTER ROLE prod WITH createrole; 
/* so that prod can modify roles at opening and closing. */

select _create_role('role_com');

SELECT _create_role('role_co');        -- when market is opened
GRANT role_com TO role_co;

SELECT _create_role('role_co_closed'); -- when market is closed
GRANT role_com TO role_co_closed;

SELECT _create_role('role_client');
GRANT role_co_closed TO role_client;         -- maket phase 101

-- role_com ---> role_bo----> user_bo

SELECT _create_role('role_bo');
GRANT role_com TO role_bo;
-- ALTER ROLE role_bo INHERIT;

SELECT _create_role('user_bo');
GRANT role_bo TO user_bo;
-- two connections are allowed for background_workers
-- BGW_OPENCLOSE and BGW_CONSUMESTACK
ALTER ROLE user_bo WITH LOGIN CONNECTION LIMIT 2;


--------------------------------------------------------------------------------
select _create_role('test_clienta');
ALTER ROLE test_clienta WITH login;
GRANT role_client TO test_clienta;

select _create_role('test_clientb');
ALTER ROLE test_clientb WITH login;
GRANT role_client TO test_clientb;

select _create_role('test_clientc');
ALTER ROLE test_clientc WITH login;
GRANT role_client TO test_clientc;

select _create_role('test_clientd');
ALTER ROLE test_clientd WITH login;
GRANT role_client TO test_clientd;
COMMIT;




