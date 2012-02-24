set schema 't';
-- uuid,owner,qua_requ,qtt_requ,qua_prov,qtt_prov,qtt,created,updated

create table torderempty ( 
    --uuid text NOT NULL,
    uuid text,
    owner text NOT NULL,
    qua_requ text NOT NULL,
    qtt_requ int8 not NULL,
    qua_prov text not NULL,
    qtt_prov int8 not NULL,
    qtt int8 not NULL,
    created timestamp not NULL,
    updated timestamp
);

ALTER TABLE torder ADD COLUMN tid int8 DEFAULT NULL;
ALTER TABLE torder ADD COLUMN uuid text DEFAULT NULL;

ALTER TABLE tmvt ADD COLUMN oruuid text DEFAULT NULL;

DROP VIEW vmvt;
CREATE VIEW vmvt AS 
	SELECT 	m.id as id,
		m.oruuid as oruuid,
		m.grp as grp,
		w_src.name as provider,
		q.name as nat,
		m.qtt as qtt,
		w_dst.name as receiver,
		m.created as created
	FROM tmvt m
	INNER JOIN towner w_src ON (m.own_src = w_src.id)
	INNER JOIN towner w_dst ON (m.own_dst = w_dst.id) 
	INNER JOIN tquality q ON (m.nat = q.id); 
	
-- ALTER TABLE tmvt DROP COLUMN orid;

--------------------------------------------------------------------------------
-- id,uuid,owner,qua_requ,qtt_requ,qua_prov,qtt_prov,qtt,nbrefused,created,updates,omega
DROP VIEW vorder;
CREATE VIEW vorder AS 
	SELECT 	
		n.id as id,
		n.uuid as uuid,
		w.name as owner,
		qr.name as qua_requ,
		n.qtt_requ,
		qp.name as qua_prov,
		n.qtt_prov,
		n.qtt,
		array_length(n.refused,1) as nbrefused,
		n.created as created,
		n.updated as updated,
		CAST(n.qtt_prov as double precision)/CAST(n.qtt_requ as double precision) as omega
	FROM torder n
	INNER JOIN tquality qr ON n.nr = qr.id 
	INNER JOIN tquality qp ON n.np = qp.id
	INNER JOIN towner w on n.own = w.id;

/* removes from refused orders that do not exist */ 

CREATE OR REPLACE FUNCTION fcleanorders(_reindex bool) RETURNS TABLE(name text,cnt int8)  AS $$
DECLARE
	_vo 		vorder%rowtype;
	_MAX_REFUSED 	int := fgetconst('MAX_REFUSED');
	_refused	int8[];
	_nrefused	int8[];
	_oid		int8;
	_tid		int8;
	_oid2		int8;
	_oid3		int8;
	_cnt 		int := 0;
	_cnt1		int;
	_changed	bool;
BEGIN
	LOCK TABLE torder IN EXCLUSIVE MODE NOWAIT;
	
	-- useless orders moved out
	FOR _vo IN SELECT * FROM vorder WHERE qtt=0 OR nbrefused >_MAX_REFUSED LOOP
		INSERT INTO torderempty (uuid,owner,qua_requ,qtt_requ,qua_prov,qtt_prov,qtt,created,updated) 
		VALUES (_vo.uuid,_vo.owner,_vo.qua_requ,_vo.qtt_requ,_vo.qua_prov,_vo.qtt_prov,_vo.qtt,_vo.created,_vo.updated);
		DELETE FROM torder WHERE id=_vo.id;
	END LOOP;
	
	IF(_reindex) THEN
		_cnt := 0;_cnt1 := 0;
		FOR _oid IN SELECT id FROM torder ORDER BY id ASC LOOP
			_cnt := _cnt +1;
			UPDATE torder SET tid = _cnt WHERE id = _oid;
			IF(_oid != _cnt) THEN
				_cnt1 := _cnt1 + 1;
			END IF;
		END LOOP;
		-- TODO serial reinit
	
		name := 'number of orders reindexed';
		cnt := _cnt1;
		RETURN NEXT;
	ELSE
		UPDATE torder SET tid = id;
	END IF;
	-- new index is in tid

	_cnt := 0;
	FOR _oid,_refused,_changed IN SELECT id,refused,id!=tid FROM torder LOOP
		_nrefused := ARRAY[]::int8[];
		
		-- foreach _oid2 in torder[_oid].refused:
		FOR _oid2 IN SELECT _refused[i] FROM generate_subscripts(_refused,1) g(i) LOOP
			SELECT tid INTO _tid FROM torder WHERE id=_oid2;
			IF(NOT FOUND) THEN
				_changed := true;
			ELSE
				_nrefused := _nrefused || _tid;
				IF(_tid != _oid2) THEN
					_changed := true;
				END IF;
			END IF;
		END LOOP;
		
		IF(_changed) THEN
			UPDATE torder SET refused = _nrefused WHERE id = _oid;
			_cnt := _cnt + 1;
		END IF;
	END LOOP;
	UPDATE torder SET id = tid, tid = NULL;
	
	name := 'number of torder.refused changed';
	cnt := _cnt;
	RETURN NEXT;
	
	RETURN;
END;
$$ LANGUAGE PLPGSQL;


