/*------------------------------------------------------------------------------
MARKET
						client role			action
STARTING

STARTING->OPENED (open)

OPENED					client_opened_role

OPENED->STOPPING (stop)

STOPPING				client_stopping_role

STOPPING->CLOSED (close)

CLOSED

CLOSED->STARTING (start)				frenumbertables()
------------------------------------------------------------------------------*/

--------------------------------------------------------------------------
CREATE TYPE ymarketstatus AS ENUM ('INITIALIZING','OPENED', 'STOPPING','CLOSED','STARTING');

create table tmarket ( 
    id serial UNIQUE not NULL,
    created timestamp not NULL
);
alter sequence tmarket_id_seq owned by tmarket.id;
SELECT _grant_read('tmarket');
--------------------------------------------------------------------------------

-- history of states of the market 
CREATE VIEW vmarkethistory AS SELECT
	id,
	(id+4)/4 as market_session,
	CASE 	WHEN (id-1)%4=0 THEN 'OPENED'::ymarketstatus 	
		WHEN (id-1)%4=1 THEN 'STOPPING'::ymarketstatus
		WHEN (id-1)%4=2 THEN 'CLOSED'::ymarketstatus
		WHEN (id-1)%4=3 THEN 'STARTING'::ymarketstatus
	END AS market_status,
	created
	FROM tmarket;
SELECT _grant_read('vmarkethistory');

-- current state of market
CREATE VIEW vmarket AS SELECT * FROM  vmarkethistory ORDER BY ID DESC LIMIT 1; 
SELECT _grant_read('vmarket');	

--------------------------------------------------------------------------------
/* change state of the market with fchangestatemarket(true)
otherwise, dry run
*/
CREATE FUNCTION fchangestatemarket(_execute bool) RETURNS ymarketstatus AS $$
DECLARE
	_cnt int;
	_hm tmarket%rowtype;
	_action text;
	_prev_status ymarketstatus;
	_res bool;
	_new_status ymarketstatus;
BEGIN

	SELECT market_status INTO _prev_status FROM vmarket;
	IF NOT FOUND THEN 
		_action := 'init';
		_prev_status := 'INITIALIZING';
		_new_status := 'OPENED';
		
	ELSIF (_prev_status = 'STARTING') THEN		
		_action := 'open';
		_new_status := 'OPENED';
		
	ELSIF (_prev_status = 'OPENED') THEN
		_action := 'stop';
		_new_status := 'STOPPING';
		
	ELSIF (_prev_status = 'STOPPING') THEN
		_action := 'close';
		_new_status := 'CLOSED';
		
	ELSE -- _prev_status='CLOSED'
		_action := 'start';
		_new_status := 'STARTING';
		RAISE NOTICE 'market_session = n->n+1';
	END IF;

	RAISE NOTICE 'market_status %->%',_prev_status,_new_status;

	IF NOT _execute THEN
		RAISE NOTICE 'The next action will be: %',_action;
		RAISE NOTICE 'market_status = % is unchanged.',_prev_status;
		RETURN _new_status;
	END IF;
	
	IF (_action = 'init' OR _action = 'open') THEN 		
		GRANT client_opened_role TO client;
		RAISE NOTICE 'The market is now opened for clients';		
		
	ELSIF (_action = 'stop') THEN
		REVOKE client_opened_role FROM client;
		GRANT  client_stopping_role TO client;	
		RAISE NOTICE 'The market is now stopping for clients';		
		
	ELSIF (_action = 'close') THEN
		REVOKE client_stopping_role FROM client;
		_res := frenumbertables(false);
		IF NOT _res THEN
			RAISE EXCEPTION USING ERRCODE='YA001';
		END IF;	
					
	ELSE -- _action='start'
		_res := frenumbertables(true);
		IF NOT _res THEN
			RAISE EXCEPTION USING ERRCODE='YA001';
		END IF;			

	END IF;
	
	INSERT INTO tmarket (created) VALUES (statement_timestamp()) RETURNING * INTO _hm;
	RETURN _new_status;
	 
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fchangestatemarket(bool) TO admin;

