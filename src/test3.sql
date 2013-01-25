drop schema IF EXISTS t CASCADE;
CREATE SCHEMA t;
SET search_path TO t;

drop extension if exists hstore cascade;
create extension hstore with version '1.1';

drop extension if exists flow cascade;
create extension flow with version '1.0';

create table torder ( 
	usr text,
    ord yorder,
    created timestamp not NULL,
    updated timestamp
);
CREATE OR REPLACE FUNCTION get_random_number(min int, max int) RETURNS int AS $$
BEGIN
    RETURN trunc(random() * (max-min) + min);
END;
$$ LANGUAGE PLPGSQL;
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

		_o := ROW(_cntloop,_cntloop,_own,_qttrequired,_qlt_requ,_qttprovided,_qtl_prov,_qttprovided)::yorder;
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

CREATE OR REPLACE FUNCTION 
	finds(_ordid int) RETURNS SETOF yorder[] AS $$
DECLARE
	_i	int;
BEGIN 
	RETURN QUERY (
	WITH RECURSIVE search_backward(debut,path,fin,seq,depth,cycle) AS(
		SELECT ord,array[ord],ord,array[(ord).id],1,false FROM torder WHERE (ord).id= _ordid
		UNION ALL
		SELECT X.ord,X.ord || Y.path,Y.fin,(ord).id || Y.seq,Y.depth+1,(X.ord).id = ANY(Y.seq)
		FROM torder X,search_backward Y
		WHERE (X.ord).qua_prov=(Y.debut).qua_requ AND Y.depth <5 AND NOT cycle AND NOT (X.ord).id = ANY(Y.seq)
	) SELECT path from search_backward WHERE (fin).qua_prov=(debut).qua_requ
	);

END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;

select fpopulates(1000);
select count(*) from finds(10);


CREATE OR REPLACE FUNCTION 
	find(_ordid int) RETURNS SETOF yflow AS $$
DECLARE
	_i	int;
BEGIN 
	RETURN QUERY (
	WITH RECURSIVE search_backward(debut,path,fin,depth,cycle) AS(
		SELECT ord,yflow_init(ord),ord,1,false FROM torder WHERE (ord).id= _ordid
		UNION ALL
		SELECT X.ord,yflow_grow(X.ord,Y.debut,Y.path),Y.fin,Y.depth+1,yflow_contains_id((X.ord).id,Y.path)
		FROM torder X,search_backward Y
		WHERE (X.ord).qua_prov=(Y.debut).qua_requ AND yflow_match(X.ord,Y.debut) 
			AND Y.depth <5 
			AND NOT cycle 
			AND NOT yflow_contains_id((X.ord).id,Y.path)
	) SELECT yflow_finish(debut,path,fin) from search_backward WHERE (fin).qua_prov=(debut).qua_requ AND yflow_match(fin,debut) 
	);

END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
select count(*) from find(10);

-- select yflow_show(x.fl) from (select yflow_max(y.fl) as fl from (SELECT find(10) as fl) y ) x;


/*

select yflow_is_draft('[(35, 93, 35, 21170, 2685, 2685, 1.000000),(636, 50, 636, 12213, 95415, 95415, 1.000000
),(389, 68, 389, 23785, 29283, 29283, 1.000000),(274, 12, 274, 58834, 80362, 80362, 1.000000),(12, 
55, 12, 35136, 55490, 55490, 1.000000)]'::yflow);

select yflow_reduce(x.f1,x.f1) from (select '[(35, 93, 35, 21170, 2685, 2685, 1.000000),(636, 50, 636, 12213, 95415, 95415, 1.000000
),(389, 68, 389, 23785, 29283, 29283, 1.000000),(274, 12, 274, 58834, 80362, 80362, 1.000000),(12, 
55, 12, 35136, 55490, 55490, 1.000000)]'::yflow as f1) x;

select yflow_show('[(35, 93, 35, 21170, 2685, 2685, 1.000000),(636, 50, 636, 12213, 95415, 95415, 1.000000
),(389, 68, 389, 23785, 29283, 29283, 1.000000),(274, 12, 274, 58834, 80362, 80362, 1.000000),(12, 
55, 12, 35136, 55490, 55490, 1.000000)]'::yflow);
select yflow_to_matrix('[(35, 93, 35, 21170, 2685, 2685, 1.000000),(636, 50, 636, 12213, 95415, 95415, 1.000000
),(389, 68, 389, 23785, 29283, 29283, 1.000000),(274, 12, 274, 58834, 80362, 80362, 1.000000),(12, 
55, 12, 35136, 55490, 55490, 1.000000)]'::yflow);

select yflow_show('[(35, 93, 35, 21170, 2685, 2685, 1.000000),(636, 50, 636, 12213, 95415, 95415, 1.000000
),(389, 68, 389, 23785, 29283, 29283, 1.000000),(274, 12, 274, 58834, 80362, 80362, 1.000000),(12, 
55, 12, 35136, 55490, 55490, 1.000000)]'::yflow);
select yflow_qtts('[(35, 93, 35, 21170, 2685, 2685, 1.000000),(636, 50, 636, 12213, 95415, 95415, 1.000000
),(389, 68, 389, 23785, 29283, 29283, 1.000000),(274, 12, 274, 58834, 80362, 80362, 1.000000),(12, 
55, 12, 35136, 55490, 55490, 1.000000)]'::yflow);
*/

TODO
yflow_match(yorder,yorder)


*/
