
INSERT INTO tconst (name,value) VALUES 
('NB_BACKUP',7); -- number of backups before rotation


CREATE TABLE tmarket  (
 	id 	serial UNIQUE,
	ph0  	timestamp not NULL,
	ph1  	timestamp,
	ph2  	timestamp,
	backup	int,
	diag	int	
);-- CHECK(ph2>ph1 and ph1>ph0 ) NULL values

INSERT INTO tmarket (ph0,ph1,ph2,backup,diag) VALUES (statement_timestamp(),statement_timestamp(),statement_timestamp(),NULL,NULL);

CREATE VIEW vmarket AS SELECT
 	CASE WHEN ph1 IS NULL THEN 'OPENED' ELSE 
 		CASE WHEN ph2 IS NULL THEN 'CLOSING' ELSE 'CLOSED' END
	END AS state,
	ph0,ph1,ph2,backup,
	CASE WHEN diag=0 THEN 'OK' ELSE diag || ' ERRORS' END as diagnostic
	FROM tmarket ORDER BY ID DESC LIMIT 1; -- fgetconst('NB_BACKUP')
		
GRANT SELECT ON vorder TO market;

--------------------------------------------------------------------------------
/* phase of market
0	closed
1	opened
2	ended
*/
CREATE FUNCTION fadmin() RETURNS bool AS $$
DECLARE
	_b	bool;
	_phase	int;
	_market tmarket%rowtype;
BEGIN
	SELECT * INTO _market FROM tmarket ORDER BY ID DESC LIMIT 1;
	IF(_market.ph1 is NULL) THEN
		_phase := 1;
	ELSE 
		IF(_market.ph2 is NULL) THEN
			_phase := 2;
		ELSE
			_phase := 0;
		END IF;
	END IF;

	IF (_phase = 0) THEN -- was closed, opening
		GRANT market TO client;
		INSERT INTO tmarket (ph0) VALUES (statement_timestamp());
		RAISE NOTICE '[1] The market is now OPENED';
		RETURN true;
	END IF;
	IF (_phase = 1) THEN -- was opened, ending
		REVOKE market FROM client;
		UPDATE tmarket SET ph1=statement_timestamp() WHERE ph1 IS NULL;		
		RAISE NOTICE '[2] The market is now CLOSING';
		RETURN true;
	END IF;
	IF (_phase = 2) THEN -- was ended, closing
		-- REVOKE market FROM client;
		UPDATE tmarket SET ph2=statement_timestamp() WHERE ph2 IS NULL;
		RAISE NOTICE 'The closing starts ...';
		_b := fclose_market();
		RAISE NOTICE '[0] The market is now CLOSED';
		RETURN _b;
	END IF;
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fadmin()  TO admin;

CREATE FUNCTION fclose_market() RETURNS bool AS $$
DECLARE
	_backup int;
	_suf text;
	_sql text;
	_cnt int;
	_nbb 	int;
	_pivot torder%rowtype;
	_cnn	int8;
BEGIN
	
	_nbb := fgetconst('NB_BACKUP');
	-- rotation of backups
	SELECT max(id) INTO _cnt FROM tmarket;
	UPDATE tmarket SET backup= ((_cnt-2) % _nbb) +1 WHERE id=_cnt RETURNING backup INTO _backup;
	_suf := CAST(_backup AS text);
	
	EXECUTE 'DROP TABLE IF EXISTS torder_back_' || _suf;
	EXECUTE 'DROP TABLE IF EXISTS tmvt_back_' || _suf;
	EXECUTE 'CREATE TABLE torder_back_' || _suf || ' AS SELECT * FROM torder';
	EXECUTE 'CREATE TABLE tmvt_back_' || _suf || ' AS SELECT * FROM tmvt';
	
	RAISE NOTICE 'TMVT and TORDER saved into backups *_BACK_% among %',_backup,_nbb;
	
	TRUNCATE tmvt,trefused,torder;
	UPDATE tquality set qtt=0 ;
	
	-- reinsertion of orders
/*
	_sql := 'FOR _pivot IN SELECT * FROM torder_back_' || _suf || ' WHERE qtt != 0 ORDER BY created ASC LOOP 
			_cnt := finsert_order_int(_pivot,true);
		END LOOP';
	EXECUTE _sql;
*/
	-- RETURN false;
 
	EXECUTE 'SELECT finsert_order_int(row(id,qtt,nr,np,qtt_prov,qtt_requ,own,created,updated)::torder ,true) 
	FROM torder_back_' || _suf || ' 
	 WHERE qtt != 0 ORDER BY created ASC';
	
	-- diagnostic
	perform fverify();	
	SELECT count(*) INTO _cnn FROM tmvt;
	UPDATE tmarket SET diag=_cnn WHERE id=_cnt;
	IF(_cnn != 0) THEN
		RAISE NOTICE 'Abnormal termination of market closing';
		RAISE NOTICE '0 != % movement where found when orders where re-inserted',_cnn;
		
		RETURN false;
	ELSE
		RAISE NOTICE 'Normal termination of closing.';
		RETURN true;
	END IF;
	
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;


