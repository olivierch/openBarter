
CREATE FUNCTION ftest() RETURNS text AS $$
DECLARE
	_ret int;
BEGIN
	RETURN 'toto';
END; 
$$ LANGUAGE PLPGSQL;

CREATE FUNCTION ftest2() RETURNS text AS $$ 
	select 'titi' $$
LANGUAGE SQL;

