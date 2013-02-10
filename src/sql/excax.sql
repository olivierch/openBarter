\i sql/model.sql
\i sql/verif.sql
RESET client_min_messages;
RESET log_error_verbosity;
SET client_min_messages = notice;
SET log_error_verbosity = terse;

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
	_qttprovided int8;
	_qttrequired int8;
	_idown int;
	_cnti int;
	_type int;
	
	
	_cntloop int;
BEGIN
	_cntloop := 1;
	_cnti := _cntl/100;
	LOOP
		_np := get_random_number(1,_cnti);
		_nr := get_random_number(1,_cnti);
		-- RAISE WARNING '_np % _nr %r',_np,_nr;
		CONTINUE WHEN _np=_nr;

		_qtl_prov := 'qlt' || (_np::text);
		_qlt_requ := 'qlt' || (_nr::text);
		
		_own := get_random_number(1,_cnti);
		_owner := 'own' || (_own::text);
		_idown := fgetowner(_owner);
		
		_qttprovided := get_random_number(100,100000);

		_qttrequired := get_random_number(100,100000);
		IF((_cntloop %2) = 1) THEN
			_type =1;
		ELSE
			_type =2;
		END IF;

		_o := ROW(_type,_cntloop,_idown,_cntloop,_qttrequired,_qlt_requ,_qttprovided,_qtl_prov,_qttprovided)::yorder;
		INSERT INTO torder(usr,ord,created,updated) VALUES (current_user,_o,statement_timestamp(),NULL);
			
		_nr := faddvalue(_qtl_prov,_qttprovided);
		
		IF((_cntloop % 10000) =0) THEN
			CHECKPOINT;
		END IF;
				
		_cntloop := _cntloop + 1;
		EXIT WHEN _cntloop > _cntl;
	END LOOP;
	PERFORM setval('tstack_id_seq',_cntloop,false);
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
	-- _cntq 	int;
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
	_idowner int;
	_cnti int;
	_init int;
BEGIN

	_cntloop := 1;
	_init := nextval('tstack_id_seq');
	_cnti := _init/100;
	
	LOOP
		_np := get_random_number(1,_cnti);
		_nr := get_random_number(1,_cnti);
		-- RAISE WARNING '_cnti % _np % _nr %',_cnti,_np,_nr;
		CONTINUE WHEN _np=_nr;

		_qlt_prov := 'qlt' || (_np::text);
		_qlt_requ := 'qlt' || (_nr::text);
		
		_own := get_random_number(1,_cnti);
		_owner := 'own' || (_own::text);
		_idowner := fgetowner(_owner);
		
		_qttprovided := get_random_number(100,100000);
		_qttrequired := get_random_number(100,100000);
		
		-- fsubmitorder(_type dtypeorder,_own text,_oid int,_qua_requ text,_qtt_requ int8,_qua_prov text,_qtt_prov int8,_qtt int8)
		_res := fsubmitorder(1,_owner,NULL,_qlt_requ,_qttrequired,_qlt_prov,_qttprovided);
		
		_nr := faddvalue(_qlt_prov,_qttprovided);
		
		_cntloop := _cntloop + 1;
		EXIT WHEN _cntloop > _cntl;
	END LOOP;

	RETURN _cntloop-1;
END; 
$$ LANGUAGE PLPGSQL;

/*
select * from fpopulates(10000);
copy torder to '/home/olivier/ob92/src/sql/torder_test_10000.sql';
copy towner to '/home/olivier/ob92/src/sql/towner_test_10000.sql';
*/
copy torder from '/home/olivier/ob92/src/sql/torder_test_10000.sql';
copy towner from '/home/olivier/ob92/src/sql/towner_test_10000.sql';
truncate tstack;
SELECT setval('tstack_id_seq',10000,true);

select * from fsubmitorder(5,'own82',NULL,'qlt22',1,'qlt23',1,1);select * from fproducemvt();
select * from fsubmitorder(1,'own82',NULL,'qlt22',67432,'qlt23',30183,30183);select * from fproducemvt();

select * from fsubmitorder(6,'own82',NULL,'qlt22',1,'qlt23',1,1);select * from fproducemvt(); 
select * from fsubmitorder(2,'own82',NULL,'qlt22',61017,'qlt23',45276,45276);select * from fproducemvt(); 
--select * from fsubmitorder(2,'own82',NULL,'qlt22',61017,'qlt23',45276,76596);select * from fproducemvt(); 
-- select * from fillstack(100);
-- select * from fproducemvt();
/*
\timing on
select * from femptystack();
\timing off
select * from fgetcounts();
select * from fverifqtts();
select * from fgeterrs();
*/

