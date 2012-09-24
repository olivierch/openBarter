\set ECHO none
/*
drop schema if exists t cascade;
create schema t;
set schema 't';
*/
SET client_min_messages = warning;
SET log_error_verbosity = terse;

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
	('VERSION-X.y.z',0),
	('VERSION-x.Y.y',4),
	('VERSION-x.y.Z',1),
	('INSERT_OWN_UNKNOWN',1), 
	-- !=0, insert an owner when it is unknown
	-- ==0, raise an error when the owner is unknown
	('CHECK_QUALITY_OWNERSHIP',0), 
	-- !=0, quality = user_name/quality_name prefix must match session_user
	-- ==0, the name of quality can be any string
	('MAXORDERFETCH',10000);
	-- maximum number of paths of the set on which the competition occurs
--------------------------------------------------------------------------------
-- fetch a constant, and verify consistancy
CREATE FUNCTION fgetconst(_name text) RETURNS int AS $$
DECLARE
	_ret int;
BEGIN
	SELECT value INTO _ret FROM tconst WHERE name=_name;
	IF(NOT FOUND) THEN
		RAISE 'the const % should be found',_name;
		RAISE EXCEPTION USING ERRCODE='YA002';
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
		CREATE ROLE client_opened_role; 
	EXCEPTION WHEN duplicate_object THEN
		NULL;	
	END;
	ALTER ROLE client_opened_role NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
	
	BEGIN 
		CREATE ROLE client_stopping_role; 
	EXCEPTION WHEN duplicate_object THEN
		NULL;	
	END;
	ALTER ROLE client_stopping_role NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
	
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
CREATE FUNCTION _reference_time(_table text) RETURNS int AS $$
DECLARE
	_res int;
BEGIN
	
	EXECUTE 'ALTER TABLE ' || _table || ' ADD created timestamp';
	EXECUTE 'ALTER TABLE ' || _table || ' ADD updated timestamp';
	EXECUTE 'CREATE TRIGGER trig_befa_' || _table || ' BEFORE INSERT
		OR UPDATE ON ' || _table || ' FOR EACH ROW
		EXECUTE PROCEDURE ftime_updated()' ; 
	RETURN 0;
END; 
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
CREATE FUNCTION _grant_read(_table text) RETURNS void AS $$

BEGIN 
	EXECUTE 'GRANT SELECT ON TABLE ' || _table || ' TO client_opened_role,client_stopping_role,admin';
	RETURN;
END; 
$$ LANGUAGE PLPGSQL;
SELECT _grant_read('tconst');
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
    idd int , -- can be NULL
    depository text,
    qtt bigint default 0,
    PRIMARY KEY (id),
    UNIQUE(name),
    CHECK(	
    	char_length(name)>0 AND 
    	char_length(depository)>0 AND
    	qtt >=0 
    ),
    CONSTRAINT ctquality_idd FOREIGN KEY (idd) references tuser(id),
    CONSTRAINT ctquality_depository FOREIGN KEY (depository) references tuser(name)
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
--	quality_name = quality
-- ELSE
--	quality_name == depository/quality
-- 
-- the length of names >=1
--------------------------------------------------------------------------------
CREATE FUNCTION fexplodequality(_quality_name text) RETURNS text[] AS $$
DECLARE
	_e int;
	_q text[];
	_CHECK_QUALITY_OWNERSHIP int := fgetconst('CHECK_QUALITY_OWNERSHIP');
BEGIN
	IF(char_length(_quality_name) <1) THEN
		RAISE NOTICE 'Quality name "%" incorrect: do not len(name)<1',_quality_name;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	IF(_CHECK_QUALITY_OWNERSHIP = 0) THEN
		_q[1] := NULL;
		_q[2] := _quality_name;
		RETURN _q;
	END IF;
	
	_e =position('/' in _quality_name);
	IF(_e < 2) THEN 
		RAISE NOTICE 'Quality name "%" incorrect: <depository>/<quality> expected',_quality_name;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	_q[1] = substring(_quality_name for _e-1);
	_q[2] = substring(_quality_name from _e+1);
	if(char_length(_q[2])<1) THEN
		RAISE NOTICE 'Quality name "%" incorrect: <depository>/<quality> expected',_quality_name;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	RETURN _q;
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
CREATE FUNCTION 
	fgetquality(_quality_name text, insert bool) RETURNS int AS $$
DECLARE 
	_idd int;
	_qlt	tquality%rowtype;
	_q text[];
	_id int;
BEGIN
	LOOP
		SELECT * INTO _qlt FROM tquality WHERE name = _quality_name;
		IF FOUND THEN
			return _qlt.id;
		END IF;
		IF(NOT insert) THEN
			return 0;
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
		
			INSERT INTO tquality (name,idd,depository,qtt) VALUES (_quality_name,_idd,_q[1],0)
				RETURNING * INTO _qlt;
			RETURN _qlt.id;
			
		EXCEPTION WHEN unique_violation THEN
			--
		END;
	END LOOP;

