/*
--------------------------------------------------------------------------------
-- BGW_OPENCLOSE
--------------------------------------------------------------------------------

openclose() is processed by postgres in background using a background worker called 
BGW_OPENCLOSE (see src/worker_ob.c). 

It performs transitions between daily market phases. Surprisingly, the sequence
of operations does not depend on time and is always performed in the same order. 
They are just special operations waiting until the end of the current gphase.

*/
--------------------------------------------------------------------------------
INSERT INTO tvar(name,value) VALUES 
    ('OC_CURRENT_PHASE',101);  -- phase of the market when it's model is settled

CREATE TABLE tmsgdaysbefore(LIKE tmsg);
GRANT SELECT ON tmsgdaysbefore TO role_com;
-- index and unique constraint are not cloned
--------------------------------------------------------------------------------
CREATE FUNCTION openclose() RETURNS int AS $$
/*
The structure of the code is:
    _phase := OC_CURRENT_PHASE
    CASE _phase
        ....
        WHEN X THEN
            dowait := operation_of_phase(X)
            OC_CURRENT_PHASE := _next_phase
        ....
    return dowait

This code is executed by the BGW_OPENCLOSE doing following:

    while(true)
        dowait := market.openclose()
        if (dowait >=0):
            wait for dowait milliseconds
        elif dowait == -100:
            VACUUM FULL
        else:
            error
*/
DECLARE

    _phase      int;
    _dowait     int := 0; 
    _rp         yerrorprim;
    _stock_id   int;
    _owner      text;
    _done       boolean;

BEGIN

    _phase := fgetvar('OC_CURRENT_PHASE');

    CASE _phase
        ------------------------------------------------------------------------
        --               GPHASE 0 BEGIN OF DAY                                --
        ------------------------------------------------------------------------

        WHEN 0 THEN -- creating the timetable of the day

            PERFORM foc_create_timesum();

            --  tmsg is archived to tmsgdaysbefore

            WITH t AS (DELETE FROM tmsg RETURNING * ) 
                INSERT INTO tmsgdaysbefore SELECT * FROM t ;
            TRUNCATE tmsg;
            PERFORM setval('tmsg_id_seq',1,false);

            PERFORM foc_next(1,'tmsg archived');

        WHEN 1 THEN -- waiting for opening

            IF(foc_in_gphase(_phase)) THEN
                _dowait := 60000; -- 1 minute
            ELSE
                PERFORM foc_next(101,'Start opening sequence');
            END IF;

        ------------------------------------------------------------------------
        --                GPHASE 1 MARKET OPENED                              --
        ------------------------------------------------------------------------

        WHEN 101 THEN -- client access opening.

            REVOKE role_co_closed FROM role_client;
            GRANT role_co TO role_client;

            PERFORM foc_next(102,'Client access opened');

        WHEN 102 THEN -- market is opened to client access, waiting for closing.

            IF(foc_in_gphase(_phase)) THEN
                PERFORM foc_clean_outdated_orders();
                _dowait := 60000; -- 1 minute
            ELSE
                PERFORM foc_next(120,'Start closing');
            END IF;

        WHEN 120 THEN -- market is closing.

            REVOKE role_co FROM role_client;
            GRANT role_co_closed TO role_client;

            PERFORM foc_next(121,'Client access revoked');

        WHEN 121 THEN -- waiting until the stack is empty
            
            -- checks wether BGW_CONSUMESTACK purged the stack
            _done := fstackdone();

            IF(not _done) THEN 
                _dowait := 60000; 
                -- waits one minute before testing again
            ELSE
                -- the stack is purged
                PERFORM foc_next(200,'Last primitives performed');
            END IF;

        ------------------------------------------------------------------------
        --               GPHASE 2 - MARKET CLOSED                             --
        ------------------------------------------------------------------------

        WHEN 200 THEN -- removing orders of the order book 

            SELECT (o.ord).id,w.name INTO _stock_id,_owner FROM torder o 
                INNER JOIN towner w ON w.id=(o.ord).own
                WHERE (o.ord).oid = (o.ord).id LIMIT 1;

            IF(FOUND) THEN
                _rp := fsubmitrmorder(_owner,_stock_id);
                IF(_rp.error.code != 0 ) THEN
                    RAISE EXCEPTION 'Error while removing orders %',_rp;
                END IF;
                -- repeate again until order_book is empty
            ELSE
                PERFORM foc_next(201,'Order book is emptied');
            END IF;

        WHEN 201 THEN -- waiting until the stack is empty
            
            -- checks wether BGW_CONSUMESTACK purged the stack
            _done := fstackdone();

            IF(not _done) THEN 
                _dowait := 60000; 
                -- waits one minute before testing again
            ELSE
                -- the stack is purged
                PERFORM foc_next(202,'rm primitives are processed'); 
            END IF;

        WHEN 202 THEN -- truncating tables except tmsg

            truncate torder;
            truncate tstack;
            PERFORM setval('tstack_id_seq',1,false);

            PERFORM setval('tmvt_id_seq',1,false);

            truncate towner;
            PERFORM setval('towner_id_seq',1,false);

            PERFORM foc_next(203,'tables torder,tsack,tmvt,towner are truncated');

        WHEN 203 THEN -- asking for VACUUM FULL execution

            _dowait := -100; 
            PERFORM foc_next(204,'VACUUM FULL is lauched');

        WHEN 204 THEN -- waiting till the end of the day 

            IF(foc_in_gphase(_phase)) THEN
                _dowait := 60000; -- 1 minute
                -- waits before testing again
            ELSE
                PERFORM foc_next(0,'End of the day'); 
            END IF;

        ELSE

            RAISE EXCEPTION 'Should not reach this point with phase=%',_phase;

    END CASE;

    -- RAISE LOG 'Phase=% _dowait=%',_phase,_dowait;

    RETURN _dowait; 
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
INSERT INTO tvar(name,value) VALUES 
    ('OC_CURRENT_OPENED',0);    -- sub-state of the opened phase

