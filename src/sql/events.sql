/*------------------------------------------------------------------------------
external interface

ce fichier est inutile
********************************************************************************
    
------------------------------------------------------------------------------*/

/*------------------------------------------------------------------------------*/
CREATE FUNCTION fgivetojson(_o torder,_mprev tmvt,_m tmvt,_mnext tmvt) 
    RETURNS json AS $$
DECLARE
    _value  json;
BEGIN
    _value := row_to_json(ROW(
                _m.id,
                _m.grp,
                ROW( -- order
                    (_o.ord).id,
                    ROW(
                        (_o.ord).qtt,
                        (_o.ord).qua_prov
                        )::yj_value, 
                    _m.own_src,
                    _o.usr
                    )::yj_barter,
                ROW( -- given
                    _m.id,
                    _m.qtt,
                    _m.nat,
                    _mnext.own_src,
                    _mnext.usr_src
                    )::yj_gvalue,
                ROW( --received
                    _mprev.id,
                    _mprev.qtt,
                    _mprev.nat,
                    _mprev.own_src,
                    _mprev.usr_src
                    )::yj_rvalue
                )::yj_mvt);

    RETURN _value;
END; 
$$ LANGUAGE PLPGSQL;

/*------------------------------------------------------------------------------
deletes barter and sub-barter and output a message for this barter
returns the number of barter+sub-barter deleted from the book
------------------------------------------------------------------------------*/

CREATE FUNCTION fincancelbarter(_o torder,_final ebarterfinal) RETURNS int AS $$
DECLARE
	_cnt   int;
    _yo     yorder%rowtype;
    _te     json;
    _owner  text;
    _DEBUG  boolean := fgetconst('DEBUG')=1;
BEGIN
    _yo := _o.ord;

    IF(_DEBUG) THEN
        SELECT count(*) INTO STRICT _cnt FROM tmvt WHERE xoid = _yo.oid AND cack is NULL;
        if(_cnt != 0) THEN -- some mvt is pending for this barter
            RAISE EXCEPTION 'fincancelbarter called while some mvt are pending';
        END IF;
    END IF;

    IF(_final = 'exhausted') AND (_yo.qtt != 0) THEN
        RAISE EXCEPTION 'barter % is exhausted while qtt % remain',_yo.oid,_yo.qtt;
    END IF;

    -- delete barter and sub-barter from the book
    DELETE FROM torder o WHERE (o.ord).oid = _yo.oid;
    GET DIAGNOSTICS _cnt = ROW_COUNT;

    IF (_cnt != 0) THEN -- notify deletion of the barter

        SELECT name INTO STRICT _owner FROM towner WHERE id = _yo.own;
        _te := row_to_json(ROW(_yo.oid,ROW(_yo.qtt,_yo.qua_prov)::yj_value,_owner,_o.usr)::yj_barter);
        
        INSERT INTO tmsg (obj,sta,oid,json,usr,created) 
            VALUES ('barter',(_final::text)::eobjstatus,_yo.oid,_te,_o.usr,statement_timestamp());
    END IF;
    -- the value is moved from torder->tmsg

	RETURN _cnt;

END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;

/*------------------------------------------------------------------------------
Delete the barter.
_o is the barter (parent order )
_final 'exhausted','outdated','cancelled'
------------------------------------------------------------------------------*/

CREATE FUNCTION fondeletebarter(_o torder,_final ebarterfinal) RETURNS int AS $$
DECLARE
	_res	eresack;
	_cnt    int;
	_gid    int;
BEGIN

    FOR _gid IN SELECT grp FROM tmvt WHERE xoid = (_o.ord).oid AND (cack is NULL) GROUP BY grp LOOP

        -- only cycles pending are considered, not those already accepted or refused 
        _res := frefusecycle(_gid,(_o.ord).id);

    END LOOP;

    -- the quantity of the parent order has changed, _o is updated
    SELECT * INTO STRICT _o FROM torder WHERE (ord).id = (_o.ord).oid;

    _cnt := fincancelbarter(_o,_final);
	RETURN 1;

END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;


