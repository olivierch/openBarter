/*
--------------------------------------------------------------------------------
TYPES
*******

postgres			C		nb bytes
*********************************************************
int8,bigint,bigserial 		int64		8, signed interger
int4,integer			int32		4, signed interger
int2,smallint			int16		2, signed interger
double precision		float8		8, long float
char				char		1 	(postgres.h)

STOCK MOVEMENTS
*********************
addaccount	stockA[market] -=qtt	stockA[owner] +=qtt
subaccount	stockA[market] +=qtt	stockA[owner] -=qtt
create stock	stockA[owner]  -=qtt		stockS[owner] +=qtt
create draft	stockS[owner]  -=qtt		stockD[owner] +=qtt

execut draft	stockD[owner]  -=qtt	
		stockA[newowner] =+qtt (commit.sid_src -> commit.sid_dst)
		
refuse draft	stockD[owner]  -=qtt	
		stockS[owner] +=qtt  (commit.sid_dst -> commit.sid_src)
		
delete bid	stockS[owner]  -=qtt		stockA[owner] +=qtt

ob_tdraft_id_seq
*****************
it is the version number of the graph. Before the insertion of a set of
drafts, ob_tdraft_id_seq=N. At the time a set of n drafts is inserted, 
stocks are modified with version N, and when it is done, ob_tdraft_id_seq <- N+n.

*/

/* 
objects like ob_* belongs to the internal state of the market
objects like market_* belongs to the public representation of the market
*/
-- provisoire

drop schema if exists ob cascade;
create schema ob;
set search_path = ob;

create type t_time AS (created timestamp,updated timestamp);

create sequence ob_tdraft_id_seq; 
select setval('ob_tdraft_id_seq',1);

--------------------------------------------------------------------------------
-- OB_TQUALITY
--------------------------------------------------------------------------------
-- creates the sequence ob_tquality_id_seq;


create table ob_tquality (
    id bigserial not NULL,
    name text not NULL,
    qtt int8 default 0,
    PRIMARY KEY (id),
    UNIQUE(name)
);
comment on table ob_tquality is 
'description of qualities';
alter sequence ob_tquality_id_seq owned by ob_tquality.id;
create index ob_quality_name_key on ob_tquality(name);
create index ob_quality_own_key on ob_tquality(own);
/*
CREATE TABLE creates:
 implicit sequence "ob_tquality_id_seq" for serial column "ob_tquality.id"
PRIMARY KEY will create implicit index "ob_tquality_pkey" for table "ob_tquality"
UNIQUE will create implicit index "ob_tquality_name_own_key" for table "ob_tquality"
*/
	
--------------------------------------------------------------------------------
-- OB_TOWNER
--------------------------------------------------------------------------------
create table ob_towner (
    id bigserial UNIQUE not NULL,
    name text not NULL,
    PRIMARY KEY (id),
    UNIQUE(name)
);
/*
CREATE TABLE will create implicit sequence "ob_towner_id_seq" for serial column "ob_towner.id"
NOTICE:  CREATE TABLE / PRIMARY KEY will create implicit index "ob_towner_pkey" for table "ob_towner"
NOTICE:  CREATE TABLE / UNIQUE will create implicit index "ob_towner_name_key" for table "ob_towner"

*/
comment on table ob_towner is 
'description of owners of values';
alter sequence ob_towner_id_seq owned by ob_towner.id;

-- insert into ob_towner (name) values ('market');

--------------------------------------------------------------------------------
-- OB_TVALUE
-- stores a value owned.

--------------------------------------------------------------------------------
create type t_value as enum('account','bid'); 
-- create sequence ob_tvalue_id_seq;
create table ob_tvalue (
    id bigserial UNIQUE not NULL,
    own int8 references ob_towner(id) 
    	on update cascade 
    		-- updated on change of ob_towner.id
	on delete restrict not NULL,
		-- owner can be deleted only if he has not stock
    qtt int8 not NULL, 
    np int8 references ob_tquality(id) on update cascade 
	on delete restrict not NULL,
    type t_value,
    PRIMARY KEY (id)
);
-- id,own,qtt,np,type
/*
NOTICE:  CREATE TABLE will create implicit sequence "ob_tvalue_id_seq" for serial column "ob_tvalue.id"
NOTICE:  CREATE TABLE / PRIMARY KEY will create implicit index "ob_tvalue_pkey" for table "ob_tvalue"

*/
comment on table ob_tvalue is 
'description of values';
comment on column ob_tvalue.own is 'refers to the owner';
comment on column ob_tvalue.qtt is 'quantity of the value';
comment on column ob_tvalue.np is 'refers to the quality of the value';
comment on column ob_tvalue.version is 'version of database of the last update';
comment on column ob_tvalue.type is 'use of the stock';

