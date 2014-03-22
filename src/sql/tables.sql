--------------------------------------------------------------------------------
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES REVOKE ALL ON TYPES FROM PUBLIC;

--------------------------------------------------------------------------------
create domain dqtt AS int8 check( VALUE>0);
create domain dtext AS text check( char_length(VALUE)>0);

--------------------------------------------------------------------------------
-- main constants of the model
--------------------------------------------------------------------------------
create table tconst(
	name dtext UNIQUE not NULL,
	value	int,
	PRIMARY KEY (name)
);
GRANT SELECT ON tconst TO role_com;

--------------------------------------------------------------------------------
/* for booleans, 0 == false and !=0 == true
*/
INSERT INTO tconst (name,value) VALUES 
	('MAXCYCLE',64), 		-- must be less than yflow_get_maxdim()

	('MAXPATHFETCHED',1024),-- maximum depth of the graph exploration

	('MAXMVTPERTRANS',128),	-- maximum number of movements per transaction
	-- if this limit is reached, next cycles are not performed but all others
	-- are included in the current transaction

	('VERSION-X',2),('VERSION-Y',0),('VERSION-Z',2),

	('OWNERINSERT',1),		-- boolean when true, owner inserted when not found
	('QUAPROVUSR',0),		-- boolean when true, the quality provided by a barter is suffixed by user name
							-- 1 prod
	('OWNUSR',0),			-- boolean when true, the owner is suffixed by user name
							-- 1 prod
	('DEBUG',1);

--------------------------------------------------------------------------------
create table tvar(
	name dtext UNIQUE not NULL,
	value	int,
	PRIMARY KEY (name)
);

--------------------------------------------------------------------------------
-- TOWNER
--------------------------------------------------------------------------------
create table towner (
    id serial UNIQUE not NULL,
    name dtext UNIQUE not NULL,
    PRIMARY KEY (id)
);
comment on table towner is 'owners of values exchanged';
alter sequence towner_id_seq owned by towner.id;
create index towner_name_idx on towner(name);
SELECT _reference_time('towner');
SELECT _grant_read('towner');

--------------------------------------------------------------------------------
-- ORDER BOOK
--------------------------------------------------------------------------------
-- type = type_flow | type_primitive <<8 | type_mode <<16
create domain dtypeorder AS int check(VALUE >=0 AND VALUE < 16777215); --((1<<24)-1)

-- type_flow &3  1 order limit,2 order best
-- type_flow &12 bit set for c calculations 
--    4 no qttlimit
--    8 ignoreomega
-- yorder.type is a type_flow = type & 255

-- type_primitive
-- 1 	order
-- 2    rmorder
-- 3    quote
-- 4    prequote

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
comment on table torder is 'Order book';
comment on column torder.usr is 'user that inserted the order ';
comment on column torder.ord is 'the order';
comment on column torder.created is 'time when the order was put on the stack';
comment on column torder.updated is 'time when the (quantity) of the order was updated by the order book';
comment on column torder.duration is 'the life time of the order';
SELECT _grant_read('torder');

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
SELECT _grant_read('vorder');

-- sans dates ni filtre sur usr
create view vorder2 as
select (o.ord).id as id,(o.ord).type as type,w.name as own,(o.ord).oid as oid,
		(o.ord).qtt_requ as qtt_requ,(o.ord).qua_requ as qua_requ,
		(o.ord).qtt_prov as qtt_prov,(o.ord).qua_prov as qua_prov,
		(o.ord).qtt as qtt
from torder o left join towner w on ((o.ord).own=w.id);
SELECT _grant_read('vorder2');

-- only parent for all users
create view vbarter as
select (o.ord).id as id,(o.ord).type as type,o.usr as user,w.name as own,
		(o.ord).qtt_requ as qtt_requ,(o.ord).qua_requ as qua_requ,
		(o.ord).qtt_prov as qtt_prov,(o.ord).qua_prov as qua_prov,
		(o.ord).qtt as qtt, o.created as created, o.updated as updated
from torder o left join towner w on ((o.ord).own=w.id) where (o.ord).oid=(o.ord).id;
SELECT _grant_read('vbarter');

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

--------------------------------------------------------------------------------
CREATE FUNCTION fgetowner(_name text) RETURNS int AS $$
DECLARE
	_wid int;
	_OWNERINSERT 	boolean := fgetconst('OWNERINSERT')=1;
BEGIN
	LOOP
		SELECT id INTO _wid FROM towner WHERE name=_name;
		IF found THEN
			return _wid;
		END IF;
		IF (NOT _OWNERINSERT) THEN
			RAISE EXCEPTION 'The owner does not exist' USING ERRCODE='YU001';
		END IF;
		BEGIN
			INSERT INTO towner (name) VALUES (_name) RETURNING id INTO _wid;
			-- RAISE NOTICE 'owner % created',_name;
			return _wid;
		EXCEPTION WHEN unique_violation THEN
			NULL;--
		END;
	END LOOP;
