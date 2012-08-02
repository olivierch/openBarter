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
	('VERSION-X.y.z',0),
	('VERSION-x.Y.y',3),
	('VERSION-x.y.Z',2),
	('INSERT_OWN_UNKNOWN',1), 
	-- !=0, insert an owner when it is unknown
	-- ==0, raise an error when the owner is unknown
	('CHECK_QUALITY_OWNERSHIP',0), 
	-- !=0, quality = user_name/quality_name prefix must match session_user
	-- ==0, the name of quality can be any string
	('MAXORDERFETCH',10000),
	-- maximum number of paths of the set on which the competition occurs
	('MAXTRY',10);
	-- life time of an order for a given couple (np,nr)
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
--------------------------------------------------------------------------------
-- TRELTRIED
--------------------------------------------------------------------------------
create table treltried (
	np int references tquality(id) NOT NULL, 
	nr int references tquality(id) NOT NULL, 
	cnt bigint DEFAULT 0,
	PRIMARY KEY (np,nr),     
	CHECK(	
    		np!=nr AND 
    		cnt >=0
    	)
);	

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
-- CREATE TYPE ymvt_origin AS ENUM ('EXECUTION', 'CANCEL');
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
	RAISE INFO 'ABORTED';
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
	RAISE INFO 'select * from fcreate_tmp(%,yorder_get%,%,%)',_id,_ord,_np,_nr;
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
	-- RAISE INFO 'flow of % commits',_nbcommit;
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
	-- RAISE INFO '_first_mvt=%',_first_mvt;
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
        
    flows yflow[]
);
--------------------------------------------------------------------------------
CREATE FUNCTION 
	fgetprequote(_owner text,_qualityprovided text,_qttprovided int8,_qualityrequired text) 
	RETURNS yresprequote AS $$
	
DECLARE
	_pivot 		 torder%rowtype;
	_ypatmax	 yflow;
	_flows		 yflow[];
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
	_r.flows 	:= ARRAY[]::yflow[];
	_r.nr 		:= _pivot.nr;
	_r.np 		:= _pivot.np;
	_r.qtt_prov 	:= _pivot.qtt_prov;
	
	_r.qtt_in_min := 0;	_r.qtt_in_max := 0; 
	_r.qtt_out_min := 0;	_r.qtt_out_max := 0;
	_om_min := 0;		_om_max := 0;
	
	_r.qtt_in_sum := 0;
	_r.qtt_out_sum := 0;
	
	FOR _ypatmax IN SELECT _patmax  FROM finsertflows(_pivot) LOOP
		_r.flows := array_append(_r.flows,_ypatmax);
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

	RETURN _r;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fgetprequote(text,text,int8,text) TO client_opened_role;

--------------------------------------------------------------------------------
-- 
--------------------------------------------------------------------------------
-- torder id,uuid,yorder,created,updated
-- yorder: qtt,nr,np,qtt_prov,qtt_requ,own
CREATE FUNCTION 
	fexecquote(_owner text,_idquote int)
	RETURNS tquote AS $$
	
DECLARE
	_wid		int;
	_o		torder%rowtype;
	_idd		int;
	_expected	tquote%rowtype;
	_q		tquote%rowtype;
	_pivot		torder%rowtype;

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
	
	_q.id      := _o.id;
	_q.qtt_in  := 0;
	_q.qtt_out := 0;
	_q.flows   := ARRAY[]::yflow[];
	
	FOR _ypatmax IN SELECT _patmax  FROM finsertflows(_o) LOOP
		_first_mvt := fexecute_flow(_ypatmax);
		_res := yflow_qtts(_ypatmax);
		_q.qtt_in  := _q.qtt_in  + _res[1];
		_q.qtt_out := _q.qtt_out + _res[2];
		_q.flows := array_append(_q.flows,_ypatmax);
	END LOOP;
	
	
	IF (	(_q.qtt_in = 0) OR (_qtt_requ = 0) OR
		((_q.qtt_out::double precision)	/(_q.qtt_in::double precision)) > 
		((_qtt_prov::double precision)	/(_qtt_requ::double precision))
	) THEN
		RAISE NOTICE 'Omega of the flows obtained is not limited by the order';
		RAISE EXCEPTION USING ERRCODE='YA003';
	END IF;
	
	PERFORM fremovequote_int(_idquote);	
	PERFORM finvalidate_treltried();
	
	RETURN _q;
	
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	-- PERFORM fremovequote_int(_idquote); 
	-- RAISE INFO 'Abort; Quote removed';
	RETURN _q; 

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
	RETURNS tquote AS $$
	
