drop schema if exists t cascade;
create schema t;
set schema 't';
drop extension if exists flow cascade;
create extension flow;
create table tconst(
	name text UNIQUE not NULL,
	value	int,
	PRIMARY KEY (name)
);
INSERT INTO tconst (name,value) VALUES 
('obCMAXCYCLE',8),
('NB_BACKUP',7), -- number of backups before rotation
('VERSION',2),
-- The following can be changed
('EXHAUST',1), -- if 1, in get_flows verifies the flow exhaust some order
('VERIFY',1), -- if 1, verifies accounting each time it is changed
('INSERT_OWN_UNKNOWN',1), -- 1, insert an owner when it is unknown
('INSERT_DUMMY_MVT',1); --1,insert even movements where the owner gives and reveices at the same time

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
-- error reported to the client only
-- OK tested
create function fuser(_she text,_quota int8) RETURNS void AS $$
BEGIN
	LOOP
		UPDATE tuser SET quota = _quota WHERE name = _she;
		IF FOUND THEN
			RAISE INFO 'user "%" updated',_she;
			RETURN;
		END IF;
			
		BEGIN
			EXECUTE 'CREATE ROLE ' || _she || ' WITH LOGIN CONNECTION LIMIT 1 IN ROLE client';
			INSERT INTO tuser (name,quota,last_in) VALUES (_she,_quota,NULL);
			RAISE INFO 'tuser and role % are created',_she;
			RETURN;
			
		EXCEPTION 
			WHEN duplicate_object THEN
				RAISE NOTICE 'ERROR the role already "%" exists while the tuser does not.',_she;
				RAISE NOTICE 'You should add the tuser.name=% first.',_she;
				RAISE EXCEPTION USING ERRCODE='YU001';
				RETURN; 
			WHEN unique_violation THEN
				RAISE NOTICE 'ERROR the role "%" does nt exists while the tuser exists.',_she;
				RAISE NOTICE 'You should delete the tuser.name=% first.',_she;
				RAISE EXCEPTION USING ERRCODE='YU001';
				RETURN; 
		END;
	END LOOP;
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE NOTICE 'ABORTED';
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fuser(text,int8) TO market;
--------------------------------------------------------------------------------
create function fspendquota(_time_begin timestamp) RETURNS bool AS $$
DECLARE
	_millisec int8;
BEGIN
	_millisec := CAST(EXTRACT(milliseconds FROM (clock_timestamp() - _time_begin)) AS INT8);
	UPDATE tuser SET spent = spent+_millisec WHERE name=current_user;
	IF NOT FOUND THEN
		RAISE NOTICE 'user "%" does not exist',current_user;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	RETURN true;
END;		
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
/*	bool fconnect(_she txt)
returns false if one of these conditions occur:
	she is not recorded, 
	she has a quota and it it consumed,
or true otherwise.
*/
create function fconnect(verifyquota bool) RETURNS int8 AS $$
DECLARE
	_user tuser%rowtype;
BEGIN
	UPDATE tuser SET last_in=clock_timestamp() WHERE name=current_user RETURNING * INTO _user;
	IF NOT FOUND THEN
		RAISE NOTICE 'user "%" does not exist',current_user;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	IF (verifyquota AND NOT(_user.quota = 0 OR _user.spent<=_user.quota)) THEN
		RAISE NOTICE 'quota reached for user "%" ',current_user;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;

	RETURN _user.id;
END;		
$$ LANGUAGE PLPGSQL;
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
    created timestamp not NULL,
    updated timestamp default NULL,
    PRIMARY KEY (id),
    CHECK(	
    	-- char_length(name)>0 AND 
    	qtt >=0 
    )
    -- qtt,qtt_prov,qtt_requ >0
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
-- create index tmvt_src_idx on tmvt(src);
-- create index tmvt_dst_idx on tmvt(dst);
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
CREATE FUNCTION fverify() RETURNS void AS $$
DECLARE
	_name	text;
	_delta	int8;
	_nberrs	int := 0;
BEGIN
	FOR _name,_delta IN SELECT name,delta FROM vstat WHERE delta!=0 LOOP
		RAISE WARNING 'quality % is in error:delta=%',_name,_delta;
		_nberrs := _nberrs +1;
	END LOOP;
	IF(_nberrs != 0) THEN
		RAISE EXCEPTION USING ERRCODE='YA001'; 		
	END IF;
	RETURN;