/*------------------------------------------------------------------------------
-- used only here
------------------------------------------------------------------------------*/
CREATE FUNCTION fgenmsg(_gid int,_status eobjstatus) RETURNS int AS $$
DECLARE
    _iprev  int;
    _inext  int;
    _i      int;
    _cntgrp int := 0;
    _m      tmvt;
    _mprev  tmvt;
    _mnext  tmvt;
    _am     tmvt[] := ARRAY[]::tmvt[];
    _o      torder;
BEGIN
    FOR _m IN SELECT * FROM tmvt WHERE grp=_gid ORDER BY id ASC LOOP
        _am := _am || _m;
        _cntgrp := _cntgrp + 1;
    END LOOP;

    _i := _cntgrp;
    _iprev := _i -1;
    FOR _inext IN 1 .. _cntgrp LOOP
        
        _mprev  := _am[_iprev];
        _m      := _am[_i];
        _mnext  := _am[_inext];

        SELECT * INTO STRICT _o FROM torder WHERE (ord).id = _m.xoid; -- the stock

        INSERT INTO tmsg (obj,sta,oid,json,usr,created) 
            VALUES ('movement',_status,_m.id,fgivetojson(_o,_mprev,_m,_mnext),_m.usr_src,statement_timestamp());
        _iprev := _i;
        _i := _inext;
    END LOOP;

    RETURN _cntgrp;
END; 
$$ LANGUAGE PLPGSQL;

/*------------------------------------------------------------------------------
the cycle is accepted
for each movement
    > Mm-executed for each movement
    if a barter is exhausted and no other cycle pending:
        cancelbarter(o,exhausted)
    elif a barter is outdated:
        cancelbarter(o,outdated)
        
--the value is moved from tmvt->tmsg: it is an output value
------------------------------------------------------------------------------*/
CREATE OR REPLACE FUNCTION fexecutecycle(_gid int) RETURNS eresack AS $$
DECLARE
	_cnt	int;
	_cntgrp int := 0;
	_m  tmvt%rowtype;
	_yo     yorder%rowtype;
	_o      torder%rowtype;
	_oids   int[];
	_oid    int;
	_te     text;
    _cntoutdated int;
	_value  json;
    -- _approved   boolean := true;
    _status eobjstatus;
    _now    timestamp;
BEGIN
    _oids := ARRAY[]::int[];
    FOR _oid IN SELECT xoid FROM tmvt WHERE grp=_gid LOOP
        IF(NOT _oids @> ARRAY[_oid]) THEN
            _oids := _oids || _oid;
        END IF;
    END LOOP;

    _now := clock_timestamp();

    -- _oids is the set of parent ids
    SELECT count(*) into strict _cntoutdated from torder WHERE (ord).oid= ANY(_oids) 
        AND (NOT(_o.duration IS NULL) ) AND ((_o.created + _o.duration) <= _now);

    IF (_cntoutdated != 0) THEN 
        _status := 'outdated';
    ELSE
        _status := 'approved';
    END IF;

    _cntgrp := fgenmsg(_gid,_status);

    IF (_status = 'approved') THEN
        --
        UPDATE tmvt SET cack = true WHERE grp = _gid;

        FOR _o IN SELECT * FROM torder WHERE (ord).oid= ANY(_oids) AND (ord).qtt = 0 LOOP
            _cntgrp := fincancelbarter(_o,'exhausted'); 
        END LOOP;

        RETURN 'cycle_approved';

    ELSE -- status = 'outdated'
        -- some parent order are obsolete
        UPDATE tmvt SET cack = false WHERE grp = _gid;

        FOR _o IN SELECT * FROM torder WHERE (ord).oid= ANY(_oids) 
            AND (NOT(_o.duration IS NULL) ) AND ((_o.created + _o.duration) <= _now)
             LOOP
            _cntgrp := fincancelbarter(_o,'outdated'); 
        END LOOP;
        
        RETURN 'cycle_outdated';

    END IF;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;

/*------------------------------------------------------------------------------
When a cycle is created, the following messages are generated:
    movement,pending    with qtt
    barter,changed      with QTT-qtt
------------------------------------------------------------------------------*/


/* END
	_ownsrcs	text[];
    _fmvtids := ARRAY[]::text[];
        IF(NOT _ownsrcs @> ARRAY[_m.ownsrc]) THEN
            _ownsrcs := _ownsrcs || _m.ownsrc;
        END IF;
*/  