END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
/* We know that _idd <=> session_user, since _idd := fverifyquota() TODO*/
CREATE FUNCTION 
	fupdate_quality(_qid int,_qtt int8) 
	RETURNS void AS $$
DECLARE 
	_qp tquality%rowtype;
	_q text[];
	_id int;
	_qtta int8;
BEGIN

	UPDATE tquality SET qtt = qtt + _qtt 
		WHERE id = _qid RETURNING qtt INTO _qtta;

	IF NOT FOUND THEN
		RAISE EXCEPTION USING ERRCODE='YA004';
	END IF;	
		
	IF (_qtt > 0)   THEN 
		IF (_qtta < _qtt) THEN 
			RAISE WARNING 'Quality "%" owerflows',_quality_name;
			RAISE EXCEPTION USING ERRCODE='YA004';
		END IF; 
	ELSIF (_qtt < 0) THEN
		IF (_qtta > _qtt) THEN 
			RAISE WARNING 'Quality "%" underflows',_quality_name;
			RAISE EXCEPTION USING ERRCODE='YA004';
		END IF;			
	END IF;
	
	RETURN;
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
if insert=false and not found, returns 0
else
if the owner does'nt exist and INSERT_OWN_UNKNOWN==1, it is created
*/
--------------------------------------------------------------------------------
CREATE FUNCTION fgetowner(_name text,_insert bool) RETURNS int AS $$
DECLARE
	_wid int;
BEGIN

	SELECT id INTO _wid FROM towner WHERE name=_name;
	IF NOT found THEN
		IF (_insert) THEN
			IF (fgetconst('INSERT_OWN_UNKNOWN')=1) THEN
				_wid := fcreateowner(_name);
			ELSE
				RAISE NOTICE 'The owner % is unknown',_name;
				RAISE EXCEPTION USING ERRCODE='YU001';
			END IF;
		ELSE
			_wid := 0;
		END IF;
	END IF;
	return _wid;
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
CREATE FUNCTION fcreateowner(_name text) RETURNS int AS $$
DECLARE
	_wid int;
BEGIN
	LOOP
		SELECT id INTO _wid FROM towner WHERE name=_name;
		IF found THEN
			RAISE WARNING 'The owner % was already created',_name;
			return _wid;
		END IF;
		BEGIN
			if(char_length(_name)<1) THEN
				RAISE NOTICE 'Owner s name cannot be empty';
				RAISE EXCEPTION USING ERRCODE='YU001';
			END IF;
			INSERT INTO towner (name) VALUES (_name) RETURNING id INTO _wid;
			RAISE NOTICE 'owner % created',_name;
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
    uuid text UNIQUE NOT NULL,
    own int NOT NULL, 
	
    nr int NOT NULL ,
    qtt_requ int8 NOT NULL,
    -- 0 allowed to pass lastignore flag
    
    np int NOT NULL ,
    qtt_prov dquantity NOT NULL,
    
    qtt int8 NOT NULL,  
    start int8,   

    created timestamp not NULL,
    updated timestamp default NULL,    
    PRIMARY KEY (id),
    CHECK(	
    	qtt >=0 AND qtt_prov >= qtt AND qtt_requ >=0
    ),
    CONSTRAINT ctorder_own FOREIGN KEY (own) references towner(id),
    CONSTRAINT ctorder_np FOREIGN KEY (np) references tquality(id),
    CONSTRAINT ctorder_nr FOREIGN KEY (nr) references tquality(id)
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
comment on column torder.start is 'position of treltried[np,nr].cnt when the order is inserted';

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
		n.start,
		n.created as created,
		n.updated as updated
	FROM torder n
	INNER JOIN tquality qr ON n.nr = qr.id 
	INNER JOIN tquality qp ON n.np = qp.id
	INNER JOIN towner w on n.own = w.id;

SELECT _grant_read('vorder');


-- Columns of torderremoved and torder are the same minus "start"
create table torderremoved ( 
    id int NOT NULL,
    uuid text NOT NULL,
    own int NOT NULL,
    nr int  not NULL ,
    qtt_requ dquantity NOT NULL,
    np int not NULL ,
    qtt_prov dquantity NOT NULL,
    qtt int8 NOT NULL, -- != 0 for order finvalidate_treltried
    start int8, 
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
        nb int not NULL,
        -- origin ymvt_origin DEFAULT 'EXECUTION',
        oruuid text NOT NULL, -- refers to order uuid
    	grp int, 
    	-- References the first mvt of an exchange.
    	-- can be NULL
	own_src int not NULL, 
	own_dst int not NULL,
	qtt dquantity not NULL,
	nat int not NULL,
	created timestamp not NULL,
	CHECK (
		(nb = 1 AND own_src = own_dst)
	OR 	(nb !=1) -- ( AND own_src != own_dst)
	),
	-- check do not covers grp==NULL AND nb !=0
	-- since when inserting, grp is NULL for the first mvt 
	CONSTRAINT ctmvt_grp 		FOREIGN KEY (grp) references tmvt(id),
	CONSTRAINT ctmvt_own_src 	FOREIGN KEY (own_src) references towner(id),
	CONSTRAINT ctmvt_own_dst 	FOREIGN KEY (own_dst) references towner(id),
	CONSTRAINT ctmvt_nat 		FOREIGN KEY (nat) references tquality(id)
);
SELECT _grant_read('tmvt');

