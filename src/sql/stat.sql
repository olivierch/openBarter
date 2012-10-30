/*------------------------------------------------------------------------------
STAT
------------------------------------------------------------------------------*/
/*------------------------------------------------------------------------------
fgetstats() 
	returns stats but not errors
------------------------------------------------------------------------------*/
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
	
	FOR _i,cnt IN select nb,count(distinct grp) FROM vmvtverif where nb!=1 GROUP BY nb LOOP
		_name := 'agreements with ' || _i || ' partners';
		RETURN NEXT;
	END LOOP;

	RETURN;
END;
$$ LANGUAGE PLPGSQL  SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fgetstats(bool) TO admin;

/*------------------------------------------------------------------------------
fgetcount() 
	returns stats but not errors
------------------------------------------------------------------------------*/
CREATE FUNCTION fgetcounts() RETURNS TABLE(_name text,cnt int8) AS $$
DECLARE 
	_cnt 		int;
BEGIN

	_name := 'count(tquality)';
	select count(*) INTO cnt FROM tquality;
	RETURN NEXT;
	
	_name := 'count(towner)';
	select count(*) INTO cnt FROM towner;
	RETURN NEXT;
	
	_name := 'count(tquote)';
	select count(*) INTO cnt FROM tquote;
	RETURN NEXT;
	
	_name := 'count(tquoteremoved)';
	select count(*) INTO cnt FROM tquoteremoved;
	RETURN NEXT;
				
	_name := 'count(torder)';
	select count(*) INTO cnt FROM torder;
	RETURN NEXT;

	_name := 'count(torderremoved)';
	select count(*) INTO cnt FROM torderremoved;
	RETURN NEXT;
		
	_name := 'count(tmvt)';
	select count(*) INTO cnt FROM tmvt;
	RETURN NEXT;

	_name := 'count(tmvtremoved)';
	select count(*) INTO cnt FROM tmvtremoved;	
	RETURN NEXT;
	
	_name := 'count(vmvtverif.grp) with nb!=1';
	select count(distinct grp) INTO cnt FROM vmvtverif where nb!=1;	
	RETURN NEXT;	
		
	_name := 'count(vmvtverif.grp) with nb==1';
	select count(distinct grp) INTO cnt FROM vmvtverif where nb=1;	
	RETURN NEXT;
		
	_name := 'count(vmvtverif.created) with nb!=1';
	select count(distinct created) INTO cnt FROM vmvtverif where nb!=1;	
	RETURN NEXT;		

	RETURN;
END;
$$ LANGUAGE PLPGSQL  SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fgetcounts() TO admin;

/*------------------------------------------------------------------------------
returns  records:
the number of errors found with fverifmvt() and fverifmvt3()
------------------------------------------------------------------------------*/
CREATE FUNCTION fgeterrs() RETURNS TABLE(_name text,cnt int8) AS $$
DECLARE 
	_i 		int;
	_cnt 		int;
BEGIN		
	_name := 'errors on quantities in mvts';
	cnt := fverifmvt();
	RETURN NEXT;

	_name := 'errors on agreements in mvts';
	cnt := fverifmvt3();
	RETURN NEXT;
	RETURN;
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fgeterrs() TO admin;

/*------------------------------------------------------------------------------
-- verifies that for all orders:
--	order.qtt_prov = sum(mvt.qtt) of movements related to that order
------------------------------------------------------------------------------*/
CREATE FUNCTION fverifmvt() RETURNS int AS $$
DECLARE
	_qtt_prov	 int8;
	_qtt		 int8;
	_uuid		 text;
	_qtta		 int8;
	_npa		 int;
	_npb		 int;
	_np		 int;
	_nb			int;
	_cnterr		 int := 0;
	_iserr		 bool;
BEGIN
	FOR _uuid,_qtta,_npa,_npb,_qtt_prov,_qtt,_np IN 
	SELECT m.oruuid,sum(m.qtt),max(m.nat),min(m.nat),o.qtt_prov,o.qtt,o.np
	FROM vmvtverif m INNER JOIN vorderverif o ON  o.uuid=m.oruuid 
	WHERE m.nb!=1 GROUP BY m.oruuid,o.qtt_prov,o.qtt,o.np LOOP
			IF(	(_qtt_prov != _qtta+_qtt) 
				-- NOT vorderverif.qtt_prov == vorderverif.qtt + sum(mvt.qtt)
				OR (_np != _npa)	
				-- NOT mvt.nat == vorderverif.nat 
				OR (_npa != _npb)
				-- NOT all mvt.nat are the same 
			)	THEN 
				_cnterr := _cnterr +1;
				RAISE NOTICE 'error on uuid:%',_uuid;
			END IF;
	END LOOP;
	RETURN _cnterr;