CREATE FUNCTION foc_clean_outdated_orders() RETURNS void AS $$
/* each 5 calls, cleans outdated orders */
DECLARE
    _cnt        int;
BEGIN
    UPDATE tvar SET value=((value+1) % 5 ) WHERE name='OC_CURRENT_OPENED' 
            RETURNING value INTO _cnt ;
    IF(_cnt !=0) THEN 
        RETURN;
    END IF;

    -- delete outdated order from the order book and related sub-orders
    DELETE FROM torder o USING torder po
        WHERE (o.ord).oid = (po.ord).id -- having a parent order that
        AND NOT (po.duration IS NULL)   -- have a timeout defined
        AND (po.created + po.duration) <= clock_timestamp(); -- and is outdated
    RETURN; 
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER  set search_path = market,public;
GRANT EXECUTE ON FUNCTION  foc_clean_outdated_orders() TO role_bo;

--------------------------------------------------------------------------------
CREATE VIEW vmsg3 AS WITH t AS (SELECT * from tmsg WHERE usr = session_user
    UNION ALL SELECT * from tmsgdaysbefore WHERE usr = session_user
    ) SELECT created,id,typ,jso 
from t order by created ASC,id ASC;

GRANT SELECT ON vmsg3 TO role_com;
/*
--------------------------------------------------------------------------------
-- TIME DEPENDANT FUNCTION foc_in_gphase(_phase int)
--------------------------------------------------------------------------------

The day is shared in 3 gphases. A table tdelay defines the durations of these gphases. 
When the model is settled and each day, the table timesum is built from tdelay to set 
the planning of the market. foc_in_gphase(_phase) returns true when the current time 
is in the planning of the _phase.

*/
--------------------------------------------------------------------------------
-- delays of the phases
--------------------------------------------------------------------------------
create table tdelay(
    id      serial,
    delay   interval
);
GRANT SELECT ON tdelay TO role_com;
/*
NB_GPHASE = 3, with id between [0,NB_GPHASE-1]
delay are defined for [0,NB_GPHASE-2],the last waits the end of the day

OC_DELAY_i is the duration of a gphase for i in [0,NB_GPHASE-2]
*/

INSERT INTO tdelay (delay) VALUES 
    ('30 minutes'::interval),   -- starts at  0h 30'
    ('23 hours'::interval)      -- stops  at 23h 30'    
    -- sum of delays < 24 hours
    ; 
--------------------------------------------------------------------------------
CREATE FUNCTION foc_create_timesum() RETURNS void AS $$
/* creates the table timesum from tdelay where each record
defines for a gphase the delay between the begin of the day 
and the end of this phase. 

    builds timesum with rows (k,ends) such as:
        ends[0] = 0
        ends[k] = sum(tdelay[i] for i in [0,k])
*/
DECLARE
    _inter      interval;
    _cnt        int;
BEGIN

    -- DROP TABLE IF EXISTS timesum;

    SELECT count(*) INTO STRICT _cnt FROM tdelay;

    CREATE TABLE timesum (id,ends) AS 
        SELECT t.id,sum(d.delay) OVER w  FROM generate_series(1,_cnt) t(id)
        LEFT JOIN tdelay d ON (t.id=d.id) WINDOW w AS (order by t.id );

    INSERT INTO timesum VALUES (0,'0'::interval);

    SELECT max(ends) INTO _inter FROM timesum;
    IF( _inter >= '24 hours'::interval) THEN
        RAISE EXCEPTION 'sum(delay) = % > 24 hours',_inter;
    END IF;

END;
$$ LANGUAGE PLPGSQL  set search_path = market,public;
GRANT EXECUTE ON FUNCTION foc_create_timesum() TO role_bo;
select market.foc_create_timesum();

--------------------------------------------------------------------------------
CREATE FUNCTION foc_in_gphase(_phase int) RETURNS boolean AS $$
/* returns TRUE when current time is between the limits of the gphase
 gphase is defined as _phase/100 */
DECLARE
    _actual_gphase  int := _phase /100;
    _planned_gphase int;
    _time           interval;
BEGIN

    -- the time since the beginning of the day
    _time := now() - date_trunc('day',now());

    
    SELECT max(id) INTO _planned_gphase FROM timesum where ends < _time ;
    -- _planned_gphase is such as 
    -- _time is in the interval (timesum[ _planned_gphase ],timesum[ _planned_gphase+1 ])

    IF (_planned_gphase = _actual_gphase) THEN
        RETURN true;
    ELSE 
        RETURN false;
    END IF;
END;
$$ LANGUAGE PLPGSQL  set search_path = market,public;
GRANT EXECUTE ON FUNCTION foc_create_timesum() TO role_bo;