/* 
TODO
1°) vérifier que le nom d'un client ne contient pas /
2°) lorsqu'un accord est refuse quand l'un des prix est trop fort,
mettre le refus sur la relation dont le prix est le plus élevé relativement au prix fixé

********************************************************************************
CH18 log_min_message,client_min_message defines which level are reported to client/log
by default 
log_min_message=
client_min_message=

BEGIN
	bloc
	RAISE EXCEPTION USING ERRCODE='YA001';
EXCEPTION WHEN SQLSTATE 'YA001' THEN
	RAISE NOTICE 'voila le PB';
END;
rollback the bloc and notice the problem to the client only
*/

END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
CREATE FUNCTION fdroporder(_oid int8) RETURNS torder AS $$
DECLARE
	_o torder%rowtype;
	_qp tquality%rowtype;
BEGIN
	DELETE FROM torder o USING tquality q 
	WHERE o.id=_oid AND o.np=q.id AND q.depository=current_user 
	RETURNING o.* INTO _o;
	IF(FOUND) THEN
		-- delete by cascade trefused
		
		UPDATE tquality SET qtt = qtt - _o.qtt 
			WHERE id = _o.np RETURNING * INTO _qp;
		IF(NOT FOUND) THEN
			RAISE WARNING 'The quality of the order % is not present',_oid;
			RAISE EXCEPTION USING ERRCODE='YA003';
		END IF;
		IF (_qp.qtt<0 ) THEN 
			RAISE WARNING 'Quality % underflows',_quality_name;
			RAISE EXCEPTION USING ERRCODE='YA001';
		END IF;
		
		IF(fgetconst('VERIFY') = 1) THEN
			perform fverify();
		END IF;
		RAISE INFO 'order % dropped',_oid;
		RETURN _o;
	ELSE
		RAISE NOTICE 'this order % is not yours or does not exist',_oid;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE NOTICE 'ABORTED';
	RETURN NULL;
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fdroporder(int8) TO market;	
--------------------------------------------------------------------------------
-- finsert_order
--------------------------------------------------------------------------------
-- PUBLIC
/* usage: 
	nb_draft int = finsertorder(_owner text,_qualityprovided text,qttprovided int8,_qttrequired int8,_qualityrequired text)
		
	action:
		inserts the order.
		if _owner,_qualityprovided or _qualityrequired do not exist, they are created
	
	returns nb_draft:
		the number of draft inserted.
		or error returned by ob_finsert_order_int

*/
--------------------------------------------------------------------------------
CREATE FUNCTION 
	finsertorder(_owner text,_qualityprovided text,_qttprovided int8,_qttrequired int8,_qualityrequired text) 
	RETURNS int AS $$
	
DECLARE
	_cnt int;
	_user text;
	_np	int8;
	_nr	int8;
	_wid	int8;
	_pivot torder%rowtype;
	_q	text[];
	_time_begin timestamp;
	_uid	int8;
BEGIN
	_uid := fconnect(true);
	_time_begin := clock_timestamp();
	
	-- order is rejected if the depository is not the user
	_q := fexplodequality(_qualityprovided);
	IF (_q[1] != current_user) THEN
		RAISE NOTICE 'depository % of quality is not the user %',_q[1],current_user;
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
	
	_pivot.own := _wid;
	_pivot.id  := 0;
	_pivot.qtt := _qttprovided;
	_pivot.np  := _np;
	_pivot.nr  := _nr;
	_pivot.qtt_prov := _qttprovided;
	_pivot.qtt_requ := _qttrequired;
	
	_cnt := finsert_order_int(_pivot,false);
	
	perform fspendquota(_time_begin);
		
	IF(fgetconst('VERIFY') = 1) THEN
		perform fverify();
	END IF;
	
	RETURN _cnt;
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE NOTICE 'ABORTED';
	RETURN 0;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION finsertorder(text,text,int8,int8,text) TO market;
