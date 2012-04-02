SET client_min_messages = warning;
\set ECHO none
/*
drop schema if exists t cascade;
create schema t;
set schema 't';
*/
drop extension if exists flow cascade;
create extension flow;

--------------------------------------------------------------------------------
-- main constants of the model
--------------------------------------------------------------------------------
create table tconst(
	name text UNIQUE not NULL,
	value	int,
	PRIMARY KEY (name)
);
--------------------------------------------------------------------------------
INSERT INTO tconst (name,value) VALUES 
	('MAXCYCLE',8),
	('VERSION',31),
	('INSERT_OWN_UNKNOWN',1), 
	-- 1, insert an owner when it is unknown
	-- 0, raise an error when the owner is unknown
	('CHECK_QUALITY_OWNERSHIP',0), 
	-- !=0, quality = user_name/quality_name prefix must match session_user
	-- ==0, the name of quality can be any string
	('MAXORDERFETCH',100);
	-- maximum number of agreements of the set on which the competition occurs
--------------------------------------------------------------------------------
-- fetch a constant, and verify consistancy
CREATE FUNCTION fgetconst(_name text) RETURNS int AS $$
DECLARE
	_ret int;
BEGIN
	SELECT value INTO _ret FROM tconst WHERE name=_name;
	IF(NOT FOUND) THEN
		RAISE 'the const % should be found',_name;
		RAISE EXCEPTION USING ERRCODE='YA003';
	END IF;
	IF(_name = 'MAXCYCLE' AND _ret >8) THEN
		RAISE EXCEPTION 'obCMAXVALUE must be <=8' USING ERRCODE='YA002';
	END IF;
	RETURN _ret;
END; 
$$ LANGUAGE PLPGSQL STABLE;
--------------------------------------------------------------------------------
-- definition of roles
--	admin market administrator -- cannot act as client
--	client -- can act as client only when it inherits from market_role 
--------------------------------------------------------------------------------
CREATE FUNCTION _create_roles() RETURNS int AS $$
DECLARE
	_rol text;
BEGIN
	BEGIN 
		CREATE ROLE market_open_role; 
	EXCEPTION WHEN duplicate_object THEN
		NULL;	
	END;
	ALTER ROLE market_open_role NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
	
	BEGIN 
		CREATE ROLE market_close_role; 
	EXCEPTION WHEN duplicate_object THEN
		NULL;	
	END;
	ALTER ROLE market_close_role NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
	
	BEGIN 
		CREATE ROLE client;
	EXCEPTION WHEN duplicate_object THEN
		NULL;
	END;
	ALTER ROLE client INHERIT;
	
	BEGIN 
		CREATE ROLE admin;
	EXCEPTION WHEN duplicate_object THEN
		NULL;
	END;
	ALTER ROLE admin NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION; 
	ALTER ROLE admin LOGIN CONNECTION LIMIT 1;
	-- a single connection is allowed
	RETURN 0;
END; 
$$ LANGUAGE PLPGSQL;

SELECT _create_roles();
DROP FUNCTION _create_roles();


--------------------------------------------------------------------------------
-- trigger before insert on some tables
--------------------------------------------------------------------------------
CREATE FUNCTION ftime_updated() 
	RETURNS trigger AS $$
BEGIN
	IF (TG_OP = 'INSERT') THEN
		NEW.created := statement_timestamp();
	ELSE 
		NEW.updated := statement_timestamp();
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;
comment on FUNCTION ftime_updated() is 
'trigger updating fields created and updated';

--------------------------------------------------------------------------------
-- add the trigger ftime_updated to a table
--------------------------------------------------------------------------------
CREATE FUNCTION _reference_time_trig(_table text) RETURNS int AS $$
DECLARE
	_trigg text;
BEGIN
	_trigg := 'trig_befa_' || _table;
	EXECUTE 'CREATE TRIGGER ' || _trigg || ' BEFORE INSERT
		OR UPDATE ON ' || _table || ' FOR EACH ROW
		EXECUTE PROCEDURE ftime_updated()' ; 
	RETURN 0;
END; 
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
CREATE FUNCTION _grant_read(_table text) RETURNS void AS $$

BEGIN 
	EXECUTE 'GRANT SELECT ON TABLE ' || _table || ' TO market_open_role,market_close_role,admin';
	RETURN;
END; 
$$ LANGUAGE PLPGSQL;
SELECT _grant_read('tconst');
--------------------------------------------------------------------------------
CREATE FUNCTION _reference_time(_table text) RETURNS int AS $$
DECLARE
	_res int;
BEGIN
	
	EXECUTE 'ALTER TABLE ' || _table || ' ADD created timestamp';
	EXECUTE 'ALTER TABLE ' || _table || ' ADD updated timestamp';
	select _reference_time_trig(_table) into _res;
	RETURN 0;
END; 
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
create domain dquantity AS int8 check( VALUE>0);
--------------------------------------------------------------------------------
create table tuser ( 
    id serial UNIQUE not NULL,
    name text not NULL,
    spent int8 default 0 not NULL,
    quota int8 default 0 not NULL,
    last_in timestamp,
    PRIMARY KEY (name),UNIQUE(name),
    CHECK(	
    	char_length(name)>0 AND
    	spent >=0 AND
    	quota >=0
    )
);
SELECT _grant_read('tuser');
alter sequence tuser_id_seq owned by tuser.id;
comment on table tuser is 'users that have been connected';
SELECT _reference_time('tuser');


--------------------------------------------------------------------------------
-- TQUALITY
--------------------------------------------------------------------------------
create table tquality (
    id serial UNIQUE not NULL,
    name text not NULL,
    idd int references tuser(id), -- can be NULL
    depository text,
    qtt bigint default 0,
    PRIMARY KEY (id),
    UNIQUE(name),
    CHECK(	
    	char_length(name)>0 AND 
    	char_length(depository)>0 AND
    	qtt >=0 
    )
);
SELECT _grant_read('tquality');
comment on table tquality is 'description of qualities';
comment on column tquality.name is 'name of depository/name of quality ';
comment on column tquality.depository is 'name of depository (user)';
comment on column tquality.qtt is 'total quantity on the market for this quality';
alter sequence tquality_id_seq owned by tquality.id;
create index tquality_name_idx on tquality(name);
SELECT _reference_time('tquality');

-- \copy tquality (depository,name) from data/ISO4217.data with delimiter '-'

--------------------------------------------------------------------------------
-- IF _CHECK_QUALITY_OWNERSHIP=0
--	quality.name = quality
-- ELSE
--	quality.name == depository/quality
-- 	the length of depository >=1
--------------------------------------------------------------------------------
CREATE FUNCTION fexplodequality(_quality_name text) RETURNS text[] AS $$
DECLARE
	_e int;
	_q text[];
	_CHECK_QUALITY_OWNERSHIP int := fgetconst('CHECK_QUALITY_OWNERSHIP');
