/*
postgres			C		nb bytes
***************************************************************************
int8,bigint,bigserial 		int64		8, signed interger
int4,integer			int32		4, signed interger
int2,smallint			int16		2, signed interger
double precision		float8		8, long float
char				char		1 			(postgres.h)

*/
CREATE ROLE market LOGIN;
CREATE ROLE depositary LOGIN;

create sequence ob_tdraft_id_seq; 
select setval('ob_tdraft_id_seq',1);
--------------------------------------------------------
-- TRIGGERS
--------------------------------------------------------
CREATE OR REPLACE FUNCTION ob_ftime_created() RETURNS trigger AS $$
BEGIN
	NEW.created := statement_timestamp();
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;
--------------------------------------------------------
-- ob_ftime_updated 
--	trigger before insert on ob_tquality, ob_towner, ob_tomega, ob_tstock
--------------------------------------------------------
CREATE OR REPLACE FUNCTION ob_ftime_updated() RETURNS trigger AS $$
BEGIN
	IF (TG_OP = 'INSERT') THEN
		NEW.created := statement_timestamp();
	ELSE 
		NEW.updated := statement_timestamp();
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;
--------------------------------------------------------
-- ob_ins_version
--------------------------------------------------------
CREATE OR REPLACE FUNCTION ob_ins_version() RETURNS trigger AS $$
BEGIN
	SELECT last_value INTO NEW.version from ob_tdraft_id_seq;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

---------------------------------------------------------------
-- OB_TQUALITY
---------------------------------------------------------------
--create sequence ob_tquality_id_seq;
create table ob_tquality (
    --id int8 UNIQUE not NULL default nextval('ob_tquality_id_seq'),
    id bigserial UNIQUE not NULL,
    name text,
    -- own name references pg_catalog.pg_user(usename) on update restrict on delete restrict not NULL,
    own name not NULL, -- references pg_catalog.pg_authid(rolname) on update restrict on delete restrict not NULL,
    qtt bigint default 0,
    created timestamp,
    updated timestamp,
    PRIMARY KEY (id),
    UNIQUE(name,own)
);
alter sequence ob_tquality_id_seq owned by ob_tquality.id;
create index ob_tquality_name_idx on ob_tquality(name);
create index ob_tquality_own_idx on ob_tquality(own);
CREATE TRIGGER trig_befa_ob_tquality BEFORE INSERT OR UPDATE ON ob_tquality FOR EACH ROW 
  EXECUTE PROCEDURE ob_ftime_updated();
---------------------------------------------------------------
-- OB_TOWNER
---------------------------------------------------------------
-- create sequence ob_towner_id_seq;
create table ob_towner (
    -- id int8 UNIQUE not NULL default nextval('ob_towner_id_seq'),
    id bigserial UNIQUE not NULL,
    name text,
    created timestamp,
    updated timestamp,
    PRIMARY KEY (id),
    UNIQUE(name)
);
alter sequence ob_towner_id_seq owned by ob_towner.id;
create index ob_towner_name_idx on ob_towner(name);
insert into ob_towner (name) values ('market');

CREATE TRIGGER trig_befa_ob_towner BEFORE INSERT OR UPDATE ON ob_towner FOR EACH ROW 
  EXECUTE PROCEDURE ob_ftime_updated();

---------------------------------------------------------------
-- OB_TSTOCK
-- stores a value owned.
/*	
	addaccount	stockA[market] -=qtt	stockA[owner] +=qtt
	subaccount	stockA[market] +=qtt	stockA[owner] -=qtt
	create stock	stockA[owner]  -=qtt	stockS[owner] +=qtt
	create draft	stockS[owner]  -=qtt	stockD[owner] +=qtt
	execut draft	stockD[owner]  -=qtt	stockA[newowner] =+qtt (commit.sid_src -> commit.sid_dst)
	refuse draft	stockD[owner]  -=qtt	stockS[owner] +=qtt  (commit.sid_dst -> commit.sid_src)
	delete bid	stockS[owner]  -=qtt	stockA[owner] +=qtt
*/
---------------------------------------------------------------
create sequence ob_tstock_id_seq;
create table ob_tstock (
    id int8 UNIQUE not NULL
    	default nextval('ob_tstock_id_seq'),
    own int8 references ob_towner(id) on update cascade on delete restrict not NULL,
		-- owner can be deleted only if he has not stock
    qtt bigint not null, -- 64 bits
    nf int8 references ob_tquality(id) on update cascade on delete restrict not NULL,
    version int8, 
    type char,
    	-- A account
    	-- S stock
    	-- D draft
    created timestamp,
    updated timestamp,
    PRIMARY KEY (id),
    CHECK (type in('A','S','D')),
    CHECK ( (type='A' and (own=1) and (qtt < 0 or qtt = 0)) 
    	-- market has only stock.qtt <=0
    	or (type='A' and (own!=1) and (qtt > 0 or qtt = 0))
    	-- owners have only stock.qtt >=0
    	or ((type='S' or type='D') /*and (own!=1) */ and (qtt > 0 or qtt = 0)))
);
alter sequence ob_tstock_id_seq owned by ob_tstock.id;
create index ob_tstock_own_idx on ob_tstock(own);
create index ob_tstock_nf_idx on ob_tstock(nf,type);

CREATE TRIGGER trig_befa_ob_tstock BEFORE INSERT OR UPDATE ON ob_tstock  FOR EACH ROW 
  EXECUTE PROCEDURE ob_ftime_updated(); 

CREATE TRIGGER trig_befb_ob_tstock BEFORE INSERT OR UPDATE ON ob_tstock FOR EACH ROW 
  EXECUTE PROCEDURE ob_ins_version();
---------------------------------------------------------------
-- OB_TNOEUD
---------------------------------------------------------------
-- create sequence ob_tnoeud_id_seq;
create table ob_tnoeud ( -- bid
    --id int8 UNIQUE not NULL default nextval('ob_tnoeud_id_seq'),
    id bigserial UNIQUE not NULL,
    sid int8 references ob_tstock(id) on update cascade on delete cascade not NULL , -- refers to a stock
    omega double precision check(omega > 0),
    nr int8 references ob_tquality(id) on update cascade on delete cascade not NULL ,
    nf int8 references ob_tquality(id) on update cascade on delete cascade not NULL ,
    own int8 references ob_towner(id) on update cascade on delete cascade not NULL ,
    provided_quantity int8,
    required_quantity int8, -- omega = provided_quantity/required_quantity
    created timestamp,
    PRIMARY KEY (id)
);
alter sequence ob_tnoeud_id_seq owned by ob_tnoeud.id;
create index ob_tnoeud_sid_idx on ob_tnoeud(sid);
create index ob_tnoeud_nr_idx on ob_tnoeud(nr);
create index ob_tnoeud_nf_idx on ob_tnoeud(nf);
create index ob_tnoeud_own_idx on ob_tnoeud(own);

CREATE TRIGGER trig_befa_ob_tnoeud BEFORE INSERT ON ob_tnoeud  FOR EACH ROW 
  EXECUTE PROCEDURE ob_ftime_created(); 
---------------------------------------------------------------
-- OB_TDRAFT
-- draft		status
-- created		D<-
-- accepted		A<-D	all commit are accepted
-- refused		R<-D	one (or more) commit is refused
---------------------------------------------------------------
create table ob_tdraft (
    id int8 UNIQUE not NULL, -- never 0, but 1..n for n drafts
    status char,
	--  DRAFT=D, ACCEPTED=A, CANCELLED=C, 
    versionsg int8, 
	-- version of the subgraph that produced it
    version_decision int8 default NULL,
    nbsource int2,
    nbnoeud int2,
    cflags int4,
    delay int8, 
    created timestamp,
     CHECK (status in('A','C','D')),
     CHECK (nbnoeud <= 8 ),
    PRIMARY KEY(id)
);

CREATE TRIGGER trig_befa_ob_tdraft BEFORE INSERT ON ob_tdraft  FOR EACH ROW 
  EXECUTE PROCEDURE ob_ftime_created(); 
  
-- alter sequence ob_tdraft_id_seq owned by ob_tdraft.id;
---------------------------------------------------------------
-- OB_TCOMMIT
---------------------------------------------------------------
-- create sequence ob_tcommit_id_seq;
create table ob_tcommit (
	--id int8 UNIQUE not NULL default nextval('ob_tcommit_id_seq'),
	id bigserial UNIQUE not NULL,
	did int8 references ob_tdraft(id) on update cascade on delete cascade,
	bid int8 references ob_tnoeud(id) on update cascade,
	sid_src int8 references ob_tstock(id) on update cascade,
	sid_dst int8 references ob_tstock(id) on update cascade,
	--qid	int8 references ob_tquality(id) on update cascade,
	wid	int8 references ob_towner(id) on update cascade,
	flags int4, 	-- [0] draft did accepted by owner wid,
			-- [1] draft did refused by owner wid,
			-- [2] exhausted: stock.qtt=fluxarrondi for sid
	PRIMARY KEY(id)
);
alter sequence ob_tcommit_id_seq owned by ob_tcommit.id;
create index ob_tcommit_did_idx on ob_tcommit(did);
create index ob_tcommit_sid_src_idx on ob_tcommit(sid_src);
create index ob_tcommit_sid_dst_idx on ob_tcommit(sid_dst);

---------------------------------------------------------------
-- OB_TLDRAFT
---------------------------------------------------------------
create table ob_tldraft (
	-- draft
    id int8, 					--[0] get_draft supposes that it is  >0 : 1,2,3 ... changes for each draft
    cix int2, -- between 0..nbnoeud-1	--[1] 
    nbsource int2,				--[2] 
    nbnoeud int2,				--[3] 
    cflags int4, -- draft flags		--[4] 
    bid int8, -- loop.rid.Xoid		--[5] 
    sid int8, -- loop.rid.Yoid		--[6] 
    wid int8, -- loop.rid.version		--[7] 
    fluxarrondi bigint,  			--[8] 
    flags int4, -- commit flags		--[9] 
    ret_algo int4,				--[10]
    versionsg int8
);
---------------------------------------------------------------
-- OB_TOMEGA
---------------------------------------------------------------
create table ob_tomega (
	scale integer, 
	-- scale=2, omega= "234.23"
	-- scale=NULL omega= "0.23423E03"
	nr int8 references ob_tquality(id) on update cascade on delete cascade not null,
	nf int8 references ob_tquality(id) on update cascade on delete cascade not null,
	name	text,
	created timestamp,
	updated timestamp,
	PRIMARY KEY(nr,nf) 
);
create index ob_tomega_name_idx on ob_tomega(name);