--------------------------------------------------------------------------------
-- fexecute_flow
--------------------------------------------------------------------------------
/*
CREATE FUNCTION fexecute_flow(_flw flow) RETURNS void AS $$
DECLARE
	_commits	int8[][];
	_i		int;
	_next_i		int;
	_nbcommit	int;
	_oid		int8;
	_w_src		int8;
	_w_dst		int8;
	_flowr		int8;
	_first_mvt	int8;
	_insert_dummy_mvt	int;
	_exhausted	bool := false;
	
BEGIN
	_commits := flow_to_matrix(_flw);
	
	-- RAISE NOTICE '_commits=%',_commits;
	_nbcommit := flow_dim(_flw); -- array_upper(_commits,1); 
	IF(_nbcommit < 2) THEN
		RAISE WARNING 'nbcommit % < 2',_nbcommit;
		RAISE EXCEPTION USING ERRCODE='YA003';
	END IF;
		
	_i := _nbcommit;
	_first_mvt := NULL;
	_insert_dummy_mvt := fgetconst('INSERT_DUMMY_MVT');
	
	FOR _next_i IN 1 .. _nbcommit LOOP
		_oid	:= _commits[_i][1];
		-- _commits[_next_i] follows _commits[_i]
		_w_src	:= _commits[_i][5];
		_w_dst	:= _commits[_next_i][5];
		_flowr	:= _commits[_i][6];
		
		IF NOT ((_insert_dummy_mvt = 0) AND (_w_src = _w_dst)) THEN
		
			UPDATE torder set qtt = qtt - _flowr ,updated = statement_timestamp()
				WHERE id = _oid AND _flowr <= qtt ;
			IF(NOT FOUND) THEN
				RAISE NOTICE 'the flow is not in sync with the database';
				RAISE INFO 'torder[%].qtt does not exist or < %',_oid,_flowr;
				RAISE EXCEPTION USING ERRCODE='YU001';
			END IF;				
*/
--------------------------------------------------------------------------------
-- finsert_order_int
--------------------------------------------------------------------------------
/* PRIVATE used by finsertorder

Find possible drafts, 
for each draft found:
If a draft is refused, the relation x->pivot is inserted into trefused,
else mvts are recorded, pivot recorded with pivot.qtt decreased 

 usage: 
	nb_draft int = finsert_order_int(_pivot torder)

*/
--------------------------------------------------------------------------------


CREATE FUNCTION 
	finsert_order_int(_pivot torder, _restoretime bool) 
	RETURNS int AS $$
DECLARE
	_commits	int8[][];
	_i	int;
	_next_i	int;
	_nbcommit	int;
	_first_mvt	int8; 
	_mvt_id	int8;
	_cnt	int := 0;
	_worst	int;
	_oid	int8;
	_oid1	int8;
	_oid2	int8;
	_flowr	int8;
	_flw	flow;
	_w_src	int8;
	_w_dst	int8;
	_created	timestamp;
	_updated	timestamp;

BEGIN
	------------------------------------------------------------------------
	
	IF(_restoretime) THEN
		_created := _pivot.created;
		_updated := _pivot.updated;
		UPDATE tquality SET qtt = qtt + _pivot.qtt WHERE id = _pivot.np;
	ELSE
		_created := statement_timestamp();
		_updated := NULL;
		_pivot.qtt := _pivot.qtt_prov;
	END IF;

	-- take a _pivot.id
	-- this record is ignored by fget_drafts due to the condition (own IS NOT NULL)	
	INSERT INTO torder (qtt,nr,np,qtt_prov,qtt_requ,own,created,updated) 
		VALUES (_pivot.qtt,_pivot.nr,_pivot.np,_pivot.qtt_prov,_pivot.qtt_requ,NULL,_created,_updated)
		RETURNING id INTO _pivot.id;
	
	-- graph traversal
	FOR _flw IN SELECT * FROM fget_drafts(_pivot) LOOP
		_commits := flow_to_matrix(_flw);
		
		-- RAISE NOTICE '_commits=%',_commits;
		_nbcommit := flow_dim(_flw); -- array_upper(_commits,1); 
		IF(_nbcommit < 2) THEN
			RAISE WARNING 'nbcommit % < 2',_nbcommit;
			RAISE EXCEPTION USING ERRCODE='YA003';
		END IF;
		
		_commits[_nbcommit][1] = _pivot.id;
		RAISE NOTICE '_commits=%',_commits;
		_worst := flow_refused(_flw);
		IF( _worst >= 0 ) THEN
			
			-- occurs when some omega > qtt_p/qtt_r 
			-- or when no solution was found
			
			-- _worst in [0,_nbcommit[
			_oid1 := _commits[((_worst-1+_nbcommit)%_nbcommit)+1][1];	
			-- -1%_nbcommit gives -1, but (-1+_nbcommit)%_nbcommit gives _nbcommit-1 		
			_oid2 := _commits[_worst+1][1];
			RAISE NOTICE 'flow_refused: _worst=%, _oid1=%, _oid2=%, _commits=%, _flw=%',_worst,_oid1,_oid2,_commits,CAST(_flw AS TEXT);
			BEGIN
				IF(_restoretime) THEN
					INSERT INTO trefused (x,y,created) VALUES (_oid1,_oid2,_pivot.created); -- _pivot.id,_created);
				ELSE 
					INSERT INTO trefused (x,y,created) VALUES (_oid1,_oid2,statement_timestamp());
				END IF;
			EXCEPTION WHEN unique_violation THEN
				-- do noting
			END;
			-- INSERT INTO trefused (x,y,created) VALUES (_oid1,_oid2,_created); -- _pivot.id,_created);
		ELSE	-- the draft is accepted	
			_i := _nbcommit;
			_first_mvt := NULL;
			FOR _next_i IN 1 .. _nbcommit LOOP
				-- _commits[_next_i] follows _commits[_i]
				_oid	   := _commits[_i][1];
				
				_w_src :=_commits[_i][5];
				_w_dst :=_commits[_next_i][5];
				_flowr := _commits[_i][6];
				
				IF NOT ((fgetconst('INSERT_DUMMY_MVT') = 0) AND (_w_src = _w_dst)) THEN
