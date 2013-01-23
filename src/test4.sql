drop schema IF EXISTS t CASCADE;
CREATE SCHEMA t;
SET search_path TO t;


drop extension if exists hstore cascade;
create extension hstore with version '1.1';

create table torder (
	id	serial,
	hs	hstore
);
-- create index torder_qua_prov_idx on torder using gin(((ord).qua_prov) text_ops);
create index hs_idx on torder using gin(hs gin_hstore_ops);

INSERT INTO torder (hs) VALUES ('a=>x'),('a=>1,b=>1.232323,c=>12.14');
	
select * from torder where hs ?& ARRAY['c','b','a'];
select * from torder where hs ?& ARRAY['a'];

select akeys('c=>1,b=>1.232323,a=>12.14'::hstore); -- sortis dans l'ordre alphabétique

select array_to_string(akeys('c=>1,b=>1.232323,a=>12.14'::hstore),'|','*');
-- donne  a|b|c
/*
hstore est un objet de postgres qui permet de stocker des dictionnaires de textes, avec des clef et des valeurs
pour 'a=>u,b=>v,c=>d' les clef sont a,b,c et les valeurs sont u,v,d

un ordre est exprimé par trois éléments quality_requ,weigth,quality_prov
la demande est exprimée par weigth = 'a=>1.0,b=>0.005,c=>0.005' et quality_requ = 'a=>u,b=>v,c=>d'
l'offre est exprimé par quality_prov = 'a=>u,b=>z,c=>d'

un matching entre ordres o1 et o2 a lieu si les clef de o1.quality_prov et o2.quality_requ coïncident
ce qui est le cas de l'exemple
poids = somme(si o2.quality_requ[i]=o1.quality_prov[i] alors o2.weigth[i] sinon 0)
ce poids est attachée à l'ordre o2
dans l'exemple il est de 1.05 car la clef b n'a pas la même valeur.

poids d'un cycle: produit des poids de ses ordres
OMEGA d'un cycle: produit des omega des ordres (quantité fournie/quantité demandée)

un cycle est ignoré si le produit poids*OMEGA < 1
les cycles sont mis en concurrence en maximisant ce produit.


*/
	

