/*------------------------------------------------------------------------------
fgetcount() 
	returns stats but not errors
------------------------------------------------------------------------------*/
CREATE FUNCTION fgetcounts() RETURNS TABLE(_count text,cnt int8) AS $$
DECLARE 
	_cnt 		int;
BEGIN

	_count := 'tstack';
	select count(*) INTO cnt FROM tstack;
	RETURN NEXT;
	
	_count := 'torder';
	select count(*) INTO cnt FROM torder;
	RETURN NEXT;
	
	_count := 'tmvt';
	select count(*) INTO cnt FROM tmvt;
	RETURN NEXT;
	
	_count := 'towner';
	select count(*) INTO cnt FROM towner;
	RETURN NEXT;
	
	_count := 'tmvt.grp with nbc!=1';
	select count(distinct grp) INTO cnt FROM tmvt where nbc!=1;	
	RETURN NEXT;	

	_count := 'tmvt.created with nbc!=1';
	select count(distinct created) INTO cnt FROM tmvt where nbc!=1;	
	RETURN NEXT;
		
	_count := 'tmvt.refused';
	select count(distinct grp) INTO cnt FROM tmvt where refused !=0;	
	RETURN NEXT;		

	RETURN;
END;
$$ LANGUAGE PLPGSQL  SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION  fgetcounts() TO role_bo;