comment on table tmvt is 'records a change of ownership';
comment on column tmvt.nb is 'number of movements of the exchange';
comment on column tmvt.oruuid is 'order.uuid producing  this movement';
comment on column tmvt.grp is 'references the first movement of the exchange';
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
	SELECT id,nb,oruuid,grp,own_src,own_dst,qtt,nat FROM tmvt where grp is not NULL
	UNION ALL
	SELECT id,nb,oruuid,grp,own_src,own_dst,qtt,nat FROM tmvtremoved where grp is not NULL;
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
/*
an order is moved to torderremoved when:
	it is executed and becomes empty,
	it is removed by user,
	it is invalidate_treltried.
*/
-------------------------------------------------------------------------------
CREATE FUNCTION  fremoveorder_int(_id int) RETURNS void AS $$
BEGIN		
	WITH a AS (DELETE FROM torder o WHERE o.id=_id RETURNING *) 
	INSERT INTO torderremoved 
		SELECT id,uuid,own,nr,qtt_requ,np,qtt_prov,qtt,start,created,statement_timestamp() 
	FROM a;					
END;
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
-- order removed by user
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
		SELECT o.* INTO _o FROM torder o,tquality q 
			WHERE 	o.np=q.id AND q.depository=session_user AND o.uuid = _uuid;
		IF NOT FOUND THEN
			RAISE WARNING 'the order % on a quality belonging to % was not found',_uuid,session_user;
			RAISE EXCEPTION USING ERRCODE='YU001';
		END IF;
	ELSE
		SELECT o.* INTO _o FROM torder o WHERE o.uuid = _uuid;
		IF NOT FOUND THEN
			RAISE WARNING 'the order % was not found',_uuid;
			RAISE EXCEPTION USING ERRCODE='YU001';
		END IF;
	END IF;

	SELECT * INTO _vo FROM vorder WHERE id = _o.id;	-- _vo returned
	
		
	UPDATE tquality SET qtt = qtt - _o.qtt WHERE id = _o.np RETURNING qtt INTO _qlt;
	-- check tquality.qtt >=0	
	-- order is removed but is NOT cleared
	perform fremoveorder_int(_o.id);
	
	RETURN _vo;
	
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE NOTICE 'ABORTED';
	RETURN _vo; 
END;		
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fremoveorder(text) TO client_opened_role,client_stopping_role;

--------------------------------------------------------------------------------
-- finsertflows
--------------------------------------------------------------------------------
CREATE FUNCTION finsertflows(_pivot torder) 
	RETURNS TABLE (_patmax yflow) AS $$
DECLARE

	_idpivot 	int;
	_cnt 		int;
	_o		torder%rowtype;
	_res	        int8[];
	_start		int8;
	_time_begin	timestamp;
BEGIN
	------------------------------------------------------------------------
	-- _pivot.qtt := _pivot.qtt_prov;
	_time_begin := clock_timestamp();
	
	_cnt := fcreate_tmp(_pivot.id,
			yorder_get(_pivot.id,_pivot.own,_pivot.nr,_pivot.qtt_requ,_pivot.np,_pivot.qtt_prov,_pivot.qtt),
			_pivot.np,_pivot.nr);

	IF(_cnt=0) THEN
		RETURN;
	END IF;
	_cnt := 0;
	
	LOOP		
		SELECT yflow_max(pat) INTO _patmax FROM _tmp  ;
		
		IF (yflow_status(_patmax)!=3) THEN -- status != draft
			EXIT; -- from LOOP
		END IF;
		_cnt := _cnt + 1;
		
		RETURN NEXT;

		UPDATE _tmp SET pat = yflow_reduce(pat,_patmax);
	END LOOP;
	
	DROP TABLE _tmp;
	
	perform fspendquota(_time_begin);
	
 	RETURN;
END; 
$$ LANGUAGE PLPGSQL; 
--------------------------------------------------------------------------------
CREATE VIEW vorderinsert AS
	SELECT id,yorder_get(id,own,nr,qtt_requ,np,qtt_prov,qtt) as ord,np,nr
	FROM torder ORDER BY ((qtt_prov::double precision)/(qtt_requ::double precision)) DESC;

--------------------------------------------------------------------------------
CREATE FUNCTION fcreate_tmp(_id int,_ord yorder,_np int,_nr int) RETURNS int AS $$
DECLARE 
	_MAXORDERFETCH	 int := fgetconst('MAXORDERFETCH'); 
	_MAXCYCLE 	int := fgetconst('MAXCYCLE');
	_cnt int;
