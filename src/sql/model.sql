\set ECHO none

drop schema IF EXISTS test CASCADE;
CREATE SCHEMA test;
SET search_path TO test;

SET client_min_messages = warning;
SET log_error_verbosity = terse;

drop extension if exists cube cascade;
create extension cube with version '1.0';

drop extension if exists btree_gin cascade;
create extension btree_gin with version '1.0';

drop extension if exists wolf cascade;
create extension wolf with version '1.0';

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
	('MAXCYCLE',16),
	-- it is the version of the model, not that of the extension
	('VERSION-X.y.z',0),
	('VERSION-x.Y.y',0),
	('VERSION-x.y.Z',1),
	('MAXPATHFETCHED',1024);
	-- maximum number of paths of the set on which the competition occurs
	-- ('MAXBRANCHFETCHED',20);


--------------------------------------------------------------------------------
-- fetch a constant, and verify consistancy
CREATE FUNCTION fgetconst(_name text) RETURNS int AS $$
DECLARE
	_ret int;
BEGIN
	SELECT value INTO _ret FROM tconst WHERE name=_name;
	IF(NOT FOUND) THEN
		RAISE EXCEPTION 'the const % is not found',_name USING ERRCODE= 'YA002';
	END IF;
	IF(_name = 'MAXCYCLE' AND _ret >64) THEN
		RAISE EXCEPTION 'obCMAXVALUE must be <=64' USING ERRCODE='YA002';
	END IF;
	RETURN _ret;
END; 
$$ LANGUAGE PLPGSQL STABLE;

--------------------------------------------------------------------------------
-- definition of roles
--	admin market administrator -- cannot act as client
--	client -- can act as client only when it inherits from role_open 
--------------------------------------------------------------------------------
CREATE FUNCTION _create_roles() RETURNS int AS $$
DECLARE
	_rol text;
BEGIN
	BEGIN 
		CREATE ROLE role_opened; 
	EXCEPTION WHEN duplicate_object THEN
		NULL;	
	END;
	ALTER ROLE role_opened NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
	
	BEGIN 
		CREATE ROLE role_stopped; 
	EXCEPTION WHEN duplicate_object THEN
		NULL;	
	END;
	ALTER ROLE role_stopped NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
	
	BEGIN 
		CREATE ROLE batch;
	EXCEPTION WHEN duplicate_object THEN
		NULL;
	END;
	ALTER ROLE batch INHERIT;
	
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
CREATE FUNCTION fifo_init(_name text) RETURNS void AS $$
BEGIN
	EXECUTE 'CREATE INDEX ' || _name || '_id_idx ON ' || _name || '((id) ASC)';
END; 
$$ LANGUAGE PLPGSQL;

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
	EXECUTE 'GRANT SELECT ON TABLE ' || _table || ' TO role_opened,role_stopped,admin';
	RETURN;
END; 
$$ LANGUAGE PLPGSQL;
SELECT _grant_read('tconst');

--------------------------------------------------------------------------------
create domain dquantity AS int8 check( VALUE>0);

--------------------------------------------------------------------------------
-- ORDER
--------------------------------------------------------------------------------
create table torder ( 
    ord yorder,
    created timestamp not NULL,
    updated timestamp
);

SELECT _grant_read('torder');

comment on table torder is 'description of orders';

create index torder_qua_prov_idx on torder using gin(((ord).qua_prov) text_ops);
create index torder_id_idx on torder(((ord).id));
create index torder_oid_idx on torder(((ord).oid));