DECLARE
	_wid		int;
	_o		torder%rowtype;
	_idd		int;
	_expected	tquote%rowtype;
	_q		tquote%rowtype;
	_pivot		torder%rowtype;
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
	
	_q.id      := _o.id;
	_q.qtt_in  := 0;
	_q.qtt_out := 0;
	_q.flows   := ARRAY[]::yflow[];
	
	FOR _ypatmax IN SELECT _patmax  FROM finsertflows(_o) LOOP
		_first_mvt := fexecute_flow(_ypatmax);
		_res := yflow_qtts(_ypatmax);
		_q.qtt_in  := _q.qtt_in  + _res[1];
		_q.qtt_out := _q.qtt_out + _res[2];
		_q.flows := array_append(_q.flows,_ypatmax);
	END LOOP;
	
	
	IF (	(_q.qtt_in != 0) AND 
		((_q.qtt_out::double precision)		/(_q.qtt_in::double precision)) > 
		((_qttprovided::double precision)	/(_qttrequired::double precision))
	) THEN
		RAISE NOTICE 'Omega of the flows obtained is not limited by the order';
		RAISE EXCEPTION USING ERRCODE='YA003';
	END IF;
		
	PERFORM finvalidate_treltried();
	
	RETURN _q;
	
EXCEPTION WHEN SQLSTATE 'YU001' THEN 
	RAISE INFO 'Abort';
	RETURN _q; 

END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  finsertorder(text,text,int8,int8,text) TO client_opened_role;

--------------------------------------------------------------------------------
/*
Some orders that are frequently included in refused cycles are removed from the database with the following algorithm:

1 - When a movement nr->np is created, a counter Q(np,nr)  is incremented
	Q(np,nr) == treltried[np,nr].cnt +=1, 
	done by fupdate_treltried(_commits int8[],_nbcommit int), called by vfexecute_flow()

2- When an order nr->np is created, the counter Q(np,nr) is recorded at position P
	torder[.].start = P = Q(np,nr)
	done by fget_treltried() called by finsert_order_int()
	
3- orders are removed from the market when their torder[.].start is such as P+MAXTRY < Q, with MAXTRY defined in tconst [10]
	This operation 3) is performed each time some movements are created.
	done by finvalidate_treltried() called by fexecquote() and finsertorder()
	
4- treltried must be truncated at market opening
	done by frenumbertables()
	
Ainsi, on permet à chaque offre d'être mis en concurrence MAXTRY fois sans pénaliser les couple (np,nr) plus rares. 
Celà suppose que toutes les solutions soient parcourus, ce qui n'est pas le cas.
	
*/
--------------------------------------------------------------------------------
-- update treltried[np,nr].cnt
--------------------------------------------------------------------------------
CREATE FUNCTION  fupdate_treltried(_commits int8[],_nbcommit int) RETURNS void AS $$
DECLARE 
	_i int;
	_np int;
	_nr int;
	_MAXTRY 	int := fgetconst('MAXTRY');
BEGIN
	IF(_MAXTRY=0) THEN
		RETURN;
	END IF;
	
	FOR _i IN 1 .. _nbcommit LOOP
		_nr	:= _commits[_i][3]::int;
		_np	:= _commits[_i][5]::int;
		LOOP
			UPDATE treltried SET cnt = cnt + 1 WHERE np=_np AND nr=_nr;
			IF FOUND THEN
				EXIT;
			ELSE
				BEGIN
					INSERT INTO treltried (np,nr,cnt) VALUES (_np,_nr,1);
				EXCEPTION WHEN check_violation THEN
					-- 
				END;
			END IF;
		END LOOP;
	END LOOP;

	RETURN;
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
-- sets torder[.].start
--------------------------------------------------------------------------------
CREATE FUNCTION  fget_treltried(_np int,_nr int) RETURNS int8 AS $$
DECLARE 
	_cnt int8;
	_MAXTRY 	int := fgetconst('MAXTRY');