CREATE TRIGGER trig_befa_ob_tomega BEFORE INSERT OR UPDATE ON ob_tomega  FOR EACH ROW 
  EXECUTE PROCEDURE ob_ftime_updated(); 
---------------------------------------------------------------
-- OB_TLOMEGA
---------------------------------------------------------------
create table ob_tlomega ( -- prices
	qttr bigint check (qttr >=0) not null,
	qttf bigint check (qttf >=0) not null,
	nr int8 references ob_tquality(id) on update cascade on delete cascade not null,
	nf int8 references ob_tquality(id) on update cascade on delete cascade not null,
	flags int4,	-- [0] when the read_omega(dnr,dnf) that inserted it was such as (dnr,dnf)=(nr,nf)
			-- [1] when inserted while a bid is inserted
	created timestamp
);
create index ob_tlomega_nr_idx on ob_tlomega(nr);
create index ob_tlomega_nf_idx on ob_tlomega(nf);
CREATE TRIGGER trig_befa_ob_tlomega BEFORE INSERT ON ob_tlomega  FOR EACH ROW 
  EXECUTE PROCEDURE ob_ftime_created(); 
---------------------------------------------------------------
-- OB_TMVT
--	An owner can be deleted only if he owns no stocks.
--	When it is deleted, it's movements are deleted
---------------------------------------------------------------
-- create sequence ob_tmvt_id_seq;
create table ob_tmvt (
    	--id int8 UNIQUE not NULL default nextval('ob_tmvt_id_seq'),
        id bigserial UNIQUE not NULL,
    	did int8 references ob_tmvt(id) on delete cascade default NULL, 
    	-- References the first mvt of a draft.
		-- NULL when movement add_account()
		-- not NULL for a draft executed. 
	-- src int8 references ob_tstock(id) on update cascade on delete set null,
	own_src int8 references ob_towner(id) on update cascade on delete cascade not null, 
	-- dst int8 references ob_tstock(id) on update cascade on delete set null,
	own_dst int8  references ob_towner(id) on update cascade on delete cascade not null,
	qtt bigint check (qtt >0 or qtt = 0) not null,
	nat int8 references ob_tquality(id) on update cascade on delete cascade not null,
	created timestamp
);
create index ob_tmvt_did_idx on ob_tmvt(did);
-- create index ob_tmvt_src_idx on ob_tmvt(src);
-- create index ob_tmvt_dst_idx on ob_tmvt(dst);
create index ob_tmvt_nat_idx on ob_tmvt(nat);
create index ob_tmvt_own_src_idx on ob_tmvt(own_src);
create index ob_tmvt_own_dst_idx on ob_tmvt(own_dst);
-- create index ob_tmvt_nat_idx on ob_tmvt(nat);

CREATE TRIGGER trig_befa_ob_tmvt BEFORE INSERT ON ob_tmvt  FOR EACH ROW 
  EXECUTE PROCEDURE ob_ftime_created();
---------------------------------------------------------------  
DROP TYPE IF EXISTS ob_tlmvt CASCADE;
create type ob_tlmvt AS (
        id int8,
    	did int8,  
	src int8,
	own_src int8, 
	dst int8,
	own_dst int8,
	qtt bigint,
	nat int8
);
 ------------------------------------------------------------------------
 -- 
 ------------------------------------------------------------------------
create table ob_tconnectdesc (
    conninfo text UNIQUE,
    conn_datas int8[], -- list of 8 int8 expressed in microseconds
    valid		bool,
    PRIMARY KEY (conninfo)
);
INSERT INTO ob_tconnectdesc (conninfo,valid) VALUES ('dbname = ob user=olivier',true);
 ------------------------------------------------------------------------
 -- Roles
 ------------------------------------------------------------------------

-- privileges granted to public
GRANT SELECT ON TABLE ob_tconnectdesc,ob_tquality,ob_towner,ob_tstock,ob_tnoeud,ob_tdraft,
	ob_tcommit,ob_tomega,ob_tlomega,ob_tmvt TO PUBLIC;
/*
 ------------------------------------------------------------------------
 Public functions
 ------------------------------------------------------------------------
ret int = ob_fadd_account(owner text,quality text,_qtt int8)
ret int = ob_fsub_account(owner text,quality text,_qtt int8)

ret int = ob_finsert_sbid(bid_id int8,_qttrequired int8,_qualityrequired text)
ret int = ob_finsert_bid(_owner text,_qualityprovided text,_qttprovided int8,_qttrequired int8,_qualityrequired text)

ret int  = ob_fbatch_omega()
ret int = ob_faccept_draft(draft_id int8,owner text)
ret int = ob_frefuse_draft(draft_id int8,owner text)
err int = ob_fdelete_bid(bid_id int8)
ob_fstats() RETURNS SETOF ob_tret_stats
------------------------------------------------------------------------
Calling tree of PUBLIC
------------------------------------------------------------------------
ob_fbatch_omega
	ob_fread_omega
		ob_finsert_omega
			ob_finsert_omega_int
		ob_fdelete_bid_int	
			ob_frefuse_draft_int
				ob_fread_status_draft
				ob_fupdate_status_commits
			ob_fremove_das

ob_finsert_sbid
	ob_finsert_bid_int
		ob_getdraft_get *
		ob_finsert_das
		ob_fomega_draft
		
ob_finsert_bid
	ob_finsert_das
	ob_finsert_bid_int
		ob_getdraft_get *
		ob_finsert_das
		ob_fomega_draft

ob_faccept_draft
	ob_fread_status_draft
	ob_fupdate_status_commits
	ob_fexecute_draft
		ob_fexecute_commit
		
ob_frefuse_draft
	ob_fread_status_draft
	ob_fupdate_status_commits

ob_fadd_account
	ob_fadd_account_int
	
ob_fsub_account
	ob_fadd_account_int

ob_fexecute_draft
	ob_fexecute_commit

ob_fstats
	ob_fread_status_draft

 the name of a depositary is a user name.
the role rdepositary has read access on ob_tmvt,ob_tstock
and can execute ob_fadd_account

error codes are 'OBxxxx' 
************************
-30401	no candidate ob_fread_omega(nr,nf)
-30402	the quality.id was not found
-30403	the bid.id was not found
-30404	the account  was not found or not big enough or it's quality not owned by user
-30405	the quality.name was not found
-30406	omega should be >=0
-30407	the pivot was not found
-30408	the stock is not big ebough
-30409	the stock.id is not found
-30410	commit.id sequence is not 0..N
-30411		the draft is outdated
-30412	the owner.name is not found
-30413	The quality does not exist or is not owned by user
-30414	the qtt sould be >0
-30415	qttprovided is <=0
-30416	No stock of this draft is both owned by owner and of a quality owned by user
-30417	The owner is not partner of the Draft
-30418	Less than 2 commit found for the draft
-30419	The draft status is corrupted
-30420	the draft.id was not found
-30421	The owner.name does not exist
-30422	The draft has a status that does not allow the transition to this status
-30423	Abort in bid removal	(unused)
-30424	The stock of a quality owned by user is not found
-30425	the stock sid_dst was not found for the draft
-30426	the stock has the wrong type
-30427	the stock could not be inserted
-30428	The draft % has less than two commits
-30429	for commit % the stock % was not found
-30430	the type of the stock should be S or D and qtt > 0
-30431	The draft % has less than two commits
-30432	The quality % already exists for market
-30433	The quality % overflows
-30434	The quality % underflows
-30435	Cannot delete the draft
-30436	Cannot delete the draft
-30437	StockD % for the draft % not found
-30438  Internal Error

-30100 to -30299 internal error
	-30144 loopOnOffer
-30800 to -30999 BerkeleyDb error
-30400 to -30499 psql error

*/
-------------------------------------------------------------------------------------------------------------------
create or replace function ob_getdraft_get(int8,double precision,int8,int8) returns setof ob_tldraft
	as '$libdir/openbarter','ob_getdraft_get' language C strict;
/*
create or replace function ob_getdraft_get(int8,double precision,int8,int8) returns setof ob_tldraft
	as '$libdir/openbarter','ob_appel_from_master' language C strict;
*/
----------------------------------------------------------------------------------------------------------------
-- ob_fcreate_quality
----------------------------------------------------------------------------------------------------------------
-- PUBLIC
/* usage: 
	ob_fcreate_quality(_owner text,_name text)
		the market should call ob_fcreate_quality('owner>qualityName')
		a depositary should call ob_fcreate_quality('qualityName')
	
	returns 0 or 
		[-30432] The quality already exists
*/
----------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ob_fcreate_quality(_name text) RETURNS int AS $$
DECLARE 
	_q 	ob_tquality%rowtype;
	_n	text;
BEGIN
	_n := user || '>' || _name;
	SELECT q.* INTO _q FROM ob_tquality q WHERE q.name=_n and q.own=user LIMIT 1;
	IF NOT FOUND THEN
		INSERT INTO ob_tquality(name,own,qtt) VALUES (_n,user,0) RETURNING * INTO _q;
	ELSE
		RAISE NOTICE '[-30432] The quality % already exists',_n;
		RETURN -30432;
	END IF;
	RETURN 0;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION ob_fcreate_quality(_name text) TO market,depositary;
----------------------------------------------------------------------------------------------------------------
-- ob_fupdate_status_commits
----------------------------------------------------------------------------------------------------------------
-- PRIVATE called by ob_faccept_draft() and ob_frefuse_draft() to update flags of commits 
/* usage: 
	cnt_updated int = ob_fupdate_status_commits(draft_id int8,own_id int8,_flags int4,mask int4)
	
	updates flags of commits of a draft for a given owner with _flags and mask
	or error -30416,-30417; then, commits remain unchanged:
*/
----------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ob_fupdate_status_commits(draft_id int8,own_id int8,_flags int4,mask int4) RETURNS int AS $$
DECLARE 
	_commot ob_tcommit%rowtype;
	cnt		int := 0;
	own_name	text;
