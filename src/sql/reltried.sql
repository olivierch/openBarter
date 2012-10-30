/*----------------------------------------------------------------------------
It is the garbadge collector of poor orders

Some orders that frequently belong to refused cycles are removed 
from the database with the following algorithm:

1- torder[.].start = 0 by table default
	
2- for orders of unempty flows of _tmp, torder[.].start += microsecs of the transaction
orders such as torder[.].start > MAXTRY are removed
 done by finvalidate_treltried(timestamp) called by fexecquote() and finsertorder()

uses yflow_iterid(tflow). example:
	update tab set q=q+1 where id in (select yflow_iterid(yflow('[(100,10,3,1,4,1,1),(101,11,4,1,5,1,1),(102,12,5,1,3,1,1)]')));
*/
INSERT INTO tconst (name,value) VALUES 	('MAXTRY',3000000); -- 3 seconds

--------------------------------------------------------------------------------
-- finvalidate_treltried(_time_begin)
--------------------------------------------------------------------------------
CREATE FUNCTION  finvalidate_treltried(_time_begin timestamp) RETURNS void AS $$
DECLARE 
	_o 	torder%rowtype;
	_MAXTRY int8 := fgetconst('MAXTRY');
	_res	int;
	_mvt_id	int;
	_uuid   text;
	_t2	timestamp;
BEGIN
	IF(_MAXTRY=0) THEN
		RETURN;
	END IF;
	
	_t2 := clock_timestamp();
	UPDATE torder SET start = start + extract (microseconds from (_t2-_time_begin)) WHERE id IN (SELECT yflow_iterid(pat) FROM _tmp);

	FOR _o IN SELECT o.* FROM torder o WHERE o.start > _MAXTRY LOOP
		
		INSERT INTO tmvt (uuid,nb,oruuid,grp,own_src,own_dst,qtt,nat,created) 
			VALUES('',1,_o.uuid,'',_o.own,_o.own,_o.qtt,_o.np,statement_timestamp()) 
			RETURNING id INTO _mvt_id;
		_uuid := fgetuuid(_mvt_id);
		UPDATE tmvt SET uuid = _uuid,grp = _uuid WHERE id=_mvt_id;
			
		-- the order order.qtt != 0
		perform fremoveorder_int(_o.id);			
	END LOOP;
	RETURN;
END;
$$ LANGUAGE PLPGSQL;