END;
$$ LANGUAGE PLPGSQL;

/*------------------------------------------------------------------------------
_mvtprec and _mvt are successive movements of an agreement
------------------------------------------------------------------------------*/
CREATE FUNCTION fverifmvt2_int(_mvtprec tmvt,_mvt tmvt) RETURNS int AS $$
DECLARE
	_o		vorderverif%rowtype;
BEGIN
	SELECT uuid,np,nr,qtt_prov,qtt_requ INTO _o.uuid,_o.np,_o.nr,_o.qtt_prov,_o.qtt_requ FROM vorderverif WHERE uuid = _mvt.oruuid;
	IF (NOT FOUND) THEN
		RAISE NOTICE 'order not found for vorderverif %',_mvt.oruuid;
		RETURN 1;
	END IF;

	IF(_o.np != _mvt.nat OR _o.nr != _mvtprec.nat) THEN
		RAISE NOTICE 'mvt.nat != np or mvtprec.nat!=nr';
		RETURN 1;
	END IF;
	
	-- NOT(_o.qtt_prov/_o.qtt_requ >= _mvt.qtt/_mvtprec.qtt)
	IF(((_o.qtt_prov::float8) / (_o.qtt_requ::float8)) < ((_mvt.qtt::float8)/(_mvtprec.qtt::float8))) THEN
		RAISE NOTICE 'order %->%, with  mvt %->%',_o.qtt_requ,_o.qtt_prov,_mvtprec.qtt,_mvt.qtt;
		RAISE NOTICE '% < 1; should be >=1',(((_o.qtt_prov::float8) / (_o.qtt_requ::float8)) / ((_mvt.qtt::float8)/(_mvtprec.qtt::float8)));
		RAISE NOTICE 'order.uuid %, with  mvtid %->%',_o.uuid,_mvtprec.id,_mvt.id;
		RETURN 1;
	END IF;


	RETURN 0;
END;
$$ LANGUAGE PLPGSQL;

/*------------------------------------------------------------------------------
-- verifies that for all agreements, movements comply with related orders.
------------------------------------------------------------------------------*/
CREATE FUNCTION fverifmvt3() RETURNS int AS $$
DECLARE
	_cnterr		 int := 0;
	_mvts		 tmvt[];
	_mvt		 tmvt%rowtype;
	_mvtprec	 tmvt%rowtype;
	_mvtfirst	 tmvt%rowtype;
	_uuiderr	 text;
	_cnt		 int;		-- count mvt in agreement
BEGIN
		
	_mvtprec.grp := NULL;
	_cnterr := 0;
	FOR _mvt IN SELECT id,uuid,nb,oruuid,grp,own_src,own_dst,qtt,nat FROM vmvtverif WHERE nb!=1 ORDER BY grp,uuid ASC  LOOP
		IF(_mvt.grp = _mvtprec.grp) THEN
			_mvts := array_append(_mvts,_mvt);
		ELSE
			IF NOT (_mvtprec.grp IS NULL) THEN
				_cnterr := fverifmvt3_int(_mvts) + _cnterr;
			END IF;
			_mvts := array_append(ARRAY[]::tmvt[],_mvt);
		END IF;
		_mvtprec.grp := _mvt.grp;
	END LOOP;
	IF NOT (_mvtprec.grp IS NULL) THEN
		_cnterr := fverifmvt3_int(_mvts) + _cnterr;
	END IF;
	RETURN _cnterr;
END;
$$ LANGUAGE PLPGSQL;

/*------------------------------------------------------------------------------
_mvtprec and _mvt are successive movements of an agreement
------------------------------------------------------------------------------*/
CREATE FUNCTION fverifmvt3_int(_mvts tmvt[]) RETURNS int AS $$
DECLARE
	_mvtprec	 tmvt%rowtype;
	_mvtfirst    tmvt%rowtype;
	_mvt		 tmvt%rowtype;
	_cnterr		 int;
	_nb			 int;