BEGIN
	IF(char_length(_quality_name) <1) THEN
		RAISE NOTICE 'Quality name "%" incorrect',_quality_name;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	IF(_CHECK_QUALITY_OWNERSHIP = 0) THEN
		_q[1] := NULL;
		_q[2] := _quality_name;
		RETURN _q;
	END IF;
	
	_e =position('/' in _quality_name);
	IF(_e < 2) THEN 
		RAISE NOTICE 'Quality name "%" incorrect',_quality_name;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	_q[1] = substring(_quality_name for _e-1);
	_q[2] = substring(_quality_name from _e+1);
	if(char_length(_q[2])<1) THEN
		RAISE NOTICE 'Quality name "%" incorrect',_quality_name;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	RETURN _q;
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
CREATE FUNCTION 
	fupdate_quality(_quality_name text,_qtt int8) 
	RETURNS int8 AS $$
DECLARE 
	_qp tquality%rowtype;
	_q text[];
	_idd int;
	_id int;
	_qtta int8;
BEGIN
	LOOP
		UPDATE tquality SET id=id,qtt = qtt + _qtt 
			WHERE name = _quality_name RETURNING id,qtt INTO _id,_qtta;

		IF FOUND THEN
			IF (((_qtt > 0) AND (_qtta < _qtt)) OR (_qtta < 0) ) THEN 
				RAISE WARNING 'Quality "%" owerflows',_quality_name;
				RAISE EXCEPTION USING ERRCODE='YA001';
			END IF;
		
			RETURN _id;
		END IF;
		
		BEGIN
			_q := fexplodequality(_quality_name);
			IF(_q[1] IS NOT NULL) THEN 	
				-- _CHECK_QUALITY_OWNERSHIP =1
				SELECT id INTO _idd FROM tuser WHERE name=_q[1];
				IF(NOT FOUND) THEN -- user should exists
					RAISE NOTICE 'The depository "%" is undefined',_q[1] ;
					RAISE EXCEPTION USING ERRCODE='YU001';
				END IF;
			ELSE
				_idd := NULL;
			END IF;
		
			INSERT INTO tquality (name,idd,depository,qtt) VALUES (_quality_name,_idd,_q[1],_qtt)
				RETURNING * INTO _qp;
			RETURN _qp.id;
			
		EXCEPTION WHEN unique_violation THEN
			--
		END;
	END LOOP;
END;
$$ LANGUAGE PLPGSQL;
	
--------------------------------------------------------------------------------
-- TOWNER
--------------------------------------------------------------------------------
create table towner (
    id serial UNIQUE not NULL,
    name text not NULL,
    PRIMARY KEY (id),
    UNIQUE(name),
    CHECK(	
    	char_length(name)>0 
    )
);
comment on table towner is 'owners of values exchanged';
alter sequence towner_id_seq owned by towner.id;
create index towner_name_idx on towner(name);
SELECT _reference_time('towner');
SELECT _grant_read('towner');
--------------------------------------------------------------------------------
/*
returns the id of an owner.
If the owner does'nt exist, it is created
*/
--------------------------------------------------------------------------------
CREATE FUNCTION fowner(_name text) RETURNS int8 AS $$
DECLARE
	_wid int;
BEGIN
	LOOP
		SELECT id INTO _wid FROM towner WHERE name=_name;
		IF found THEN
			return _wid;
		ELSE
			IF (fgetconst('INSERT_OWN_UNKNOWN')=0) THEN
				RAISE NOTICE 'The owner % is unknown',_name;
				RAISE EXCEPTION USING ERRCODE='YU001';
			END IF;
		END IF;
		BEGIN
			if(char_length(_name)<1) THEN
				RAISE NOTICE 'Owner s name empty';
				RAISE EXCEPTION USING ERRCODE='YU001';
			END IF;
			INSERT INTO towner (name) VALUES (_name) RETURNING id INTO _wid;
			RAISE INFO 'owner % created',_name;
			return _wid;
		EXCEPTION WHEN unique_violation THEN
			--
		END;
	END LOOP;
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
-- ORDER
--------------------------------------------------------------------------------
-- id,uuid,own,nr,qtt_requ,np,qtt_prov,qtt,created,updated
create table torder ( 
    id serial UNIQUE not NULL,
    uuid text NOT NULL,
    own int references towner(id) NOT NULL, 
	
    nr int references tquality(id) not NULL ,
    qtt_requ dquantity NOT NULL,
    
    np int references tquality(id) not NULL ,
    qtt_prov dquantity NOT NULL,
    qtt int NOT NULL,     

    created timestamp not NULL,
    updated timestamp default NULL,    
    PRIMARY KEY (id),
    CHECK(	
    	qtt >=0 AND qtt_prov >= qtt
    )
);
SELECT _grant_read('torder');

comment on table torder is 'description of orders';
comment on column torder.id is 'unique id for the session of the market';
comment on column torder.uuid is 'unique id for all sessions';
comment on column torder.own is 'owner of the value provided';
comment on column torder.nr is 'quality required';
comment on column torder.qtt_requ is 'quantity required; used to express omega=qtt_prov/qtt_req';
comment on column torder.np is 'quality provided';
comment on column torder.qtt_prov is 'quantity offered';
comment on column torder.qtt is 'current quantity remaining (<= quantity offered)';

alter sequence torder_id_seq owned by torder.id;
create index torder_nr_idx on torder(nr);
create index torder_np_idx on torder(np);

--------------------------------------------------------------------------------
CREATE VIEW vorder AS 
	SELECT 	
		n.id as id,
		n.uuid as uuid,
		w.name as owner,
		qr.name as qua_requ,
		n.qtt_requ,
		qp.name as qua_prov,
		n.qtt_prov,
		n.qtt,
		n.created as created,
		n.updated as updated
	FROM torder n
	INNER JOIN tquality qr ON n.nr = qr.id 
	INNER JOIN tquality qp ON n.np = qp.id
	INNER JOIN towner w on n.own = w.id;

SELECT _grant_read('vorder');


-- Columns of torderremoved and torder are the same 
create table torderremoved ( 
    id int NOT NULL,
    uuid text NOT NULL,
    own int NOT NULL,
    nr int  not NULL ,
    qtt_requ dquantity NOT NULL,
    np int not NULL ,
    qtt_prov dquantity NOT NULL,
    qtt int NOT NULL,
    created timestamp not NULL,
    updated timestamp default NULL,
    PRIMARY KEY (uuid)
);
SELECT _grant_read('torderremoved');

