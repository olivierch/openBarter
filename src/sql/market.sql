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
CREATE FUNCTION fchangestatemarket(_execute bool) RETURNS  TABLE (_market_session int,_market_status ymarketstatus) AS $$
DECLARE
	_cnt int;
	_hm tmarket%rowtype;
	_action text;
	_prev_status ymarketstatus;
	_res bool;
	_new_status ymarketstatus;
BEGIN

	SELECT market_status,market_session INTO _prev_status,_market_session FROM vmarket;
	_market_status := _prev_status;
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
	END IF;

	-- RAISE NOTICE 'market_status %->%',_prev_status,_new_status;

	IF NOT _execute THEN
		RAISE NOTICE 'The next market state will be %',_new_status;
		RETURN NEXT;
		RETURN;
	END IF;
	
	INSERT INTO tmarket (created) VALUES (statement_timestamp()) RETURNING * INTO _hm;
	SELECT market_status,market_session INTO _new_status,_market_session FROM vmarket;
	_market_status := _new_status;
	
	IF (_action = 'init' OR _action = 'open') THEN
		-- INITIALIZING	->OPENED
		-- STARTING		->OPENED 	
		-- REVOKE  client_stopping_role FROM client;	
		GRANT client_opened_role TO client;
				
	ELSIF (_action = 'stop') THEN
		-- OPENED		->STOPPING
		REVOKE client_opened_role FROM client;
		GRANT  client_stopping_role TO client;			
		
	ELSIF (_action = 'close') THEN
		-- STOPPING		->CLOSED 
		REVOKE client_stopping_role FROM client;
		GRANT DELETE ON TABLE torderremoved,tmvtremoved TO admin;
		RAISE NOTICE 'Connexions by clients are forbidden. The role admin has exclusive access to the market.';
					
	ELSE -- _action='start'
		-- CLOSED		->STARTING
		REVOKE DELETE ON TABLE torderremoved,tmvtremoved FROM admin;
		_res := frenumbertables(true);
		IF NOT _res THEN
			RAISE EXCEPTION USING ERRCODE='YA001';
		END IF;	
		RAISE NOTICE 'A new market session is created. Run the command: VACUUM FULL ANALYZE before changing the market state to OPENED.';		

	END IF;
	
	
	RETURN NEXT;
	RETURN;
	 
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fchangestatemarket(bool) TO admin;

--------------------------------------------------------------------------------
CREATE FUNCTION frenumbertables(exec bool) RETURNS bool AS $$
DECLARE
	_cnt int;
	_id int;
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
		DROP CONSTRAINT ctquality_depository,
		ADD CONSTRAINT ctquality_depository FOREIGN KEY (depository) references tuser(name) 
		ON UPDATE RESTRICT;  -- must not be changed
	  			
	ALTER TABLE torder 
		DROP CONSTRAINT ctorder_own,
		ADD CONSTRAINT ctorder_own FOREIGN KEY (own) references towner(id) ON UPDATE CASCADE ON DELETE RESTRICT,
		DROP CONSTRAINT ctorder_np,
		ADD CONSTRAINT ctorder_np FOREIGN KEY (np) references tquality(id) ON UPDATE CASCADE ON DELETE RESTRICT,
		DROP CONSTRAINT ctorder_nr,
		ADD CONSTRAINT ctorder_nr FOREIGN KEY (nr) references tquality(id) ON UPDATE CASCADE ON DELETE RESTRICT;
		
	ALTER TABLE torderremoved 
		ADD CONSTRAINT ctorderremoved_own FOREIGN KEY (own) references towner(id) ON UPDATE CASCADE ON DELETE RESTRICT,
		ADD CONSTRAINT ctorderremoved_np FOREIGN KEY (np) references tquality(id) ON UPDATE CASCADE ON DELETE RESTRICT,
		ADD CONSTRAINT ctorderremoved_nr FOREIGN KEY (nr) references tquality(id) ON UPDATE CASCADE ON DELETE RESTRICT;

	ALTER TABLE tmvt 
		DROP CONSTRAINT ctmvt_own_src,
		ADD CONSTRAINT ctmvt_own_src FOREIGN KEY (own_src) references towner(id) ON UPDATE CASCADE ON DELETE RESTRICT,
		DROP CONSTRAINT ctmvt_own_dst,
		ADD CONSTRAINT ctmvt_own_dst FOREIGN KEY (own_dst) references towner(id) ON UPDATE CASCADE ON DELETE RESTRICT,
		DROP CONSTRAINT ctmvt_nat,
		ADD CONSTRAINT ctmvt_nat FOREIGN KEY (nat) references tquality(id) ON UPDATE CASCADE ON DELETE RESTRICT;

	ALTER TABLE tmvtremoved 
		ADD CONSTRAINT ctmvtremoved_own_src FOREIGN KEY (own_src) references towner(id) ON UPDATE CASCADE ON DELETE RESTRICT,
		ADD CONSTRAINT ctmvtremoved_own_dst FOREIGN KEY (own_dst) references towner(id) ON UPDATE CASCADE ON DELETE RESTRICT,
		ADD CONSTRAINT ctmvtremoved_nat FOREIGN KEY (nat) references tquality(id) ON UPDATE CASCADE ON DELETE RESTRICT;

	-- tquote truncated
	TRUNCATE tquote;
	PERFORM setval('tquote_id_seq',1,false);

	-- remove unused qualities
	DELETE FROM tquality q WHERE q.id NOT IN (SELECT np FROM torder UNION SELECT np FROM torderremoved )	
				AND	q.id NOT IN (SELECT nr FROM torder UNION SELECT nr FROM torderremoved )
				AND q.id NOT IN (SELECT nat FROM tmvt UNION SELECT nat FROM tmvtremoved );
	
	-- renumbering qualities
	PERFORM setval('tquality_id_seq',1,false);
	FOR _id IN SELECT * FROM tquality ORDER BY id ASC LOOP
		UPDATE tquality SET id = nextval('tquality_id_seq') WHERE id = _id;
	END LOOP;
	
	-- resetting quotas
	-- tuser is not touched since it is linked to pg_roles
	UPDATE tuser SET spent = 0;
	
	-- renumbering orders
	PERFORM setval('torder_id_seq',1,false);
	FOR _id IN SELECT * FROM torder ORDER BY id ASC LOOP
		UPDATE torder SET id = nextval('torder_id_seq') WHERE id = _id;
	END LOOP;
	
	-- renumbering movements
	PERFORM setval('tmvt_id_seq',1,false);
	FOR _id IN SELECT * FROM tmvt ORDER BY id ASC LOOP
		UPDATE tmvt SET id = nextval('tmvt_id_seq') WHERE id = _id;
	END LOOP;

