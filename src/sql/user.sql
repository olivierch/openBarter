-- set schema 't';

create table tmvtremoved (
        id bigserial UNIQUE not NULL,
        nb int not null,
        oruuid text NOT NULL, -- refers to order uuid
    	grp int NOT NULL, 
    	-- References the first mvt of an exchange.
    	-- can be NULL
	own_src int references towner(id)  not null, 
	own_dst int  references towner(id) not null,
	qtt dquantity not NULL,
	nat int references tquality(id) not null,
	created timestamp not NULL,
	deleted timestamp not NULL
);
--------------------------------------------------------------------------------
-- moves all movements of an agreement belonging to the user into tmvtremoved 
CREATE FUNCTION 
	fremoveagreement(_grp int) 
	RETURNS int AS $$
DECLARE 
	_nat int;
	_cnt int8;
	_qtt int8;
	_qlt tquality%rowtype;
BEGIN
	_cnt := 0;
	FOR _nat,_qtt IN SELECT m.nat,sum(m.qtt) FROM tmvt m, tquality q,tuser u 
		WHERE m.nat=q.id AND q.idd=u.id AND u.name=session_user AND m.grp=_grp GROUP BY m.nat LOOP
		
		_cnt := _cnt +1;
		UPDATE tquality SET qtt = qtt - _qtt WHERE id = _nat RETURNING qtt INTO _qlt;
		IF(_qlt.qtt <0) THEN
			RAISE WARNING 'the quantity % underflows',_qlt.name;
			RAISE EXCEPTION USING ERRCODE='YA002';
		END IF;		
	END LOOP;
	IF (_cnt=0) THEN
		RAISE WARNING 'The agreement "%" does not exist or no movement of this agreement belongs to the user %',_grp,session_user;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	
	WITH a AS (DELETE FROM tmvt m USING tquality q,tuser u WHERE m.nat=q.id AND q.idd=u.id AND u.name=session_user AND m.grp=_grp RETURNING m.*) 
	INSERT INTO tmvtremoved SELECT id,nb,oruuid,grp,own_src,own_dst,qtt,nat,created,statement_timestamp() as deleted FROM a;

	RETURN _cnt::int;
	
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE INFO 'ABORTED';
	RETURN 0; 
END;
$$ LANGUAGE PLPGSQL;
GRANT EXECUTE ON FUNCTION fremoveagreement(int) TO market;

--------------------------------------------------------------------------------
-- 
--------------------------------------------------------------------------------
create function fconnect(verifyquota bool) RETURNS int AS $$
DECLARE 
	_u	tuser%rowtype;
BEGIN
	SELECT * INTO _u FROM tuser WHERE name=session_user;
	IF(_u.id is NULL) THEN
		RAISE WARNING 'the user % is undefined',session_user;
		RAISE EXCEPTION USING ERRCODE='YA003';
	END IF;
	UPDATE tuser SET last_in = statement_timestamp() WHERE name = session_user;
	IF(_u.quota =0 OR NOT verifyquota) THEN
		RETURN _u.id;
	END IF;
/*
	IF(_u.quota < _u.spent) THEN
		RAISE WARNING 'the user % is undefined',session_user;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	RETURN _u.id;
*/
END;		
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
-- 
--------------------------------------------------------------------------------
create function fspendquota(_time_begin timestamp) RETURNS bool AS $$
BEGIN
	-- TODO to be written
	RETURN true;
END;		
$$ LANGUAGE PLPGSQL;