BEGIN
/*	DROP TABLE IF EXISTS _tmp;
	RAISE NOTICE 'select * from fcreate_tmp(%,yorder_get%,%,%)',_id,_ord,_np,_nr;
	CREATE TEMPORARY TABLE _tmp ON COMMIT DROP  AS (
*/	
	CREATE TEMPORARY TABLE _tmp ON COMMIT DROP AS (
		SELECT A.id,A.ord,A.nr,A.pat FROM (
			WITH RECURSIVE search_backward(id,ord,pat,nr) AS (
				SELECT 	_id,_ord,yflow_get(_ord),_nr
				UNION ALL
				SELECT 	X.id,X.ord,
					yflow_get(X.ord,Y.pat), 
					-- add the order at the beginning of the yflow
					X.nr
					FROM search_backward Y,vorderinsert X
					WHERE   yflow_follow(_MAXCYCLE,X.ord,Y.pat) 
					-- X->Y === X.qtt>0 and X.np=Y[0].nr
					-- Y.pat does not contain X.ord 
					-- len(X.ord+Y.path) <= _MAXCYCLE	
					-- it is not an unexpected cycle: Y[!=-1]|->X === Y[i].np != X.nr with i!= -1
					 
			)
			SELECT id,ord,nr,pat 
			FROM search_backward LIMIT _MAXORDERFETCH 
		) A WHERE  yflow_status(A.pat)=3 --draft
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
	_commits	int8[][];
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
	_res		text;
BEGIN

	_commits := yflow_to_matrix(_flw);
	-- indices in _commits
	-- 1  2   3  4        5  6        7   8
	-- id,own,nr,qtt_requ,np,qtt_prov,qtt,flowr
	
	_nbcommit := yflow_dim(_flw); -- raise an error when flow->dim not in [2,8]
	_first_mvt := NULL;
	_exhausted := false;
	-- RAISE NOTICE 'flow of % commits',_nbcommit;
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
			RAISE WARNING 'the flow is not in sync with the database torder[%] does not exist or torder.qtt < %',_oid,_flowr ;
			RAISE EXCEPTION USING ERRCODE='YU002';
		END IF;
			
		INSERT INTO tmvt (nb,oruuid,grp,own_src,own_dst,qtt,nat,created) 
			VALUES(_nbcommit,_uuid,_first_mvt,_w_src,_w_dst,_flowr,_commits[_i][5]::int,statement_timestamp())
			RETURNING id INTO _mvt_id;
					
		IF(_first_mvt IS NULL) THEN
			_first_mvt := _mvt_id;
		END IF;
		
		IF(_qtt=0) THEN
			perform fremoveorder_int(_oid);
			_exhausted := true;
		END IF;

		_i := _next_i;
		----------------------------------------------------------------
	END LOOP;
	-- RAISE NOTICE '_first_mvt=%',_first_mvt;
	UPDATE tmvt SET grp = _first_mvt WHERE id = _first_mvt  AND (grp IS NULL); --done only for oruuid==_uuid	
	IF(NOT FOUND) THEN
		RAISE EXCEPTION 'the movement % does not exist',_first_mvt 
			USING ERRCODE='YA003';
	END IF;
	
	IF(NOT _exhausted) THEN
		--  some order should be exhausted 
		RAISE EXCEPTION 'the cycle should exhaust some order' 
			USING ERRCODE='YA003';
	END IF;
	
	PERFORM fupdate_treltried(_commits,_nbcommit);
	
	RETURN _first_mvt;
END;
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
CREATE FUNCTION fgetuuid(_id int) RETURNS text AS $$ 
DECLARE
	_market_session	int;
BEGIN
	SELECT market_session INTO _market_session FROM vmarket;
	-- RETURN lpad(_market_session::text,19,'0') || '-' || lpad(_id::text,19,'0');
	RETURN _market_session::text || '-' || _id::text;
END;
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
-- tquote
--------------------------------------------------------------------------------
-- id,nr,qtt_requ,np,qtt_prov,qtt_in,qtt_out,flows
CREATE TABLE tquote (
    id serial UNIQUE not NULL,
    
    own int NOT NULL,
    nr int NOT NULL,
    qtt_requ int8,
    np int NOT NULL,
    qtt_prov int8,
    
    qtt_in int8,
    qtt_out int8,
    flows yflow[],
    
    created timestamp not NULL,
    removed timestamp default NULL,    
    PRIMARY KEY (id)
);
SELECT _grant_read('tquote');
-- SELECT _reference_time('tquote');
-- TODO truncate at market opening
-- id,own,nr,qtt_requ,np,qtt_prov,qtt_in,qtt_out,flows,created,removed
CREATE TABLE tquoteremoved (
    id int NOT NULL,
    
    own int NOT NULL,
    nr int NOT NULL,
    qtt_requ int8,
    np int NOT NULL,
    qtt_prov int8,
    
    qtt_in int8,
    qtt_out int8,
    flows yflow[],
    
    created timestamp,
    removed timestamp
);
SELECT _grant_read('tquoteremoved');

--------------------------------------------------------------------------------
-- (id,own,qtt_in,qtt_out,flows) = fgetquote(owner,qltprovided,qttprovided,qttrequired,qltprovided)
/* if qttrequired == 0, 
	qtt_in is the minimum quantity received for a given qtt_out provided
	id == 0 (the quote is not recorded)
   else
   	(qtt_in,qtt_out) is the execution result of an order (qttprovided,qttprovided)
   
   if (id!=0) the quote is recorded
*/
--------------------------------------------------------------------------------
CREATE FUNCTION 
	fgetquote(_owner text,_qualityprovided text,_qttprovided int8,_qttrequired int8,_qualityrequired text) 
	RETURNS tquote AS $$
	
DECLARE
	_pivot 		 torder%rowtype;
	_ypatmax	 yflow;
	_flows		 yflow[];
	_res	         int8[];
	_cumul		 int8[];
	_qtt_prov	 int8;
	_qtt_requ	 int8;
	_idd		 int;
	_q		 text[];
	_ret		 tquote%rowtype;
	_r		 tquote%rowtype;
BEGIN
	_idd := fverifyquota();
	
	-- quantities must be >0
	IF(_qttprovided<=0 OR _qttrequired<0) THEN
		RAISE NOTICE 'quantities incorrect: %<=0 or %<0', _qttprovided,_qttrequired;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	_q := fexplodequality(_qualityprovided);
	IF ((_q[1] IS NOT NULL) AND (_q[1] != session_user)) THEN
		RAISE NOTICE 'depository % of quality is not the user %',_q[1],session_user;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	-- qualities are red and inserted if necessary
	_pivot.np := fgetquality(_qualityprovided,true); 
	_pivot.nr := fgetquality(_qualityrequired,true); 
	_pivot.id  := 0; 
	
	-- if does not exists, inserted
	_pivot.own := fgetowner(_owner,true); 
	 
	_pivot.qtt_requ := _qttrequired; -- if _qttrequired==0 then lastignore == true
	_pivot.qtt_prov := _qttprovided; 
	_pivot.qtt := _qttprovided;
	
	_r.id 		:= 0;
	_r.own 		:= _pivot.own;
	_r.flows 	:= ARRAY[]::yflow[];
	_r.nr 		:= _pivot.nr;
	_r.qtt_requ 	:= _pivot.qtt_requ;
	_r.np 		:= _pivot.np;
	_r.qtt_prov 	:= _pivot.qtt_prov;
	
	_cumul[1] := 0; -- in
	_cumul[2] := 0; -- out
	FOR _ypatmax IN SELECT _patmax  FROM finsertflows(_pivot) LOOP
		_r.flows := array_append(_r.flows,_ypatmax);
		_res := yflow_qtts(_ypatmax); -- [in,out] of the last node
		IF(_qttrequired = 0) THEN
			_cumul := yorder_moyen(_cumul[1],_cumul[2],_res[1],_res[2]);
		ELSE
			_cumul[1] := _cumul[1]+_res[1];
			_cumul[2] := _cumul[2]+_res[2];
		END IF;
	END LOOP;
	_r.qtt_in  := _cumul[1];
	_r.qtt_out := _cumul[2];
	
	IF (_qttrequired != 0 AND _r.qtt_out != 0 AND _r.qtt_in != 0) THEN
		INSERT INTO tquote (own,nr,qtt_requ,np,qtt_prov,qtt_in,qtt_out,flows,created,removed) 
			VALUES (_pivot.own,_r.nr,_r.qtt_requ,_r.np,_r.qtt_prov,_r.qtt_in,_r.qtt_out,_r.flows,statement_timestamp(),NULL)
		RETURNING * INTO _ret;
		RETURN _ret;
	ELSE
		RETURN _r;
	END IF;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fgetquote(text,text,int8,int8,text) TO client_opened_role;
--------------------------------------------------------------------------------
CREATE TYPE yresprequote AS (
    own int,
    nr int,
    np int,
    qtt_prov int8,
    
    qtt_in_min int8,
    qtt_out_min int8,
    
    qtt_in_max int8,
    qtt_out_max int8,
    
    qtt_in_sum int8,
    qtt_out_sum int8,
        
    flows text -- json of yflow[]
);
--------------------------------------------------------------------------------
CREATE FUNCTION 
	fgetprequote(_owner text,_qualityprovided text,_qttprovided int8,_qualityrequired text) 
	RETURNS yresprequote AS $$
	
DECLARE
	_pivot 		 torder%rowtype;
	_ypatmax	 yflow;
	_flows		 text[];
	_res	         int8[];
	_idd		 int;
	_q		 text[];
	_r		 yresprequote;
	_om_min		double precision;
	_om_max		double precision;
	_om		double precision;
BEGIN
	_idd := fverifyquota();
	
	-- quantity must be >0
	IF(_qttprovided<=0) THEN
		RAISE NOTICE 'quantities incorrect: %<=0', _qttprovided;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	_q := fexplodequality(_qualityprovided);
	IF ((_q[1] IS NOT NULL) AND (_q[1] != session_user)) THEN
		RAISE NOTICE 'depository % of quality is not the user %',_q[1],session_user;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	-- qualities are red and inserted if necessary
	_pivot.np := fgetquality(_qualityprovided,true); 
	_pivot.nr := fgetquality(_qualityrequired,true); 
	_pivot.id  := 0; 
	
	-- if does not exists, inserted
	_pivot.own := fgetowner(_owner,true); 
	 
	_pivot.qtt_requ := 0; -- lastignore == true
	_pivot.qtt_prov := _qttprovided; 
	_pivot.qtt := _qttprovided;
	
	_r.own 		:= _pivot.own;
	-- _r.flows 	:= ARRAY[]::yflow[];
	_flows		:= ARRAY[]::text[];
	_r.nr 		:= _pivot.nr;
	_r.np 		:= _pivot.np;
	_r.qtt_prov 	:= _pivot.qtt_prov;
	
	_r.qtt_in_min := 0;	_r.qtt_in_max := 0; 
	_r.qtt_out_min := 0;	_r.qtt_out_max := 0;
	_om_min := 0;		_om_max := 0;
	
	_r.qtt_in_sum := 0;
	_r.qtt_out_sum := 0;
	
	FOR _ypatmax IN SELECT _patmax  FROM finsertflows(_pivot) LOOP
		_flows := array_append(_flows,yflow_to_json(_ypatmax));
		_res := yflow_qtts(_ypatmax); -- [in,out] of the last node
		
		_r.qtt_in_sum  := _r.qtt_in_sum + _res[1];
		_r.qtt_out_sum := _r.qtt_out_sum + _res[2];
		
		_om := (_res[2]::double precision)/(_res[1]::double precision);
		
		IF(_om_min = 0 OR _om < _om_min) THEN
			_r.qtt_in_min := _res[1];
			_r.qtt_out_min := _res[2];
			_om_min := _om;
		END IF;
		IF(_om_max = 0 OR _om > _om_max) THEN
			_r.qtt_in_max := _res[1];
			_r.qtt_out_max := _res[2];
			_om_max := _om;
		END IF;
	END LOOP;
	_r.flows := array_to_json(_flows);

	RETURN _r;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fgetprequote(text,text,int8,text) TO client_opened_role;

--------------------------------------------------------------------------------
-- -- id,uuid,own,nr,qtt_requ,np,qtt_prov,qtt_in,qtt_out,flows
CREATE TYPE yresorder AS (
    id int,
    uuid text,
    own int,
    nr int,
    qtt_requ int8,
    np int,
    qtt_prov int8,
    qtt_in int8,
    qtt_out int8,
    flows yflow[]
);
--------------------------------------------------------------------------------
-- torder id,uuid,yorder,created,updated
-- yorder: qtt,nr,np,qtt_prov,qtt_requ,own
CREATE FUNCTION 
	fexecquote(_owner text,_idquote int)
	RETURNS yresorder AS $$
	
DECLARE
	_wid		int;
	_o		torder%rowtype;
	_idd		int;
	_q		tquote%rowtype;
	_ro		yresorder%ROWTYPE;

	_flows		yflow[];
	_ypatmax	yflow;	
	_res	        int8[];
	_qtt_prov	int8;
	_qtt_requ	int8;
	_first_mvt	int;

BEGIN
	
	_idd := fverifyquota();
	_wid := fgetowner(_owner,false); -- returns _wid == 0 if not found
	
	SELECT * INTO _q FROM tquote WHERE id=_idquote AND own=_wid;
	IF (NOT FOUND) THEN
		IF(_wid = 0) THEN
			RAISE NOTICE 'the owner % is not found',_owner;
		ELSE
			RAISE NOTICE 'this quote % was not made by owner %',_idquote,_owner;
		END IF;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
		
	-- _q.qtt_requ != 0		
	_qtt_requ := _q.qtt_requ;
	_qtt_prov := _q.qtt_prov;
	
	_o := finsert_toint(_qtt_prov,_q.nr,_q.np,_qtt_requ,_q.own);
	
	-- id,uuid,own,nr,qtt_requ,np,qtt_prov,qtt_in,qtt_out,flows
	_ro.id      	:= _o.id;
	_ro.uuid    	:= _o.uuid;
	_ro.own     	:= _q.own;
	_ro.nr      	:= _q.nr;
	_ro.qtt_requ	:= _q.qtt_requ;
	_ro.np      	:= _q.np;
	_ro.qtt_prov	:= _q.qtt_prov;
	_ro.qtt_in  	:= 0;
	_ro.qtt_out 	:= 0;
	_ro.flows   	:= ARRAY[]::yflow[];
	
	FOR _ypatmax IN SELECT _patmax  FROM finsertflows(_o) LOOP
		_first_mvt := fexecute_flow(_ypatmax);
		_res := yflow_qtts(_ypatmax);
		_ro.qtt_in  := _ro.qtt_in  + _res[1];
		_ro.qtt_out := _ro.qtt_out + _res[2];
		_ro.flows := array_append(_ro.flows,_ypatmax);
	END LOOP;
	
	
	IF (	(_ro.qtt_in = 0) OR (_qtt_requ = 0) OR
		((_ro.qtt_out::double precision)	/(_ro.qtt_in::double precision)) > 
		((_qtt_prov::double precision)		/(_qtt_requ::double precision))
	) THEN
		RAISE NOTICE 'Omega of the flows obtained is not limited by the order';
		RAISE EXCEPTION USING ERRCODE='YA003';
	END IF;
	
	PERFORM fremovequote_int(_idquote);	
	PERFORM finvalidate_treltried();
	
	RETURN _ro;
	
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	-- PERFORM fremovequote_int(_idquote); 
	-- RAISE NOTICE 'Abort; Quote removed';
	RETURN _ro; 

END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fexecquote(text,int) TO client_opened_role;


--------------------------------------------------------------------------------
CREATE FUNCTION  fremovequote_int(_idquote int) RETURNS void AS $$
BEGIN		
	WITH a AS (DELETE FROM tquote o WHERE o.id=_idquote RETURNING *) 
	INSERT INTO tquoteremoved 
		SELECT id,own,nr,qtt_requ,np,qtt_prov,qtt_in,qtt_out,flows,created,statement_timestamp() 
	FROM a;					
END;
$$ LANGUAGE PLPGSQL;

CREATE FUNCTION  finsert_toint(_qtt_prov int8,_nr int,_np int,_qtt_requ int8,_own int8) RETURNS torder AS $$
DECLARE
	_o		 torder%rowtype;
	_id		 int;
	_uuid		 text;
	_start		 int8;
BEGIN	
	perform fupdate_quality(_np,_qtt_prov);	
		
	INSERT INTO torder (uuid,qtt,nr,np,qtt_prov,qtt_requ,own,created,updated) 
		VALUES ('',_qtt_prov,_nr,_np,_qtt_prov,_qtt_requ,_own,statement_timestamp(),NULL)
		RETURNING id INTO _id;
	
	_uuid := fgetuuid(_id);
	_start := fget_treltried(_np,_nr);
	
	UPDATE torder SET uuid = _uuid,start = _start WHERE id=_id RETURNING * INTO _o;	
	
	RETURN _o;					
END;
$$ LANGUAGE PLPGSQL;


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- 
--------------------------------------------------------------------------------
-- torder id,uuid,yorder,created,updated
-- yorder: qtt,nr,np,qtt_prov,qtt_requ,own
CREATE FUNCTION 
	finsertorder(_owner text,_qualityprovided text,_qttprovided int8,_qttrequired int8,_qualityrequired text)
	RETURNS yresorder AS $$
	
DECLARE
	_wid		int;
	_o		torder%rowtype;
	_idd		int;
	-- _expected	tquote%rowtype;
	_q		tquote%rowtype;
	_ro		yresorder%rowTYPE;
	-- _pivot		torder%rowtype;
	_qua		text[];

	_flows		yflow[];
	_ypatmax	yflow;
	_res	        int8[];
	_first_mvt	int;
BEGIN
	
	_idd := fverifyquota();
	_q.own := fgetowner(_owner,true); -- inserted if not found
	
	-- quantities must be >0
	IF(_qttprovided<=0 OR _qttrequired<=0) THEN
		RAISE NOTICE 'quantities incorrect: %<=0 or %<=0', _qttprovided,_qttrequired;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	_qua := fexplodequality(_qualityprovided);
	IF ((_qua[1] IS NOT NULL) AND (_qua[1] != session_user)) THEN
		RAISE NOTICE 'depository % of quality is not the user %',_qua[1],session_user;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	-- qualities are red and inserted if necessary
	_q.np := fgetquality(_qualityprovided,true); 
	_q.nr := fgetquality(_qualityrequired,true); 
	-- _q.qtt_requ != 0
		
	_q.qtt_requ := _qttrequired;
	_q.qtt_prov := _qttprovided;
	
	_o := finsert_toint(_qttprovided,_q.nr,_q.np,_qttrequired,_q.own);
	
	_ro.id      	:= _o.id;
	_ro.uuid    	:= _o.uuid;
	_ro.own     	:= _q.own;
	_ro.nr      	:= _q.nr;
	_ro.qtt_requ	:= _q.qtt_requ;
	_ro.np      	:= _q.np;
	_ro.qtt_prov	:= _q.qtt_prov;
	_ro.qtt_in  	:= 0;
	_ro.qtt_out 	:= 0;
	_ro.flows   	:= ARRAY[]::yflow[];
	
	FOR _ypatmax IN SELECT _patmax  FROM finsertflows(_o) LOOP
		_first_mvt := fexecute_flow(_ypatmax);
		_res := yflow_qtts(_ypatmax);
		_ro.qtt_in  := _ro.qtt_in  + _res[1];
		_ro.qtt_out := _ro.qtt_out + _res[2];
		_ro.flows := array_append(_ro.flows,_ypatmax);
	END LOOP;
	
	
	IF (	(_ro.qtt_in != 0) AND 
		((_ro.qtt_out::double precision)	/(_ro.qtt_in::double precision)) > 
		((_qttprovided::double precision)	/(_qttrequired::double precision))
	) THEN
		RAISE NOTICE 'Omega of the flows obtained is not limited by the order';
		RAISE EXCEPTION USING ERRCODE='YA003';
	END IF;
		
	PERFORM finvalidate_treltried();
	
	RETURN _ro;
	
EXCEPTION WHEN SQLSTATE 'YU001' THEN 
	RAISE NOTICE 'Abort';
	RETURN _ro; 

END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  finsertorder(text,text,int8,int8,text) TO client_opened_role;

--------------------------------------------------------------------------------
-- admin
--------------------------------------------------------------------------------

CREATE FUNCTION fcreateuser(_name text) RETURNS void AS $$
DECLARE
	_user	tuser%rowtype;
	_super	bool;
	_market_status	text;
BEGIN
	IF( _name IN ('admin','client','client_opened_role','client_stopping_role')) THEN
		RAISE WARNING 'The name % is not allowed',_name;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	SELECT * INTO _user FROM tuser WHERE name=_name;
	IF FOUND THEN
		RAISE WARNING 'The user % exists',_name;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	INSERT INTO tuser (name) VALUES (_name);
	
	SELECT rolsuper INTO _super FROM pg_authid where rolname=_name;
	IF NOT FOUND THEN
		EXECUTE 'CREATE ROLE ' || _name;
		EXECUTE 'ALTER ROLE ' || _name || ' NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION'; 
		EXECUTE 'ALTER ROLE ' || _name || ' LOGIN CONNECTION LIMIT 1';
	ELSE
		IF(_super) THEN
			-- RAISE NOTICE 'The role % is a super user.',_name;
			RAISE NOTICE 'The role is a super user.';
		ELSE
			-- RAISE WARNING 'The user is not found but a role % already exists - unchanged.',_name;
			RAISE WARNING 'The user is not found but the role already exists - unchanged.';
			RAISE EXCEPTION USING ERRCODE='YU001';				
		END IF;
	END IF;
	
	SELECT market_status INTO _market_status FROM vmarket;
	IF(_market_status = 'OPENED') THEN 
		-- RAISE NOTICE 'The market is opened for this user %', _name;
		RAISE NOTICE 'The market is opened for this user';
		EXECUTE 'GRANT client_opened_role TO ' || _name;
	ELSIF(_market_status = 'STOPPING') THEN
		-- RAISE NOTICE 'The market is stopping for this user %', _name;
		RAISE NOTICE 'The market is stopping for this user ';
		EXECUTE 'GRANT client_stopping_role TO ' || _name;	
	END IF;
	
	RETURN;
		
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fcreateuser(text) TO admin;

\i sql/market.sql

--------------------------------------------------------------------------------
-- moves all movements of an exchange belonging to the user into tmvtremoved
-- returns the number of movements moved
CREATE FUNCTION 
	fremoveagreement(_grp int) 
	RETURNS int AS $$
DECLARE 
	_nat int;
	_scntq	int;
	_cntm	int;
	_scntm	int;
	_qtt int8;
	_qlt tquality%rowtype;
	_CHECK_QUALITY_OWNERSHIP int := fgetconst('CHECK_QUALITY_OWNERSHIP');
BEGIN
	_scntq := 0;_scntm := 0;
	FOR _nat,_qtt,_cntm IN SELECT m.nat,sum(m.qtt),count(m.id) FROM tmvt m, tquality q 
		WHERE m.nat=q.id AND 
		((q.depository=session_user) OR (_CHECK_QUALITY_OWNERSHIP = 0)) AND 
		m.grp=_grp GROUP BY m.nat LOOP
		
		_scntq := _scntq +1;
		_scntm := _scntm + _cntm;
		UPDATE tquality SET qtt = qtt - _qtt WHERE id = _nat RETURNING qtt INTO _qlt;
		-- constraint  tquality.qtt >=0	
	END LOOP;
	
	IF (_scntm=0) THEN
		RAISE WARNING 'The agreement "%" does not exist or no movement of this agreement belongs to the user %',_grp,session_user;
	ELSE
		WITH a AS (DELETE FROM tmvt m USING tquality q WHERE m.nat=q.id AND 
			((q.depository=session_user) OR (_CHECK_QUALITY_OWNERSHIP = 0)) 
			AND m.grp=_grp RETURNING m.*) 
		INSERT INTO tmvtremoved SELECT id,nb,oruuid,grp,own_src,own_dst,qtt,nat,created,statement_timestamp() as deleted FROM a;

	END IF;
	
	RETURN _scntm;

END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fremoveagreement(int) TO client_opened_role,client_stopping_role;

\i sql/quota.sql

\i sql/stat.sql
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
\i sql/reltried.sql
CREATE FUNCTION _removepublic() RETURNS void AS $$
BEGIN
	EXECUTE 'REVOKE ALL ON DATABASE ' || current_catalog || ' FROM PUBLIC';
	RETURN;
END; 
$$ LANGUAGE PLPGSQL;
SELECT _removepublic();
--------------------------------------------------------------------------------
DROP FUNCTION _removepublic();
DROP FUNCTION _grant_read(_table text);
DROP FUNCTION _reference_time(text);

--------------------------------------------------------------------------------
SELECT * from fchangestatemarket(true); 
-- market is opened
\set ECHO all
 RESET client_min_messages;
 RESET log_error_verbosity;

