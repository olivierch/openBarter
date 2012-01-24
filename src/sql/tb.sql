create or replace function ftable() RETURNS TABLE(_id int8,_np int8) as $$
DECLARE
	_r	RECORD;
BEGIN
	FOR _id,_np IN SELECT id,np from torder LOOP
		RETURN NEXT;
	END LOOP;
	RETURN;
END;
$$ LANGUAGE PLPGSQL;

