CREATE OR REPLACE FUNCTION hello( TEXT )
RETURNS TEXT AS
  'exampleText.so', 'hello'
LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION
  matchts( TSQUERY,TSVECTOR )
RETURNS
  BOOLEAN
AS
  'exampleText.so', 'matchts'
LANGUAGE
  C
STRICT
IMMUTABLE; 
/*
CREATE TYPE ctext AS (
	tleft text,
	tright text
);*/
CREATE OR REPLACE FUNCTION hello2( ctext )
RETURNS TEXT AS
  'exampleText.so', 'hello2'
LANGUAGE C STRICT IMMUTABLE;


CREATE TYPE __retcomposite AS (f1 integer, f2 integer, f3 integer);

CREATE OR REPLACE FUNCTION retcomposite(integer, integer)
    RETURNS SETOF __retcomposite
    AS 'exampleText.so', 'retcomposite'
    LANGUAGE C IMMUTABLE STRICT;
/*
CREATE TEMP TABLE testt(tv,c) as values (to_tsvector('fat cats ate fat rats'),'(0,0),(1,1)'::cube),(to_tsvector('fat cats ate fat rots'),'(0,0),(1,1)'::cube);
CREATE INDEX testt_gin ON testt USING GIST(tv,c);
select * from testt where tv @@ to_tsquery('fat & cat') and c@> '0.5,0.5'::cube;

pour l'indexation text, charger l'extension btree_gin,
CREATE EXTENSION btree_gin;
CREATE INDEX .... USING (t text_ops);

SELECT matchts(to_tsquery('fat & rat'),to_tsvector('fat cats ate fat rats'));

CREATE EXTENSION cube;
******************************************************
le multicolumn index est possible avec GIN et GIST
cube n'a pas de GIN method
******************************************************

create aggregate ar_int_cat(int[]) (
sfunc = array_cat,
stype = int[],
initcond = '{}'       
);
create temp table te(ar) as values (array[1,2]),(array[3,4]),(array[5,6]);
select ar_int_cat(ar) from te;

un agregat peut se faire sur des tableaux d'entiers
*******************************************************




*/