BEGIN
	SELECT count(c.id) INTO cnt FROM ob_tcommit c
		INNER JOIN ob_tstock s on (c.sid_src=s.id)
	 	INNER JOIN ob_tquality q ON (q.id=s.nf)
	WHERE c.did=draft_id AND q.own = user;
	IF cnt=0 THEN
		RAISE NOTICE '[-30416] No stock of the draft % is both owned by % and of a quality owned by user',draft_id,own_id;
		RETURN -30416;
	END IF; 
	cnt := 0;
	<<UPDATE_STATUS>>
	FOR _commot IN SELECT * FROM ob_tcommit WHERE did = draft_id AND wid = own_id LOOP 
		UPDATE ob_tcommit SET flags = (_flags & mask) |(flags & (~mask)) WHERE  id = _commot.id;
		cnt := cnt +1;
	END LOOP UPDATE_STATUS;
	if(cnt =0) THEN 
		SELECT name INTO own_name FROM ob_towner WHERE id=own_id;
		RAISE NOTICE '[-30417] The owner % is not partner of the Draft %',own_name,draft_id;
		RETURN -30417;
	END IF;
	RETURN cnt;
END;
$$ LANGUAGE plpgsql;
----------------------------------------------------------------------------------------------------------------
-- ob_fread_status_draft
----------------------------------------------------------------------------------------------------------------
-- PRIVATE  used by ob_faccept_draft,ob_frefuse_draft,ob_fstats
/* usage: 
	ret int = ob_fread_status_draft(draft ob_tdraft)
	
conditions:
	draft_id exists
	the status of draft is normal
	
returns:
	2	Cancelled
	1	Accepted
	0	Draft
	-30418,-30419	error

*/
----------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION ob_fread_status_draft(draft ob_tdraft) RETURNS int AS $$
DECLARE
	_commot	ob_tcommit%rowtype;
	cnt		int := 0;
	_andflags	int4 := ~0;
	_orflags	int4 := 0;
	expected	char;
BEGIN	-- 
	SELECT bit_and(flags),bit_or(flags),count(id) INTO _andflags,_orflags,cnt FROM ob_tcommit WHERE did = draft.id;
	IF(cnt <2) THEN
		RAISE NOTICE '[-30418] Less than 2 commit found for the draft %',draft.id;
		RETURN -30418;
	END IF;
	expected := 'D';
	IF(_orflags & 2 = 2) THEN -- one _commot.flags[1] set 
		expected := 'C';
	ELSE
		IF(_andflags & 1 = 1) THEN -- all _commot.flags[0] set
			expected :='A';
		END IF;
	END IF;
	IF(draft.status != expected) THEN
		RAISE NOTICE '[-30419] the status of the draft % should be % instead of %',draft.id,expected,draft.status;
		RETURN -30419;
	END IF;
	IF(draft.status = 'D') THEN
		RETURN 0;
	ELSIF (draft.status = 'A') THEN
		RETURN 1;
	ELSIF (draft.status = 'C') THEN
		RETURN 2;
	END IF;
	RAISE NOTICE '[-30419] the draft % has an illegal status %',draft.id,draft.status;
	RETURN -30419;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------------------------------------------------
-- ob_fstats
----------------------------------------------------------------------------------------------------------------
-- PUBLIC
/* usage:
	ret ob_fstats = ob_fstats()


	returns a list of ob_tret_stats
*/
----------------------------------------------------------------------------------------------------------------
DROP TYPE IF EXISTS ob_tret_stats CASCADE;
CREATE TYPE ob_tret_stats AS (

	mean_time_drafts int8, -- mean of delay for every drafts
	
	nb_drafts		int8,
	nb_drafts_c	int8,
	nb_drafts_d	int8,
	nb_drafts_a	int8,
	nb_noeuds		int8,
	nb_stocks		int8,
	nb_stocks_s	int8,
	nb_stocks_d	int8,
	nb_stocks_a	int8,
	nb_qualities 	int8,
	nb_owners		int8,

	
	-- should be all 0
	
	unbananced_qualities 	int8,
	corrupted_draft		int8,
	corrupted_stock_s	int8,
	corrupted_stock_a	int8,
	
	created timestamp
);
DROP FUNCTION IF EXISTS ob_fstats();
CREATE FUNCTION ob_fstats() RETURNS ob_tret_stats AS $$
DECLARE
	ret ob_tret_stats%rowtype;
	delays int8;
	cnt int8;
	err int8;
	_draft ob_tdraft%rowtype;
	res int;
BEGIN
	ret.created := statement_timestamp();
	
	-- mean time of draft
	SELECT SUM(delay),count(*) INTO delays,cnt FROM ob_tdraft;
	ret.nb_drafts := cnt;
	ret.mean_time_drafts = delays/cnt;
	
	SELECT count(*) INTO cnt FROM ob_tnoeud;
	ret.nb_noeuds := cnt;
	SELECT count(*) INTO cnt FROM ob_tstock;
	ret.nb_stocks := cnt;
	SELECT count(*) INTO cnt FROM ob_tstock where type='A';
	ret.nb_stocks_a := cnt;
	SELECT count(*) INTO cnt FROM ob_tstock where type='D';
	ret.nb_stocks_d := cnt;
	SELECT count(*) INTO cnt FROM ob_tstock where type='S';
	ret.nb_stocks_s := cnt;
	SELECT count(*) INTO cnt FROM ob_tquality;
	ret.nb_qualities := cnt;
	SELECT count(*) INTO cnt FROM ob_towner;
	ret.nb_owners := cnt;	

	-- number of unbalanced qualities 
	-- for a given quality:
	-- 	sum(stock_A.qtt)+sum(stock_S.qtt)+sum(stock_D.qtt) = quality.qtt 
	SELECT count(*) INTO cnt FROM (
		SELECT sum(abs(s.qtt)) FROM ob_tstock s,ob_tquality q where s.nf=q.id
		GROUP BY s.nf,q.qtt having (sum(abs(s.qtt))!= q.qtt)
	) as q;
	ret.unbananced_qualities := cnt;
	
	-- number of draft corrupted
	ret.corrupted_draft := 0;
	ret.nb_drafts_d := 0;
	ret.nb_drafts_a := 0;
	ret.nb_drafts_c := 0;
	FOR _draft IN SELECT * FROM ob_tdraft LOOP
		res := ob_fread_status_draft(_draft);
		IF(res < 0) THEN 
			ret.corrupted_draft := ret.corrupted_draft +1;
		ELSIF (res = 0) THEN 
			ret.nb_drafts_d := ret.nb_drafts_d +1;
		ELSIF (res = 1) THEN 
			ret.nb_drafts_a := ret.nb_drafts_a +1;
		ELSIF (res = 2) THEN 
			ret.nb_drafts_c := ret.nb_drafts_c +1;
		END IF;
	END LOOP;
	
	-- stock corrupted
	-- stock_s unrelated to a bid should not exist 
	SELECT count(s.id) INTO err FROM ob_tstock s LEFT JOIN ob_tnoeud n ON n.sid=s.id
	WHERE s.type='S' AND n.id is NULL;
	ret.corrupted_stock_s := err;
	-- Stock_A not unique
	SELECT count(*) INTO err FROM(
		SELECT count(s.id) FROM ob_tstock s WHERE s.type='A'
		GROUP BY s.nf,s.own HAVING count(s.id)>1) as c;
	ret.corrupted_stock_a := err;
	RETURN ret;
END; 
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION ob_fstats() TO market;
-- TODO
----------------------------------------------------------------------------------------------------------------
-- ob_fexecute_commit
----------------------------------------------------------------------------------------------------------------
-- PRIVATE used by ob_fexecute_draft()
/* usage: 
	mvt_id int8 = ob_fexecute_commit(commit_src ob_tcommit,commitsdt ob_tcommit)
		(commit_src,commit_dst) are two successive commits of a draft
		
condition:
	commit_src.sid_dst exists
actions:
	moves commit_src.sid_dst to account[commit_dst.wid,stock[commit_src.sid_dst].nf]
	records the movement
	removes the stock[commit_src.sid_dst]
	
returns:
	the id of the movement
*/
----------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION ob_fexecute_commit(commit_src ob_tcommit,commit_dst ob_tcommit) RETURNS int8 AS $$
DECLARE
	m ob_tstock%rowtype;
	stock_src ob_tstock%rowtype;
	id_mvt int8;
BEGIN
	SELECT s.* INTO stock_src FROM ob_tstock s WHERE s.id = commit_src.sid_dst;
	IF NOT FOUND THEN
		RAISE NOTICE '[-30429] for commit % the stock % was not found',commit_src.id,commit_src.sid_dst;  
		RETURN -30429;
	END IF;
	SELECT s.* INTO m FROM ob_tstock s WHERE s.own = commit_dst.wid AND s.nf = stock_src.nf AND s.type = 'A' LIMIT 1;
	IF NOT FOUND THEN
		INSERT INTO ob_tstock (own,qtt,nf,type) VALUES (commit_dst.wid,stock_src.qtt,stock_src.nf,'A') RETURNING * INTO m;
	ELSE
		UPDATE ob_tstock SET qtt = qtt + stock_src.qtt WHERE id = m.id RETURNING * INTO m;
	END IF;

	INSERT INTO ob_tmvt (own_src,own_dst,qtt,nat) 
		VALUES (commit_src.wid,commit_dst.wid,stock_src.qtt,stock_src.nf) 
		RETURNING id INTO id_mvt;
	-- did is NOT set, it is at the end of the execute_draft to the first mvt_id for all commits of the draft	
	-- delete stock is useless since the draft is deleted just after execution, in ob_faccept_draft() by ob_fdelete_draft()
	-- DELETE FROM ob_tstock WHERE id=stock_src.id;
	RETURN id_mvt;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------------------------------------------------
-- ob_fexecute_draft
----------------------------------------------------------------------------------------------------------------
-- PRIVATE called by ob_faccept_draft() when the draft should be executed 
/* usage: 
	cnt_commit integer = ob_fexecute_draft(draft_id int8)
action:
	execute ob_fexecute_commit(commit_src,commit_dst) for successive commits
*/
----------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION ob_fexecute_draft(draft_id int8) RETURNS int AS $$
DECLARE
	prev_commit	ob_tcommit%rowtype;
	first_commit	ob_tcommit%rowtype;
	first_mvt_id	int8;
	_commot		ob_tcommit%rowtype;
	cnt		int;
	mvt_id	int8;