--------------------------------------------------------------------------------
-- TMVT
-- id,nbc,nbt,grp,own_src,own_dst,qtt,nat,created
--------------------------------------------------------------------------------
create table tmvt (
	id serial UNIQUE not NULL,
	nbc int not NULL, -- Number of mvts in the exchange
	nbt int not NULL, -- Number of mvts in the transaction
	grp int, -- References the first mvt of an exchange.
	-- can be NULL
	xid int not NULL,
	xoid int not NULL,
	own_src text not NULL, 
	own_dst text not NULL,
	qtt dquantity not NULL,
	nat text not NULL,
	created timestamp not NULL,
	CHECK (
		(nbc = 1 AND own_src = own_dst)
	OR 	(nbc !=1) -- ( AND own_src != own_dst)
	),
	-- check do not covers grp==NULL AND nb !=0
	-- since when inserting, grp is NULL for the first mvt 
	CONSTRAINT ctmvt_grp FOREIGN KEY (grp) references tmvt(id) ON UPDATE CASCADE
);
SELECT _grant_read('tmvt');

comment on table tmvt is 'Records a ownership changes';
comment on column tmvt.nbc is 'number of movements of the exchange';
comment on column tmvt.nbt is 'number of movements of the transaction';
comment on column tmvt.grp is 'references the first movement of the exchange';
comment on column tmvt.xid is 'references the order.id';
comment on column tmvt.xoid is 'references the order.oid';
comment on column tmvt.own_src is 'owner provider';
comment on column tmvt.own_dst is 'owner receiver';
comment on column tmvt.qtt is 'quantity of the value moved';
comment on column tmvt.nat is 'quality of the value moved';

alter sequence tmvt_id_seq owned by tmvt.id;
create index tmvt_grp_idx on tmvt(grp);
create index tmvt_nat_idx on tmvt(nat);
create index tmvt_own_src_idx on tmvt(own_src);
create index tmvt_own_dst_idx on tmvt(own_dst);

SELECT fifo_init('tmvt');


--------------------------------------------------------------------------------
-- STACK
--------------------------------------------------------------------------------
create table tstack ( 
    id serial UNIQUE not NULL,
    own text NOT NULL,
    oid int, -- can be NULL
    qua_requ text NOT NULL ,
    qtt_requ dquantity NOT NULL,
    qua_prov text NOT NULL ,
    qtt_prov dquantity NOT NULL,
    created timestamp not NULL,   
    PRIMARY KEY (id)
);

comment on table tstack is 'Records a stack of orders';
comment on column tstack.id is 'id of this order';
comment on column tstack.oid is 'id of a parent order';
comment on column tstack.own is 'owner of this order';
comment on column tstack.qua_requ is 'quality required';
comment on column tstack.qtt_requ is 'quantity required';
comment on column tstack.qua_prov is 'quality provided';
comment on column tstack.qtt_prov is 'quantity provided';

alter sequence tstack_id_seq owned by tstack.id;

SELECT _grant_read('tstack');
SELECT fifo_init('tstack');



--------------------------------------------------------------------------------
/* fomega_max_iterator
creates a temporary table _tmp of potential exchanges
among potential exchanges of _tmp, selects the ones having the product of omegas maximum
*/
--------------------------------------------------------------------------------
CREATE FUNCTION fomega_max_iterator(_pivot yorder) 
	RETURNS TABLE (_patmax yorder[]) AS $$
DECLARE

	_idpivot 	int;
	_cnt 		int;
	_o			torder%rowtype;
	_res	    int8[];
	_start		int8;
BEGIN
	------------------------------------------------------------------------
	_cnt := fcreate_tmp(_pivot);
			
	LOOP		
		SELECT ywolf_max(pat) INTO _patmax FROM _tmp;
		
		IF(NOT FOUND) THEN
			EXIT; -- from LOOP
		END IF;
		
		-- among potential exchange cycles of _tmp, selects the one having the product of omegas maximum
		IF (ywolf_status(_patmax)!=3) THEN -- status != draft
			EXIT; -- no potential exchange where found; exit from LOOP
		END IF;
		_cnt := _cnt + 1;
		RETURN NEXT;

		UPDATE _tmp SET pat = ywolf_reduce(pat,_patmax);
	END LOOP;
	
	-- DROP TABLE _tmp; it is dropped at the end of the transaction
	
 	RETURN;