--------------------------------------------------------------------------------
CREATE FUNCTION fresetmarket_int() RETURNS void AS $$
DECLARE
	_prev_status ymarketstatus;
BEGIN
	SELECT market_status INTO _prev_status FROM vmarket; 
	IF(_prev_status != 'STOPPING') THEN
		RAISE NOTICE 'The market state is %!= STOPPING, abort.',_prev_status;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	TRUNCATE tmvt;
	TRUNCATE torder;
	TRUNCATE towner CASCADE;
	TRUNCATE tquality CASCADE;
	-- TRUNCATE tuser CASCADE;
	-- PERFORM setval('tuser_id_seq',1,false);
	RETURN;
END;
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
CREATE FUNCTION fresetmarket() RETURNS void AS $$
DECLARE
	_prev_status 	ymarketstatus;
	_new_status 	ymarketstatus;
BEGIN
	LOOP
		_new_status := fchangestatemarket(true); 
		IF(_new_status = 'STOPPING') THEN
			perform fresetmarket_int();
			CONTINUE WHEN true;
		END IF;
		EXIT WHEN _new_status = 'OPENED';
	END LOOP;
	RAISE NOTICE 'The market is reset and opened';
	RETURN;
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fresetmarket() TO admin;

--------------------------------------------------------------------------------
CREATE FUNCTION frenumbertables(exec bool) RETURNS bool AS $$
DECLARE
	_cnt int;
	_res bool;
BEGIN
	
	_res := true;
		
	IF NOT exec THEN
		RETURN _res;
	END IF;
	
	--TODO lier les id des *removed
	
	-- desable triggers
	ALTER TABLE towner DISABLE TRIGGER ALL;
	ALTER TABLE tquality DISABLE TRIGGER ALL;
	ALTER TABLE tuser DISABLE TRIGGER ALL;
	
	-- DROP CONSTRAINT ON UPDATE CASCADE on tables tquality,torder,tmvt
    ALTER TABLE tquality 
		DROP CONSTRAINT ctquality_idd,
		ADD CONSTRAINT ctquality_idd FOREIGN KEY (idd) references tuser(id) 
		ON UPDATE CASCADE;

	ALTER TABLE tquality 
		DROP CONSTRAINT ctquality_depository,
		ADD CONSTRAINT ctquality_depository FOREIGN KEY (depository) references tuser(name) 
		ON UPDATE RESTRICT;  -- must not be changed
	  			
	ALTER TABLE torder 
		DROP CONSTRAINT ctorder_own,
		ADD CONSTRAINT ctorder_own 	FOREIGN KEY (own) references towner(id) 
		ON UPDATE CASCADE;

	ALTER TABLE torder 
		DROP CONSTRAINT ctorder_np,
		ADD CONSTRAINT ctorder_np 	FOREIGN KEY (np) references tquality(id) 
		ON UPDATE CASCADE;

	ALTER TABLE torder 
		DROP CONSTRAINT ctorder_nr,
		ADD CONSTRAINT ctorder_nr 	FOREIGN KEY (nr) references tquality(id) 
		ON UPDATE CASCADE;