BEGIN
	cnt := 0;
	FOR _commot IN SELECT * FROM ob_tcommit WHERE did = draft_id  ORDER BY id ASC LOOP
		IF (cnt = 0) THEN
			first_commit := _commot;
		ELSE
			mvt_id := ob_fexecute_commit(prev_commit,_commot);
			if(mvt_id < 0) THEN RETURN mvt_id; END IF;
			if(cnt = 1) THEN first_mvt_id := mvt_id; END IF;
		END IF;
		prev_commit := _commot;
		cnt := cnt+1;
	END LOOP;
	IF( cnt <2 ) THEN
		RAISE NOTICE '[-30431] The draft % has less than two commits',draft_id;
		RETURN -30431;
	END IF;
	
	mvt_id := ob_fexecute_commit(_commot,first_commit);
	if(mvt_id < 0) THEN  RETURN mvt_id; END IF;
	-- sets did of movements to the first mvt.id
	UPDATE ob_tmvt set did=first_mvt_id where id>= first_mvt_id and id <= mvt_id;
	RETURN cnt;
END;
$$ LANGUAGE plpgsql;
----------------------------------------------------------------------------------------------------------------
-- PRIVATE 
----------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ob_finsert_omegap(_nr int8,_nf int8) RETURNS int AS $$
DECLARE
	t		int8;
	namef		text;
	namer		text;

BEGIN
	SELECT o.nf INTO t FROM ob_tomega o WHERE o.nr = _nr and o.nf = _nf;
	IF (NOT FOUND) THEN
		SELECT name INTO namef FROM ob_tquality WHERE id=_nf;
		SELECT name INTO namer FROM ob_tquality WHERE id=_nr;
		INSERT INTO ob_tomega (nr,nf,name) VALUES (_nr,_nf,namer || '/' || namef);
	ELSE
		-- it will be at the last position for candidates for update in ob_fbatch_omega
		UPDATE ob_tomega SET updated=statement_timestamp()  WHERE nr = _nr and nf = _nf;
	END IF;
	RETURN 0;
END; 
$$ LANGUAGE plpgsql;
----------------------------------------------------------------------------------------------------------------
-- PRIVATE called by ob_fomega_draft() while inserting a new bid
-- ret int = ob_finsert_omega_int(sid_src int8,sid_dst int8) used by ob_finsert_omega
-- sid_src,sid_dst are two commit.sid_dst of successive commmits of a draft
----------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ob_finsert_omega_int(sid_src int8,sid_dst int8) RETURNS int AS $$
DECLARE
	_nr		int8;
	_nf		int8;
	_flux_src	int8;
	_flux_dst	int8;
	namef	text;
	namer	text;
	t		int8;
	_flags		int4 :=2;
	ret		int;

BEGIN
	SELECT nf,qtt INTO _nf,_flux_src FROM ob_tstock WHERE id=sid_src;
	IF NOT FOUND THEN
		RAISE NOTICE '[-30409] stock % not found',sid_src;
		RETURN -30409;
	END IF;
	SELECT nf,qtt INTO _nr,_flux_dst FROM ob_tstock WHERE id=sid_dst;
	IF NOT FOUND THEN
		RAISE NOTICE '[-30409] stock % not found',sid_dst;
		RETURN -30409;
	END IF;
	ret := ob_finsert_omegap(_nr,_nf);
	INSERT INTO ob_tlomega(nr,nf,qttr,qttf,flags) VALUES (_nr,_nf,_flux_src,_flux_dst,_flags);
	RETURN 0;
END; 
$$ LANGUAGE plpgsql;
----------------------------------------------------------------------------------------------------------------
-- ob_fomega_draft
----------------------------------------------------------------------------------------------------------------
-- PRIVATE called by ob_finsert_bid_int

/* usage: 
	ret int = ob_fomega_draft(draft_id int8)
		
conditions:
	draft exists with more than 1 commit
action:
	inserts omega for a given draft

*/
----------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ob_fomega_draft(draft_id int8) RETURNS int AS $$
DECLARE
	prev_commit	ob_tcommit%rowtype;
	first_commit	ob_tcommit%rowtype;
	_commot		ob_tcommit%rowtype;
	_flux_src	int8;
	_flux_dst	int8;
	cnt		int;
	err		int; 
BEGIN
	cnt := 0;
	FOR _commot IN SELECT * FROM ob_tcommit WHERE did = draft_id  ORDER BY id ASC LOOP
		IF (cnt = 0) THEN
			first_commit := _commot;
		ELSE
			err := ob_finsert_omega_int(prev_commit.sid_dst,_commot.sid_dst);
			if(err <0) THEN
				RETURN err;
			END IF;
		END IF;
		prev_commit := _commot;
		cnt := cnt+1;
	END LOOP;
	IF( cnt <=1 ) THEN
		RAISE INFO '[-30428] The draft % has less than two commits',draft_id;
		RETURN -30428; 
	END IF;	
	err := ob_finsert_omega_int(_commot.sid_dst,first_commit.sid_dst);
	if(err <0) THEN
		RETURN err;
	END IF;
	RETURN cnt;
END;
$$ LANGUAGE plpgsql;
----------------------------------------------------------------------------------------------------------------
-- ob_finsert_omega
----------------------------------------------------------------------------------------------------------------
-- PRIVATE called by ob_fread_omega(_dnr,_dnf).

/* usage: 
	ret int = ob_finsert_omega(sid_src int8,sid_dst int8,flux_src int8,flux_dst int8,_dnr int8,_dnf int8)
		(_dnf,_dnr) 		is the quality couple which was used to find this draft,
		(*src,*dst)		are two successive commits of a draft.
		
conditions:
	stock.id=sid_src exists
	stock.id=sid_dst exists
action:
	inserts a new lomega from two successive commits of a draft found. 
	the bit 0 of lomega.flags is set when (_dnf,_dnr) == (stock[sid_src].nf,stock[sid_dst].nf)

	primary := ( (_dnf,_dnr) == (stock[sid_src].nf,stock[sid_dst].nf) )
		
	ob_tlomega[_dnf,_dnr] is inserted with flags = primary

*/
----------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION ob_finsert_omega(sid_src int8,sid_dst int8,flux_src int8,flux_dst int8,_dnr int8,_dnf int8) RETURNS int AS $$
DECLARE
	_nr		int8;
	_nf		int8;
	t		int8;
	namef	text;
	namer	text;
	_flags   	int4;
	ret		int;

BEGIN
	IF (sid_src is NULL) THEN _nf = _dnf;
	ELSE
		SELECT nf INTO _nf FROM ob_tstock WHERE id=sid_src;
		IF NOT FOUND THEN
			RAISE NOTICE '[-30409] stock % not found',sid_src;
			RETURN -30409;
		END IF;
	END IF;
	IF (sid_dst is NULL) THEN _nr = _dnr;
	ELSE
		SELECT nf INTO _nr FROM ob_tstock WHERE id=sid_dst;
		IF NOT FOUND THEN
			RAISE NOTICE '[-30409] stock % not found',sid_dst;
			RETURN -30409;
		END IF;
	END IF;

	ret := ob_finsert_omegap(_nr,_nf); -- insert (_nr,_nf) record in ob_tomega
	
	IF(_nr=_dnr AND _nf=_dnf) THEN
		_flags := 1;
	ELSE 
		_flags := 0;
	END IF;
	INSERT INTO ob_tlomega (nr,nf,qttr,qttf,flags) VALUES (_nr,_nf,flux_src,flux_dst,_flags);
	RETURN 0;
END; 
$$ LANGUAGE plpgsql;

---------------------------------------------------------------------------------------------------------------
-- ob_vowned
---------------------------------------------------------------------------------------------------------------
/* List of values owned by users GROUP BY s.own,s.nf,q.name,o.name,q.own 
	view
		returns qtt owned for each (quality,own).
			qown		quality.own
			qname:		quality.name
			owner: 		owner.name
			qtt:		sum(qtt) for this (quality,own)
			created:	min(created)
			updated:	max(updated?updated:created)
	usage:
		SELECT * FROM ob_vowned WHERE owner='toto'
			total values owned by the owner 'toto'
		SELECT * FROM ob_vowned WHERE qown='banquedefrance'
			total values of owners whose qualities are owned by the depositary 'banquedefrance'
*/
---------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW ob_vowned AS SELECT 
		q.own as qown,
		q.name as qname,
		o.name as owner,
		sum(s.qtt) as qtt,
		min(s.created) as created,
		max(CASE WHEN s.updated IS NULL THEN s.created ELSE s.updated END) as updated
    	FROM ob_tstock s INNER JOIN ob_towner o ON (s.own=o.id) INNER JOIN ob_tquality q on (s.nf=q.id) 
	GROUP BY s.own,s.nf,q.name,o.name,q.own ORDER BY q.own ASC,q.name ASC,o.name ASC;
	
GRANT SELECT ON TABLE ob_vowned TO market,depositary;
----------------------------------------------------------------------------------------------------------------
-- ob_vbalance 
----------------------------------------------------------------------------------------------------------------
-- PUBLIC
/* List of values owned by users GROUP BY q.name,q.own
view
	returns sum(qtt)  for each quality.
			qown:		quality.own
			qname:		quality.name
			qtt:		sum(qtt) for this (quality)
			created:	min(created)
			updated:	max(updated?updated:created)
	usage:
	
		SELECT * FROM ob_vbalance WHERE qown='banquedefrance'
			total values owned by the depositary 'banquedefrance'
			
		SELECT * FROM ob_vbalance WHERE qtt != 0 and qown='banquedefrance'
			Is empty if accounting is correct for the depositary
*/
----------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW ob_vbalance AS SELECT 
		q.own as qown,
    		q.name as qname,
		sum(s.qtt) as qtt,
    		min(s.created) as created,
    		max(CASE WHEN s.updated IS NULL THEN s.created ELSE s.updated END)  as updated
    	FROM ob_tstock s INNER JOIN ob_tquality q on (s.nf=q.id)
	GROUP BY q.name,q.own ORDER BY q.own ASC, q.name ASC;
	
GRANT SELECT ON TABLE ob_vbalance TO depositary,market;

