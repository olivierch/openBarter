/*
manage transitions between daily market phases.
*/
--------------------------------------------------------------------------------
INSERT INTO tvar(name,value) VALUES 
	('OC_CURRENT_PHASE',101),  -- phase of the model when settled
	('OC_CURRENT_OPENED',0);	-- sub-state of the opened phase

CREATE TABLE tmsgdaysbefore(LIKE tmsg);
SELECT _grant_read('tmsgdaysbefore');
-- index and unique constraint are not cloned
--------------------------------------------------------------------------------
CREATE FUNCTION openclose() RETURNS int AS $$
/*
 * This code is executed by the bg_worker 1 doing following:
 	while(true)
 		status := market.openclose()
 		if (status >=0):
 			do_wait := status
 		elif status == -100:
 			VACUUM FULL
 			do_wait := 0

 		wait(do_wait) milliseconds


*/
DECLARE
	_phase 		int;
	_dowait		int := 0; -- not DOWAIT
	_cnt		int;
	_rp			yerrorprim;
	_stock_id   int;
	_owner		text;
	_done 		boolean;
BEGIN
	set search_path to market;
	_phase := fgetvar('OC_CURRENT_PHASE');
    CASE _phase

    	/* PHASE 0XX BEGIN OF THE DAY
    	*/
    	WHEN 0 THEN
    		/* creates the timetable */ 
    		PERFORM foc_create_timesum();

    		/* pruge tmsg - single transaction */
			WITH t AS (DELETE FROM tmsg RETURNING * ) 
				INSERT INTO tmsgdaysbefore SELECT * FROM t ;
			TRUNCATE tmsg;
			PERFORM setval('tmsg_id_seq',1,false);

		    PERFORM foc_next(1,'tmsg archived');

    	WHEN 1 THEN 

    		IF(foc_in_phase(_phase)) THEN
    			_dowait := 60000; -- 1 minute
    		ELSE
    			PERFORM foc_next(101,'Start opening sequence');
    		END IF;

		/* PHASE 1XX -- MARKET OPENED
		*/
    	WHEN 101 THEN 
			/* open client access  */

		    REVOKE role_co_closed FROM role_client;
		    GRANT role_co TO role_client;

		    PERFORM foc_next(102,'Client access opened');

    	WHEN 102 THEN
    		/* market is opened to client access:
    		While in phase,
    			OC_CURRENT_OPENED <- OC_CURRENT_OPENED % 5
    			if 0:
    				delete outdated order and sub-orders from the book
    				do_wait = 1 minute
    		else,
    			phase <- 120
    		*/

    		IF(foc_in_phase(_phase)) THEN
     			UPDATE tvar SET value=((value+1)/5) WHERE name='OC_CURRENT_OPENED' 
     				RETURNING value INTO _cnt ;
    			_dowait := 60000; -- 1 minute
    			IF(_cnt =0) THEN
	    		-- every 5 calls(5 minutes), 
		    	-- delete outdated order and sub-orders from the book
				    DELETE FROM torder o USING torder po
				    	WHERE (o.ord).oid = (po.ord).id 
				    	-- outdated parent orders
				    	AND (po.ord).oid = (po.ord).oid 
				    	AND NOT (po.duration IS NULL) 
				    	AND (po.created + po.duration) <= clock_timestamp();
    			END IF;
    		ELSE
    			PERFORM foc_next(120,'Start closing');
    		END IF;

    	WHEN 120 THEN 
    		/* market closing

    		revoke client access 
    		*/
		    REVOKE role_co FROM role_client;
		    GRANT role_co_closed TO role_client;

		    PERFORM foc_next(121,'Client access revoked');

    	WHEN 121 THEN 
    		/* wait until the stack is compleatly consumed */

		    -- waiting worker2 stack purge
		    _done := fstackdone();
		    -- SELECT count(*) INTO _cnt FROM tstack;

		    IF(not _done) THEN 
		    	_dowait := 60000; -- 1 minute
		    	-- wait and test again
		    ELSE
		    	PERFORM foc_next(200,'Last primitives performed');
		    END IF;

    	/* PHASE 2XX MARKET CLOSED */
    	WHEN 200 THEN 
    		/* remove orders of the order book */

			SELECT (o.ord).id,w.name INTO _stock_id,_owner FROM torder o 
				INNER JOIN town w ON w.id=(o.ord).own
				WHERE (o.ord).oid = (o.ord).id LIMIT 1;

			IF(FOUND) THEN
				_rp := fsubmitrmorder(_owner,_stock_id);
				-- repeate again until order_book is empty
			ELSE
				PERFORM foc_next(201,'Order book is emptied');
			END IF;

    	WHEN 201 THEN 
    		/* wait until stack is empty */

		    -- waiting worker2 stack purge
		    _done := fstackdone();
		    -- SELECT count(*) INTO _cnt FROM tstack;

		    IF(not _done) THEN 
		    	_dowait := 60000; -- 1 minute
		    	-- wait and test again
		    ELSE
		    	PERFORM foc_next(202,'rm primitives are processed'); 
		    END IF;

    	WHEN 202 THEN 
		    /* tables truncated except tmsg */

			truncate torder;
			truncate tstack;
			PERFORM setval('tstack_id_seq',1,false);

			PERFORM setval('tmvt_id_seq',1,false);

			truncate towner;
			PERFORM setval('towner_id_seq',1,false);

			PERFORM foc_next(203,'tables torder,tsack,tmvt,towner are truncated');

    	WHEN 203 THEN 

			_dowait := -100; -- VACUUM FULL; executed by pg_worker 1 openclose
			PERFORM foc_next(204,'VACUUM FULL is lauched');

    	WHEN 204 THEN
    		/* wait till the end of the day */

    		IF(foc_in_phase(_phase)) THEN
    			_dowait := 60000; -- 1 minute
    			-- wait and test again
    		ELSE
    			PERFORM foc_next(0,'End of the day');
    		END IF;
    	ELSE
    		RAISE EXCEPTION 'Should not reach this point';
    END CASE;
	RETURN _dowait; -- DOWAIT or VACUUM FULL
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER  set search_path = market,public;
GRANT EXECUTE ON FUNCTION  openclose() TO role_bo;