CREATE VIEW vorderremoved AS 
	SELECT 	
		n.id,
		n.uuid as uuid,
		w.name as owner,
		qr.name as qua_requ,
		n.qtt_requ,
		qp.name as qua_prov,
		n.qtt_prov,
		n.qtt,
		n.created as created,
		n.updated as updated
	FROM torderremoved n
	INNER JOIN tquality qr ON n.nr = qr.id 
	INNER JOIN tquality qp ON n.np = qp.id
	INNER JOIN towner w on n.own = w.id;
	
SELECT _grant_read('vorderremoved');
--------------------------------------------------------------------------------
CREATE VIEW vorderverif AS
	SELECT id,uuid,own,nr,qtt_requ,np,qtt_prov,qtt FROM torder
	UNION
	SELECT id,uuid,own,nr,qtt_requ,np,qtt_prov,qtt FROM torderremoved;
	
SELECT _grant_read('vorderverif');

--------------------------------------------------------------------------------
-- TMVT
--------------------------------------------------------------------------------
create table tmvt (
        id serial UNIQUE not NULL,
        nb int not null,
        oruuid text NOT NULL, -- refers to order uuid
    	grp int references tmvt(id), 
    	-- References the first mvt of an exchange.
    	-- can be NULL
	own_src int references towner(id)  not null, 
	own_dst int  references towner(id) not null,
	qtt dquantity not NULL,
	nat int references tquality(id) not null,
	created timestamp not NULL
);
SELECT _grant_read('tmvt');

comment on table tmvt is 'records a change of ownership';
comment on column tmvt.nb is 'number of movements of the exchange';
comment on column tmvt.oruuid is 'order.uuid producing  this movement';
comment on column tmvt.grp is 'first movement of the exchange';
comment on column tmvt.own_src is 'owner provider';
comment on column tmvt.own_dst is 'owner receiver';
comment on column tmvt.qtt is 'quantity of the value moved';
comment on column tmvt.nat is 'quality of the value moved';

alter sequence tmvt_id_seq owned by tmvt.id;
create index tmvt_did_idx on tmvt(grp);
create index tmvt_nat_idx on tmvt(nat);
create index tmvt_own_src_idx on tmvt(own_src);
create index tmvt_own_dst_idx on tmvt(own_dst);

--------------------------------------------------------------------------------
-- vmvt 
--------------------------------------------------------------------------------
CREATE VIEW vmvt AS 
	SELECT 	m.id as id,
		m.nb as nb,
		m.oruuid as oruuid,
		m.grp as grp,
		w_src.name as provider,
		q.name as quality,
		m.qtt as qtt,
		w_dst.name as receiver,
		m.created as created
	FROM tmvt m
	INNER JOIN towner w_src ON (m.own_src = w_src.id)
	INNER JOIN towner w_dst ON (m.own_dst = w_dst.id) 
	INNER JOIN tquality q ON (m.nat = q.id); 	
SELECT _grant_read('vmvt');
COMMENT ON VIEW vmvt IS 'List of movements';
COMMENT ON COLUMN vmvt.nb IS 'number of movements of the exchange';
COMMENT ON COLUMN vmvt.oruuid IS 'reference to the exchange';
COMMENT ON COLUMN vmvt.grp IS 'id of the first movement of the exchange';
COMMENT ON COLUMN vmvt.provider IS 'name of the provider of the movement';
COMMENT ON COLUMN vmvt.quality IS 'name of the quality moved';
COMMENT ON COLUMN vmvt.qtt IS 'quantity moved';
COMMENT ON COLUMN vmvt.receiver IS 'name of the receiver of the movement';
COMMENT ON COLUMN vmvt.created IS 'time of the transaction';

