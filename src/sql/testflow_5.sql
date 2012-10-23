reset role;
SET log_error_verbosity = terse;
SET client_min_messages = notice;

-- all orders removed
CREATE FUNCTION swallow_orders() RETURNS int AS $$
DECLARE
	_i 		int;
	_uuid	text;
	_vo		vorder%rowtype;
BEGIN
	_i := 0;
	FOR _uuid IN SELECT m.uuid FROM torder m LOOP
		_vo :=  fremoveorder(_uuid);
		_i := _i + 1;
	END LOOP;
	RETURN _i;
END;
$$ LANGUAGE PLPGSQL;

-- all mvts removed
CREATE FUNCTION swallow_agreements() RETURNS int AS $$
DECLARE
	_i 		int;
	_uuid	text;
	_CHECK_QUALITY_OWNERSHIP int := fgetconst('CHECK_QUALITY_OWNERSHIP');
BEGIN
	_i := 0;
	FOR _uuid IN SELECT m.uuid FROM tmvt m, tquality q WHERE m.nat=q.id 
		AND ((q.depository=session_user) OR (_CHECK_QUALITY_OWNERSHIP = 0)) 
		GROUP BY m.uuid LOOP
		_i := _i + fremovemvt(_uuid);
	END LOOP;
	RETURN _i;
END;
$$ LANGUAGE PLPGSQL;

select swallow_orders();
select swallow_agreements();

set role admin;
select * from fchangestatemarket(true);
select * from fchangestatemarket(true);
select * from fchangestatemarket(true);
select * from fchangestatemarket(true);
select id,market_session,market_status from vmarket;

set role client;

select finsertorder('u','b',1000,1000,'a');
select finsertorder('v','c',1000,1000,'b');
select qtt_in,qtt_out from fgetquote('w','a',1000,0,'c');
select finsertorder('w','a',1000,1000,'c');
select id,uuid,nb,oruuid,grp,provider,quality,qtt,receiver from vmvt order by uuid;
select fremovemvt('2-1');
select fremovemvt('2-2');
select fremovemvt('2-3');

select finsertorder('u','b',2000,1000,'a');
select finsertorder('v','c',2000,1000,'b');
select  qtt_in,qtt_out from fgetquote('w','a',500,0,'c');
--select finsertorder('w','a',500,2000,'c');
select qtt_in,qtt_out from fgetquote('w','a',500,2000,'c');
select qtt_in,qtt_out from fexecquote('w',1);
select id,uuid,nb,oruuid,grp,provider,quality,qtt,receiver from vmvt order by uuid;
select fremovemvt('2-4');
select fremovemvt('2-5');
select fremovemvt('2-6');

select fgetquote('w','a',500,0,'b');
select finsertorder('w','a',500,1000,'b');

set role admin;
select * from fchangestatemarket(true);
select id,market_session,market_status from vmarket;
-- market is closed
set role client;
select fremovemvt('2-7');
select fremovemvt('2-8');

set role admin;
select * from fgetstats(true);
select * from fgeterrs() where cnt != 0;


select * from fchangestatemarket(true);
select * from fchangestatemarket(true);
select * from fchangestatemarket(true);
select id,market_session,market_status from vmarket;
-- merket is opened
select * from fgetstats(true);

