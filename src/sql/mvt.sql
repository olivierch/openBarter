

--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fverify() RETURNS void AS $$
DECLARE
	_name	text;
	_delta	int8;
	_nberrs	int := 0;
BEGIN
	FOR _name,_delta IN SELECT name,delta FROM vstat WHERE delta!=0 LOOP
		RAISE WARNING 'quality % is in error:delta=%',_name,_delta;
		_nberrs := _nberrs +1;
	END LOOP;
	IF(_nberrs != 0) THEN
		RAISE EXCEPTION USING ERRCODE='YA001'; 		
	END IF;
	RETURN;
/* 
TODO
1°) vérifier que le nom d'un client ne contient pas /
2°) lorsqu'un accord est refuse quand l'un des prix est trop fort,
mettre le refus sur la relation dont le prix est le plus élevé relativement au prix fixé

********************************************************************************
CH18 log_min_message,client_min_message defines which level are reported to client/log
by default 
log_min_message=
client_min_message=

BEGIN
	bloc
	RAISE EXCEPTION USING ERRCODE='YA001';
EXCEPTION WHEN SQLSTATE 'YA001' THEN
	RAISE NOTICE 'voila le PB';
END;
rollback the bloc and notice the problem to the client only
*/

END;
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
/* the table of movements tmvt can only be selected by the role CLIS
a given record can be deleted by CLIS only if nat is owned by this user 
*/
--------------------------------------------------------------------------------
create function fackmvt(_mid int8) RETURNS bool AS $$
DECLARE
	_mvt 	tmvt%rowtype;
	_q	tquality%rowtype;
	_uid	int8;
	_cnt 	int;
BEGIN
	_uid := fconnect(false);
	DELETE FROM tmvt USING tquality 
		WHERE tmvt.id=_mid AND tmvt.nat=tquality.id AND tquality.did=_uid 
		RETURNING * INTO _mvt;
		
	IF(FOUND) THEN
		UPDATE tquality SET qtt = qtt - _mvt.qtt WHERE id=_mvt.nat
			RETURNING * INTO _q;
		IF(NOT FOUND) THEN
			RAISE WARNING 'quality[%] of the movement not found',_mvt.nat;
			RAISE EXCEPTION USING ERRCODE='YA003';
		ELSE
			IF (_q.qtt<0 ) THEN 
				RAISE WARNING 'Quality % underflows',_quality_name;
				RAISE EXCEPTION USING ERRCODE='YA001';
			END IF;
		END IF;
		-- TODO supprimer les ordres associés s'ils sont vides et qu'ils ne sont pas associés à d'autres mvts
		SELECT count(*) INTO _cnt FROM tmvt WHERE orid=_mvt.orid;
		IF(_cnt=0) THEN
			DELETE FROM torder o USING tmvt m 
				WHERE o.id=_mvt.orid;
		END IF;
		
		IF(fgetconst('VERIFY') = 1) THEN
			perform fverify();
		END IF;
		
		RAISE INFO 'movement removed';
		RETURN true;
	ELSE
		RAISE NOTICE 'the quality of the movement is not yours';
		RAISE EXCEPTION USING ERRCODE='YU001';
		RETURN false;
	END IF;
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE NOTICE 'ABORTED';
	RETURN 0;
END;		
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fackmvt(int8) TO market;

--------------------------------------------------------------------------------
CREATE FUNCTION fdroporder(_oid int8) RETURNS torder AS $$
DECLARE
	_o torder%rowtype;
	_qp tquality%rowtype;
BEGIN
	DELETE FROM torder o USING tquality q 
	WHERE o.id=_oid AND o.np=q.id AND q.depository=current_user 
	RETURNING o.* INTO _o;
	IF(FOUND) THEN
		-- delete by cascade trefused
		
		UPDATE tquality SET qtt = qtt - _o.qtt 
			WHERE id = _o.np RETURNING * INTO _qp;
		IF(NOT FOUND) THEN
			RAISE WARNING 'The quality of the order % is not present',_oid;
			RAISE EXCEPTION USING ERRCODE='YA003';
		END IF;
		IF (_qp.qtt<0 ) THEN 
			RAISE WARNING 'Quality % underflows',_quality_name;
			RAISE EXCEPTION USING ERRCODE='YA001';
		END IF;
		
		IF(fgetconst('VERIFY') = 1) THEN
			perform fverify();
		END IF;
		RAISE INFO 'order % dropped',_oid;
		RETURN _o;
	ELSE
		RAISE NOTICE 'this order % is not yours or does not exist',_oid;
		RAISE EXCEPTION USING ERRCODE='YU001';
	END IF;
EXCEPTION WHEN SQLSTATE 'YU001' THEN
	RAISE NOTICE 'ABORTED';
	RETURN NULL;
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION fdroporder(int8) TO market;