BEGIN
	IF(_MAXTRY=0) THEN
		RETURN 0;
	END IF;
	SELECT cnt into _cnt FROM treltried WHERE np=_np AND nr=_nr;
	IF NOT FOUND THEN
		_cnt := 0;
	END IF;

	RETURN _cnt;
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
-- 
--------------------------------------------------------------------------------
CREATE FUNCTION  finvalidate_treltried() RETURNS void AS $$
DECLARE 
	_o 	torder%rowtype;
	_MAXTRY int := fgetconst('MAXTRY');
	_res	int;
	_mvt_id	int;
BEGIN
	IF(_MAXTRY=0) THEN
		RETURN;
	END IF;
	
	FOR _o IN SELECT o.* FROM torder o,treltried r 
		WHERE o.np=r.np AND o.nr=r.nr AND o.start IS NOT NULL AND o.start + _MAXTRY < r.cnt LOOP
		
		INSERT INTO tmvt (nb,oruuid,grp,own_src,own_dst,qtt,nat,created) 
			VALUES(1,_o.uuid,NULL,_o.own,_o.own,_o.qtt,_o.np,statement_timestamp()) 
			RETURNING id INTO _mvt_id;
			
		-- the order order.qtt != 0
		perform fremoveorder_int(_o.id);			
	END LOOP;
	RETURN;
END;
$$ LANGUAGE PLPGSQL;

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
			-- RAISE INFO 'The role % is a super user.',_name;
			RAISE INFO 'The role is a super user.';
		ELSE
			-- RAISE WARNING 'The user is not found but a role % already exists - unchanged.',_name;
			RAISE WARNING 'The user is not found but the role already exists - unchanged.';
			RAISE EXCEPTION USING ERRCODE='YU001';				
		END IF;
	END IF;
	
	SELECT market_status INTO _market_status FROM vmarket;
	IF(_market_status = 'OPENED') THEN 
		-- RAISE INFO 'The market is opened for this user %', _name;
		RAISE INFO 'The market is opened for this user';
		EXECUTE 'GRANT client_opened_role TO ' || _name;
	ELSIF(_market_status = 'STOPPING') THEN
		-- RAISE INFO 'The market is stopping for this user %', _name;
		RAISE INFO 'The market is stopping for this user ';
		EXECUTE 'GRANT client_stopping_role TO ' || _name;	
	END IF;
	
	RETURN;
		
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fcreateuser(text) TO admin;

--------------------------------------------------------------------------------

create table tmarket ( 
    id serial UNIQUE not NULL,
    created timestamp not NULL
);
alter sequence tmarket_id_seq owned by tmarket.id;
SELECT _grant_read('tmarket');
--------------------------------------------------------------------------------
CREATE TYPE ymarketaction AS ENUM ('init', 'open','stop','close','start');
CREATE TYPE ymarketstatus AS ENUM ('INITIALIZING','OPENED', 'STOPPING','CLOSED','STARTING');
CREATE VIEW vmarket AS SELECT
 	(id+4)/4 as market_session,
 	CASE 	WHEN (id-1)%4=0 THEN 'OPENED'::ymarketstatus 	
 		WHEN (id-1)%4=1 THEN 'STOPPING'::ymarketstatus
 		WHEN (id-1)%4=2 THEN 'CLOSED'::ymarketstatus
 		WHEN (id-1)%4=3 THEN 'STARTING'::ymarketstatus
	END AS market_status,
 	created
	FROM tmarket ORDER BY ID DESC LIMIT 1; 
SELECT _grant_read('vmarket');	

