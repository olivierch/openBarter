/* utilities */

--------------------------------------------------------------------------------
-- fetch a constant, and verify consistancy
CREATE FUNCTION fgetconst(_name text) RETURNS int AS $$
DECLARE
	_ret int;
BEGIN
	SELECT value INTO _ret FROM tconst WHERE name=_name;
	IF(NOT FOUND) THEN
		RAISE EXCEPTION 'the const % is not found',_name USING ERRCODE= 'YA002';
	END IF;
	IF(_name = 'MAXCYCLE' AND _ret >yflow_get_maxdim()) THEN
		RAISE EXCEPTION 'MAXVALUE must be <=%',yflow_get_maxdim() USING ERRCODE='YA002';
	END IF;
	RETURN _ret;
END; 
$$ LANGUAGE PLPGSQL STABLE set search_path to market;

--------------------------------------------------------------------------------
CREATE FUNCTION fsetvar(_name text,_value int) RETURNS int AS $$
DECLARE
	_ret int;
BEGIN
	UPDATE tvar SET value=_value WHERE name=_name;
	GET DIAGNOSTICS _ret = ROW_COUNT;
	IF(_ret !=1) THEN
		RAISE EXCEPTION 'the var % is not found',_name USING ERRCODE= 'YA002';
	END IF;
	RETURN 0;
END; 
$$ LANGUAGE PLPGSQL set search_path to market;

--------------------------------------------------------------------------------
CREATE FUNCTION fgetvar(_name text) RETURNS int AS $$
DECLARE
	_ret int;
BEGIN
	SELECT value INTO _ret FROM tvar WHERE name=_name;
	IF(NOT FOUND) THEN
		RAISE EXCEPTION 'the var % is not found',_name USING ERRCODE= 'YA002';
	END IF;
	RETURN _ret;
END; 
$$ LANGUAGE PLPGSQL set search_path to market;

--------------------------------------------------------------------------------
CREATE FUNCTION fversion() RETURNS text AS $$
DECLARE
	_ret text;
	_x	 int;
	_y	 int;
	_z	 int;
BEGIN
	SELECT value INTO _x FROM tconst WHERE name='VERSION-X';
	SELECT value INTO _y FROM tconst WHERE name='VERSION-Y';
	SELECT value INTO _z FROM tconst WHERE name='VERSION-Z';
	RETURN 'openBarter VERSION-' || ((_x)::text) || '.' || ((_y)::text)|| '.' || ((_z)::text);
END; 
$$ LANGUAGE PLPGSQL STABLE set search_path to market;
GRANT EXECUTE ON FUNCTION  fversion() TO role_com;


--------------------------------------------------------------------------------
CREATE FUNCTION fifo_init(_name text) RETURNS void AS $$
BEGIN
	EXECUTE 'CREATE INDEX ' || _name || '_id_idx ON ' || _name || '((id) ASC)';
END; 
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
-- trigger before insert on some tables
--------------------------------------------------------------------------------
CREATE FUNCTION ftime_updated() 
	RETURNS trigger AS $$
BEGIN
	IF (TG_OP = 'INSERT') THEN
		NEW.created := statement_timestamp();
	ELSE 
		NEW.updated := statement_timestamp();
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;
comment on FUNCTION ftime_updated() is 
'trigger updating fields created and updated';

--------------------------------------------------------------------------------
-- add ftime_updated trigger to the table
--------------------------------------------------------------------------------
CREATE FUNCTION _reference_time(_table text) RETURNS int AS $$
DECLARE
	_res int;
	_tablem text;
	_tl text;
	_tr text;
BEGIN
    _tablem := _table;
	LOOP -- remplaces dots by underscores
	    _res := position('.' in _tablem);
	    EXIT WHEN _res=0;
	    _tl := substring(_tablem for _res-1);
	    _tr := substring(_tablem from _res+1);
	    _tablem := _tl || '_' || _tr;  
	    
	END LOOP;
	EXECUTE 'ALTER TABLE ' || _table || ' ADD created timestamp';
	EXECUTE 'ALTER TABLE ' || _table || ' ADD updated timestamp';
	EXECUTE 'CREATE TRIGGER trig_befa_' || _tablem || ' BEFORE INSERT
		OR UPDATE ON ' || _table || ' FOR EACH ROW
		EXECUTE PROCEDURE ftime_updated()' ; 
	RETURN 0;
END; 
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
CREATE FUNCTION _grant_read(_table text) RETURNS void AS $$
/* deprecated, use GRANT SELECT ON _table TO role_com instead */
BEGIN 
	EXECUTE 'GRANT SELECT ON ' || _table || ' TO role_com';
	RETURN;
END; 
$$ LANGUAGE PLPGSQL;
--GRANT SELECT ON tconst TO role_com;

