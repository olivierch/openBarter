--------------------------------------------------------------------------------
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES REVOKE ALL ON TYPES FROM PUBLIC;

--------------------------------------------------------------------------------
create domain dqtt AS int8 check( VALUE>0);
create domain dtext AS text check( char_length(VALUE)>0);

--------------------------------------------------------------------------------
-- Main constants of the model
--------------------------------------------------------------------------------
create table tconst(
	name dtext UNIQUE not NULL,
	value	int,
	PRIMARY KEY (name)
);
GRANT SELECT ON tconst TO role_com;

--------------------------------------------------------------------------------
INSERT INTO tconst (name,value) VALUES 
	('MAXCYCLE',64), 		-- must be less than yflow_get_maxdim()

	('MAXPATHFETCHED',1024),-- maximum depth of the graph exploration

	('MAXMVTPERTRANS',128),	-- maximum number of movements per transaction
	-- if this limit is reached, next cycles are not performed but all others
	-- are included in the current transaction

	('VERSION-X',2),('VERSION-Y',1),('VERSION-Z',0),

	--  booleans, 0 == false and !=0 == true

	('QUAPROVUSR',0),		-- when true, the quality provided by a barter is suffixed by user name
							-- 1 prod
	('OWNUSR',0),			-- when true, the owner is suffixed by user name
							-- 1 prod
	('DEBUG',1);
	-- 


--------------------------------------------------------------------------------
create table tvar(
	name dtext UNIQUE not NULL,
	value	int,
	PRIMARY KEY (name)
);
-- btree index tvar_pkey on name
INSERT INTO tvar (name,value) 
	VALUES ('INSTALLED',0); -- set to 1 when the model is installed
GRANT SELECT ON tvar TO role_com;

--------------------------------------------------------------------------------
-- TOWNER
--------------------------------------------------------------------------------
create table towner (
    id serial UNIQUE not NULL,
    name dtext UNIQUE not NULL,
    PRIMARY KEY (id)
);

comment on table towner 			is 'owners of values exchanged';
comment on column towner.id 		is 'id of this owner';
comment on column towner.name 		is 'the name of the owner';

alter sequence towner_id_seq owned by towner.id;
create index towner_name_idx on towner(name);
SELECT _reference_time('towner');
GRANT SELECT ON towner TO role_com;
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
CREATE FUNCTION fgetowner(_name text) RETURNS int AS $$
DECLARE
	_wid 			int;
BEGIN
	LOOP
		SELECT id INTO _wid FROM towner WHERE name=_name;
		IF found THEN
			return _wid;
		END IF;

		BEGIN
			INSERT INTO towner (name) VALUES (_name) RETURNING id INTO _wid;
			return _wid;
		EXCEPTION WHEN unique_violation THEN
			NULL;
		END;
	END LOOP;
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
-- MOVEMENTS
--------------------------------------------------------------------------------
CREATE SEQUENCE tmvt_id_seq;
--------------------------------------------------------------------------------
-- ORDER BOOK
--------------------------------------------------------------------------------
-- type = type_flow | type_primitive <<8 | type_mode <<16
create domain dtypeorder AS int check(VALUE >=0 AND VALUE < ((1<<24)-1)); 
-- type_flow &3  1 order limit,2 order best
-- type_flow &12 bit reserved for c internal calculations 
--    4 no qttlimit
--    8 ignoreomega
-- yorder.type is a type_flow = type & 255


CREATE TYPE eordertype AS ENUM ('best','limit');
CREATE TYPE eprimitivetype AS ENUM ('order','childorder','rmorder','quote','prequote');

create table torder ( 
	usr dtext,
	own dtext,
    ord yorder, --defined by the extension flowf
    created timestamp not NULL,
    updated timestamp,
    duration interval
);
comment on table torder is 			'Order book';
comment on column torder.usr is 	'user that inserted the order ';
comment on column torder.ord is 	'the order';
comment on column torder.created is 'time when the order was put on the stack';
comment on column torder.updated is 'time when the (quantity) of the order was updated by the order book';
comment on column torder.duration is 'the life time of the order';
GRANT SELECT ON torder TO role_com;

create index torder_qua_prov_idx on torder(((ord).qua_prov)); -- using gin(((ord).qua_prov) text_ops);
create index torder_id_idx on torder(((ord).id));
create index torder_oid_idx on torder(((ord).oid));

-- id,type,own,oid,qtt_requ,qua_requ,qtt_prov,qua_prov,qtt
create view vorder as
select (o.ord).id as id,(o.ord).type as type,w.name as own,(o.ord).oid as oid,
		(o.ord).qtt_requ as qtt_requ,(o.ord).qua_requ as qua_requ,
		(o.ord).qtt_prov as qtt_prov,(o.ord).qua_prov as qua_prov,
		(o.ord).qtt as qtt, o.created as created, o.updated as updated
from torder o left join towner w on ((o.ord).own=w.id) where o.usr=session_user;
GRANT SELECT ON vorder TO role_com;

-- sans dates ni filtre sur usr
create view vorder2 as
select (o.ord).id as id,(o.ord).type as type,w.name as own,(o.ord).oid as oid,
		(o.ord).qtt_requ as qtt_requ,(o.ord).qua_requ as qua_requ,
		(o.ord).qtt_prov as qtt_prov,(o.ord).qua_prov as qua_prov,
		(o.ord).qtt as qtt