/*				
				IF(_restoretime) THEN
					UPDATE torder set qtt = qtt - _flowr ,updated =_pivot.created
						WHERE id = _oid AND _flowr <= qtt ;
				ELSE 
					UPDATE torder set qtt = qtt - _flowr ,updated =statement_timestamp()
						WHERE id = _oid AND _flowr <= qtt ;
				END IF; */
					IF(_restoretime) THEN
						UPDATE torder set qtt = qtt - _flowr ,updated =_pivot.created
							WHERE id = _oid AND _flowr <= qtt ;
						IF(NOT FOUND) THEN
							RAISE NOTICE 'the flow is not in sync with the database';
							RAISE INFO 'torder[%].qtt does not exist or < %',_orid,_flowr;
							RAISE EXCEPTION USING ERRCODE='YU001';
						END IF;				

						INSERT INTO tmvt (orid,grp,own_src,own_dst,qtt,nat,created) 
							VALUES(_oid,_first_mvt,_w_src,_w_dst,_flowr,_commits[_i][7],_pivot.created)
							RETURNING id INTO _mvt_id;
							
					ELSE --same thing with statement_timestamp() instead of _pivot.created
						UPDATE torder set qtt = qtt - _flowr ,updated = statement_timestamp()
							WHERE id = _oid AND _flowr <= qtt ;
						IF(NOT FOUND) THEN
							RAISE NOTICE 'the flow is not in sync with the database';
							RAISE INFO 'torder[%].qtt does not exist or < %',_oid,_flowr;
							RAISE EXCEPTION USING ERRCODE='YU001';
						END IF;				

						INSERT INTO tmvt (orid,grp,own_src,own_dst,qtt,nat,created) 
							VALUES(_oid,_first_mvt,_w_src,_w_dst,_flowr,_commits[_i][7],statement_timestamp())
							RETURNING id INTO _mvt_id;
							
					END IF;	
					IF(_first_mvt IS NULL) THEN
						_first_mvt := _mvt_id;
					END IF;
				END IF;
				
				---------------------------------------------------------
				_i := _next_i;
			END LOOP;
		
			UPDATE tmvt SET grp = _first_mvt WHERE id = _first_mvt;	
	 		_cnt := _cnt +1;
 		END IF;
 	END LOOP;
 	
 	UPDATE torder SET own = _pivot.own WHERE id=_pivot.id;
 	RETURN _cnt;
END; 
$$ LANGUAGE PLPGSQL; 

--------------------------------------------------------------------------------
/* the table of movements tmvt can only be selected by the role CLIS
a given record can be deleted by CLIS only if nat is owned by this user 
*/
--------------------------------------------------------------------------------
create function fackmvt(_mid int8) RETURNS bool AS $$
DECLARE
	_mvt 	tmvt%rowtype;
	_q	tquality%rowtype;
	_uid	int8;
	_cnt 	int;
BEGIN
	_uid := fconnect(false);
	DELETE FROM tmvt USING tquality 
		WHERE tmvt.id=_mid AND tmvt.nat=tquality.id AND tquality.did=_uid 
		RETURNING * INTO _mvt;
		
	IF(FOUND) THEN
		UPDATE tquality SET qtt = qtt - _mvt.qtt WHERE id=_mvt.nat
			RETURNING * INTO _q;
		IF(NOT FOUND) THEN
			RAISE WARNING 'quality[%] of the movement not found',_mvt.nat;
			RAISE EXCEPTION USING ERRCODE='YA003';
		ELSE
			IF (_q.qtt<0 ) THEN 
				RAISE WARNING 'Quality % underflows',_quality_name;
				RAISE EXCEPTION USING ERRCODE='YA001';
			END IF;
		END IF;
		-- TODO supprimer les ordres associés s'ils sont vides et qu'ils ne sont pas associés à d'autres mvts
		SELECT count(*) INTO _cnt FROM tmvt WHERE orid=_mvt.orid;
		IF(_cnt=0) THEN
			DELETE FROM torder o USING tmvt m 
				WHERE o.id=_mvt.orid;
		END IF;
		
		IF(fgetconst('VERIFY') = 1) THEN
			perform fverify();
		END IF;
		
		RAISE INFO 'movement removed';
		RETURN true;
	ELSE
		RAISE NOTICE 'the quality of the movement is not yours';
		RAISE EXCEPTION USING ERRCODE='YU001';
		RETURN false;
	END IF;
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE NOTICE 'ABORTED';
	RETURN 0;
