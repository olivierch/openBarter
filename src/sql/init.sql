set schema 't';
--------------------------------------------------------------------------------
-- 
--------------------------------------------------------------------------------
-- OK tested
CREATE FUNCTION _create_roles() RETURNS int AS $$
DECLARE
	_rol text;
BEGIN
	BEGIN 
		CREATE ROLE market NOINHERIT; 
	EXCEPTION WHEN duplicate_object THEN
		ALTER ROLE market NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
	END;
	BEGIN 
		CREATE ROLE client;
	EXCEPTION WHEN duplicate_object THEN
		ALTER ROLE client INHERIT;
	END;
	BEGIN 
		CREATE ROLE admin WITH NOINHERIT LOGIN CONNECTION LIMIT 1;
	EXCEPTION WHEN duplicate_object THEN
		ALTER ROLE admin NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION 
			LOGIN CONNECTION LIMIT 1;
	END;
	RETURN 0;
END; 
$$ LANGUAGE PLPGSQL;

SELECT _create_roles();
DROP FUNCTION _create_roles();

--------------------------------------------------------------------------------
-- dummy functions defined by user.sql
create function fspendquota(_time_begin timestamp) RETURNS bool AS $$
BEGIN
	RETURN true;
END;		
$$ LANGUAGE PLPGSQL;

create function fconnect(verifyquota bool) RETURNS int8 AS $$
BEGIN
	RETURN 0; -- returns user.id
END;		
$$ LANGUAGE PLPGSQL;

create function fverify() RETURNS void AS $$
BEGIN
	RETURN; 
END;		
$$ LANGUAGE PLPGSQL;

create function fdeleteorder(id int8) RETURNS void AS $$
BEGIN
	RETURN; 
END;		
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
-- 
--------------------------------------------------------------------------------
create table tconst(
	name text UNIQUE not NULL,
	value	int,
	PRIMARY KEY (name)
);
INSERT INTO tconst (name,value) VALUES 
('obCMAXCYCLE',8),
('MAX_REFUSED',30), -- for an order, maximum number of relation refused 
('VERSION',2),
('INSERT_OWN_UNKNOWN',1); -- 1, insert an owner when it is unknown

CREATE FUNCTION fgetconst(_name text) RETURNS int AS $$
DECLARE
	_ret text;
BEGIN
	SELECT value INTO _ret FROM tconst WHERE name=_name;
	IF(NOT FOUND) THEN
		RAISE 'the const % should be found',_name;
		RAISE EXCEPTION USING ERRCODE='YA003';
	END IF;
	RETURN _ret;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fgetconst(text) TO market;

--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- ob_ftime_updated 
--	trigger before insert on tables
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
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
comment on FUNCTION ftime_updated() is 
'trigger updating fields created and updated';

--------------------------------------------------------------------------------
-- 
--------------------------------------------------------------------------------
CREATE FUNCTION _reference_time_trig(_table text) RETURNS int AS $$
DECLARE
	_trigg text;
BEGIN
	_trigg := 'trig_befa_' || _table;
	EXECUTE 'CREATE TRIGGER ' || _trigg || ' BEFORE INSERT
		OR UPDATE ON ' || _table || ' FOR EACH ROW
		EXECUTE PROCEDURE ftime_updated()' ; 
	EXECUTE 'GRANT SELECT ON TABLE ' || _table || ' TO market';
	-- EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON ' || _table || ' TO MARKET';
	RETURN 0;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
/*
--------------------------------------------------------------------------------
-- 
--------------------------------------------------------------------------------
CREATE FUNCTION _grant_exec(_public bool,_funct text) RETURNS int AS $$

BEGIN
	EXECUTE 'REVOKE ALL ON FUNCTION ' || _funct || ' FROM public' ; 
	IF(_public) THEN
		EXECUTE 'GRANT EXECUTE ON FUNCTION ' || _funct || ' TO market';
	END IF;
	RETURN 0;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
*/

CREATE FUNCTION _reference_time(_table text) RETURNS int AS $$
DECLARE
	_res int;
BEGIN
	
	EXECUTE 'ALTER TABLE ' || _table || ' ADD created timestamp';
	EXECUTE 'ALTER TABLE ' || _table || ' ADD updated timestamp';
	select _reference_time_trig(_table) into _res;
	RETURN 0;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;


