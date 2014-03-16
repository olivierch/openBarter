
/*
*/
create schema market;
grant usage on schema market to role_bo;
	
create table market.sta_worker (
	id serial,
	status int 
);
insert into market.sta_worker (status) VALUES (3),(3);

CREATE FUNCTION market.worker(_id int) RETURNS int AS $$
DECLARE 
	_ret int;
BEGIN
	UPDATE market.sta_worker SET status = status-1  WHERE id=_id RETURNING status INTO _ret;
	RAISE LOG 'worker% called',_id;
	IF(_ret < 0) THEN
		RETURN 1; -- OB_DOWAIT
	ELSE
		RETURN 0;
	END IF;
END;
$$ LANGUAGE PLPGSQL;

CREATE FUNCTION market.worker1() RETURNS int AS $$
DECLARE 
	_ret int;
BEGIN
	_ret := market.worker(1);
	RETURN _ret;
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION market.worker1() TO role_bo;

CREATE FUNCTION market.worker2() RETURNS int AS $$
DECLARE 
	_ret int;
BEGIN
	_ret := market.worker(2);
	RETURN _ret;
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION market.worker2() TO role_bo;