----------------------------------------------------------------------------------------------------------------
-- ob_vdraft
----------------------------------------------------------------------------------------------------------------
-- PUBLIC
/* List of draft by owner
view
		returns a list of drafts where the owner is partner.
			did		draft.id		
			status		'D','A' or 'C'
			owner		owner providing the value
			cntcommit	number of commits
			flags		[0] set when accepted by owner
					[1] set when refuse by owner
			created:	timestamp
	usage:
		SELECT * FROM ob_vdraft WHERE owner='toto'
			list of drafts for the owner 'toto'
*/
----------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW ob_vdraft AS 
		SELECT 	
			dr.id as did,
			dr.status as status,
			w.name as owner,
			co.cnt as cntcommit,
			co.flags as flags,
			dr.created as created
		FROM (
			SELECT c.did,c.wid,(bit_or(c.flags)&2)|(bit_and(c.flags)&1) as flags,count(*) as cnt 
			FROM ob_tcommit c GROUP BY c.wid,c.did 
				) AS co 
		INNER JOIN ob_tdraft dr ON co.did = dr.id
		INNER JOIN ob_towner w ON w.id = co.wid
		ORDER BY dr.id ASC;
	
GRANT SELECT ON TABLE ob_vdraft TO depositary,market;
----------------------------------------------------------------------------------------------------------------
-- ob_vbid
----------------------------------------------------------------------------------------------------------------
-- PUBLIC
/* List of bids
view
		returns a list of bids.
			id			noeud.id		
			owner			w.owner
			required_quality
			required quantity
			omega
			provided quality
			provided_quantity
			sid
			qtt
			created	
	usage:
		SELECT * FROM ob_vbid WHERE owner='toto'
			list of bids of the owner 'toto'
*/
----------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW ob_vbid AS 
	SELECT 	
		n.id as id,
		w.name as owner,
		qr.name as required_quality,
		n.required_quantity as required_quantity,
		CAST(n.provided_quantity as double precision)/CAST(n.required_quantity as double precision) as omega,
		qf.name as provided_quality,
		n.provided_quantity as provided_quantity,
		s.id as sid,
		s.qtt as qtt,
		n.created as created
	FROM ob_tnoeud n
	INNER JOIN ob_tquality qr ON n.nr = qr.id 
	INNER JOIN ob_tstock s ON n.sid = s.id
	INNER JOIN ob_tquality qf ON s.nf =qf.id
	INNER JOIN ob_towner w on s.own = w.id
	ORDER BY n.created DESC;
	
GRANT SELECT ON TABLE ob_vbid TO depositary,market;
----------------------------------------------------------------------------------------------------------------
-- ob_vmvt R
----------------------------------------------------------------------------------------------------------------
-- view PUBLIC
/* 
		returns a list of movements related to the owner.
			id		ob_tmvt.id
			did:		NULL for a movement made by ob_fadd_account()
					not NULL for a draft executed, even if it has been deleted.
			provider
			nat:		quality.name moved
			qtt:		quantity moved, 
			receiver
			created:	timestamp

*/
----------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW ob_vmvt AS 
	SELECT 	m.id as id,
		m.did as did,
		w_src.name as provider,
		q.name as nat,
		m.qtt as qtt,
		w_dst.name as receiver,
		m.created as created
	FROM ob_tmvt m
	INNER JOIN ob_towner w_src ON (m.own_src=w_src.id)
	INNER JOIN ob_towner w_dst ON (m.own_dst=w_dst.id) 
	INNER JOIN ob_tquality q ON (m.nat = q.id);
	
GRANT SELECT ON TABLE ob_vmvt TO depositary,market;

----------------------------------------------------------------------------------------------------------------
-- ob_fadd_account 
-- PUBLIC
/* usage:
	ret int = ob_fadd_account(owner text,quality text,_qtt int8)
	
	conditions:
		quality  exist,
		_qtt >=0
		
	actions:
		owner is created is it does not exist
		moves qtt from 	market_account[nat]		->	owners_account[own,nat]
		accounts are created when they do not exist
		the movement is recorded.
			
	returns 0 when done correctly
*/
----------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ob_fadd_account(_owner text,_quality text,_qtt int8) RETURNS int AS $$
DECLARE
	_wid int8;
	_nf int8;
	_qtt_quality int8;
	_new_qtt_quality int8;
	mvt ob_tmvt%rowtype;
	acc ob_tstock%rowtype;
	err	int :=0;
BEGIN
	SELECT id,qtt INTO _nf,_qtt_quality FROM ob_tquality WHERE name = (user || '>' || _quality);
	IF NOT FOUND THEN 
		err := -30405;
		RAISE EXCEPTION '[-30405]The quality % does not exist or is not yours',_quality   USING ERRCODE='38000';
	END IF;
	IF (_qtt <= 0) THEN
		err := -30414;
		RAISE EXCEPTION '[-30414] the quantity cannot be negative or null'   USING ERRCODE='38000';
	END IF;
	BEGIN
		INSERT INTO ob_towner (name) VALUES ( _owner) RETURNING id INTO _wid;
	EXCEPTION WHEN unique_violation THEN 
	END;
	SELECT id INTO _wid from ob_towner where name=_owner;

	UPDATE ob_tquality SET qtt = qtt + _qtt where id= _nf RETURNING qtt INTO _new_qtt_quality;
	IF (_qtt_quality >= _new_qtt_quality ) THEN 
		err := -30433;
		RAISE EXCEPTION '[-30433] Quality % owerflows',_quality   USING ERRCODE='38000';
	END IF;
	
	-- foreign keys of quality and owner protects form insertion of unknown keys
	UPDATE ob_tstock SET qtt = qtt+_qtt  WHERE own=_wid AND nf=_nf AND type='A' RETURNING * INTO acc;
	IF NOT FOUND THEN
		INSERT INTO ob_tstock (own,qtt,nf,type) VALUES (_wid,_qtt,_nf,'A') RETURNING * INTO acc;
	END IF;
	INSERT INTO ob_tmvt (own_src,own_dst,qtt,nat) 
		VALUES (1,acc.own, _qtt,acc.nf) RETURNING * INTO mvt;
	RETURN 0;
END; 
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION ob_fadd_account(_owner text,_quality text,_qtt int8) TO market,depositary;
----------------------------------------------------------------------------------------------------------------
-- ob_fsub_account R
-- PUBLIC
/* usage:
	ret int = ob_fsub_account(_owner text,_quality text,_qtt int8)
	
	conditions:
		owner and quality  exist,
		_qtt >=0
		
	actions:
		moves qtt from 	market_account[nat]		<-	owners_account[own,nat]
		account are deleted when empty
		the movement is recorded.
			
	returns 0 when done correctly
*/
----------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ob_fsub_account(_owner text,_quality text,_qtt int8) RETURNS int AS $$
DECLARE
	_wid int8;
	_nf int8;
	_qtt_quality int8;
	acc ob_tstock%rowtype;
	mar ob_tstock%rowtype;
	mvt ob_tmvt%rowtype;
BEGIN
	SELECT id INTO _wid FROM ob_towner WHERE name=_owner;
	IF (NOT FOUND) THEN 
		RAISE EXCEPTION '[-30412] The owner % does not exist',owner;
	END IF;
	SELECT id INTO _nf FROM ob_tquality WHERE name=(user || '>' || _quality);
	IF (NOT FOUND) THEN 
		RAISE EXCEPTION '[-30413] The quality % does not exist or is not deposited by user',_quality   USING ERRCODE='38000';
	END IF;
	IF (_qtt <= 0) THEN
		RAISE EXCEPTION '[-30414] the quantity cannot be negative or null'  USING ERRCODE='38000';
	END IF;

	-- foreign keys of quality and owner protects form insertion of unknown keys
	SELECT s.* INTO acc FROM ob_tstock s WHERE s.own=_wid AND s.nf=_nf AND s.type='A' LIMIT 1;
	IF NOT FOUND THEN
		RAISE EXCEPTION '[-30404] the account is empty'  USING ERRCODE='38000';
	END IF;

	UPDATE ob_tstock SET qtt = qtt-_qtt WHERE id = acc.id RETURNING * INTO acc;
	IF(acc.qtt < 0) THEN
		RAISE EXCEPTION '[-30404] the account is not big enough'  USING ERRCODE='38000';	
	END IF;	
		
	UPDATE ob_tquality SET qtt = qtt - _qtt where id=acc.nf RETURNING qtt INTO _qtt_quality;
	IF (_qtt_quality < 0) THEN
		RAISE EXCEPTION '[-30434] the quality % underflows ',_quality  USING ERRCODE='38000';
	END IF;	
	
	INSERT INTO ob_tmvt (own_src,own_dst,qtt,nat) 
		VALUES (acc.own,1,_qtt,acc.nf) RETURNING * INTO mvt;

	IF(acc.qtt = 0) THEN 
		DELETE FROM ob_tstock WHERE id=acc.id;
	END IF;

	RETURN 0;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION ob_fsub_account(_owner text,_quality text,_qtt int8) TO market,depositary;
----------------------------------------------------------------------------------------------------------------
-- ob_fremove_das
----------------------------------------------------------------------------------------------------------------
-- PRIVATE called by ob_fdelete_bid
/* usage:
	mvt ob_tlmvt = ob_fremove_das(id_src int8)
	
	conditions:
		stock.id=id_src exists, it is a stock (type S)
		
	actions;
		for the stock stock.id=id_src
			stock.qtt -> account[own,nat]
		the stock is deleted
		the movement is NOT recorded (the owner is unchanged) but
	
	returns the movement with mvt.id=ret
	ret <0 if error
*/
----------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ob_fremove_das(id_src int8) RETURNS ob_tlmvt AS $$
DECLARE
	id_dst int8;
	stock ob_tstock%rowtype;
	id_mvt int8;
	mvt ob_tlmvt%rowtype;
BEGIN
	mvt.id := 0;
	SELECT s.* INTO stock FROM ob_tstock s WHERE s.id=id_src and s.type='S';
	IF NOT FOUND THEN 
		RAISE NOTICE '[-30409] the stock % with type S was not found',id_src;
		mvt.id = -30409;
		RETURN mvt;
	END IF;
	SELECT id INTO id_dst FROM ob_tstock s WHERE s.own=stock.own AND s.nf=stock.nf AND s.type='A' LIMIT 1;
	IF NOT FOUND THEN
		INSERT INTO ob_tstock (own,qtt,nf,type) VALUES (stock.own,stock.qtt,stock.nf,'A') RETURNING id INTO id_dst;
	ELSE 
		UPDATE ob_tstock SET qtt=qtt+stock.qtt WHERE id=id_dst;
	END IF;

	mvt.src := id_src;mvt.own_src := stock.own;
	mvt.dst := id_dst;mvt.own_dst := stock.own;
	mvt.qtt := stock.qtt;  mvt.nat := stock.nf;

	DELETE FROM ob_tstock WHERE id=id_src;	
	RETURN mvt;