--------------------------------------------------------------------------------
CREATE FUNCTION fchangestatemarket(_execute bool) RETURNS ymarketstatus AS $$
DECLARE
	_cnt int;
	_hm tmarket%rowtype;
	_action ymarketaction;
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
		RAISE INFO 'market_session = n->n+1';
	END IF;
	
	RAISE INFO 'market_status %->%',_prev_status,_new_status;
	IF NOT _execute THEN
		RAISE INFO 'The next action will be: %',_action;
		RAISE INFO 'market_status = % is unchanged.',_prev_status;
		RETURN _new_status;
	END IF;
	
	IF (_action = 'init' OR _action = 'open') THEN 		
		GRANT client_opened_role TO client;
		RAISE INFO 'The market is now opened for clients';		
		
	ELSIF (_action = 'stop') THEN
		REVOKE client_opened_role FROM client;
		GRANT  client_stopping_role TO client;	
		RAISE INFO 'The market is now stopping for clients';		
		
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
		RAISE INFO 'The market state is %!= STOPPING, abort.',_prev_status;
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
	RAISE INFO 'The market is reset and opened';
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
	
	SELECT count(*) INTO _cnt FROM tmvt;
	IF (_cnt != 0) THEN
		RAISE INFO 'tmvt must be cleared';
		_res := false;
	ELSE
		_res := true;
	END IF;
		
	IF NOT exec THEN
		RETURN _res;
	END IF;
	
	IF NOT _res THEN
		RAISE WARNING 'tmvt must be cleared';
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
	
	-- desable triggers
	ALTER TABLE towner DISABLE TRIGGER ALL;
	ALTER TABLE tquality DISABLE TRIGGER ALL;
	ALTER TABLE tuser DISABLE TRIGGER ALL;
	
	-- DROP CONSTRAINT ON UPDATE CASCADE on tables tquality,torder,tmvt
    	ALTER TABLE tquality DROP CONSTRAINT ctquality_idd,ADD CONSTRAINT ctquality_idd FOREIGN KEY (idd) references tuser(id) ON UPDATE CASCADE;
	ALTER TABLE tquality DROP CONSTRAINT ctquality_depository,ADD CONSTRAINT ctquality_depository FOREIGN KEY (depository) references tuser(name) ON UPDATE RESTRICT;  -- must not be changed
	  			
	ALTER TABLE torder DROP CONSTRAINT ctorder_own,ADD CONSTRAINT ctorder_own 	FOREIGN KEY (own) references towner(id) ON UPDATE CASCADE;
	ALTER TABLE torder DROP CONSTRAINT ctorder_np,ADD CONSTRAINT ctorder_np 	FOREIGN KEY (np) references tquality(id) ON UPDATE CASCADE;
	ALTER TABLE torder DROP CONSTRAINT ctorder_nr,ADD CONSTRAINT ctorder_nr 	FOREIGN KEY (nr) references tquality(id) ON UPDATE CASCADE;

	ALTER TABLE tmvt DROP CONSTRAINT ctmvt_grp,ADD CONSTRAINT ctmvt_grp 		FOREIGN KEY (grp) references tmvt(id) ON UPDATE CASCADE;
	ALTER TABLE tmvt DROP CONSTRAINT ctmvt_own_src,ADD CONSTRAINT ctmvt_own_src 	FOREIGN KEY (own_src) references towner(id) ON UPDATE CASCADE;
	ALTER TABLE tmvt DROP CONSTRAINT ctmvt_own_dst,ADD CONSTRAINT ctmvt_own_dst 	FOREIGN KEY (own_dst) references towner(id) ON UPDATE CASCADE;
	ALTER TABLE tmvt DROP CONSTRAINT ctmvt_nat,ADD CONSTRAINT ctmvt_nat 		FOREIGN KEY (nat) references tquality(id) ON UPDATE CASCADE;

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
    	ALTER TABLE tquality DROP CONSTRAINT ctquality_idd,ADD CONSTRAINT ctquality_idd FOREIGN KEY (idd) references tuser(id);
    	ALTER TABLE tquality DROP CONSTRAINT ctquality_depository,ADD CONSTRAINT ctquality_depository FOREIGN KEY (depository) references tuser(name);
    		
	ALTER TABLE torder DROP CONSTRAINT ctorder_own,ADD CONSTRAINT ctorder_own 	FOREIGN KEY (own) references towner(id);
	ALTER TABLE torder DROP CONSTRAINT ctorder_np,ADD CONSTRAINT ctorder_np 	FOREIGN KEY (np) references tquality(id);
	ALTER TABLE torder DROP CONSTRAINT ctorder_nr,ADD CONSTRAINT ctorder_nr 	FOREIGN KEY (nr) references tquality(id);

	ALTER TABLE tmvt DROP CONSTRAINT ctmvt_grp,ADD CONSTRAINT ctmvt_grp 		FOREIGN KEY (grp) references tmvt(id);
	ALTER TABLE tmvt DROP CONSTRAINT ctmvt_own_src,ADD CONSTRAINT ctmvt_own_src 	FOREIGN KEY (own_src) references towner(id);
	ALTER TABLE tmvt DROP CONSTRAINT ctmvt_own_dst,ADD CONSTRAINT ctmvt_own_dst 	FOREIGN KEY (own_dst) references towner(id);
	ALTER TABLE tmvt DROP CONSTRAINT ctmvt_nat,ADD CONSTRAINT ctmvt_nat 		FOREIGN KEY (nat) references tquality(id);
	
	-- enable triggers
	ALTER TABLE towner ENABLE TRIGGER ALL;
	ALTER TABLE tquality ENABLE TRIGGER ALL;
	ALTER TABLE tuser ENABLE TRIGGER ALL;
	
	RAISE INFO 'Run the command:'; 
	RAISE INFO '	VACUUM FULL ANALYZE';
	RAISE INFO 'before starting the market';
	RETURN true;
	 
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;