--------------------------------------------------------------------------------
create domain dquantity AS bigint check( VALUE>0);
--------------------------------------------------------------------------------
create table tuser ( 
    id bigserial UNIQUE not NULL,
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

comment on table tuser is 'users that have been connected';
SELECT _reference_time('tuser');


--------------------------------------------------------------------------------
-- TQUALITY
--------------------------------------------------------------------------------
-- create sequence tquality_id_seq;
create table tquality (
    id bigserial UNIQUE not NULL,
    name text not NULL,
    idd int8 references tuser(id) on update cascade 
	on delete cascade not NULL,
    depository text not NULL,
    qtt bigint default 0,
    PRIMARY KEY (id),
    UNIQUE(name),
    CHECK(	
    	char_length(name)>0 AND 
    	char_length(depository)>0 AND
    	qtt >=0 
    )
);
comment on table tquality is 'description of qualities';
comment on column tquality.name is 'name of depository/name of quality ';
comment on column tquality.qtt is 'total quantity delegated';
alter sequence tquality_id_seq owned by tquality.id;
create index tquality_name_idx on tquality(name);
SELECT _reference_time('tquality');
-- \copy tquality (depository,name) from data/ISO4217.data with delimiter '-'

--------------------------------------------------------------------------------
-- quality.name == depository/quality
-- the length of depository >=1
--------------------------------------------------------------------------------
CREATE FUNCTION fexplodequality(_quality_name text) RETURNS text[] AS $$
DECLARE
	_e int;
	_q text[];
BEGIN
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
	_idd int8;
	_id int8;
	_qtta int8;
BEGIN
	LOOP
		-- RAISE NOTICE 'fupdate_quality(%,%)',_quality_name,_qtt;
		UPDATE tquality SET id=id,qtt = qtt + _qtt 
			WHERE name = _quality_name RETURNING id,qtt INTO _id,_qtta;

		IF FOUND THEN
			IF (((_qtt >0) AND (_qtta < _qtt)) OR (_qtta<0) ) THEN 
				RAISE WARNING 'Quality "%" owerflows',_quality_name;
				RAISE EXCEPTION USING ERRCODE='YA001';
			END IF;
		
			RETURN _id;
		END IF;
		
		BEGIN
			_q := fexplodequality(_quality_name);
		
			
			SELECT id INTO _idd FROM tuser WHERE name=_q[1];
			IF(NOT FOUND) THEN -- user should exists
				RAISE NOTICE 'The depository "%" is undefined',_q[1] ;
				RAISE EXCEPTION USING ERRCODE='YU001';
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
-- create sequence towner_id_seq;
create table towner (
    id bigserial UNIQUE not NULL,
    name text not NULL,
    PRIMARY KEY (id),
    UNIQUE(name),
    CHECK(	
    	char_length(name)>0 
    )
);
comment on table towner is 
'description of owners of values';
alter sequence towner_id_seq owned by towner.id;
create index towner_name_idx on towner(name);
SELECT _reference_time('towner');
--------------------------------------------------------------------------------
/*
returns the id of an owner.
If the owner does'nt exist, it is created
*/
CREATE FUNCTION fowner(_name text) RETURNS int8 AS $$
DECLARE
	_wid int8;
BEGIN
	LOOP
		SELECT id INTO _wid FROM towner WHERE name=_name;
		IF found THEN
			return _wid;
		ELSE
			IF (fgetconst('INSERT_OWN_UNKNOWN')!=1) THEN
				RAISE NOTICE 'The owner % is unknown',_name;
				RAISE EXCEPTION USING ERRCODE='YU001';
			END IF;
		END IF;
		BEGIN
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
/*
If the owner exists, it is updated, else it is inserted
*/
/*
CREATE FUNCTION faddowner(_name text,_pass text) RETURNS int8 AS $$
DECLARE
	_wid int8;
BEGIN
	LOOP
		UPDATE towner SET pass=_pass WHERE name=_name RETURNING id INTO _wid;
		IF found THEN
			RAISE NOTICE 'owner % updated',_name;
			return _wid;
		END IF;
		BEGIN
			INSERT INTO towner (name,pass) VALUES (_name,_pass) RETURNING id INTO _wid;
			RAISE INFO 'owner % inserted',_name;
			return _wid;
		EXCEPTION WHEN unique_violation THEN
			--
		END;
	END LOOP;
END;
$$ LANGUAGE PLPGSQL; */
--------------------------------------------------------------------------------
/*
CREATE FUNCTION fchecktowner(_name text,_pass text) RETURNS bool AS $$
DECLARE
	_w towner%rowtype;
BEGIN
	SELECT * INTO _w FROM towner where name =_name;
	IF(FOUND AND _w.pass = _pass) THEN
		RETURN TRUE;
	ELSE 
		RETURN FALSE;
	END IF;
END;
$$ LANGUAGE PLPGSQL; */
--------------------------------------------------------------------------------
-- ORDER
--------------------------------------------------------------------------------

create table torder ( 
    id bigserial UNIQUE not NULL,
    qtt int8 NOT NULL,
    nr int8 references tquality(id) on update cascade 
	on delete cascade not NULL ,
    np int8 references tquality(id) on update cascade 
	on delete cascade not NULL ,
    qtt_prov dquantity NOT NULL,
    qtt_requ dquantity NOT NULL, 
    own int8 references towner(id) on update cascade 
	on delete cascade, -- when the order is inserted it is NULL until all mvts and refused are inserted
    refused int8[] NOT NULL DEFAULT array[]::int8[],
    created timestamp not NULL,
    updated timestamp default NULL,
    PRIMARY KEY (id),
    CHECK(	
    	-- char_length(name)>0 AND 
    	qtt >=0 
    )
);

comment on table torder is 'description of orders';
comment on column torder.nr is 'quality required';
comment on column torder.np is 'quality provided';
comment on column torder.qtt is 'current quantity remaining';
comment on column torder.qtt_prov is 'quantity offered';
comment on column torder.qtt_requ is 'used to express omega=qtt_prov/qtt_req';
comment on column torder.own is 'owner of the value provided';

alter sequence torder_id_seq owned by torder.id;
create index torder_nr_idx on torder(nr);
create index torder_np_idx on torder(np);
-- SELECT _reference_time('torder');

--------------------------------------------------------------------------------

CREATE VIEW vorder AS 
	SELECT 	
		n.id as id,
		w.name as owner,
		qr.name as qua_requ,
		n.qtt_requ,
		qp.name as qua_prov,
		n.qtt_prov,
		n.qtt,
		array_upper(n.refused,1) as nbrefused,
		n.created as created,
		n.updated as updated,
		CAST(n.qtt_prov as double precision)/CAST(n.qtt_requ as double precision) as omega
	FROM torder n
	INNER JOIN tquality qr ON n.nr = qr.id 
	INNER JOIN tquality qp ON n.np = qp.id
	INNER JOIN towner w on n.own = w.id;
	
GRANT SELECT ON vorder TO market;

--------------------------------------------------------------------------------
-- TREFUSED
--------------------------------------------------------------------------------
-- create sequence trefused_id_seq;
/*
create table trefused ( -- bid
    x int8 references torder(id) on update cascade 
	on delete cascade not NULL,
    y int8 references torder(id) on update cascade 
	on delete cascade,
    created timestamp,
    PRIMARY KEY (x,y),UNIQUE(x,y)
    -- when y is NULL (x,NULL) should also be unique
);

comment on table trefused is 'list of relations refused';
*/
--------------------------------------------------------------------------------
-- TMVT
--	An owner can be deleted only if he owns no stocks.
--	When it is deleted, it's movements are deleted
--------------------------------------------------------------------------------
-- create sequence tmvt_id_seq;
create table tmvt (
        id bigserial UNIQUE not NULL,
        orid int8 references torder,
        -- references the order
        -- can be NULL
    	grp int8 references tmvt(id), 
    	-- References the first mvt of an exchange.
    	-- can be NULL
	own_src int8 references towner(id) 
		on update cascade on delete cascade not null, 
	own_dst int8  references towner(id) 
		on update cascade on delete cascade not null,
	qtt dquantity not NULL,
	nat int8 references tquality(id) 
		on update cascade on delete cascade not null,
	created timestamp not NULL
);
comment on table tmvt is 'records a change of ownership';
comment on column tmvt.orid is 
	'order creating this movement';
comment on column tmvt.grp is 
	'refers to an exchange cycle that created this movement';
comment on column tmvt.own_src is 
	'old owner';
comment on column tmvt.own_dst is 
	'new owner';
comment on column tmvt.qtt is 
	'quantity of the value';
comment on column tmvt.nat is 
	'quality of the value';

create index tmvt_did_idx on tmvt(grp);
create index tmvt_nat_idx on tmvt(nat);
create index tmvt_own_src_idx on tmvt(own_src);
create index tmvt_own_dst_idx on tmvt(own_dst);



--------------------------------------------------------------------------------
-- vmvt R
--------------------------------------------------------------------------------
-- view PUBLIC
/* 
		returns a list of movements.
			id		tmvt.id
			orid		reference to the order
			grp:		exchange cycle
			provider
			nat:		quality moved
			qtt:		quantity moved, 
			receiver
			created:	timestamp

*/
--------------------------------------------------------------------------------
CREATE VIEW vmvt AS 
	SELECT 	m.id as id,
		m.orid as orid,
		m.grp as grp,
		w_src.name as provider,
		q.name as nat,
		m.qtt as qtt,
		w_dst.name as receiver,
		m.created as created
	FROM tmvt m
	INNER JOIN towner w_src ON (m.own_src = w_src.id)
	INNER JOIN towner w_dst ON (m.own_dst = w_dst.id) 
	INNER JOIN tquality q ON (m.nat = q.id); 
	
GRANT SELECT ON vmvt TO market;	
--------------------------------------------------------------------------------
CREATE VIEW vstat AS 
	SELECT 	q.name as name,
		sum(d.qtt) - q.qtt as delta,
		q.qtt as qtt_quality,
		sum(d.qtt) as qtt_detail
	FROM (
		SELECT np as nat,qtt FROM torder
		UNION ALL
		SELECT nat,qtt FROM tmvt
	) AS d
	INNER JOIN tquality AS q ON (d.nat=q.id)
	GROUP BY q.id ORDER BY q.name; 
	
GRANT SELECT ON vstat TO market;	

/* select count(*) from vstat where delta!=0;
should return 0 */

--------------------------------------------------------------------------------
DROP FUNCTION _reference_time(text);
DROP FUNCTION _reference_time_trig(text);
