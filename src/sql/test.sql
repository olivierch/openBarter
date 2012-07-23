
CREATE FUNCTION ftest() RETURNS text AS $$
DECLARE
	_ret int;
	_p 	torder%rowtype;
BEGIN
	_p.qtt_requ := 0;
	RETURN 'toto';
END; 
$$ LANGUAGE PLPGSQL;

CREATE FUNCTION ftest2() RETURNS text AS $$ 
	select 'titi' $$
LANGUAGE SQL;