END; 
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------------------------------------------------
-- ob_finsert_das
----------------------------------------------------------------------------------------------------------------
-- PRIVATE
--	used by ob_finsert_bid and ob_finsert_bid_int
/* usage:
	mvt ob_tlmvt = ob_finsert_das(stock_src ob_tstock,_qtt bigint,_type char)
		creates a stock of type=_type 
		returns the movement
	conditions:
		_type is S or D
		_qtt >0
		the stock_src stock_src.id=id_src exists, 
		stock_src.type=A or S
		stock_src.qtt >= _qtt
		
	actions;
		for the stock_src stock_src.id=id_src
			qtt moved from stock_src[id_src]-> NEW stock
		the stock_src is NOT deleted if qtt=0
		the movement is NOT recorded (the owner is unchanged)
	
	returns the movement
	or an exception
*/
----------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ob_finsert_das(stock ob_tstock,_qtt bigint,_type char) RETURNS ob_tlmvt AS $$
DECLARE
	id_dst int8;
	id_mvt int8;
	mvt ob_tlmvt%rowtype;
	_owned	bool;
BEGIN
	mvt.id := 0;
	IF stock.type='D' THEN
		RAISE LOG '[-30426] the stock[%].type should be A or S',stock.id;
		mvt.id := -30426;
		RETURN mvt;
	END IF;
	IF NOT (_type IN('D','S') AND (_qtt >0)) THEN
		RAISE  LOG '[-30430] the _type=% should be S or D and qtt > 0',_type;
		mvt.id := -30430;
		RETURN mvt;
	END IF;
	IF (stock.qtt < _qtt) THEN
		RAISE LOG '[-30408] the stock % has qtt=%,it is not big enough for % ',stock.id,stock.qtt,_qtt;
		mvt.id := -30408;
		RETURN mvt;
	END IF;	
	--------------------------------------------------------------------------------------------------------
	INSERT INTO ob_tstock (own,nf,qtt,type) VALUES (stock.own,stock.nf,_qtt,_type) RETURNING id INTO id_dst;
	IF NOT FOUND THEN
		RAISE LOG '[-30427] the stock could not be inserted'; 
		mvt.id := -30427;
		return mvt;
	END IF;

	UPDATE ob_tstock set qtt = stock.qtt - _qtt where id = stock.id;
	--TODO  when the stock is empty where is it removed?
	mvt.id := 0;
	mvt.src := stock.id;mvt.own_src := stock.own;
	mvt.dst := id_dst;mvt.own_dst := stock.own;
	mvt.qtt := _qtt;  mvt.nat := stock.nf;
	RETURN mvt;
END; 
$$ LANGUAGE plpgsql;
----------------------------------------------------------------------------------------------------------------
-- ob_fdelete_bid
----------------------------------------------------------------------------------------------------------------
-- PUBLIC 
/* usage: 
	err int = ob_fdelete_bid(bid_id int8)
	
	delete bid and related drafts
	delete related stock if it is not related to an other bid
		(in this case, the stock is not referenced by any draft). The quantity of this stock is moved back to the account.
	
	A given stock is deleted by the ob_fdelete_bid of the last bid it references.
*/
----------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ob_fdelete_bid(bid_id int8) RETURNS int AS $$
DECLARE
	ret		int;
BEGIN
	START TRANSACTION;
	ret := ob_fdelete_bid_int(bid_id);
	IF(ret <0) THEN ROLLBACK; 
	ELSE COMMIT; END IF;
	RETURN 0;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION  ob_fdelete_bid(bid_id int8) TO market;
----------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ob_fdelete_bid_int(bid_id int8) RETURNS int AS $$
DECLARE
	noeud		ob_tnoeud%rowtype;
	_commot		ob_tcommit%rowtype;
	quality		text;
	mvt		ob_tlmvt%rowtype;
	cnt		int;
	ret		int;
	draft_id	int8;
BEGIN
	SELECT n.* INTO noeud FROM ob_tnoeud n WHERE n.id=bid_id;
	IF NOT FOUND THEN
		RAISE NOTICE '[-30403]the noeud % was not found',bid_id ;
		RETURN -30403;
	END IF;
	-- verifies the user owns the quality offered
	SELECT q.name INTO quality FROM ob_tstock s INNER JOIN ob_tquality q on (q.id=s.nf) 
		WHERE s.id=noeud.sid and q.own =user ;
	IF NOT FOUND THEN 
		RAISE INFO '[-30413] The quality % does not exist or is not owned by user',quality;
		RETURN -30413;
	END IF;

	FOR draft_id IN SELECT c.did FROM ob_tcommit c INNER JOIN ob_tdraft d ON (d.id=c.did)
		WHERE c.bid = bid_id and d.status='D' GROUP BY c.did LOOP
		
		-- more than one commit can be found, but only one is enough to refuse the draft
		SELECT c.* INTO _commot FROM ob_tcommit c WHERE c.did=draft_id LIMIT 1;
		ret := ob_frefuse_draft_int(_commot.did,_commot.wid);
		IF (ret < 0 ) THEN
			RAISE INFO '[%] Abort in ob_frefuse_draft_int(%,%)',ret,_commot.did,_commot.wid;
			RETURN ret;
		END IF;
		
	END LOOP;
	
	-- no draft reference this bid
	DELETE FROM ob_tnoeud WHERE id=bid_id;
	-- the stock S is deleted if no other bid reference it.
	SELECT count(id) INTO cnt FROM ob_tnoeud WHERE sid=noeud.sid;
	if(cnt =0) THEN 
		mvt := ob_fremove_das(noeud.sid); -- the stock is removed and qtt goes back to the account
		IF (mvt.id < 0) THEN 
			RAISE INFO '[%] ob_fremoved_das(%) failed',mvt.id,noeud.sid;
			RETURN mvt.id;
		END IF;
	END IF;
	RETURN 0;
END;
$$ LANGUAGE plpgsql;
----------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ob_fdelete_draft(draft_id int8) RETURNS int AS $$
DECLARE
	_commot	ob_tcommit%rowtype;
	_stock ob_tstock%rowtype;
	_cnt integer;
	_qtt int8;
BEGIN
	-- empty stocks sid_src and sid_dst are deleted
	FOR _commot IN SELECT * from ob_tcommit WHERE did = draft_id LOOP
		
		SELECT qtt INTO _qtt FROM ob_tstock WHERE id = _commot.sid_dst AND TYPE='D';
		IF(NOT FOUND OR (_qtt != 0)) THEN
			RAISE INFO '[-30435] cannot delete the draft %',draft_id;
			RETURN -30435;
		END IF;
		-- a stock sid_dst is always referenced by a single commit
		UPDATE ob_tcommit SET sid_dst=NULL,bid=NULL where id=_commot.id;
		DELETE FROM ob_tstock WHERE id=_commot.sid_dst;
		-- this stock is D; it is not related to ob_tnoeud
			
		-- Several draft can refer to the same stockS, and the stockS can be non empty
		SELECT count(c.did) INTO _cnt FROM ob_tcommit c INNER JOIN ob_tstock s ON (c.sid_src=s.id) 
			WHERE s.qtt=0 AND _commot.sid_src=s.id; 
		IF (_cnt=1) THEN
			UPDATE ob_tcommit SET sid_src=NULL,bid=NULL where id=_commot.id;
			DELETE FROM ob_tstock WHERE id=_commot.sid_src;
			-- ob_tnoeud deleted by cascade
		-- ELSE other draft refers to the same stock, we must keep it even if it is empty
		END IF;
	END LOOP;
	
	DELETE FROM ob_tdraft d where d.id=draft_id;
	-- ob_tcommit deleted by cascade
	RETURN 0;
END;
$$ LANGUAGE plpgsql;
----------------------------------------------------------------------------------------------------------------
-- ob_faccept_draft
----------------------------------------------------------------------------------------------------------------
-- PUBLIC 
/* usage: 
	ret int = ob_faccept_draft(draft_id int8,owner text)
		own_id
		draft_id
conditions:
	draft_id exists with status D

returns a char:
		0 the draft is not yet accepted, 
		1 the draft is executed,
		< 0 error
*/
----------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION ob_faccept_draft(draft_id int8,owner text) RETURNS int AS $$
DECLARE
	draft 		ob_tdraft%rowtype;
	_commot	ob_tcommit%rowtype;
	accepted	int4; -- 1 when accepted by others
	_nbcommit	int :=0;
	ownfound	bool := false;
	d_status	char;
	res 		int;
	own_id		int8;
BEGIN
	START TRANSACTION;
	SELECT d.* INTO draft FROM ob_tdraft d WHERE d.id=draft_id;
	IF NOT FOUND THEN
		RAISE INFO '[-30420] the draft % was not found',draft_id;
		ROLLBACK;
		RETURN -30420;
	END IF;
	SELECT id INTO own_id FROM ob_towner WHERE name=owner;
	IF NOT FOUND THEN
		RAISE INFO '[-30421] The owner % does not exist',owner;
		ROLLBACK;
		RETURN -30421;
	END IF;
	res := ob_fread_status_draft(draft);
	-- res=0 means it is a draft
	IF (res <0) THEN
		ROLLBACK;
		RETURN res;
	END IF;
	IF((NOT(draft.status = 'D')) OR res!=0 ) THEN 
		RAISE INFO '[-30422] The draft % has a status %, whith res=%',draft.id,draft.status,res;
		ROLLBACK;
		RETURN -30422;
	END IF;	

	SELECT bit_and(flags&1) INTO accepted FROM ob_tcommit WHERE did = draft_id AND wid!=own_id;
	-- accepted=1 when is it accepted by others
	
	------------- update status of commits ------------	
	res := ob_fupdate_status_commits(draft_id,own_id,1,3);
	IF (res < 0 ) THEN -- the owner was not found, draft unmodified
		ROLLBACK;
		RETURN res; 
	END IF;
	
	------------- execute ---------------------------
	--    RAISE INFO 'accepted by others %',accepted;
	if(accepted = 1) THEN
		res := ob_fexecute_draft(draft_id);
		IF (res<0) THEN ROLLBACK;RETURN res; END IF;
		-- the draft is now empty, it can be deleted
		res := ob_fdelete_draft(draft_id);
		IF (res<0) THEN ROLLBACK;RETURN res; END IF;
	END IF;

	COMMIT;
	RETURN 0;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION ob_faccept_draft(draft_id int8,owner text) TO market;