from torder o left join towner w on ((o.ord).own=w.id);
GRANT SELECT ON vorder2 TO role_com;

-- only parent for all users
create view vbarter as
select (o.ord).id as id,(o.ord).type as type,o.usr as user,w.name as own,
		(o.ord).qtt_requ as qtt_requ,(o.ord).qua_requ as qua_requ,
		(o.ord).qtt_prov as qtt_prov,(o.ord).qua_prov as qua_prov,
		(o.ord).qtt as qtt, o.created as created, o.updated as updated
from torder o left join towner w on ((o.ord).own=w.id) where (o.ord).oid=(o.ord).id;
GRANT SELECT ON vbarter TO role_com;

-- parent and childs for all users, used with vmvto
create view vordero as 
    select id,
    	(case when (type & 3=1) then 'limit' else 'best' end)::eordertype as type,
    	own as owner,
        case when id=oid then (qtt::text || ' ' || qua_prov) else '' end as stock,
        '(' || qtt_prov::text || '/' || qtt_requ::text || ') ' || 
        qua_prov || ' / '|| qua_requ as expected_ω,        
        case when id=oid then '' else oid::text end as oid
    from vorder order by id asc;
GRANT SELECT ON vordero TO role_com;
comment on view vordero is 'order book for all users, to be used with vmvto';
comment on column vordero.id is 'the id of the order';
comment on column vordero.owner is 'the owner';
comment on column vordero.stock is 'for a parent order the stock offered by the owner';
comment on column vordero.expected_ω is 'the ω of the order';
comment on column vordero.oid is 'for a child-order, the id of the parent-order';

--------------------------------------------------------------------------------
-- MSG
--------------------------------------------------------------------------------
CREATE TYPE emsgtype AS ENUM ('response', 'exchange');

create table tmsg (
	id serial UNIQUE not NULL,
	usr dtext default NULL, -- the user receiver of this message
	typ emsgtype not NULL,
	jso json default NULL,
	created	timestamp not NULL 
);
alter sequence tmsg_id_seq owned by tmsg.id;	
GRANT SELECT ON tmsg TO role_com;
GRANT SELECT ON tmsg_id_seq TO role_com;
SELECT fifo_init('tmsg');
CREATE VIEW vmsg AS select * from tmsg WHERE usr = session_user;
GRANT SELECT ON vmsg TO role_com;


CREATE FUNCTION fmtmvt(_j json) RETURNS text AS $$
DECLARE
	_r	 text;
BEGIN
	_r := json_extract_path_text(_j,'own') || ' (' || json_extract_path_text(_j,'qtt') || ' ' || json_extract_path_text(_j,'nat') || ')';
	RETURN _r;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;

-- DROP VIEW IF EXISTS vmsg_mvt;
CREATE VIEW vmsg_mvt AS SELECT 
json_extract_path_text(jso,'cycle')::int as grp,
json_extract_path_text(jso,'mvt_from','id')::int as mvt_from_id,
json_extract_path_text(jso,'stock','own') as own,
fmtmvt(json_extract_path(jso,'mvt_from')) as gives,
fmtmvt(json_extract_path(jso,'mvt_to')) as receives,
id as msg_id,
json_extract_path_text(jso,'orde','id')::int as order_id,
json_extract_path_text(jso,'stock','id')::int as stock_id,
json_extract_path_text(jso,'orig')::int as orig_id,
-- json_extract_path_text(jso,'stock','qtt')::bigint as stock_remain
json_extract_path_text(jso,'stock','qtt') || ' ' || json_extract_path_text(jso,'mvt_from','nat') as stock_remains
 from tmsg WHERE typ='exchange' and usr = session_user order by id;

CREATE VIEW vmsg_resp AS SELECT 
json_extract_path_text(jso,'id')::int as msg_id,
created::date as date,
CASE WHEN (json_extract_path_text(jso,'error','reason') IS NULL)THEN '' ELSE json_extract_path_text(jso,'error','reason') END as error,
json_extract_path_text(jso,'primitive','owner') as owner,
json_extract_path_text(jso,'primitive','kind') as primitive,
json_extract_path_text(jso,'result','id') as prim_id,
json_extract_path_text(jso,'value') as value
 from tmsg WHERE typ='response' and usr = session_user order by id;

--------------------------------------------------------------------------------
CREATE TYPE yj_error AS (
	code int,
	reason text
);
CREATE TYPE yerrorprim AS (
	id int,
	error yj_error
);
CREATE TYPE yj_value AS (
	qtt int8,
	nat text
);
CREATE TYPE yj_stock AS (
	id int,
	qtt int8,
	nat text,
	own text,
	usr text
);
CREATE TYPE yj_ω AS (
	id int,
	qtt_prov int8,
	qtt_requ int8,
	type eordertype
);
CREATE TYPE yj_mvt AS (
	id int,
	cycle int,
	orde yj_ω, 
	stock    yj_stock,
	mvt_from yj_stock,
	mvt_to   yj_stock,
	orig int
);
  
CREATE TYPE yj_order AS (
	id int,
	error yj_error
);
CREATE TYPE yj_primitive AS (
	id int,
	error yj_error,
	primitive json,
	result json,
	value json
);