/*		
	TRUNCATE torderremoved; -- does not reset associated sequence if any
	TRUNCATE tmvtremoved;
	TRUNCATE tquoteremoved;
*/
	
	-- reset of constraints
    ALTER TABLE tquality 
		DROP CONSTRAINT ctquality_depository,
		ADD CONSTRAINT ctquality_depository FOREIGN KEY (depository) references tuser(name);
    		
	ALTER TABLE torder 
		DROP CONSTRAINT ctorder_own,
		ADD CONSTRAINT ctorder_own 	FOREIGN KEY (own) references towner(id), 
		DROP CONSTRAINT ctorder_np,
		ADD CONSTRAINT ctorder_np 	FOREIGN KEY (np) references tquality(id),
		DROP CONSTRAINT ctorder_nr,
		ADD CONSTRAINT ctorder_nr 	FOREIGN KEY (nr) references tquality(id);
		
		
	ALTER TABLE torderremoved 
		DROP CONSTRAINT ctorderremoved_own,
		DROP CONSTRAINT ctorderremoved_np,
		DROP CONSTRAINT ctorderremoved_nr;
/*
	ALTER TABLE tmvt 
		DROP CONSTRAINT ctmvt_grp,
		ADD CONSTRAINT ctmvt_grp 	FOREIGN KEY (grp) references tmvt(id);
*/
	ALTER TABLE tmvt 
		DROP CONSTRAINT ctmvt_own_src,
		ADD CONSTRAINT ctmvt_own_src 	FOREIGN KEY (own_src) references towner(id),
		DROP CONSTRAINT ctmvt_own_dst,
		ADD CONSTRAINT ctmvt_own_dst 	FOREIGN KEY (own_dst) references towner(id),
		DROP CONSTRAINT ctmvt_nat,
		ADD CONSTRAINT ctmvt_nat 	FOREIGN KEY (nat) references tquality(id);
		
	ALTER TABLE tmvtremoved 
		DROP CONSTRAINT ctmvtremoved_own_src,
		DROP CONSTRAINT ctmvtremoved_own_dst,
		DROP CONSTRAINT ctmvtremoved_nat;
			
	-- enable triggers
	ALTER TABLE towner ENABLE TRIGGER ALL;
	ALTER TABLE tquality ENABLE TRIGGER ALL;
	ALTER TABLE tuser ENABLE TRIGGER ALL;

	RETURN true;
	 
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;