END; 
$$ LANGUAGE PLPGSQL; 

--------------------------------------------------------------------------------
/* for an order O creates a temporary table _tmp of objects.
Each object represents a chain of orders - a flows - going to O. 
The table has columns
	id	id of an order X
	ord	order X
	nr	quality required by this order X
	pat	path of orders - a flow - from X to O
One object for each paths to O
objects having the shortest path are fetched first
objects having best orders (using the view vorderinsert) are fetched first
The number of objects fetched is limited to MAXPATHFETCHED
Among those objects representing chains of orders, 
only those making a potential exchange (draft) are recorded.
*/
--------------------------------------------------------------------------------
/*
CREATE VIEW vorderinsert AS
	SELECT id,yorder_get(id,own,nr,qtt_requ,np,qtt_prov,qtt) as ord,np,nr
	FROM torder ORDER BY ((qtt_prov::double precision)/(qtt_requ::double precision)) DESC; */
--------------------------------------------------------------------------------
CREATE FUNCTION fcreate_tmp(_ord yorder) RETURNS int AS $$
DECLARE 
	_MAXPATHFETCHED	 int := fgetconst('MAXPATHFETCHED'); 
	-- _MAXBRANCHFETCHED	 int := fgetconst('MAXBRANCHFETCHED'); 
	_MAXCYCLE 	int := fgetconst('MAXCYCLE');
	_cnt int;
BEGIN
/*	DROP TABLE IF EXISTS _tmp;
	RAISE NOTICE 'select * from fcreate_tmp(%,yorder_get%,%,%)',_id,_ord,_np,_nr;
	CREATE TEMPORARY TABLE _tmp ON COMMIT DROP  AS (
*/	
	CREATE TEMPORARY TABLE _tmp ON COMMIT DROP AS (
		SELECT A.ord,A.pat FROM (
			WITH RECURSIVE search_backward(ord,pat,qua_requ) AS (
				SELECT 	_ord,ARRAY[_ord]::yorder[],_ord.qua_requ
				UNION ALL
				SELECT 	X.ord,ywolf_cat(X.ord,Y.pat),(X.ord).qua_requ
					-- add the order at the beginning of the array
					FROM search_backward Y,
					(
						SELECT ord FROM torder 
						-- ORDER BY ((qtt_prov::double precision)/(qtt_requ::double precision)) DESC
						-- LIMIT _MAXBRANCHFETCHED					
					) X
					WHERE  ((X.ord).qua_prov)=(Y.qua_requ) AND ywolf_follow(_MAXCYCLE,X.ord,Y.pat) 
					-- X->Y === X.qtt>0 and X.np=Y[0].nr
					-- Y.pat does not contain X.ord 
					-- len(X.ord+Y.path) <= _MAXCYCLE	
					-- it is not an unexpected cycle: Y[!=-1]|->X === Y[i].np != X.nr with i!= -1
					 
			)
			SELECT ord,pat 
			FROM search_backward LIMIT _MAXPATHFETCHED 
		) A WHERE  ywolf_status(A.pat)>=2 -- potential exchange (refused,draft,empty)
	);
	RETURN 0;
END;
$$ LANGUAGE PLPGSQL;


--------------------------------------------------------------------------------
/* fexecute_flow
from a flow representing a draft, for each order:
	inserts a new movement
	updates the order
*/
--------------------------------------------------------------------------------
CREATE TYPE yresexec AS (
    first_mvt int, -- id of the first mvt
    nbc int, -- number of mvts
    mvts int[] -- list of id des mvts
);
CREATE FUNCTION fexecute_flow(_flw yorder[]) RETURNS  yresexec AS $$
DECLARE
	_i			int;
	_next_i		int;
	_nbcommit	int;
	
	_first_mvt  int;
	_exhausted	bool;
	_mvt_id		int;

	_cnt 		int;
	_resx		yresexec%rowtype;
	_qtt		int8;
	_o			yorder;
	_onext		yorder;