END;		
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fackmvt(int8) TO market;

/*******************************************/
 -- GRAPH FUNCTIONS
/*******************************************/
-- id,nr,qtt_prov,qtt_requ,own,qtt,np

/*--------------------------------------------------------------------------------
read omega, returns setof __flow_to_commits
	__flow_to_commit (num int8,qtt_r int8,nr int8,qtt_p int8,np int8)
-------------------------------------------------------------------------------*/
CREATE FUNCTION fget_omegas(_qr text,_qp text) RETURNS TABLE(_num int8,_qtt_r int8,_qua_r text,_qtt_p int8,_qua_p text) AS $$
DECLARE 
	_sidPivot int8 := 0;
	_maxDepth int;
	_flow	flow;
	_commit	__flow_to_commits;
	_time_begin timestamp;
	_np	int8;
	_nr	int8;
BEGIN
	_time_begin := clock_timestamp();
	SELECT id INTO _nr FROM tquality WHERE name=_qr;
	IF(NOT FOUND) THEN RAISE NOTICE 'Quality % unknown',_qr; RAISE EXCEPTION USING ERRCODE='YU001';END IF;
	SELECT id INTO _np FROM tquality WHERE name=_qp;
	IF(NOT FOUND) THEN RAISE NOTICE 'Quality % unknown',_qp; RAISE EXCEPTION USING ERRCODE='YU001';END IF;
	
	_maxDepth := fcreate_tmp(_nr);
	
	IF (_maxDepth is NULL or _maxDepth = 0) THEN
		RAISE INFO 'No results';
		RETURN;
	END IF;
	-- insert the pivot
	INSERT INTO _tmp (id, nr,qtt_prov,qtt_requ,own,qtt,np, flow,     valid,depth) VALUES
			 (0 ,_nr,1,       1,       0,  1,  _np,NULL::flow,0,1);
	_num := 0;
	FOR _flow IN SELECT fget_flows FROM fget_flows(_np,_maxDepth) LOOP
		FOR _qtt_r,_qua_r,_qtt_r,_qua_r IN SELECT c.qtt_r,qr.name,c.qtt_p,qp.name 
			FROM flow_to_commits(_flow) c
			INNER JOIN tquality qp ON (c.np=qp.id)
			INNER JOIN tquality qr ON (c.nr=qr.id) LOOP
			_num := _num+1;
			--_commit.num := _num;
			RETURN NEXT; -- _commit;
		END LOOP;	
	END LOOP;
	-- id == 0 is the pivot
	-- own==0 indicates that the flow should ignore the quantity of the pivot
	
	perform fspendquota(_time_begin);
	RETURN;
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE NOTICE 'ABORTED';
	RETURN;	 
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fget_omegas(text,text)  TO market;

--------------------------------------------------------------------------------
-- used by finsert_order_int(_pivot torder)
--------------------------------------------------------------------------------
CREATE FUNCTION fget_drafts(_pivot torder) RETURNS SETOF flow AS $$
DECLARE 
	_maxDepth int;
BEGIN
	_maxDepth := fcreate_tmp(_pivot.nr);
	
	IF (_maxDepth is NULL or _maxDepth = 0) THEN
		RETURN;
	END IF;
	-- insert the pivot
	INSERT INTO _tmp (id, nr, qtt_prov, qtt_requ,own, qtt, np, flow,valid,depth) VALUES
			 (0 ,
			 _pivot.nr,
			 _pivot.qtt_prov,
			 _pivot.qtt_requ,
			 _pivot.own,
			 _pivot.qtt,
			 _pivot.np,
			 NULL::flow,    0,    1);
	-- own!=0 indicates that the flow should consider the quantity of the pivot
	
	RETURN QUERY SELECT fget_flows FROM fget_flows(_pivot.np,_maxDepth);
/*	FOR _flow IN SELECT fget_flows FROM fget_flows(_pivot.np,_maxDepth) LOOP
		RETURN NEXT;
	END LOOP;*/
	RETURN;
END; 
$$ LANGUAGE PLPGSQL;

