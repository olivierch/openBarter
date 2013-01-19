
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION 
	fpopulates(_cntl int) RETURNS int AS $$
DECLARE
	_own int;
	_owner text;
	_np int;
	_qtl_prov text;
	_nr int;
	_qlt_requ text;
	_o yorder;
	_qttprovided int;
	_qttrequired int;
	
	_cntloop int;
BEGIN
	_cntloop := 1;
	LOOP
		_np := get_random_number(1,_cntl/10);
		_nr := get_random_number(1,_cntl/10);
		-- RAISE WARNING '_np % _nr %r',_np,_nr;
		CONTINUE WHEN _np=_nr;

		_qtl_prov := 'qlt' || (_np::text);
		_qlt_requ := 'qlt' || (_nr::text);
		
		_own := get_random_number(1,_cntl/10);
		_owner := 'own' || (_own::text);
		
		_qttprovided := get_random_number(100,100000);

		_qttrequired := get_random_number(100,100000);

		_o := ROW(_cntloop,_owner,_cntloop,_qttrequired,_qlt_requ,_qttprovided,_qtl_prov,_qttprovided,0)::yorder;
		INSERT INTO torder(usr,ord,created,updated) VALUES (current_user,_o,statement_timestamp(),NULL);	
		
		IF((_cntloop % 10000) =0) THEN
			CHECKPOINT;
		END IF;
				
		_cntloop := _cntloop + 1;
		EXIT WHEN _cntloop > _cntl;
	END LOOP;

	RETURN _cntloop-1;

END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
    
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_random_number(min int, max int) RETURNS int AS $$
BEGIN
    RETURN trunc(random() * (max-min) + min);
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION  fillstack(_cntl int) RETURNS int AS $$
DECLARE
	_cnto 	int;
	_cntq 	int;
	_cntloop int;
	_np int;
	_nr int;
	_own int;
	_qlt_prov text;
	_qlt_requ text;
	_qttprovided	int8;
	_qttrequired	int8;
	_owner text;
	_qp int;
	_qr int;
	_res yressubmit;
BEGIN

	_cntloop := 1;
	LOOP
		_np := get_random_number(1,_cntl/10);
		_nr := get_random_number(1,_cntl/10);
		-- RAISE WARNING '_np % _nr %r',_np,_nr;
		CONTINUE WHEN _np=_nr;

		_qlt_prov := 'qlt' || (_np::text);
		_qlt_requ := 'qlt' || (_nr::text);
		
		_own := get_random_number(1,_cntl/10);
		_owner := 'own' || (_own::text);
		
		_qttprovided := get_random_number(100,100000);
		_qttrequired := get_random_number(100,100000);

		_np := get_random_number(1,_cntq);
		_nr := get_random_number(1,_cntq);
		
		_res := fsubmitorder(_owner,NULL,_qlt_requ,_qttrequired,NULL,_qlt_prov,_qttprovided,NULL,NULL,NULL);
		
		_cntloop := _cntloop + 1;
		EXIT WHEN _cntloop > _cntl;
	END LOOP;

	RETURN _cntloop-1;
END; 
$$ LANGUAGE PLPGSQL;
select * from fpopulates(1000);
select * from fillstack(100);
select * from femptystack();