-------------------------------------------------------------------------------
CREATE FUNCTION foc_next(_phase int,_msg text) RETURNS void AS $$
BEGIN
	PERFORM fsetvar('OC_CURRENT_PHASE',_phase);
	RAISE LOG 'MARKET PHASE %: %',_phase,_msg;
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER  set search_path = market,public;
GRANT EXECUTE ON FUNCTION  foc_next(int,text) TO role_bo;

--------------------------------------------------------------------------------
/*	access by clients can be disabled/enabled with a single command:
		REVOKE role_co FROM role_client
		GRANT role_co TO role_client
		
	same thing for role batch with role_bo:
		REVOKE role_bo FROM user_bo
		GRANT role_bo TO user_bo
*/


CREATE VIEW vmsg3 AS WITH t AS (SELECT * from tmsg WHERE usr = session_user
	UNION ALL SELECT * from tmsgdaysbefore WHERE usr = session_user
	) SELECT created,id,typ,jso 
from t order by created ASC,id ASC;

SELECT _grant_read('vmsg3');

/*------------------------------------------------------------------------------
 TIME DEPENDANT FUNCTION
------------------------------------------------------------------------------*/
/* the day is shared in NB_PHASE, with id between [0,NB_PHASE-1]
delay are defined for [0,NB_PHASE-2],the last waits the end of the day

OC_DELAY_i are number of seconds for a phase for i in [0,NB_PHASE-2]
*/

INSERT INTO tconst (name,value) VALUES 
	('OC_DELAY_0',30*60),   -- stops at  0h 30'
	('OC_DELAY_1',23*60*60) -- stops at 23h 30' 	
	-- sum of delays < 24*60*60
	; 

CREATE FUNCTION foc_create_timesum() RETURNS void AS $$
DECLARE
	_cnt	int;
BEGIN
	DROP TABLE IF EXISTS timesum;
	SELECT count(*) INTO STRICT _cnt FROM tconst WHERE name like 'OC_DELAY_%';
	CREATE TABLE timesum (id,ends) AS 
		SELECT t.id+1,sum(d.value) OVER w  FROM generate_series(0,_cnt-1) t(id)
		LEFT JOIN tconst d ON (('OC_DELAY_' ||(t.id)::text) = d.name)
		WINDOW w AS (order by t.id );
	INSERT INTO timesum VALUES (0,0);

END;
$$ LANGUAGE PLPGSQL;
GRANT EXECUTE ON FUNCTION foc_create_timesum() TO role_bo;
select foc_create_timesum();

--------------------------------------------------------------------------------
CREATE FUNCTION foc_in_phase(_phase int) RETURNS boolean AS $$
-- returns TRUE when in phase, else returns the suffix of the archive
DECLARE
	_actual_gphase   int := _phase /100;
	_planned_gphase	int;
BEGIN

	-- the number of seconds since the beginning of the day
	-- in the interval (timesum[id],timesum[id+1])
	SELECT max(id) INTO _planned_gphase FROM 
	timesum where ends < (EXTRACT(HOUR FROM now()) *60*60) 
						+ (EXTRACT(MINUTE FROM now()) *60) 
						+ EXTRACT(SECOND FROM now()) ;

	IF (_planned_gphase = _actual_gphase) THEN
		RETURN true;
	ELSE 
		RETURN false;
	END IF;
END;
$$ LANGUAGE PLPGSQL;