END;
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
-- TMVT
-- id,nbc,nbt,grp,xid,usr_src,usr_dst,xoid,own_src,own_dst,qtt,nat,ack,exhausted,order_created,created
--------------------------------------------------------------------------------
/*
create table tmvt (
	id serial UNIQUE not NULL,
	nbc int default NULL, 
	nbt int default NULL, 
	grp int default NULL,
	xid int default NULL,
	usr_src text default NULL,
	usr_dst text default NULL,
	xoid int default NULL,
	own_src text default NULL, 
	own_dst text default NULL,
	qtt int8 default NULL,
	nat text default NULL,
	ack	boolean default NULL,
	cack boolean default NULL,
	exhausted boolean default NULL,
	order_created timestamp default NULL,
	created	timestamp default NULL,
	om_exp double precision default NULL,
	om_rea double precision default NULL,

	CONSTRAINT ctmvt_grp FOREIGN KEY (grp) references tmvt(id) ON UPDATE CASCADE
);

GRANT SELECT ON tmvt TO role_com;

comment on table tmvt is 'Records ownership changes';

comment on column tmvt.nbc is 'number of movements of the exchange cycle';
comment on column tmvt.nbt is 'number of movements of the transaction containing several exchange cycles';
comment on column tmvt.grp is 'references the first movement of the exchange';
comment on column tmvt.xid is 'references the order.id';
comment on column tmvt.usr_src is 'usr provider';
comment on column tmvt.usr_dst is 'usr receiver';
comment on column tmvt.xoid is 'references the order.oid';
comment on column tmvt.own_src is 'owner provider';
comment on column tmvt.own_dst is 'owner receiver';
comment on column tmvt.qtt is 'quantity of the value moved';
comment on column tmvt.nat is 'quality of the value moved';
comment on column tmvt.ack is 'set when movement has been acknowledged';
comment on column tmvt.cack is 'set when the cycle has been acknowledged';
comment on column tmvt.exhausted is 'set when the movement exhausted the order providing the value';
comment on column tmvt.om_exp is 'ω expected by the order';
comment on column tmvt.om_rea is 'real ω of movement';

alter sequence tmvt_id_seq owned by tmvt.id;
GRANT SELECT ON tmvt_id_seq TO role_com;

create index tmvt_grp_idx on tmvt(grp);
create index tmvt_nat_idx on tmvt(nat);
create index tmvt_own_src_idx on tmvt(own_src);
create index tmvt_own_dst_idx on tmvt(own_dst);

CREATE VIEW vmvt AS select * from tmvt;
GRANT SELECT ON vmvt TO role_com;

CREATE VIEW vmvt_tu AS select  id,nbc,grp,xid,xoid,own_src,own_dst,qtt,nat,ack,cack,exhausted from tmvt;
GRANT SELECT ON vmvt_tu TO role_com;

create view vmvto as 
    select  id,grp,
    usr_src as from_usr,
    own_src as from_own,
    qtt::text || ' ' || nat as value,
    usr_dst as to_usr,
    own_dst as to_own,
    to_char(om_exp, 'FM999.9999990') as expected_ω,
    to_char(om_rea, 'FM999.9999990') as actual_ω,
    ack 
    from tmvt where cack is NULL order by id asc;
GRANT SELECT ON vmvto TO role_com;
*/
CREATE SEQUENCE tmvt_id_seq;

--------------------------------------------------------------------------------
-- STACK id,usr,kind,jso,submitted
--------------------------------------------------------------------------------
create table tstack ( 
    id serial UNIQUE not NULL,
    usr dtext,
    kind eprimitivetype,
    jso 	json, -- representation of the primitive
    submitted timestamp not NULL,
    PRIMARY KEY (id)
);

comment on table tstack is 'Records the stack of primitives';
comment on column tstack.id is 'id of this primitive';
comment on column tstack.usr is 'user submitting the primitive';
comment on column tstack.kind is 'type of primitive';
comment on column tstack.jso is 'primitive payload';
comment on column tstack.submitted is 'timestamp when the primitive was successfully submitted';

alter sequence tstack_id_seq owned by tstack.id;

GRANT SELECT ON tstack TO role_com;
SELECT fifo_init('tstack');
GRANT SELECT ON tstack_id_seq TO role_com;


--------------------------------------------------------------------------------	
CREATE TYPE eprimphase AS ENUM ('submit', 'execute');

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
SELECT _grant_read('tmsg');
SELECT _grant_read('tmsg_id_seq');
SELECT fifo_init('tmsg');
CREATE VIEW vmsg AS select * from tmsg WHERE usr = session_user;
SELECT _grant_read('vmsg');

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
	mvt_to   yj_stock
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