alter sequence ob_tvalue_id_seq owned by ob_tvalue.id;
create index ob_tvalue_own_key on ob_tvalue(own);
create index ob_tvalue_np_key on ob_tvalue(np);
	
--------------------------------------------------------------------------------
-- OB_TBID
--------------------------------------------------------------------------------
-- create sequence ob_tbid_id_seq;
create table ob_tbid ( -- bid
    id bigserial UNIQUE not NULL,
    sid int8 references ob_tvalue(id) on update cascade 
	on delete cascade not NULL , 
    nr int8 references ob_tquality(id) on update cascade 
	on delete cascade not NULL ,
    qtt_prov int8,
    qtt_requ int8, 
    PRIMARY KEY (id)
);
-- id,sid,nr,prov_qtt,requ_qtt
/*
NOTICE:  CREATE TABLE will create implicit sequence "ob_tbid_id_seq" for serial column "ob_tbid.id"
NOTICE:  CREATE TABLE / PRIMARY KEY will create implicit index "ob_tbid_pkey" for table "ob_tbid"

*/
comment on table ob_tbid is 'description of bids';
comment on column ob_tbid.sid is 'refers to the stock offered';
comment on column ob_tbid.nr is 'refers to quality required';
comment on column ob_tbid.qtt_prov is 
'used to express omega, but not the quantity offered';
comment on column ob_tbid.qtt_requ is 
'used to express omega';

alter sequence ob_tbid_id_seq owned by ob_tbid.id;
create index ob_tbid_sid_key on ob_tbid(sid);
create index ob_tbid_nr_key on ob_tbid(nr);
/*
create type t_draft as (
	
);*/
/*
CREATE FUNCTION market.fstats(pivot_id int8,omega float,qr text,qf text) RETURNS SETOF t_draft AS $$
DECLARE
	ret market.tret_stats%rowtype;
BEGIN
*/
INSERT INTO ob_tquality (name) VALUES
('qua1'),('qua2'),('qua3'),('qua4'),('qua5');
INSERT INTO ob_towner (name) VALUES
('o1'),('o2'),('o3'),('o4'),('o5');
INSERT INTO ob_tvalue (own,qtt,np,type) VALUES
(1,100,1,'bid'),(2,200,2,'bid'),(3,300,3,'bid'),(4,400,4,'bid'),(5,500,5,'bid');
INSERT INTO ob_tbid (sid,nr,qtt_prov,qtt_requ) VALUES
(1,5,1,1),(2,1,1,1),(3,2,1,1),(4,3,1,1),(5,4,1,1);
UPDATE ob_tbid SET id=0 WHERE id=1;

/* path for b.id=1 
*/ 
-- forward
CREATE TEMP TABLE tmp AS (
WITH RECURSIVE search_forward(id,sid,nr,qtt_prov,qtt_requ,
				own,qtt,np,
				depth) AS (
	SELECT b.id, b.sid, b.nr,b.qtt_prov,b.qtt_requ,
		v.own,v.qtt,v.np,
		1
		FROM ob_tbid b, ob_tvalue v
		WHERE b.id=0 AND b.sid=v.id AND v.qtt != 0
	UNION ALL
	SELECT b.id, b.sid, b.nr,b.qtt_prov,b.qtt_requ,
		v.own,v.qtt,v.np,
		sf.depth + 1
		FROM ob_tbid b, ob_tvalue v, search_forward sf
		WHERE b.sid=v.id AND sf.np = b.nr AND v.qtt !=0 
			AND sf.depth < 8
)
SELECT DISTINCT id,sid,nr,qtt_prov,qtt_requ,own,qtt,np,-1 as graph FROM search_forward);

-- OK
WITH RECURSIVE search_backward(id,nr,np,depth) AS (
	SELECT t.id,t.nr,t.np,1
		FROM tmp t
		WHERE t.id=0 
	UNION ALL
	SELECT t.id,t.nr,t.np,sb.depth + 1
		FROM tmp t,search_backward sb
		WHERE t.np = sb.nr AND sb.depth < 8
) 
UPDATE tmp t SET graph = 0 FROM search_backward sb WHERE t.id = sb.id;


/*	
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
*/
