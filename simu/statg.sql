CREATE OR REPLACE VIEW vmvtverif AS
	SELECT id,nb,oruuid,grp,own_src,own_dst,qtt,nat,created FROM tmvt where grp is not NULL
	UNION ALL
	SELECT id,nb,oruuid,grp,own_src,own_dst,qtt,nat,created FROM tmvtremoved where grp is not NULL;	
--------------------------------------------------------------------------------
CREATE OR REPLACE VIEW vorderverif AS
	SELECT id,uuid,own,nr,qtt_requ,np,qtt_prov,qtt,created FROM torder
	UNION
	SELECT id,uuid,own,nr,qtt_requ,np,qtt_prov,qtt,created FROM torderremoved;
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fgetstats(mini timestamp,maxi timestamp) RETURNS TABLE(_name text,cnt int8) AS $$
DECLARE 
	_i 		int;
	_cnt 		int;
BEGIN
/*
	_name := 'number of qualities';
	select count(*) INTO cnt FROM tquality where updated>=mini and updated<maxi;
	RETURN NEXT;
	
	_name := 'number of owners';
	select count(*) INTO cnt FROM towner where created>=mini and created<maxi;
	RETURN NEXT;
	
	_name := 'number of quotes';
	select count(*) INTO cnt FROM tquote where created>=mini and created<maxi;
	RETURN NEXT;
*/			
	_name := 'number of orders';
	select count(*) INTO cnt FROM vorderverif where  created<maxi;
	RETURN NEXT;
	
	_name := 'number of movements';
	select count(*) INTO cnt FROM vmvtverif where  created<maxi;
	RETURN NEXT;
/*	
	_name := 'number of quotes removed';
	select count(*) INTO cnt FROM tquoteremoved where removed>=mini and removed<maxi;
	RETURN NEXT;

	_name := 'number of orders removed';
	select count(*) INTO cnt FROM torderremoved where updated>=mini and updated<maxi;
	RETURN NEXT;
	
	_name := 'number of movements removed';
	select count(*) INTO cnt FROM tmvtremoved where deleted>=mini and deleted<maxi;	
	RETURN NEXT;
	
	_name := 'number of agreements';
	select count(distinct grp) INTO cnt FROM vmvtverif where nb!=1 and created>=mini and created<maxi;	
	RETURN NEXT;	
*/	
	_name := 'number of orders rejected';
	select count(*) INTO cnt FROM tmvt where nb=1 and created>=mini and created<maxi;	
	RETURN NEXT;	
	
	FOR _i,cnt IN select nb,count(distinct grp) FROM vmvtverif where nb!=1  and created>=mini and created<maxi GROUP BY nb LOOP
		_name := 'agr. with ' || _i || ' partners';
		RETURN NEXT;
	END LOOP;

	RETURN;
END;
$$ LANGUAGE PLPGSQL  SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fgetstats(timestamp,timestamp) TO admin;

