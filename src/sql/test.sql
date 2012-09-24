
CREATE OR REPLACE  FUNCTION ftest() RETURNS int AS $$
BEGIN
	-- SET client_min_messages = warning;
	-- ne pas utiliser INFO!! mais DEBUG1,LOG,NOTICE*,WARNING,ERROR
	RAISE NOTICE ' should be found';
	RETURN 1;
END; 
$$ LANGUAGE PLPGSQL;