BEGIN
	_nbcommit := array_length(_flw,1);
	
	-- sanity check
	IF( _nbcommit <2 OR _flw[0].flowr <=0 ) THEN
		RAISE EXCEPTION 'the flow should be draft' 
			USING ERRCODE='YA003';
	END IF;
	-- RAISE NOTICE 'flow of % commits',_nbcommit;
	
	--lock table torder in share row exclusive mode;
	lock table torder in share update exclusive mode;
	
	_first_mvt := NULL;
	_exhausted := false;
	_i := _nbcommit;
	_resx.nbc := _nbcommit;	
	_resx.mvts := ARRAY[]::int[];
	FOR _next_i IN 1 .. _nbcommit LOOP
		------------------------------------------------------------------------
		_onext  := _flw[_next_i];
		_o	    := _flw[_i];	

		SELECT count(*) INTO _cnt FROM torder WHERE (ord).oid = _o.oid AND _o.flowr > (ord).qtt;
		IF(_cnt >0) THEN
			RAISE EXCEPTION 'the wolf is not in sync with the database. the flow exeeds orders'  USING ERRCODE='YU003';
		END IF;
		UPDATE torder SET ord.qtt = (ord).qtt - _o.flowr ,updated = statement_timestamp()
			WHERE (ord).oid = _o.oid RETURNING (ord).qtt INTO _qtt;
		-- _xo := _aa.ord; -- RAISE NOTICE 'ici11 %',_aa;
		GET DIAGNOSTICS _cnt = ROW_COUNT;
		IF(_cnt = 0) THEN
			RAISE EXCEPTION 'the wolf is not in sync with the database. torder[%] does not exist',_o.oid  USING ERRCODE='YU002';
		END IF;
		
		INSERT INTO tmvt (nbc,nbt,grp,xid,xoid,own_src,own_dst,qtt,nat,created) 
			VALUES(_nbcommit,1,_first_mvt,_o.id,_o.oid,_o.own,_onext.own,_o.flowr,_o.qua_prov,statement_timestamp())
			RETURNING id INTO _mvt_id;
		IF(_first_mvt IS NULL) THEN
			_first_mvt := _mvt_id;
			_resx.first_mvt := _mvt_id;
			UPDATE tmvt SET grp = _first_mvt WHERE id = _first_mvt;
		END IF;
		_resx.mvts := array_append(_resx.mvts,_mvt_id);

		-- RAISE NOTICE 'ici1 %',_xo;
		IF( _qtt = 0 ) THEN
			DELETE FROM torder WHERE (ord).oid=_o.oid;
			_exhausted := true;
		END IF;
		-- RAISE NOTICE 'ici2 %',_xo;
		_i := _next_i;
		------------------------------------------------------------------------
	END LOOP;

	IF( NOT _exhausted ) THEN
		--  some order should be exhausted 
		RAISE EXCEPTION 'the cycle should exhaust some order' 
			USING ERRCODE='YA003';
	END IF;
	-- RAISE NOTICE 'ici3 %',_xo;
	RETURN _resx;
END;
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
CREATE TYPE yresorder AS (
    ord yorder,
    qtt_in int8,
    qtt_out int8
);
--------------------------------------------------------------------------------
-- order unstacked and inserted into torder
/* if the referenced oid is found,
	the order is inserted, and the process is loached
else a movement is created
*/
--------------------------------------------------------------------------------
CREATE FUNCTION fproducemvt() RETURNS yresorder AS $$
DECLARE
	_wid		int;
	_o			yorder;
	_or			yorder;
	_t			tstack%rowtype;
	_ro		    yresorder%rowtype;
	_fmvtids	int[];
	_first_mvt 	int;

	--_flows		json[]:= ARRAY[]::json[];
	_ypatmax	yorder[];
	_res	    int8[];
	_tid		int;
	_resx		yresexec%rowtype;
	_time_begin	timestamp;
	_qtt		int8;