/*--------------------------------------------------------------------------------
 creates the table _tmp deleted on commit
 torder.own is NULL identifies record temporarilly inserted when orders are being 
 inserted.
-------------------------------------------------------------------------------*/
CREATE FUNCTION fcreate_tmp(_nr int8) RETURNS int AS $$
DECLARE 
	_obCMAXCYCLE int := fgetconst('obCMAXCYCLE');
	_maxDepth int;
BEGIN
	-- select relname,oid from pg_class where pg_table_is_visible(oid) and relname='_tmp';
	DROP TABLE IF EXISTS _tmp;
	CREATE TEMP TABLE _tmp ON COMMIT DROP AS (
		WITH RECURSIVE search_backward(id,nr,qtt_prov,qtt_requ,
						own,qtt,np,
						depth) AS (
			SELECT b.id, b.nr,b.qtt_prov,b.qtt_requ,
				b.own,b.qtt,b.np,
				2
				FROM torder b
				WHERE 	b.np = _nr -- v->pivot
					AND b.qtt > 0 
					AND (b.own IS NOT NULL) -- excludes the pivot
			UNION 
			SELECT Xb.id, Xb.nr,Xb.qtt_prov,Xb.qtt_requ,
				Xb.own,Xb.qtt,Xb.np,
				Y.depth + 1
				FROM torder Xb, search_backward Y
				WHERE 	Xb.np = Y.nr -- X->Y
					AND Xb.qtt > 0 
					AND (Xb.own IS NOT NULL) -- excludes the pivot
					AND Y.depth < _obCMAXCYCLE
					AND NOT EXISTS (
						SELECT * FROM trefused WHERE Xb.id=x and Y.id=y)
		)
		SELECT id,nr,qtt_prov,qtt_requ,own,qtt,np,NULL::flow as flow,0 as valid,depth 
		FROM search_backward
	);
	SELECT max(depth) INTO _maxDepth FROM _tmp;
	RETURN _maxDepth;
END;
$$ LANGUAGE PLPGSQL;


/*--------------------------------------------------------------------------------
 returns a set of flows found in the graph contained in the table _tmp

-------------------------------------------------------------------------------*/
CREATE FUNCTION fget_flows(_np int8,_maxDepth int) RETURNS SETOF flow AS $$
DECLARE 
	_cnt 	int;
	_cntgraph int :=0; 
	_flow 	flow;
	_idPivot int8 := 0;
	
	_id	int8;
	_dim	int;
	_flowrs	int8[];
	_ids	int8[];
	_owns	int8[];
	_qtt	int8;
	_lastIgnore bool := false;
BEGIN
	-- CREATE INDEX _tmp_idx ON _tmp(valid,nr);
	LOOP -- repeate as long as some draft is found
		_cntgraph := _cntgraph+1;
/*		******************************************************************************
		the graph is traversed forward to be reduced
		*******************************************************************************/
		-- RAISE NOTICE '_maxDepth=% _np=% _idPivot=% _cntgraph=%',_maxDepth,_np,_idpivot,_cntgraph;
		WITH RECURSIVE search_forward(id,nr,np,qtt,depth) AS (
			SELECT src.id,src.nr,src.np,src.qtt,1
				FROM _tmp src
				WHERE src.id = _idPivot AND src.valid = _cntgraph-1 -- sources
					AND src.qtt != 0 
					
			UNION
			SELECT Y.id,Y.nr,Y.np,Y.qtt,X.depth + 1
				FROM search_forward X, _tmp Y
				WHERE X.np = Y.nr AND Y.valid = _cntgraph-1 -- X->Y, use of index
					AND Y.qtt != 0 
					AND Y.id != _idPivot  -- includes pivot
					AND X.depth < _maxDepth
		) 
	
		UPDATE _tmp t 
		SET flow = CASE WHEN _np = t.nr -- source
				THEN flow_init(t.id,t.nr,t.qtt_prov,t.qtt_requ,t.own,t.qtt,t.np) 
				ELSE NULL::flow END,
			valid = _cntgraph
		FROM search_forward sf WHERE t.id = sf.id;
		
		-- nodes that cannot be reached are deleted
		DELETE FROM _tmp WHERE valid != _cntgraph;
		
/*******************************************************************************
bellman_ford

At the beginning, all sources S are such as S.flow=[S,]
for t in [1,_maxDepth]:
	for all arcs[X,Y] of the graph: UPDATE
		if X.flow empty continue
		fl = X.flow followed by Y.order
		if fl is better than X.flow, then Y.flow <- fl
		
		
When it is not empty, a node T contains a path [S,..,T] where S is a source 
At the end of UPDATE, Each node.flow not empty is the best flow from a source S to this node
with at most t arcs. 
The pivot contains the best flow from a source to pivot [S,..,pivot] that is at most _maxDepth long

the algorithm is normally repeated for all node, but here only
_maxDepth times. 

*******************************************************************************/	
/*TODO il reste à prendre en compte _lastIgnore représenté pas sid==0*/

