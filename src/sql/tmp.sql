/* Renumbering function */
CREATE TABLE t (
	id serial UNIQUE NOT NULL,
	c text DEFAULT 'aaa'
);

INSERT INTO t (id,c) VALUES (1,'a'),(2,'b'),(4,'c');

ALTER TABLE t DISABLE TRIGGER ALL;

CREATE TEMP SEQUENCE tmp_seq;
WITH a AS (SELECT * FROM t ORDER BY id ASC)
UPDATE t SET id=nextval('tmp_seq') FROM a WHERE t.id=a.id;
DROP SEQUENCE tmp_seq;
ALTER TABLE t ENABLE TRIGGER ALL;

/* liste des exceptions 
YA001	table renumbering problem
YA002	incorrect values of parameters of the model
YA003	panic
YA004	overflow of a quality
YA005	unknown user

YU001	command failed due to incorrect input.
YU002	the flow is not in sync with the database.
YU003	quota reached


*/
/* liste des tables */
tconst		
tuser		
tquality
treltried
towner

ALTER TABLE tquality DROP CONSTRAINT cquality_idd,ADD CONSTRAINT ctquality_idd FOREIGN KEY (idd) references tuser(id)


	LOOP
		UPDATE tquality SET id = id,qtt = qtt + _qtt 
			WHERE name = _quality_name RETURNING id,qtt INTO _id,_qtta;

		IF FOUND THEN
			RETURN _id;
		END IF;
		
		BEGIN
		
			INSERT INTO tquality (name,idd,depository,qtt) VALUES (_quality_name,_idd,_q[1],_qtt)
				RETURNING * INTO _qp;
			RETURN _qp.id;
			
		EXCEPTION WHEN unique_violation THEN
			--
		END;
	END LOOP;
	
************************************************************
/*
fonctions modifiées
ouverture,fermeture .. du marché remplacées par fchangestatemarket(_execute bool)


ACCOUNTING
----------------------------------------------------------
* fremoveagreement(_grp int)

when mvt->mvtremoved by user 
	quality is decreased

----------------------------------------------------------
* fremoveorder(_uuid text)
	
when order is removed by user 
	quality is decreased (symetric with finsertorder)
	order->orderremoved (it is not cleared)
	=>
		order is removed but related mvts may remain
		
----------------------------------------------------------	
* fexecute_flow(_flw yflow)

when order produces movements as the result of agreement execution
	movements are created
	
----------------------------------------------------------
* finsertorder(_owner text,_qualityprovided text,_qttprovided int8,_qttrequired int8,_qualityrequired text)

when order is created
	quality is increased
	
----------------------------------------------------------
* finvalidate_treltried()

when order is cancelled due to maxtry
	movement is created =>
		quality is NOT decreased	
	order->orderremoved (it is NOT empty)
	
----------------------------------------------------------
* fremoveagreement(_grp int)

when an agreement is red by user
	quality is decreased
	mvt -> mvtremoved
*/
/*
MARKET PHASES

*/
A VOIR 
- LES PHASES DU MARCHE OK
- LES CODES ERREUR OK
- LES QUOTAS DE TEMPS OK 
- MAXTRY VENTILE SUR LES USER

CREATE FUNCTION fi() RETURNS int8 AS $$ 
DECLARE
	_t1 timestamp;
	_t2 timestamp;
BEGIN
	_t1 := clock_timestamp();
	perform pg_sleep(1.5);
	_t2 := clock_timestamp();
	return extract (microseconds from (_t2-_t1));
END;
$$ LANGUAGE PLPGSQL;