BEGIN

	lock table torder in share update exclusive mode;
	_ro.ord 		:= NULL;
	_ro.qtt_in 		:= 0;
	_ro.qtt_out 	:= 0;
	
	SELECT id INTO _tid FROM tstack ORDER BY id ASC LIMIT 1;
	IF(NOT FOUND) THEN
		RETURN _ro; -- the stack is empty
	END IF;
	-- SELECT * INTO STRICT _t from tstack WHERE id=_tid;
	DELETE FROM tstack WHERE id=_tid RETURNING * INTO STRICT _t;
	-- RAISE NOTICE 'tstack %',_t;
	
	IF NOT (_t.oid IS NULL) THEN
		-- look for the referenced oid
		SELECT o.ord INTO _or from torder o WHERE (o.ord).id= _t.oid;
		IF NOT FOUND THEN
			INSERT INTO tmvt (nbc,nbt,grp,own_src,own_dst,qtt,nat,created) 
				VALUES(1,1,NULL,_o.own,_o.own,_o.qtt,_o.qua_prov,statement_timestamp());
			_ro.ord := _o;
			RETURN _ro; -- the referenced order was not found in the book
		ELSE
			_qtt	:= _or.qtt;
		END IF;
	ELSE 
		-- RAISE NOTICE 'ici % % % %',_t.id,_t.qtt_prov,_t.oid,_qtt;
		_t.oid 	:= _t.id;
		-- RAISE NOTICE 'ici % % % %',_t.id,_t.qtt_prov,_t.oid,_qtt;
		_qtt  	:= _t.qtt_prov;
		-- RAISE NOTICE 'ici % % % %',_t.id,_t.qtt_prov,_t.oid,_qtt;
	END IF;
	

	_o := ROW(_t.id,_t.own,_t.oid,_t.qtt_requ,_t.qua_requ,_t.qtt_prov,_t.qua_prov,_qtt,0)::yorder;
	
	INSERT INTO torder(ord,created,updated) VALUES (_o,_t.created,NULL);	

	_ro.ord      	:= _o;
	 
	_fmvtids := ARRAY[]::int[];
	
	_time_begin := clock_timestamp();
	
	FOR _ypatmax IN SELECT _patmax  FROM fomega_max_iterator(_o) LOOP
	
		_resx := fexecute_flow(_ypatmax);
		_fmvtids := _fmvtids || _resx.mvts;
		
		_res := ywolf_qtts(_ypatmax);
		_ro.qtt_in  := _ro.qtt_in  + _res[1];
		_ro.qtt_out := _ro.qtt_out + _res[2];
		
		-- _flows := array_append(_flows,(yflow_to_json(_ypatmax)::text)::json);
		
	END LOOP;
	
	IF (	(_ro.qtt_in != 0) AND 
		((_ro.qtt_out::double precision)	/(_ro.qtt_in::double precision)) > 
		((_o.qtt_prov::double precision)	/(_o.qtt_requ::double precision))
	) THEN
		RAISE EXCEPTION 'Omega of the flows obtained is not limited by the order' USING ERRCODE='YA003';
	END IF;
	
	-- set the number of movements in this transaction
	UPDATE tmvt SET nbt= array_length(_fmvtids,1) WHERE id = ANY (_fmvtids);
	
	-- PERFORM finvalidate_treltried(_time_begin);
	
	-- _ro.flows := array_to_json(_flows);
	RETURN _ro;

END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fproducemvt() TO role_opened;