----------------------------------------------------------------------------------------------------------------
-- ob_frefuse_draft
----------------------------------------------------------------------------------------------------------------
-- PUBLIC 
/* usage: 
	ret int = ob_frefuse_draft(draft_id int8,owner text)
		own_id
		draft_id
	quantities are stored back into the stock S
	A ret is returned.
		1 the draft is cancelled
		<0 error

*/
----------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION ob_frefuse_draft(draft_id int8,owner text) RETURNS int AS $$
DECLARE
	own_id	int8;
	res	int;
BEGIN
	START TRANSACTION;
	SELECT id INTO own_id FROM ob_towner WHERE name=owner;
	IF NOT FOUND THEN
		RAISE INFO '[-30421] The owner % does not exist',owner;
		ROLLBACK;
		RETURN -30421;
	END IF;
	res := ob_frefuse_draft_int(draft_id,own_id);
	IF(res <0) THEN ROLLBACK; 
	ELSE COMMIT;
	END IF;
	RETURN res;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION ob_frefuse_draft(draft_id int8,owner text) TO market;

-- PRIVATE
----------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ob_frefuse_draft_int(draft_id int8,own_id int8) RETURNS int as $$
DECLARE
	draft 		ob_tdraft%rowtype;
	_commot	ob_tcommit%rowtype;
	res		int;
	_qtt		int8;
	stock		ob_tstock%rowtype;

BEGIN
	SELECT d.* INTO draft FROM ob_tdraft d WHERE d.id=draft_id;
	IF NOT FOUND THEN
		RAISE INFO '[-30420] the draft % was not found',draft_id ;
		RETURN -30420;
	END IF;

	------------- controls --------------------------
	res := ob_fread_status_draft(draft);
	IF(res < 0) THEN --draft status corrupted
		RETURN res;
	END IF;
	
	IF ((NOT(draft.status = 'D')) OR res!=0) THEN 
		RAISE INFO '[-30422] tried to refuse the draft % with the status % and res=%',draft_id,draft.status,res ;
		RETURN -30422;
	END IF;
	
	res := ob_fupdate_status_commits(draft_id,own_id,2,2); -- flags,mask
	IF (res < 0) THEN -- the owner was not found
		RETURN res;
	END IF;
	
	------------- refuse  ---------------------------------
	FOR _commot IN SELECT * FROM ob_tcommit WHERE did = draft_id LOOP
		-- commit.sid_src <- commit.sid_dst
		SELECT qtt INTO _qtt FROM ob_tstock WHERE id=_commot.sid_dst; 
		IF (NOT FOUND) THEN 
			RAISE INFO '[-30437] stockD % of draft % not found',_commot.sid_dst,draft_id;
			RETURN -30437;
		END IF;
		UPDATE ob_tstock SET qtt = qtt-_qtt WHERE id=_commot.sid_dst; -- becomes empty
		UPDATE ob_tstock SET qtt = qtt+_qtt WHERE id=_commot.sid_src;
			
	END LOOP;
	------------- delete draft ---------------------------
	res := ob_fdelete_draft(draft_id); -- stock_dst are empty
	 
	RETURN res;
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------------------------------------------------
-- ob_finsert_bid_int
----------------------------------------------------------------------------------------------------------------
-- PRIVATE used by ob_finsert_bid and ob_finsert_sbid
/* usage: 
	nb_draft int8 = ob_finsert_bid_int(_sid int8,_qttprovided int8,_qttrequired int8,_qualityrequired text)

	conditions:
		the pivot stock.id=_sid exists.
		_omega > 0
		_qualityrequired exists
		
	action:
		tries to insert a bid with the stock _sid.
	
	returns nb_draft:
		the number of draft inserted.
		when nb_draft == -1, the insert was aborted after 3 retry
		nb_draft == -6 the pivot was not found
		-30403 qualityrequired not found
		-30406 omega <=0
		-30407 the pivot was not found or not deposited to user
*/
----------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ob_finsert_bid_int(_sid int8,_qttprovided int8,_qttrequired int8,_qualityrequired text) RETURNS int4 AS $$
DECLARE
	cnt int;
	draft_id int8;
	commit_id int8;
	i	int8;
	r ob_tldraft%rowtype;
	stockb ob_tstock%rowtype;
	pivot ob_tstock%rowtype;
	mvt ob_tlmvt%rowtype;
	acc_id int8;
	version_cur int8;
	err int4;
	_err int4;
	first_commit int8;
	first_draft int8;
	_commot ob_tcommit%rowtype;
	time_begin timestamp;
	delai	int8;
	_nr	int8;
	_omega double precision;
	cnt2	int;
	_delay  int4;
	new_noeud_id int8;
BEGIN
	-- controls
	SELECT q.id INTO _nr FROM ob_tquality q WHERE q.name = _qualityrequired;
	IF NOT FOUND THEN
		RAISE NOTICE '[-30405] the quality % was not found',_qualityrequired;
		RETURN -30405;
	END IF;

	SELECT s.* INTO pivot FROM ob_tstock s WHERE s.id = _sid and s.type='S';
	IF NOT FOUND THEN
		RAISE NOTICE '[-30407] the pivot % was not found',_sid;
		RETURN -30407;
	END IF;
	IF(_qttrequired <= 0 ) THEN
		RAISE NOTICE '[-30414] _qttrequired % should be > 0',_qttrequired;
		RETURN -30414;
	END IF;
	IF(_qttprovided <= 0 ) THEN
		RAISE NOTICE '[-30415] _qttrprovided % should be > 0',_qttprovided;
		RETURN -30415;
	END IF;
	_omega := CAST(_qttprovided as double precision)/CAST(_qttrequired as double precision);
	IF(_omega <= 0.) THEN
		RAISE NOTICE '[-30406] omega % should be > 0',_omega;
		RETURN -30406;
	END IF;
	--

	version_cur := ob_fcurrval('ob_tdraft_id_seq');

	cnt := 0;err := 0; first_commit :=0; first_draft := 0;
	time_begin := clock_timestamp(); err := 0;

	FOR r IN SELECT * FROM ob_getdraft_get(pivot.id,_omega,pivot.nf,_nr) LOOP
		-- RAISE INFO 'err %',r.ret_algo;	
		err := r.ret_algo;
		IF (err != 0) THEN
			IF ( err = -30144 ) THEN -- arc forbidden
				RAISE NOTICE '[-30144] Loop found for arc (Xoid,Yoid)=(%,%)',r.bid,r.sid;
				_err := ob_fdelete_bid_int(r.bid);
				IF(_err !=0) THEN
					RAISE NOTICE '[%s] Error in ob_finsert_bid_int()',_err;
				END IF;
			END IF;
			RAISE NOTICE '[%s] Error in ob_getdraft_get()',err;
			RETURN err;
		END IF;
	
		IF (cnt != (r.id+1)) THEN -- r.id starts from 0
			-- starts a new draft
			cnt := cnt+1;
			IF(cnt != (r.id+1)) THEN -- should not append
				RAISE  NOTICE '[-30410] r.id sequence is not 0..N';
				RETURN -30410;
			END IF;
			IF(cnt !=1) THEN -- omega's of the previous draft are recorded 
				_err := ob_fomega_draft(draft_id); --records omegas of the previous draft
				if(_err <0) THEN
					RAISE NOTICE '[%s] Error in ob_finsert_bid_int()',_err;
					RETURN _err;
				END IF;
			END IF;

			INSERT INTO ob_tdraft -- version_decision = NULL is the default
					(id,status,versionsg,nbsource,nbnoeud,cflags) 
				VALUES (version_cur+r.id,'D',r.versionsg,r.nbsource,r.nbnoeud,r.cflags)
				RETURNING id INTO draft_id;
			IF(first_draft = 0) THEN
				first_draft := draft_id;
			END IF; 	

		END IF;
		/* 					
		The version of the subgraph r.versionsg is defined as MAX(stock[].version) for all stocks of the subgraph
		at the time the subgraph was formed.
			
		Since the subgraph contains the stock[r.sid] the condition:
			stock[r.sid].version > r.versionsg
		means the stock[r.sid] has been updated AFTER the draft was formed.
			
		*/				
		SELECT * INTO stockb FROM ob_tstock s WHERE s.id = r.sid;
		IF (NOT FOUND or (stockb.qtt < r.fluxarrondi) or (stockb.version > r.versionsg)) THEN
			-- when the stock used by the commit does not exist or not big enough, the draft is outdated
			err := -30411;
			RETURN err;
		END IF;

		-- stock_draft created
		mvt := ob_finsert_das(stockb,r.fluxarrondi,'D'); 
		-- if stockb[r.sid] becomes empty, it is not deleted,
		-- it will be when the draft is executed or refused
		-- the trigger updates stock.version to 'ob_tdraft_id_seq'= version_cur
		IF(mvt.id <0) THEN 
			_err := mvt.id;
			IF (_err = -30408) THEN
				RAISE NOTICE 'stock.qtt=% < fluxarrondi=%',stockb.qtt,r.fluxarrondi;
			END IF;
			RAISE NOTICE '[%s] Error in ob_finsert_bid_int()',_err;
			return _err;
		END IF;
		
		-- RAISE NOTICE 'mvt % r.sid %,r.fluxarrondi %',mvt.id,r.sid,r.fluxarrondi;
		-- update ob_tstock set version = version_cur where id=mvt.src;
		-- RAISE INFO 'commit % % % % % %',draft_id,r.bid,r.sid,mvt.dst,r.wid,r.flags;				
		INSERT INTO ob_tcommit(did,bid,sid_src,sid_dst,wid,flags)
			VALUES (draft_id,r.bid,r.sid,mvt.dst,r.wid,r.flags) 
			RETURNING id INTO commit_id;
		
		IF(first_commit = 0) THEN 
			first_commit := commit_id;
		END IF;
			
	END LOOP;
	
	INSERT INTO ob_tnoeud (sid,omega,nr,nf,own,provided_quantity,required_quantity) 
		VALUES (pivot.id,_omega,_nr,pivot.nf,pivot.own,_qttprovided,_qttrequired)
		RETURNING id INTO new_noeud_id;
	
	IF(cnt != 0) THEN -- some draft were found
		-- omega's of the last draft are recorded
		_err := ob_fomega_draft(draft_id);
		IF(_err <0) THEN
			RAISE NOTICE '[%s] Error in ob_finsert_bid_int()',_err;
			RETURN _err;
		END IF;
		
		-- _delay int4 stores up to 30 minutes in microseconds
		_delay := EXTRACT(microseconds FROM (clock_timestamp() - time_begin))/cnt;
		UPDATE ob_tdraft SET delay = _delay WHERE id >= first_draft;
		
		-- sets the noeud.id 
		UPDATE ob_tcommit  SET bid = new_noeud_id 
		WHERE   id >= first_commit and bid is NULL;
		
		-- empty stocks are NOT deleted
		
		SELECT setval('ob_tdraft_id_seq',version_cur+cnt) INTO version_cur;
	END IF;
	
	RETURN cnt;