BEGIN
	_nb := array_length(_mvts,1);
	_mvtprec.uuid := NULL;
	_cnterr := 0;
	FOREACH _mvt IN ARRAY _mvts LOOP
		IF ( _nb != _mvt.nb ) THEN
			RAISE NOTICE 'mvt.nb incorrect for movement %',_mvt.oruuid;
			_cnterr := _cnterr + 1 ;
		END IF;
		IF (_mvtprec.uuid IS NULL) THEN
			_mvtfirst := _mvt;
		ELSE
			_cnterr := fverifmvt2_int(_mvtprec,_mvt) + _cnterr;
		END IF;
		_mvtprec.uuid := _mvt.grp;
	END LOOP;
	IF NOT (_mvtprec.grp IS NULL) THEN
		_cnterr := fverifmvt2_int(_mvt,_mvtfirst) + _cnterr;
	END IF;
	RETURN _cnterr;
END;
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
-- number of partners for the 100 last movements
-- select nb,count(distinct grp) from (select * from vmvtverif order by id desc limit 100) a group by nb;

-- performances
--------------------------------------------------------------------------------
-- list of transactions created at date increasing
CREATE VIEW vtransaction(id,cnt_grp,created,delay) AS SELECT max(id),count(distinct grp) as cnt_grp,created,created-(lag(created) over(order by created)) as delay from tmvt group by created order by created;
COMMENT ON VIEW vtransaction IS 'list of transactions, ';

--------------------------------------------------------------------------------
-- list of ten groups ntile( 10 over delay)
-- cnt_tr 		number of transactions
-- cnt_grp     	number of cycles
-- delay_tr_min		min duration of transaction
-- delay_tr_max		max duration of transaction
-- delay_grp_avg	average duration of cycles

CREATE VIEW vperf(cnt_tr,cnt_grp,delay_tr_min,delay_tr_max,delay_grp_avg) AS 
select count(*) as cnt_tr,sum(cnt_grp) as cnt_grp,min(delay) as delay_tr_min,max(delay) as delay_tr_max,sum(delay)/sum(cnt_grp) as delay_grp_avg from (
	select cnt_grp,delay,ntile(10) over(order by delay desc) as n from (
		select * from vtransaction order by id desc
		) as t2
	) as t group by n order by delay_tr_min desc;

-- for 1000 last transactions
CREATE VIEW vperf1000(cnt_tr,cnt_grp,delay_tr_min,delay_tr_max,delay_grp_avg) AS 
select count(*) as cnt_tr,sum(cnt_grp) as cnt_grp,min(delay) as delay_tr_min,max(delay) as delay_tr_max,sum(delay)/sum(cnt_grp) as delay_grp_avg from (
	select cnt_grp,delay,ntile(10) over(order by delay desc) as n from (
		select * from vtransaction order by id desc limit 1000
		) as t2
	) as t group by n order by delay_tr_min desc;
--------------------------------------------------------------------------------
-- list of ten groups ntile( 10 over cnt_grp)
-- cnt_grp_min,cnt_grp_max	number of grp per transaction
-- cnt_tr 		total number of transactions
-- sum_grp     	total number of cycles
-- delay_grp_avg	average duration of cycles

CREATE VIEW vperfcntgrp(cnt_grp_min,cnt_grp_max,cnt_tr,sum_grp,delay_grp_avg) AS 
select min(cnt_grp) as cnt_grp_min,max(cnt_grp) as cnt_grp_max,count(*) as cnt_tr,sum(cnt_grp) as sum_grp,sum(delay)/sum(cnt_grp) as delay_grp_avg from (
	select cnt_grp,delay,ntile(10) over(order by cnt_grp desc) as n from (
		select * from vtransaction 
		) as t2
	) as t group by n order by n asc;
--------------------------------------------------------------------------------	
-- distribution of cycles by number of partners 
CREATE VIEW vnbgrp(nb,cnt_grp) AS SELECT nb,count(*) as cnt_grp from (
	SELECT max(id) as gid,grp,max(nb) as nb from tmvt group by grp order by gid desc
) as t group by nb order by nb asc;

-- for 1000 last cycles
CREATE VIEW vnbgrp1000(nb,cnt) AS SELECT nb,count(*) as cnt from (
	SELECT max(id) as gid,grp,max(nb) as nb from tmvt group by grp order by gid desc limit 1000
) as t group by nb order by nb asc;
--------------------------------------------------------------------------------	
-- proba que deux ordres soient connectés
/*
with torl as (select * from torder order by id asc limit 1000)
select sum(t.x)::float/count(*) from(select case when s.np=d.nr THEN 1 ELSE 0 END as x from torl s,torl d) as t;
*/