--------------------------------------------------------------------------------
CREATE TYPE yressubmit AS (
    id int,
    diag int
);
--------------------------------------------------------------------------------
-- order submission    DONE
/*
returns (id,0) or (0,diag) with diag:
	-1 _qua_prov = _qua_requ
	-2 _qtt_prov <=0 or _qtt_requ <=0
*/
--------------------------------------------------------------------------------
CREATE FUNCTION 
	fsubmitorder(_own text,_oid int,_qua_requ text,_qtt_requ int8,_qua_prov text,_qtt_prov int8)
	RETURNS yressubmit AS $$	
DECLARE
	_t			tstack%rowtype;
	_r			yressubmit%rowtype;
	_o			int;
	_tid		int;
BEGIN
	_r.id := 0;
	_r.diag := 0;
	IF(_qua_prov = _qua_requ) THEN
		_r.diag := -1;
		RETURN _r;
	END IF;
	
	IF(_qtt_requ <=0 OR _qtt_prov <= 0) THEN
		_r.diag := -2;
		RETURN _r;
	END IF;	
	
	INSERT INTO tstack(own,oid,qua_requ,qtt_requ,qua_prov,qtt_prov,created)
	VALUES (_own,_oid,_qua_requ,_qtt_requ,_qua_prov,_qtt_prov,statement_timestamp()) RETURNING * into _t;
	_r.id := _t.id;
	RETURN _r;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fsubmitorder(text,int,text,int8,text,int8) TO client;	

--------------------------------------------------------------------------------
CREATE FUNCTION deletemvt() RETURNS int AS $$
DECLARE
	_tid	int;
	_m  tmvt%rowtype;
BEGIN
	SELECT id INTO _tid FROM tmvt ORDER BY id ASC LIMIT 1;
	IF(NOT FOUND) THEN
		RETURN 0;
	END IF;
	SELECT * INTO STRICT _m FROM tmvt WHERE id=_tid;
	DELETE FROM tmvt where id=_tid;
	RETURN 1;

END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  deletemvt() TO client;

--------------------------------------------------------------------------------
-- renumber a table with an index on id asc (init_fifo(_name) sets this index)
CREATE FUNCTION _frenumber_table(_name text) RETURNS int AS $$
DECLARE
	_id  int;
	_idr int;
BEGIN
	PERFORM setval(_name || '_id_seq',1,false);
	LOOP
		_idr := nextval(_name || '_id_seq');
		_id := NULL;
		EXECUTE 'SELECT id FROM ' || _name::regclass || ' WHERE id >= $1 ORDER BY id ASC LIMIT 1' INTO _id USING _idr;
		EXIT WHEN _id IS NULL;
		
		CONTINUE WHEN _id = _idr;
		EXECUTE 'UPDATE ' || _name::regclass || ' SET id = $1 WHERE id = $2' USING _idr,_id;
	END LOOP;
	RAISE NOTICE 'table % retumbered with % rows',_name,_idr;
	RETURN _idr;
END; 
$$ LANGUAGE PLPGSQL;

CREATE FUNCTION frenumber_tables() RETURNS TABLE(_table text,_cnt int) AS $$
DECLARE
	_cnt int;
BEGIN
	_table := 'torder';
	_cnt := _frenumber_table(_table);
	RETURN NEXT;
	_table := 'tmvt';
	_cnt := _frenumber_table(_table);
	RETURN NEXT;
	RETURN;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  frenumber_tables() TO admin;

--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION femptystack() RETURNS int AS $$
DECLARE
	_t tstack%rowtype;
	_cur int;
	_res yresorder%rowtype;
	_cnt int := 0;
BEGIN
	_cur := 0;
	LOOP
		SELECT * INTO _t FROM tstack WHERE id > _cur ORDER BY id ASC LIMIT 1;
		EXIT WHEN NOT FOUND;
		_cur = _t.id; 
		_cnt := _cnt +1;
		
		_res := fproducemvt();
		DROP TABLE _tmp;
		
		IF((_cnt % 100) =0) THEN
			CHECKPOINT;
		END IF;
		
	END LOOP;
	RETURN _cnt;
END;
$$ LANGUAGE PLPGSQL;