--------------------------------------------------------------------------------
create table tmvtremoved (
        id int UNIQUE not NULL,
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
SELECT _grant_read('tmvtremoved');
--------------------------------------------------------------------------------
CREATE VIEW vmvtverif AS
	SELECT id,nb,oruuid,grp,own_src,own_dst,qtt,nat FROM tmvt
	UNION ALL
	SELECT id,nb,oruuid,grp,own_src,own_dst,qtt,nat FROM tmvtremoved;
SELECT _grant_read('vmvtverif');

--------------------------------------------------------------------------------
CREATE VIEW vstat AS 
	SELECT 	q.name as name,
		sum(d.qtt) - q.qtt as delta,
		q.qtt as qtt_quality,
		sum(d.qtt) as qtt_detail
	FROM (
		SELECT np as nat,qtt FROM vorderverif
		UNION ALL
		SELECT nat,qtt FROM vmvtverif
	) AS d
	INNER JOIN tquality AS q ON (d.nat=q.id)
	GROUP BY q.id ORDER BY q.name; 

SELECT _grant_read('vstat');	

/* examples:
	 select count(*) from vstat where delta!=0;
		should return 0 
*/
--------------------------------------------------------------------------------
-- order
--------------------------------------------------------------------------------
CREATE function fremoveorder(_uuid text) RETURNS vorder AS $$
DECLARE
	_qtt		int8;
	_o 		torder%rowtype;
	_vo		vorder%rowtype;
	_qlt		tquality%rowtype;
	_CHECK_QUALITY_OWNERSHIP int := fgetconst('CHECK_QUALITY_OWNERSHIP');
BEGIN
	_vo.id = NULL;
	IF(_CHECK_QUALITY_OWNERSHIP != 0) THEN
		SELECT o.* INTO _o FROM torder o,tquality q,tuser u 
			WHERE 	o.np=q.id AND q.idd=u.id AND u.name=session_user AND o.uuid = _uuid;
		IF NOT FOUND THEN
			RAISE WARNING 'the order % on a quality belonging to % was not found',_uuid,session_user;
			RAISE EXCEPTION USING ERRCODE='YU001';
		END IF;
	ELSE
		SELECT o.* INTO _o FROM torder o,tquality q,tuser u 
			WHERE 	o.np=q.id AND o.uuid = _uuid;
		IF NOT FOUND THEN
			RAISE WARNING 'the order % on a quality was not found',_uuid;
			RAISE EXCEPTION USING ERRCODE='YU001';
		END IF;
	END IF;
	
	UPDATE tquality SET qtt = qtt - _o.qtt WHERE id = _o.np RETURNING qtt INTO _qlt;	
	IF(_qlt.qtt <0) THEN
		RAISE WARNING 'the quality % underflows',_qlt.name;
		RAISE EXCEPTION USING ERRCODE='YA002';
	END IF;
	
	SELECT * INTO _vo FROM vorder WHERE id = _o.id;	
	WITH a AS (DELETE FROM torder o WHERE o.id=_o.id RETURNING *) 
	INSERT INTO torderremoved SELECT id,uuid,own,nr,qtt_requ,np,qtt_prov,qtt,created,updated FROM a;
	
	RETURN _vo;
	
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE INFO 'ABORTED';
	RETURN _vo; 
END;		
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fremoveorder(text) TO market_open_role,market_close_role;

--------------------------------------------------------------------------------
-- finsert_order
--------------------------------------------------------------------------------
/* usage: 
	nb_draft int = finsertorder(_owner text,_qualityprovided text,qttprovided int8,_qttrequired int8,_qualityrequired text)
		
	action:
		inserts the order.
		if _owner,_qualityprovided or _qualityrequired do not exist, they are created
*/
--------------------------------------------------------------------------------
-- torder id,uuid,yorder,created,updated
-- yorder: qtt,nr,np,qtt_prov,qtt_requ,own
CREATE FUNCTION 
	finsertorder(_owner text,_qualityprovided text,_qttprovided int8,_qttrequired int8,_qualityrequired text)
	RETURNS TABLE ( _yuuid text, _ydim int, _ygrp int) AS $$
	
DECLARE
	_user text;
	_np	int;
	_nr	int;
	_wid	int;
	_pivot torder%rowtype;
	_q	text[];
	_time_begin timestamp;
	_uid	int;
	_CHECK_QUALITY_OWNERSHIP int := fgetconst('CHECK_QUALITY_OWNERSHIP');
BEGIN
	_uid := fconnect(true);
	_time_begin := clock_timestamp();
	
	-- order is rejected if the depository is not the user
	_q := fexplodequality(_qualityprovided);
	IF ((_q[1] IS NOT NULL) AND (_q[1] != session_user)) THEN
		RAISE NOTICE 'depository % of quality is not the user %',_q[1],session_user;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	-- quantities should be >0
	IF(_qttprovided<=0 OR _qttrequired<=0) THEN
		RAISE NOTICE 'quantities incorrect: %<=0 or %<=0', _qttprovided,_qttrequired;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	-- qualities are inserted if necessary (depository should exist)
	_np := fupdate_quality(_qualityprovided,_qttprovided); 
	_nr := fupdate_quality(_qualityrequired,0);
	
	-- if the owner does not exist, it is inserted
	_wid := fowner(_owner);
	
	_pivot.id  := 0;
	_pivot.own := _wid;
	
	_pivot.nr  := _nr;
	_pivot.qtt_requ := _qttrequired;
	
	_pivot.np  := _np;
	_pivot.qtt_prov := _qttprovided;
	_pivot.qtt := _qttprovided;
	
	FOR _yuuid,_ydim,_ygrp IN SELECT _zuuid,_zdim,_zgrp  FROM finsert_order_int(_pivot,TRUE) LOOP
		RETURN NEXT;
	END LOOP;
	
	perform fspendquota(_time_begin);
	
	RETURN;
	
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE INFO 'ABORTED';
	RETURN; 

END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  finsertorder(text,text,int8,int8,text) TO market_open_role;

CREATE VIEW vorderinsert AS
	SELECT id,yorder_get(id,own,nr,qtt_requ,np,qtt_prov,qtt) as ord,np,nr
	FROM torder ORDER BY id ASC;
	
--------------------------------------------------------------------------------
-- finsert_order_int
--------------------------------------------------------------------------------
CREATE FUNCTION 
	finsert_order_int(_pivot torder,_insert bool) 
	RETURNS TABLE (_zuuid text, _zdim int, _zgrp int,_zqtt_prov int8,_zqtt_requ int8) AS $$
DECLARE

	_idpivot 	int;
	_patmax		yflow;
	_cnt 		int;
	_o		torder%rowtype;
	_res	        int8[];
BEGIN
	------------------------------------------------------------------------
	_pivot.qtt := _pivot.qtt_prov;
	
	IF(_insert) THEN
		INSERT INTO torder (uuid,qtt,nr,np,qtt_prov,qtt_requ,own,created,updated) 
			VALUES ('',_pivot.qtt,_pivot.nr,_pivot.np,_pivot.qtt_prov,_pivot.qtt_requ,_pivot.own,statement_timestamp(),NULL)
			RETURNING id INTO _idpivot;
		_zuuid := fgetuuid(_idpivot);
		UPDATE torder SET uuid = _zuuid WHERE id=_idpivot RETURNING * INTO _o;
		_cnt := fcreate_tmp(_o.id,
				yorder_get(_o.id,_o.own,_o.nr,_o.qtt_requ,_o.np,_o.qtt_prov,_o.qtt),
				_o.np,_o.nr);
	ELSE
		select max(id)+1 INTO _pivot.id FROM torder;
		-- _pivot.id!=0 and from all id inserted => lastignore=false 
		_cnt := fcreate_tmp(_pivot.id,
				yorder_get(_pivot.id,_pivot.own,_pivot.nr,_pivot.qtt_requ,_pivot.np,_pivot.qtt_prov,_pivot.qtt),
				_pivot.np,_pivot.nr);
	END IF;

	IF(_cnt=0) THEN
		RETURN;
	END IF;
	_cnt := 0;
/*	
	DROP TABLE IF EXISTS _tmp_insert;
	CREATE TABLE _tmp_insert AS (SELECT * FROM _tmp);
*/	
	LOOP
		_cnt := _cnt + 1;
		SELECT yflow_max(pat) INTO _patmax FROM _tmp;
		IF (yflow_status(_patmax)!=3) THEN
			EXIT; -- from LOOP
		END IF;

/*
		IF(_cnt = 1) THEN
			RAISE NOTICE 'get max = %',yflow_show(_patmax);
		END IF;
*/
		IF(_insert) THEN
		----------------------------------------------------------------
			_zgrp := fexecute_flow(_patmax);
			_zdim := yflow_dim(_patmax);
			RETURN NEXT;
		ELSE
			_res := yflow_qtts(_patmax);
			_zqtt_prov := _res[1];
			_zqtt_requ := _res[2];
			_zdim 	:= _res[3];
			-- RAISE NOTICE 'maxflow %' ,yflow_show(_patmax);
			RETURN NEXT;		
		END IF;
		----------------------------------------------------------------
		UPDATE _tmp SET pat = yflow_reduce(pat,_patmax);
	END LOOP;
	
	DROP TABLE _tmp;
 	RETURN;
END; 
$$ LANGUAGE PLPGSQL; 
--------------------------------------------------------------------------------
CREATE FUNCTION fcreate_tmp(_id int,_ord yorder,_np int,_nr int) RETURNS int AS $$
DECLARE 
	_MAXORDERFETCH	 int := fgetconst('MAXORDERFETCH'); 
	_MAXCYCLE 	int := fgetconst('MAXCYCLE');
	_cnt int;
BEGIN
	-- DROP TABLE IF EXISTS _tmp;
	-- RAISE INFO 'pivot: id=% ord=%, np=%, nr=%',_id,_ord,_np,_nr;
	CREATE TEMPORARY TABLE _tmp ON COMMIT DROP AS (
		WITH RECURSIVE search_backward(id,ord,pat,np,nr) AS (
			SELECT 	_id,_ord,yflow_get(_ord),_np,_nr
			UNION ALL
			SELECT 	X.id,X.ord,
				yflow_get(X.ord,Y.pat), -- add the order at the begin of the yflow
				X.np,X.nr
				FROM vorderinsert X, search_backward Y
				WHERE  X.np = yorder_nr(Y.ord) -- use of indexe 
					AND yflow_follow(_MAXCYCLE,X.ord,Y.pat) 
					-- X->Y === X.qtt>0 and X.np=Y[0].nr
					-- Y.pat does not contain X.ord 
					-- len(X.ord+Y.path) <= _MAXCYCLE	
					-- Y[!=-1]|->X === Y[i].np != X.nr with i!= -1
				 
		)
		SELECT id,ord,nr,pat 
		FROM search_backward where yflow_status(pat)=3 LIMIT _MAXORDERFETCH --draft
	);
	SELECT COUNT(*) INTO _cnt FROM _tmp;
	
	RETURN _cnt;
END;
$$ LANGUAGE PLPGSQL;


--------------------------------------------------------------------------------
-- fexecute_flow
--------------------------------------------------------------------------------

CREATE FUNCTION fexecute_flow(_flw yflow) RETURNS int AS $$
DECLARE
	_commits	int[][];
	_i		int;
	_next_i		int;
	_nbcommit	int;
	
	_oid		int;
	_w_src		int;
	_w_dst		int;
	_flowr		int8;
	_first_mvt	int;
	_exhausted	bool;
	_mvt_id		int;
	_qtt		int8;
	_cnt 		int;
	_uuid		text;
BEGIN

	_commits := yflow_to_matrix(_flw);
	-- indices in _commits
	-- 1  2   3  4        5  6        7   8
	-- id,own,nr,qtt_requ,np,qtt_prov,qtt,flowr
	
	_nbcommit := yflow_dim(_flw);
	_first_mvt := NULL;
	_exhausted := false;
	
	_i := _nbcommit;	
	FOR _next_i IN 1 .. _nbcommit LOOP
		-- _commits[_next_i] follows _commits[_i]
		_oid	:= _commits[_i][1]::int;
		_w_src	:= _commits[_i][2]::int;
		_w_dst	:= _commits[_next_i][2]::int;
		_flowr	:= _commits[_i][8];
		
		UPDATE torder set qtt = qtt - _flowr ,updated = statement_timestamp()
			WHERE id = _oid AND _flowr <= qtt RETURNING uuid,qtt INTO _uuid,_qtt;
		IF(NOT FOUND) THEN
			RAISE WARNING 'the flow is not in sync with the databasetorder[%].qtt does not exist or < %',_oid,_flowr ;
			RAISE EXCEPTION USING ERRCODE='YU001';
		END IF;
			
		INSERT INTO tmvt (nb,oruuid,grp,own_src,own_dst,qtt,nat,created) 
			VALUES(_nbcommit,_uuid,_first_mvt,_w_src,_w_dst,_flowr,_commits[_i][5]::int,statement_timestamp())
			RETURNING id INTO _mvt_id;
					
		IF(_first_mvt IS NULL) THEN
			_first_mvt := _mvt_id;
		END IF;
		
		IF(_qtt=0) THEN
			-- order is moved to orderremoved
			WITH a AS (DELETE FROM torder WHERE id=_oid RETURNING *) 
			INSERT INTO torderremoved SELECT id,uuid,own,nr,qtt_requ,np,qtt_prov,qtt,created,updated FROM a;
			_exhausted := true;
		END IF;

		_i := _next_i;
		------------------------------------------------------
	END LOOP;

	UPDATE tmvt SET grp = _first_mvt WHERE id = _first_mvt  AND (grp IS NULL);	
	IF(NOT FOUND) THEN
		RAISE EXCEPTION 'the movement % does not exist',_first_mvt 
			USING ERRCODE='YA003';
	END IF;
	
	IF(NOT _exhausted) THEN
		--  some order should be exhausted 
		RAISE EXCEPTION 'the cycle should exhaust some order' 
			USING ERRCODE='YA003';
	END IF;
	
	RETURN _first_mvt;
END;
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
-- quote
--------------------------------------------------------------------------------

CREATE FUNCTION 
	fget_quality(_quality_name text) 
	RETURNS int AS $$
DECLARE 
	_id int;
BEGIN
	SELECT id INTO _id FROM tquality WHERE name = _quality_name;
	IF NOT FOUND THEN
		RAISE WARNING 'The quality "%" is undefined',_quality_name;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	RETURN _id;
END;
$$ LANGUAGE PLPGSQL;
	
--------------------------------------------------------------------------------
-- fgetquote
--------------------------------------------------------------------------------
/* usage: 
	nb_draft int = fgetquote(_qualityprovided text,_qualityrequired text)
		
	action:
		read omegas.
		if _qualityprovided or _qualityrequired do not exist, the function exists
	
	returns list of
		_qtt_prov,_qtt_requ

*/
--------------------------------------------------------------------------------
CREATE FUNCTION 
	fgetquote(_owner text,_qualityprovided text,_qualityrequired text) 
	RETURNS TABLE(_dim int,_qtt_prov int8,_qtt_requ int8 ) AS $$
	
DECLARE
	_np	int;
	_nr	int;
	_time_begin timestamp;
	_uid	int;
	_wid	int;
BEGIN
	_uid := fconnect(true);
	_time_begin := clock_timestamp();
	
	-- qualities are red
	_np := fget_quality(_qualityprovided); 
	_nr := fget_quality(_qualityrequired);
	-- RAISE INFO '_np=%,_nr=%' , _np,_nr;

	SELECT id INTO _wid FROM towner WHERE name = _owner;
	IF NOT FOUND THEN
		_wid := 0;
	END IF;
		
	FOR _dim,_qtt_prov,_qtt_requ IN SELECT * FROM fgetquote_int(_wid,_np,_nr) LOOP
		RETURN NEXT;
	END LOOP;
	
	perform fspendquota(_time_begin);
	
	RETURN;
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE INFO 'ABORTED';
	RETURN;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fgetquote(text,text,text) TO market_open_role;
/*
CREATE VIEW vorder_int AS
	SELECT id,yorder_get(id,own,nr,qtt_requ,np,qtt_prov,qtt) as ord,np,nr FROM torder;
*/
--------------------------------------------------------------------------------
CREATE FUNCTION fgetquote_int(_wid int,_np int,_nr int) 
	RETURNS TABLE(_dim int,_qtt_prov int8,_qtt_requ int8) AS $$
DECLARE 
	_patmax	yflow;
	_res	int8[];
	_cnt int;
	_start timestamp;
BEGIN
	_cnt := fcreate_tmp(0,yorder_get(0,_wid,_nr,1,_np,1,1),_np,_nr);
	
/*	DROP TABLE IF EXISTS _tmp_quote;
	CREATE TABLE _tmp_quote AS (SELECT * FROM _tmp);
*/
	IF(_cnt=0) THEN
		RETURN;
	END IF;
	_cnt :=0;
	LOOP	
		_cnt := _cnt+1;
		SELECT yflow_max(pat) INTO _patmax FROM _tmp;
		IF (yflow_status(_patmax)!=3) THEN
			EXIT; -- from LOOP
		END IF;		
/*
		IF(_cnt = 1) THEN
			RAISE NOTICE 'get max = %',yflow_show(_patmax);
		END IF;
*/
		----------------------------------------------------------------
		_res := yflow_qtts(_patmax);
		_qtt_prov := _res[1];
		_qtt_requ := _res[2];
		_dim 	:= _res[3];
		-- RAISE NOTICE 'maxflow %' ,yflow_show(_patmax);
		RETURN NEXT;
		----------------------------------------------------------------
		UPDATE _tmp SET pat = yflow_reduce(pat,_patmax);

	END LOOP;
	
	DROP TABLE _tmp;
	RETURN;
END; 
$$ LANGUAGE PLPGSQL;
	
--------------------------------------------------------------------------------
-- fgetquoteorder
--------------------------------------------------------------------------------
/* usage: 
	nb_draft int = fgetquoteorder(_owner text,_qualityprovided text,_qttprovided int8,_qttrequired int8,_qualityrequired text)
		
	action:
		read omegas.
		if _qualityprovided or _qualityrequired do not exist, the function exists
	
	returns list of
		_qtt_prov,_qtt_requ

*/
--------------------------------------------------------------------------------

CREATE FUNCTION 
	fgetquoteorder(_owner text,_qualityprovided text,_qttprovided int8,_qttrequired int8,_qualityrequired text) 
	RETURNS TABLE(_dim int,_qtt_prov int8,_qtt_requ int8 ) AS $$
	
DECLARE
	_np	int;
	_nr	int;
	_time_begin timestamp;
	_uid	int;
	_wid	int;
	_pivot torder%rowtype;
BEGIN
	_uid := fconnect(true);
	_time_begin := clock_timestamp();
	
	SELECT id INTO _wid FROM towner WHERE name = _owner;
	IF NOT FOUND THEN
		_wid := 0;
	END IF;
	
	-- qualities are red
	_pivot.np := fget_quality(_qualityprovided); 
	_pivot.nr := fget_quality(_qualityrequired);
	-- _pivot.id  := 0;
	_pivot.own := _wid;
	_pivot.qtt_requ := _qttrequired;
	_pivot.qtt_prov := _qttprovided;
	_pivot.qtt := _qttprovided;
		
	FOR _dim,_qtt_prov,_qtt_requ IN SELECT _zdim,_zqtt_prov,_zqtt_requ  FROM finsert_order_int(_pivot,FALSE) LOOP
		RETURN NEXT;
	END LOOP;
	
	perform fspendquota(_time_begin);
	
	RETURN;
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE INFO 'ABORTED';
	RETURN;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fgetquoteorder(text,text,int8,int8,text) TO market_open_role;

--------------------------------------------------------------------------------
-- admin
--------------------------------------------------------------------------------
-- init->close->prepare->open->close->prepare->open ...
create type ymarketaction AS ENUM ('init','close','prepare','open');
create table tmarket ( 
    id serial UNIQUE not NULL,
    sess	int not NULL,
    action ymarketaction NOT NULL,
    created timestamp not NULL
);
alter sequence tmarket_id_seq owned by tmarket.id;
SELECT _grant_read('tmarket');
--------------------------------------------------------------------------------
CREATE VIEW vmarket AS SELECT
 	sess AS market_session,
 	created,
 	CASE WHEN action IN ('init','open') THEN 'OPENED' ELSE  'CLOSED' 
	END AS state
	FROM tmarket ORDER BY ID DESC LIMIT 1; 
SELECT _grant_read('vmarket');	
--------------------------------------------------------------------------------
CREATE FUNCTION fcreateuser(_name text) RETURNS void AS $$
DECLARE
	_user	tuser%rowtype;
	_super	bool;
	_statemarket	text;
BEGIN
-- TODO give a role depending on market phase
	IF( _name IN ('admin','client','market_open_role','market_close_role')) THEN
		RAISE WARNING 'The name % is not allowed',_name;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	SELECT * INTO _user FROM tuser WHERE name=_name;
	IF FOUND THEN
		RAISE WARNING 'The user % exists',_name;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	SELECT rolsuper INTO _super FROM pg_authid where rolname=_name;
	IF NOT FOUND THEN
		EXECUTE 'CREATE ROLE ' || _name;
		EXECUTE 'ALTER ROLE ' || _name || ' NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION'; 
		EXECUTE 'ALTER ROLE ' || _name || ' LOGIN CONNECTION LIMIT 1';
	ELSE
		IF(_super) THEN
			RAISE INFO 'The role % is a super user.',_name;
		ELSE
			RAISE WARNING 'The user is not found but a role % already exists - unchanged.',_name;
			RAISE EXCEPTION USING ERRCODE='YU001';				
		END IF;
	END IF;
	
	INSERT INTO tuser (name) VALUES (_name);
	SELECT state INTO _statemarket FROM vmarket;
	IF(_statemarket = 'OPENED') THEN
		RAISE INFO 'The market is opened for this user %', _name;
		EXECUTE 'GRANT market_open_role TO ' || _name;
	END IF;
	
	RETURN;
		
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE INFO 'ABORTED';
	RETURN; 
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fcreateuser(text) TO admin;

--------------------------------------------------------------------------------
CREATE FUNCTION fclose() RETURNS tmarket AS $$
DECLARE
	_hm tmarket%rowtype;
BEGIN
	
	REVOKE market_open_role FROM client;
	GRANT  market_close_role TO client;
	
	SELECT * INTO _hm FROM fchangestatemarket('close');
	
	REVOKE EXECUTE ON FUNCTION fclose() FROM admin;
	GRANT EXECUTE ON FUNCTION  fprepare() TO admin;
	RAISE INFO 'The market is now closed';
	RAISE INFO 'The function fprepare() is enabled.';
	RAISE INFO 'It will succeed only when tables tmvt and torder are empty.';
	RETURN _hm;
	
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE INFO 'ABORTED';
	RETURN _hm; 
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;

--
-- close client access 
-- aborts when some tables are not empty
--------------------------------------------------------------------------------
CREATE FUNCTION fprepare() RETURNS tmarket AS $$
DECLARE
	_hm tmarket%rowtype;
	_cnt int;
BEGIN
	
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
			
	REVOKE EXECUTE ON FUNCTION fprepare() FROM admin;
	GRANT EXECUTE ON FUNCTION fopen() TO admin;
		
	REVOKE market_close_role FROM client;
	RAISE INFO 'fopen() is enabled';
	RAISE INFO 'All market tables will be truncated when you will execute it';
	RETURN _hm;
	
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE INFO 'ABORTED';
	RETURN _hm; 
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;

--------------------------------------------------------------------------------
CREATE FUNCTION fopen() RETURNS tmarket AS $$
DECLARE
	_hm tmarket%rowtype;
	_cnt int;
BEGIN
	
	perform ftruncatetables();
	
	_hm := fchangestatemarket('open');
	
	REVOKE EXECUTE ON FUNCTION fopen() FROM admin;
	GRANT EXECUTE ON FUNCTION  fclose() TO admin;
	 
	GRANT market_open_role TO client;
	RAISE INFO 'fclose() is enabled';
	RAISE INFO 'The market is now opened';
	RETURN _hm;
	
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE INFO 'ABORTED';
	RETURN _hm; 
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;

--------------------------------------------------------------------------------
CREATE FUNCTION ftruncatetables() RETURNS void AS $$
DECLARE
	_hm tmarket%rowtype;
	_cnt int;
BEGIN
	
	TRUNCATE tmvt;
	PERFORM setval('tmvt_id_seq',1,false);	
	TRUNCATE torder CASCADE;
	PERFORM setval('torder_id_seq',1,false);
	TRUNCATE tquality CASCADE;
	PERFORM setval('tquality_id_seq',1,false);
	TRUNCATE towner CASCADE;
	PERFORM setval('towner_id_seq',1,false);
		
	TRUNCATE torderemoved;
	TRUNCATE tmvtremoved;
	
	VACUUM FULL ANALYZE;
	RAISE INFO 'All market tables have been truncated';
	RETURN;
	 
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;


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
		GRANT EXECUTE ON FUNCTION  fclose() TO admin;
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
-- execution of fclose() is granted to admin

--------------------------------------------------------------------------------
CREATE FUNCTION fgetuuid(_id int) RETURNS text AS $$ 
DECLARE
	_session	int;
BEGIN
	SELECT value INTO _session FROM tconst WHERE name='MARKET_SESSION';
	RETURN _session::text || '-' || _id::text; 
END;
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
-- user
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- moves all movements of an exchange belonging to the user into tmvtremoved 
CREATE FUNCTION 
	fremoveagreement(_grp int) 
	RETURNS int AS $$
DECLARE 
	_nat int;
	_cnt int8;
	_qtt int8;
	_qlt tquality%rowtype;
	_CHECK_QUALITY_OWNERSHIP int := fgetconst('CHECK_QUALITY_OWNERSHIP');
BEGIN
	_cnt := 0;
	FOR _nat,_qtt IN SELECT m.nat,sum(m.qtt) FROM tmvt m, tquality q,tuser u 
		WHERE m.nat=q.id AND 
		((q.idd=u.id AND u.name=session_user) OR (_CHECK_QUALITY_OWNERSHIP = 0)) AND 
		m.grp=_grp GROUP BY m.nat LOOP
		
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
	
	
	WITH a AS (DELETE FROM tmvt m USING tquality q,tuser u WHERE m.nat=q.id AND 
		((q.idd=u.id AND u.name=session_user) OR (_CHECK_QUALITY_OWNERSHIP = 0)) 
		AND m.grp=_grp RETURNING m.*) 
	INSERT INTO tmvtremoved SELECT id,nb,oruuid,grp,own_src,own_dst,qtt,nat,created,statement_timestamp() as deleted FROM a;

	RETURN _cnt::int;
	
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE INFO 'ABORTED';
	RETURN 0; 
END;
$$ LANGUAGE PLPGSQL;
GRANT EXECUTE ON FUNCTION  fremoveagreement(int) TO market_open_role,market_close_role;

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


--------------------------------------------------------------------------------
-- stat
--------------------------------------------------------------------------------
	
--------------------------------------------------------------------------------
CREATE FUNCTION fgetstats(_extra bool) RETURNS TABLE(_name text,cnt int8) AS $$
DECLARE 
	_i 		int;
	_cnt 		int;
BEGIN

	_name := 'number of qualities';
	select count(*) INTO cnt FROM tquality;
	RETURN NEXT;
	
	_name := 'number of owners';
	select count(*) INTO cnt FROM towner;
	RETURN NEXT;
		
	_name := 'number of orders';
	select count(*) INTO cnt FROM vorderverif;
	RETURN NEXT;
	
	_name := 'number of movements';
	select count(*) INTO cnt FROM vmvtverif;
	RETURN NEXT;

	_name := 'number of orders removed';
	select count(*) INTO cnt FROM torderremoved;
	RETURN NEXT;
	
	_name := 'number of movements removed';
	select count(*) INTO cnt FROM tmvtremoved;	
	RETURN NEXT;
	
	_name := 'total number of agreements';
	select count(distinct grp) INTO cnt FROM vmvtverif;	
	RETURN NEXT;
	

	IF(_extra) THEN
	
		_name := 'errors on quantities in mvts';
		cnt := fverifmvt();
		RETURN NEXT;
	
		_name := 'errors on agreements in mvts';
		cnt := fverifmvt2();
		RETURN NEXT;

		FOR _name,cnt IN SELECT name,value FROM tconst LOOP
			RETURN NEXT;
		END LOOP;
				
		_cnt := 0;
		FOR _i,cnt IN SELECT * FROM fcntcycles() LOOP
			IF(_i !=1) THEN
				_name := 'agreements with ' || _i || ' partners';
				_cnt := _cnt + cnt;
			RETURN NEXT;
			END IF;
		END LOOP;
		
	END IF;
	
	RETURN;
END;
$$ LANGUAGE PLPGSQL;
GRANT EXECUTE ON FUNCTION  fgetstats(bool) TO admin;

--------------------------------------------------------------------------------
-- for each cycle length, gives the number of agreements
CREATE FUNCTION fcntcycles() RETURNS TABLE(nbCycle int,cnt int) AS $$ 
	select a.cxt as nbCycle ,count(*)::int as cnt from (
		select count(*)::int as cxt from vmvtverif group by grp
	) a group by a.cxt order by a.cxt asc $$
LANGUAGE SQL;
	
--------------------------------------------------------------------------------
CREATE FUNCTION fverifmvt() RETURNS int AS $$
DECLARE
	_qtt_prov	 int8;
	_qtt		 int8;
	_uuid		 text;
	_qtta		 int8;
	_npa		 int;
	_npb		 int;
	_np		 int;
	_cnterr		 int := 0;
	_cnt		 int;
	_nb		 int;
BEGIN
	
	FOR _qtt_prov,_qtt,_uuid,_np IN SELECT qtt_prov,qtt,uuid,np FROM vorderverif LOOP
		
		SELECT sum(qtt),max(nat),min(nat),count(*),max(nb) INTO _qtta,_npa,_npb,_cnt,_nb 
			FROM vmvtverif WHERE oruuid=_uuid GROUP BY oruuid;
		IF(FOUND AND (_cnt=_nb)) THEN 
			IF((_qtt_prov != _qtta+_qtt) OR (_np != _npa) OR (_npa != _npb)) THEN 
				_cnterr := _cnterr +1;
				-- raise INFO 'uuid:%, nb:%',_uuid,_nb;
			END IF;
		END IF;
	END LOOP;

	RETURN _cnterr;
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
/* count error in movements when compared to orders  */
CREATE FUNCTION fverifmvt2() RETURNS int AS $$
DECLARE
	_cnterr		 int := 0;
	_cnterrtot	 int := 0;
	_mvt		 tmvt%rowtype;
	_mvtprec	 tmvt%rowtype;
	_mvtfirst	 tmvt%rowtype;
	_uuiderr	 text;
	_cnt		 int;		-- count mvt in agreement
BEGIN
		
	_mvtprec.grp := NULL;_mvtfirst.grp := NULL;
	_uuiderr := NULL;
	FOR _mvt IN SELECT * FROM vmvtverif ORDER BY grp,id ASC  LOOP
		IF(_mvt.grp != _mvtprec.grp) THEN -- first mvt of agreement
			--> finish last agreement
			IF NOT (_mvtprec.grp IS NULL OR _mvtfirst.grp IS NULL) THEN
				_cnterr := _cnterr + fverifmvt2_int(_mvtprec,_mvtfirst);
				_cnt := _cnt +1;
				
				if(_cnt != _mvtprec.nb) THEN
					_cnterr := _cnterr +1;
					RAISE INFO 'wrong number of movements for agreement %',_mvtprec.oruuid;
				END IF;
				-- errors found
				if(_cnterr != 0) THEN
					_cnterrtot := _cnterr + _cnterrtot;
					IF(_uuiderr IS NULL) THEN
						_uuiderr := _mvtprec.oruuid;
					END IF;
				END IF;
			END IF;
			--< A
			_mvtfirst := _mvt;
			_cnt := 0;
			_cnterr := 0;
		ELSE
			_cnterr := _cnterr + fverifmvt2_int(_mvtprec,_mvt);
			_cnt := _cnt +1;
		END IF;
		_mvtprec := _mvt;
	END LOOP;
	--> finish last agreement
	IF NOT (_mvtprec.grp IS NULL OR _mvtfirst.grp IS NULL) THEN
		_cnterr := _cnterr + fverifmvt2_int(_mvtprec,_mvtfirst);
		_cnt := _cnt +1;
		
		if(_cnt != _mvtprec.nb) THEN
			_cnterr := _cnterr +1;
			RAISE INFO 'wrong number of movements for agreement %',_mvtprec.oruuid;
		END IF;
		-- errors found
		if(_cnterr != 0) THEN
			_cnterrtot := _cnterr + _cnterrtot;
			IF(_uuiderr IS NULL) THEN
				_uuiderr := _mvtprec.oruuid;
			END IF;
		END IF;
	END IF;
	--< A
	IF(_cnterrtot != 0) THEN
		RAISE NOTICE 'mvt.oruuid= % is the first agreement where an error is found',_uuiderr;
		RETURN _cnterrtot;
	ELSE
		RETURN 0;
	END IF;
END;
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
CREATE FUNCTION fverifmvt2_int(_mvtprec tmvt,_mvt tmvt) RETURNS int AS $$
DECLARE
	_o		vorderverif%rowtype;
BEGIN
	SELECT uuid,np,nr,qtt_prov,qtt_requ INTO _o.uuid,_o.np,_o.nr,_o.qtt_prov,_o.qtt_requ FROM vorderverif WHERE uuid = _mvt.oruuid;
	IF (NOT FOUND) THEN
		RAISE INFO 'order not found for vorderverif %',_mvt.oruuid;
		RETURN 1;
	END IF;

	IF(_o.np != _mvt.nat OR _o.nr != _mvtprec.nat) THEN
		RAISE INFO 'mvt.nat != np or mvtprec.nat!=nr';
		RETURN 1;
	END IF;
	
	-- _o.qtt_prov/_o.qtt_requ < _mvt.qtt/_mvtprec.qtt
	IF((_o.qtt_prov * _mvtprec.qtt) < (_mvt.qtt * _o.qtt_requ)) THEN
		RAISE INFO 'order %->%, with  mvt %->%',_o.qtt_requ,_o.qtt_prov,_mvtprec.qtt,_mvt.qtt;
		RAISE INFO 'orderid %, with  mvtid %->%',_o.id,_mvtprec.id,_mvt.id;
		RETURN 1;
	END IF;


	RETURN 0;
END;
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
/* agreement 
for all owners : select * from fgetagr(1);
for a given owner: select * from fgetagr(1) where _own='1';
*/
CREATE FUNCTION fgetagr(_grp int) RETURNS TABLE(_own text,_natp text,_qtt_prov int8,_qtt_requ int8,_natr text) AS $$
DECLARE 
	_fnat	 text;
	_fqtt	 int8;
	_fown	 text;
	_m	 vmvtverif%rowtype;
BEGIN
		_qtt_requ := NULL;
		FOR _m IN SELECT * FROM vmvtverif WHERE grp=_grp ORDER BY id ASC LOOP
			IF(_qtt_requ IS NULL) THEN
				_qtt_requ := _m.qtt;
				SELECT name INTO _natr FROM tquality WHERE _m.nat=id;
				SELECT name INTO _fown FROM towner WHERE _m.own_src=id;
				_fqtt := _m.qtt;
				_fnat := _natr;
			ELSE
				SELECT name INTO _natp FROM tquality WHERE _m.nat=id;
				SELECT name INTO _own FROM towner WHERE _m.own_src=id;
				_qtt_prov := _m.qtt;
				
				RETURN NEXT;
				_qtt_requ := _qtt_prov;
				_natr := _natp;
			END IF;
		END LOOP;
		IF(_qtt_requ IS NOT NULL) THEN
			_own := _fown;
			_natp := _fnat;
			_qtt_prov := _fqtt;
			--_qtt_requ := _qtt_requ;
			--_natr :=  _natr;
			RETURN NEXT;
		END IF;
	RETURN;
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
DROP FUNCTION _grant_read(_table text);
DROP FUNCTION _reference_time(text);
DROP FUNCTION _reference_time_trig(text);
--------------------------------------------------------------------------------
GRANT market_open_role TO client; -- market is opened
\set ECHO all
 RESET client_min_messages;