/*
	ALTER TABLE tmvt 
		DROP CONSTRAINT ctmvt_grp,
		ADD CONSTRAINT ctmvt_grp 	FOREIGN KEY (grp) references tmvt(id) 
		ON UPDATE CASCADE;
*/
	ALTER TABLE tmvt 
		DROP CONSTRAINT ctmvt_own_src,
		ADD CONSTRAINT ctmvt_own_src 	FOREIGN KEY (own_src) references towner(id) 
		ON UPDATE CASCADE;

	ALTER TABLE tmvt 
		DROP CONSTRAINT ctmvt_own_dst,
		ADD CONSTRAINT ctmvt_own_dst 	FOREIGN KEY (own_dst) references towner(id) 
		ON UPDATE CASCADE;

	ALTER TABLE tmvt 
		DROP CONSTRAINT ctmvt_nat,
		ADD CONSTRAINT ctmvt_nat 	FOREIGN KEY (nat) references tquality(id) 
		ON UPDATE CASCADE;

	TRUNCATE tquote;
	PERFORM setval('tquote_id_seq',1,false);
	
	TRUNCATE tmvt;
	PERFORM setval('tmvt_id_seq',1,false);
	
	-- remove unused qualities
	DELETE FROM tquality q WHERE	q.id NOT IN (SELECT np FROM torder)	
				AND	q.id NOT IN (SELECT nr FROM torder)
				AND 	q.id NOT IN (SELECT nat FROM tmvt);
	
	-- renumbering qualities
	PERFORM setval('tquality_id_seq',1,false);
	WITH a AS (SELECT * FROM tquality ORDER BY id ASC)
	UPDATE tquality SET id = nextval('tquality_id_seq') FROM a WHERE a.id = tquality.id;
	
	-- remove unused owners
	DELETE FROM towner o WHERE o.id NOT IN (SELECT idd FROM tquality);
	
	-- renumbering owners
	PERFORM setval('towner_id_seq',1,false);
	WITH a AS (SELECT * FROM towner ORDER BY id ASC)
	UPDATE towner SET id = nextval('towner_id_seq') FROM a WHERE a.id = towner.id;
	
	-- resetting quotas
	UPDATE tuser SET spent = 0;
		
	-- renumbering orders
	PERFORM setval('torder_id_seq',1,false);
	WITH a AS (SELECT * FROM torder ORDER BY id ASC)
	UPDATE torder SET id = nextval('torder_id_seq') FROM a WHERE a.id = torder.id;
		
	TRUNCATE torderremoved; -- does not reset associated sequence if any
	TRUNCATE tmvtremoved;
	TRUNCATE tquoteremoved;
	TRUNCATE treltried;
	
	
	-- reset of constraints
    ALTER TABLE tquality 
		DROP CONSTRAINT ctquality_idd,
		ADD CONSTRAINT ctquality_idd 	FOREIGN KEY (idd) references tuser(id);

    	ALTER TABLE tquality 
		DROP CONSTRAINT ctquality_depository,
		ADD CONSTRAINT ctquality_depository FOREIGN KEY (depository) references tuser(name);
    		
	ALTER TABLE torder 
		DROP CONSTRAINT ctorder_own,
		ADD CONSTRAINT ctorder_own 	FOREIGN KEY (own) references towner(id);

	ALTER TABLE torder 
		DROP CONSTRAINT ctorder_np,
		ADD CONSTRAINT ctorder_np 	FOREIGN KEY (np) references tquality(id);

	ALTER TABLE torder 
		DROP CONSTRAINT ctorder_nr,
		ADD CONSTRAINT ctorder_nr 	FOREIGN KEY (nr) references tquality(id);
/*
	ALTER TABLE tmvt 
		DROP CONSTRAINT ctmvt_grp,
		ADD CONSTRAINT ctmvt_grp 	FOREIGN KEY (grp) references tmvt(id);
*/
	ALTER TABLE tmvt 
		DROP CONSTRAINT ctmvt_own_src,
		ADD CONSTRAINT ctmvt_own_src 	FOREIGN KEY (own_src) references towner(id);

	ALTER TABLE tmvt 
		DROP CONSTRAINT ctmvt_own_dst,
		ADD CONSTRAINT ctmvt_own_dst 	FOREIGN KEY (own_dst) references towner(id);

	ALTER TABLE tmvt 
		DROP CONSTRAINT ctmvt_nat,
		ADD CONSTRAINT ctmvt_nat 	FOREIGN KEY (nat) references tquality(id);
	
	-- enable triggers
	ALTER TABLE towner ENABLE TRIGGER ALL;
	ALTER TABLE tquality ENABLE TRIGGER ALL;
	ALTER TABLE tuser ENABLE TRIGGER ALL;
	
	RAISE NOTICE 'Run the command:'; 
	RAISE NOTICE '	VACUUM FULL ANALYZE';
	RAISE NOTICE 'before starting the market';
	RETURN true;
	 
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;