/*
RULE: 
when pivot is reached, the path is a loop (refused or draft) and omegas are adjusted such as their product becomes 1.

********************************
update only if X.np=Y.nr AND X.flow IS NOT NULL

Z = X.flow+Y.order, it can be noloop,undefined,refused or draft
if Y.flow is NULL 	
	Y.flow <- Z;end
	
if Y.flow is noloop (Z should be noloop)
	if omega(Z.flow) > omega(Y.flow)
		Y.flow <- Z;end	
if Z.flow is draft
	if Y.flow is draft 
		if omega(Z.flow) > omega(Y.flow)
			Y.flow <- Z;end
	else 
		Y.flow <- Z;end
*******************************	

since the UPDATE condition is 
				X.np  = Y.nr  
				AND X.id != _idPivot -- arcs pivot->sources are not considered
				AND  X.flow IS NOT NULL 
				AND ( 	Y.flow IS NULL 
					OR flow_omegaz(....)
				);
and flow_catt is:
	try
		Z <- X.flow+Y.order
		Y.flow <- Z 
	except Z in error:
		Y.flow <- empty path
		
flow_omegaz should be the rest.
*/

		FOR _cnt IN 2 .. _maxDepth LOOP
			UPDATE _tmp Y 
			SET flow = flow_catt(X.flow,Y.flow,Y.id,Y.nr,Y.qtt_prov,Y.qtt_requ,Y.own,Y.qtt,Y.np) 
			-- Y.flow <- X.flow+Y.order	
			FROM _tmp X WHERE 
				X.np  = Y.nr  
				AND X.id != _idPivot -- arcs pivot->sources are not considered
				AND  X.flow IS NOT NULL 
				AND ( 	Y.flow IS NULL 
					OR flow_omegaz(X.flow,Y.flow,Y.id,Y.nr,Y.qtt_prov,Y.qtt_requ,Y.own,Y.qtt,Y.np)
				);

		END LOOP;

		-- flow of pivot
		SELECT flow INTO _flow FROM _tmp WHERE id = _idPivot; 
		
		EXIT WHEN _flow IS NULL OR flow_dim(_flow) = 0;
		
		RETURN NEXT _flow; -- new row returned
		
		-- values used by this flow are substracted from _tmp

		_flowrs := flow_proj(_flow,8);
		_ids	:= flow_proj(_flow,1);
		_owns	:= flow_proj(_flow,5); 
		_dim    := flow_dim(_flow); 
		
		FOR _cnt IN 1 .. _dim LOOP
			_id   := _ids[_cnt]; 
			-- RAISE NOTICE 'flowrs[%]=% ',_cnt,_flowr;
			IF (_id = 0 AND _owns[_cnt] = 0) THEN
				_lastIgnore := true; -- it's a price read, the pivot is not decreased
			ELSE 
				UPDATE _tmp SET qtt = qtt - _flowrs[_cnt] WHERE id = _id and qtt >= _flowrs[_cnt];
				IF (NOT FOUND) THEN
					RAISE WARNING 'order[%] was not found or found with negative value',_id;
					RAISE EXCEPTION USING ERRCODE='YA003'; 
				END IF;
			END IF;
		END LOOP;
		
		IF(fgetconst('EXHAUST') = 1) THEN
			SELECT count(*) INTO _cnt FROM _tmp WHERE 
				id = ANY (_ids) 
				AND qtt=0 
				AND (NOT _lastIgnore OR (_lastIgnore AND id!=0));
			IF(_cnt <1) THEN
				-- when _lastIgnore, some order other than the pivot should be exhausted
				-- otherwise, some order including the pivot should be exhausted 
				RAISE WARNING 'the cycle should exhaust some order';
				RAISE EXCEPTION USING ERRCODE='YA003';
			END IF;
		END IF;
		
	END LOOP;

END; 
$$ LANGUAGE PLPGSQL;

CREATE TABLE tmarket  (
 	id 	serial UNIQUE,
	ph0  	timestamp not NULL,
	ph1  	timestamp,
	ph2  	timestamp,
	backup	int,
	diag	int	
);-- CHECK(ph2>ph1 and ph1>ph0 ) NULL values
INSERT INTO tmarket (ph0,ph1,ph2,backup,diag) VALUES (statement_timestamp(),statement_timestamp(),statement_timestamp(),NULL,NULL);

