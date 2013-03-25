
CREATE OR REPLACE VIEW vmvtverif AS
	SELECT id,uuid,nb,oruuid,grp,own_src,own_dst,qtt,nat,false AS removed,created FROM tmvt where grp is not NULL
	UNION ALL
	SELECT id,uuid,nb,oruuid,grp,own_src,own_dst,qtt,nat,true AS removed,created FROM tmvtremoved where grp is not NULL;	
--------------------------------------------------------------------------------
CREATE OR REPLACE VIEW vorderverif AS
	SELECT id,uuid,own,nr,qtt_requ,np,qtt_prov,qtt,false AS removed,created FROM torder
	UNION
	SELECT id,uuid,own,nr,qtt_requ,np,qtt_prov,qtt,true AS removed,created FROM torderremoved;
--------------------------------------------------------------------------------

	
CREATE OR REPLACE FUNCTION fgetstats(mini timestamp,maxi timestamp) RETURNS TABLE(_name text,cnt int8) AS $$
DECLARE 
	_i 		int;
	_cnt 		int;
BEGIN
		
	_name := 'number of orders';
	select count(*) INTO cnt FROM vorderverif where  created<maxi;
	RETURN NEXT;
	
	_name := 'number of movements';
	select count(*) INTO cnt FROM vmvtverif where  created<maxi;
	RETURN NEXT;
	
	_name := 'number of orders rejected';
	select count(*) INTO cnt FROM tmvt where nb=1 and mini<=created and created<maxi;	
	RETURN NEXT;	
	
	FOR _i,cnt IN select nb,count(distinct grp) FROM vmvtverif where nb!=1  and created>=mini and created<maxi GROUP BY nb LOOP
		_name := 'agr. with ' || _i || ' partners';
		RETURN NEXT;
	END LOOP;

	RETURN;
END;
$$ LANGUAGE PLPGSQL  SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fgetstats(timestamp,timestamp) TO admin;