--------------------------------------------------------------------------------
-- user
--------------------------------------------------------------------------------

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

/*-------------------------------------------------------------------------------
-- QUOTA MANAGEMENT

for long functions, the time spent to execute it is added to the time used by the user. 
When the time spent reaches a limit, these functions become forbidden for this user.

if this time is greater than a quota defined for this user at the beginning of the function, 
the function is aborted.
The time spent is cleared when the market starts. 

The quota management can be disabled by resetting the quota of users globally or for each user.

-------------------------------------------------------------------------------*/
create function fverifyquota() RETURNS int AS $$
DECLARE 
	_u	tuser%rowtype;
BEGIN
	SELECT * INTO _u FROM tuser WHERE name=session_user;
	IF(_u.id is NULL) THEN
		RAISE WARNING 'the user % is undefined',session_user;
		RAISE EXCEPTION USING ERRCODE='YA005';
	END IF;
	UPDATE tuser SET last_in = statement_timestamp() WHERE name = session_user;
	IF(_u.quota = 0 ) THEN
		RETURN _u.id;
	END IF;

	IF(_u.quota < _u.spent) THEN
		RAISE WARNING 'the quota is reached for the user %',session_user;
		RAISE EXCEPTION USING ERRCODE='YU003';
	END IF;
	RETURN _u.id;

END;		
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
-- 
--------------------------------------------------------------------------------
create function fspendquota(_time_begin timestamp) RETURNS bool AS $$
DECLARE 
	_t2	timestamp;
BEGIN
	_t2 := clock_timestamp();
	UPDATE tuser SET spent = spent + extract (microseconds from (_t2-_time_begin)) WHERE name = session_user;
	RETURN true;
END;		
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
-- stat
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- returns 0 when for each quality  tquality.qtt= sum(torder.qtt)+sum(tmvt.qtt)
--------------------------------------------------------------------------------
create function fbalance() RETURNS int AS $$
DECLARE 
	_cnt 		int;
BEGIN
	WITH accounting_order AS (SELECT np,sum(qtt) AS qtt FROM torder GROUP BY np),
	     accounting_mvt   AS (SELECT nat as np,sum(qtt) AS qtt FROM tmvt GROUP BY nat)
	SELECT count(*) INTO _cnt FROM tquality,accounting_order,accounting_mvt
	WHERE tquality.id=accounting_order.np AND tquality.id=accounting_mvt.np
		AND tquality.qtt != accounting_order.qtt + accounting_mvt.qtt;
	RETURN _cnt;
END;		
$$ LANGUAGE PLPGSQL;
	