CREATE VIEW vmarket AS SELECT
 	CASE WHEN ph1 IS NULL THEN 'OPENED' ELSE 
 		CASE WHEN ph2 IS NULL THEN 'CLOSING' ELSE 'CLOSED' END
	END AS state,
	ph0,ph1,ph2,backup,
	CASE WHEN diag=0 THEN 'OK' ELSE diag || ' ERRORS' END as diagnostic
	FROM tmarket ORDER BY ID DESC LIMIT 1; -- fgetconst('NB_BACKUP')	
GRANT SELECT ON vorder TO market;

--------------------------------------------------------------------------------
/* phase of market
0	closed
1	opened
2	ended
*/
CREATE FUNCTION fadmin() RETURNS bool AS $$
DECLARE
	_b	bool;
	_phase	int;
	_market tmarket%rowtype;
BEGIN
	SELECT * INTO _market FROM tmarket ORDER BY ID DESC LIMIT 1;
	IF(_market.ph1 is NULL) THEN
		_phase := 1;
	ELSE 
		IF(_market.ph2 is NULL) THEN
			_phase := 2;
		ELSE
			_phase := 0;
		END IF;
	END IF;

	IF (_phase = 0) THEN -- was closed, opening
		GRANT market TO client;
		INSERT INTO tmarket (ph0) VALUES (statement_timestamp());
		RAISE NOTICE '[1] The market is now OPENED';
		RETURN true;
	END IF;
	IF (_phase = 1) THEN -- was opened, ending
		REVOKE market FROM client;
		UPDATE tmarket SET ph1=statement_timestamp() WHERE ph1 IS NULL;		
		RAISE NOTICE '[2] The market is now CLOSING';
		RETURN true;
	END IF;
	IF (_phase = 2) THEN -- was ended, closing
		-- REVOKE market FROM client;
		UPDATE tmarket SET ph2=statement_timestamp() WHERE ph2 IS NULL;
		RAISE NOTICE 'The closing starts ...';
		_b := fclose_market();
		RAISE NOTICE '[0] The market is now CLOSED';
		RETURN _b;
	END IF;
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fadmin()  TO admin;

CREATE FUNCTION fclose_market() RETURNS bool AS $$
DECLARE
	_backup int;
	_suf text;
	_sql text;
	_cnt int;
	_nbb 	int;
	_pivot torder%rowtype;
	_cnn	int8;
BEGIN
	
	_nbb := fgetconst('NB_BACKUP');
	-- rotation of backups
	SELECT max(id) INTO _cnt FROM tmarket;
	UPDATE tmarket SET backup= ((_cnt-2) % _nbb) +1 WHERE id=_cnt RETURNING backup INTO _backup;
	_suf := CAST(_backup AS text);
	
	EXECUTE 'DROP TABLE IF EXISTS torder_back_' || _suf;
	EXECUTE 'DROP TABLE IF EXISTS tmvt_back_' || _suf;
	EXECUTE 'CREATE TABLE torder_back_' || _suf || ' AS SELECT * FROM torder';
	EXECUTE 'CREATE TABLE tmvt_back_' || _suf || ' AS SELECT * FROM tmvt';
	
	RAISE NOTICE 'TMVT and TORDER saved into backups *_BACK_% among %',_backup,_nbb;
	
	TRUNCATE tmvt,trefused,torder;
	UPDATE tquality set qtt=0 ;
	
	-- reinsertion of orders
/*
	_sql := 'FOR _pivot IN SELECT * FROM torder_back_' || _suf || ' WHERE qtt != 0 ORDER BY created ASC LOOP 
			_cnt := finsert_order_int(_pivot,true);
		END LOOP';
	EXECUTE _sql;
*/
	-- RETURN false;
 
	EXECUTE 'SELECT finsert_order_int(row(id,qtt,nr,np,qtt_prov,qtt_requ,own,created,updated)::torder ,true) 
	FROM torder_back_' || _suf || ' 
	 WHERE qtt != 0 ORDER BY created ASC';
	
	-- diagnostic
	perform fverify();	
	SELECT count(*) INTO _cnn FROM tmvt;
	UPDATE tmarket SET diag=_cnn WHERE id=_cnt;
	IF(_cnn != 0) THEN
		RAISE NOTICE 'Abnormal termination of market closing';
		RAISE NOTICE '0 != % movement where found when orders where re-inserted',_cnn;
		
		RETURN false;
	ELSE
		RAISE NOTICE 'Normal termination of closing.';
		RETURN true;
	END IF;
	
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
--------------------------------------------------------------------------------
DROP FUNCTION _reference_time(text);
DROP FUNCTION _reference_time_trig(text);
