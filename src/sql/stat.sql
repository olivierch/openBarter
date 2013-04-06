/*------------------------------------------------------------------------------
fgetcount() 
	returns stats but not errors
------------------------------------------------------------------------------*/
CREATE FUNCTION market.fgetcounts() RETURNS TABLE(_count text,cnt int8) AS $$
DECLARE 
	_cnt 		int;
BEGIN

	_count := 'market.tstack';
	select count(*) INTO cnt FROM market.tstack;
	RETURN NEXT;
	
	_count := 'market.torder';
	select count(*) INTO cnt FROM market.torder;
	RETURN NEXT;
	
	_count := 'market.tmvt';
	select count(*) INTO cnt FROM market.tmvt;
	RETURN NEXT;
	
	_count := 'market.towner';
	select count(*) INTO cnt FROM market.towner;
	RETURN NEXT;
	
	_count := 'market.tmvt.grp with nbc!=1';
	select count(distinct grp) INTO cnt FROM market.tmvt where nbc!=1;	
	RETURN NEXT;	

	_count := 'market.tmvt.created with nbc!=1';
	select count(distinct created) INTO cnt FROM market.tmvt where nbc!=1;	
	RETURN NEXT;
		
	_count := 'market.tmvt.refused';
	select count(distinct grp) INTO cnt FROM market.tmvt where refused !=0;	
	RETURN NEXT;		

	RETURN;
END;
$$ LANGUAGE PLPGSQL  SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  market.fgetcounts() TO role_bo;