--------------------------------------------------------------------------------
CREATE FUNCTION fgetstats(_details bool) RETURNS TABLE(_name text,cnt int8) AS $$
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
	
	_name := 'number of quotes';
	select count(*) INTO cnt FROM tquote;
	RETURN NEXT;
			
	_name := 'number of orders';
	select count(*) INTO cnt FROM vorderverif;
	RETURN NEXT;
	
	_name := 'number of movements';
	select count(*) INTO cnt FROM vmvtverif;
	RETURN NEXT;
	
	_name := 'number of quotes removed';
	select count(*) INTO cnt FROM tquoteremoved;
	RETURN NEXT;

	_name := 'number of orders removed';
	select count(*) INTO cnt FROM torderremoved;
	RETURN NEXT;
	
	_name := 'number of movements removed';
	select count(*) INTO cnt FROM tmvtremoved;	
	RETURN NEXT;
	
	_name := 'number of agreements';
	select count(distinct grp) INTO cnt FROM vmvtverif where nb!=1;	
	RETURN NEXT;	
	
	_name := 'number of orders rejected';
	select count(distinct grp) INTO cnt FROM vmvtverif where nb=1;	
	RETURN NEXT;

/*	
	FOR _name,cnt IN SELECT name,value FROM tconst LOOP
		RETURN NEXT;
	END LOOP;
*/		
	
	FOR _i,cnt IN select nb,count(distinct grp) FROM vmvtverif where nb!=1 GROUP BY nb LOOP
		_name := 'agreements with ' || _i || ' partners';
		RETURN NEXT;
	END LOOP;

	RETURN;
END;
$$ LANGUAGE PLPGSQL  SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fgetstats(bool) TO admin;

--------------------------------------------------------------------------------
CREATE FUNCTION fgeterrs(_details bool) RETURNS TABLE(_name text,cnt int8) AS $$
DECLARE 
	_i 		int;
	_cnt 		int;
BEGIN		
	_name := 'balance';
	cnt := fbalance();	
	RETURN NEXT;
	
	IF(_details) THEN
	
		_name := 'errors on quantities in mvts';
		cnt := fverifmvt();
		RETURN NEXT;
	
		_name := 'errors on agreements in mvts';
		cnt := fverifmvt2();
		RETURN NEXT;
	END IF;
	RETURN;
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fgeterrs(bool) TO admin;
--------------------------------------------------------------------------------
-- number of partners for the 100 last movements
-- select nb,count(distinct grp) from (select * from vmvtverif order by id desc limit 100) a group by nb;
--------------------------------------------------------------------------------
-- verifies that:
--	vorderverif.qtt_prov and vorderverif.nat are coherent with mvt
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
	_iserr		 bool;
BEGIN
	
	FOR _qtt_prov,_qtt,_uuid,_np IN SELECT qtt_prov,qtt,uuid,np FROM vorderverif LOOP
	
		_iserr := false;
	
		SELECT sum(qtt),max(nat),min(nat) INTO _qtta,_npa,_npb 
			FROM vmvtverif WHERE oruuid=_uuid GROUP BY oruuid;
			
		IF(	FOUND ) THEN 
			IF(	(_qtt_prov != _qtta+_qtt) 
				-- NOT vorderverif.qtt_prov == vorderverif.qtt + sum(mvt.qtt)
				OR (_np != _npa)	
				-- NOT mvt.nat == vorderverif.nat 
				OR (_npa != _npb)
				-- NOT all mvt.nat are the same 
			)	THEN 
				_iserr := true;
				
			END IF;	
		END IF;
		
		IF(_iserr) THEN
			_cnterr := _cnterr +1;
			raise INFO 'error on uuid:%',_uuid;
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
	IF(((_o.qtt_prov::float8) / (_o.qtt_requ::float8)) < ((_mvt.qtt::float8)/(_mvtprec.qtt::float8))) THEN
		RAISE INFO 'order %->%, with  mvt %->%',_o.qtt_requ,_o.qtt_prov,_mvtprec.qtt,_mvt.qtt;
		RAISE INFO '% < 1; should be >=1',(((_o.qtt_prov::float8) / (_o.qtt_requ::float8)) / ((_mvt.qtt::float8)/(_mvtprec.qtt::float8)));
		RAISE INFO 'order.uuid %, with  mvtid %->%',_o.uuid,_mvtprec.id,_mvt.id;
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