END; 
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------------------------------------------------
-- ob_finsert_sbid
----------------------------------------------------------------------------------------------------------------
-- PUBLIC
/* usage: 
	nb_draft int8 = ob_finsert_sbid(bid_id int8,_qttprovided int8,_qttrequired int8,_qualityrequired text)
	
	conditions:
		noeud.id=bid_id exists
		the pivot noeud.sid exists.
		_omega > 0
		_qualityrequired text
		
	action:
		inserts a bid with the same stock as bid_id. 
	
	returns nb_draft:
		the number of draft inserted.
		-30403, the bid_id was not found
		-30404, the quality of stock offered is not owned by user 
		or error returned by ob_finsert_bid_int
*/
----------------------------------------------------------------------------------------------------------------		
CREATE OR REPLACE FUNCTION ob_finsert_sbid(bid_id int8,_qttprovided int8,_qttrequired int8,_qualityrequired text) RETURNS int4 AS $$
DECLARE
	noeud	ob_tnoeud%rowtype;
	cnt 		int4;
	stock 	ob_tstock%rowtype;
BEGIN
	START TRANSACTION;
	SELECT n.* INTO noeud FROM ob_tnoeud n WHERE n.id = bid_id;
	IF NOT FOUND THEN
		RAISE INFO '[-30403] the bid % was not found',bid_id;
		ROLLBACK;
		RETURN -30403;
	END IF;
	-- controls
	SELECT s.* INTO stock FROM ob_tstock s WHERE  s.id = noeud.sid ;
	IF NOT FOUND THEN
		RAISE INFO '[-30404] the stock % was not found',noeud.sid,user;
		ROLLBACK;
		RETURN -30404;
	END IF;
	
	cnt := ob_finsert_bid_int(noeud.sid,_qttrequired,_qttprovided,_qualityrequired);
	if cnt <0 THEN 
		ROLLBACK;
	ELSE COMMIT;
	END IF;
	RETURN cnt;
END; 
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION ob_finsert_sbid(bid_id int8,_qttprovided int8,_qttrequired int8,_qualityrequired text) TO market;
----------------------------------------------------------------------------------------------------------------
-- ob_finsert_bid
----------------------------------------------------------------------------------------------------------------
-- PUBLIC
/* usage: 
	nb_draft int8 = ob_finsert_bid(_owner text,_qualityprovided text,qttprovided int8,_qttrequired int8,_qualityrequired text)

	conditions:
		stock.id=acc exists and stock.qtt >=qtt
		_omega != 0
		_qualityrequired exists
		
	action:
		inserts a stock and a bid.
	
	returns nb_draft:
		the number of draft inserted.
		nb_draft == -30404, the _acc was not big enough or it's quality not owner by the user
		or error returned by ob_finsert_bid_int

*/
----------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ob_finsert_bid(_owner text,_qualityprovided text,_qttprovided int8,_qttrequired int8,_qualityrequired text) RETURNS int4 AS $$
DECLARE
	cnt int4;
	i	int8;
	mvt ob_tlmvt%rowtype;
	stock ob_tstock%rowtype;
BEGIN
	-- controls
	START TRANSACTION;
	SELECT s.* INTO stock FROM ob_tstock s INNER JOIN ob_towner w ON (w.id=s.own ) INNER JOIN ob_tquality q ON ( s.nf=q.id )
		WHERE s.type='A' and (s.qtt >=_qttprovided) AND q.name=_qualityprovided and w.name=_owner;
	IF NOT FOUND THEN
		RAISE INFO '[-30404] the account was not found or not big enough';
		ROLLBACK;
		RETURN -30404;
	END IF;
	
	-- stock with qtt=0 does not exist.
	mvt := ob_finsert_das(stock,_qttprovided,'S');
	-- RAISE INFO 'la % ',stock.id;
	IF(mvt.id <0) THEN 
		ROLLBACK;
		RETURN mvt.id; 
	END IF;
	cnt := ob_finsert_bid_int(mvt.dst,_qttprovided,_qttrequired,_qualityrequired);
	if cnt <0 THEN ROLLBACK;
	ELSE COMMIT;
	END IF;
	RETURN cnt;
END; 
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION ob_finsert_bid(_owner text,_qualityprovided text,_qttprovided int8,_qttrequired int8,_qualityrequired text) 
TO market;
----------------------------------------------------------------------------------------------------------------
-- ob_fread_omega
----------------------------------------------------------------------------------------------------------------
-- PRIVATE used by ob_fbatch_omega(commit_src ob_tcommit,tmpc_dst ob_tcommit)
/* usage: 
	error int ob_fread_omega(nr int8,nf int8)
conditions:
	_nr and _nf exist
actions:

*/
----------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION ob_fread_omega(_nr int8,_nf int8) RETURNS int4 AS $$
DECLARE
	prem_r ob_tldraft%rowtype;
	der_r ob_tldraft%rowtype;
	r ob_tldraft%rowtype;
	cnt_draft int;
	ret int4;
	_err int4;
	qu int8;
	retry bool;
	_nrn text;
	_nfn text;
BEGIN
	SELECT q.name INTO _nrn FROM ob_tquality q WHERE q.id = _nr;
	IF NOT FOUND THEN
		RAISE NOTICE '[-30402] the quality nr=% was not found',_nr;
		RETURN -30402;
	END IF;
	SELECT q.name INTO _nfn FROM ob_tquality q WHERE q.id = _nf;
	IF NOT FOUND THEN
		RAISE  NOTICE '[-30402] the quality nf=% was not found',_nf;
		RETURN -30402;
	END IF;
	--
	cnt_draft := 0;
	<<DRAFT_LINES>>
	FOR r IN SELECT * FROM ob_getdraft_get(0,1.0,_nr,_nf) LOOP
		ret := r.ret_algo;
		IF(ret <0 ) THEN
			IF ( ret = -30144 ) THEN -- arc forbidden
				RAISE NOTICE '[%] Loop found for arc (Xoid,Yoid)=(%,%)',ret,r.bid,r.sid;
				_err := ob_fdelete_bid_int(r.bid);
				IF(_err !=0) THEN
					RAISE NOTICE '[%s] Error in ob_fread_omega()',_err;
				END IF;
				RETURN ret;
			END IF;
			RETURN ret;
		END IF;

		IF (r.cix = 0) THEN -- the first commit
			cnt_draft := cnt_draft + 1;
			IF (cnt_draft != 1) THEN -- the last commit of the last draft
				ret := ob_finsert_omega(der_r.sid,prem_r.sid,der_r.fluxarrondi,prem_r.fluxarrondi,_nr,_nf); 
				IF (ret < 0) THEN -- -30409 the stock was not found
					RETURN ret; 
				END IF;
			END IF;
			prem_r := r;

		ELSE
			ret := ob_finsert_omega(der_r.sid,r.sid,der_r.fluxarrondi,r.fluxarrondi,_nr,_nf); 
			IF (ret <0) THEN 
				RETURN ret; 
			END IF;
		END IF;
		der_r := r; 
	END LOOP DRAFT_LINES;
	-- 
	IF(cnt_draft != 0) THEN
		ret := ob_finsert_omega(der_r.sid,prem_r.sid,der_r.fluxarrondi,prem_r.fluxarrondi,_nr,_nf);
		IF (ret<0) THEN 
			RETURN ret; 
		END IF;
	END IF;
	
	RETURN 0;
END; 
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------------------------------------------------
-- ob_fbatch_omega
----------------------------------------------------------------------------------------------------------------
-- PUBLIC 
/* usage: ret int  = ob_fbatch_omega()

utility calling ob_fread_omega(nr,nf) for the couple (nr,nf) that needs refresh the most:
	-- a couple (nr,nf) such as ob_tomega[nr,nf] does not exist,
	-- if not found, oldest couple (cflags&1=0),
	-- if not found,  oldest couple such as (cflags&1=1)
	
Should be called by a cron.
*/
----------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION ob_fbatch_omega() RETURNS int AS $$
DECLARE
	_nr	int8 :=0;
	_nf	int8 :=0;
	err 	int := 0;
	namef	text;
	namer	text;
	t	int8;
BEGIN
	START TRANSACTION;
	-- a couple (nr,nf) such as ob_tomega[nr,nf] does not exist,
	select pq.nr,pq.nf into _nr,_nf from (
		select q1.id as nr,q2.id as nf 
			from ob_tquality q1,ob_tquality q2 where q1.id!=q2.id) as pq 
			left join ob_tomega o on (o.nr=pq.nr and o.nf=pq.nf) 
			where o.nr is null limit 1;
	IF NOT FOUND THEN 
		-- oldest couple (cflags&1=0), 
		-- if not found, oldest couple such as (cflags&1=1)
		-- select nr,nf into _nr,_nf from ob_tlomega 
		--	group by (flags&1=1),nr,nf order by (flags&1=1),max(created) asc limit 1;
		select nr,nf into _nr,_nf from ob_tomega group by nr,nf order by max(
			CASE WHEN updated IS NULL THEN created ELSE updated END) asc limit 1;
		IF NOT FOUND THEN
			RAISE NOTICE '[-30401] no candidate ob_fread_omega(nr,nf)';
			ROLLBACK;
			RETURN -30401;
		END IF;
	END IF;
	
	err = ob_fread_omega(_nr,_nf);
	IF(err<0) THEN 
		IF (err = -30144) THEN
			COMMIT;
		ELSE
			ROLLBACK; 
		END IF;
		RETURN err; 
	END IF;
	
	COMMIT;
	RETURN err;
END; 
$$ LANGUAGE plpgsql;

-- privileges of depositary are granted to market
-- GRANT ROLE depositary TO market;



