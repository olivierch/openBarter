-- Trilateral exchange between owners with distinct users
---------------------------------------------------------
--variables
--USER:admin
select  * from market.tvar where name != 'OC_CURRENT_OPENED' order by name; 
---------------------------------------------------------
\set ECHO all
SELECT * FROM fsubmitorder('best','Mallory','Fe',200,'Ni',40);
SELECT * FROM fsubmitorder('best','Luc','Ni',100,'Co',50);
SELECT * FROM fsubmitorder('best','Bob','Fe',40,'Co',50);

SELECT * FROM fsubmitorder('best','Alice','Co',80,'Fe',100);

SELECT * from vmsg_mvt;

/*
à l'init du modèle et en tests:
tconst ('QUAPROVUSR',0),('OWNUSR',0),('DEBUG',1)
tvar ('OC_CURRENT_PHASE',102),('OC_BGW_CONSUMESTACK_ACTIVE',1),('OC_BGW_OPENCLOSE_ACTIVE',0)

en prod- possible qd foc_in_gphase(100)
tconst ('QUAPROVUSR',1),('OWNUSR',1),('DEBUG',0)
tvar ('OC_CURRENT_PHASE',102),('OC_BGW_CONSUMESTACK_ACTIVE',1),('OC_BGW_OPENCLOSE_ACTIVE',1)

stopper l'évolution des phases

POUR CREER UN CLIENT
select create_client('nom_du_client');
retourne 1 si c'est fait, 0 sinon

POUR DEMARRER LE MARCHE
select fset_debug(false)
select fstart_phases(1)

POUR ARRETER LE MARCHER
select fstart_phase(-1)

POUR FAIRE DES TESTS
select fset_debug(true)

*****************************************************************************************
TODO
site www.openbarter.org
	copier le site www.openbarter.org en local
	ajouter les actualités et pages statiques
	rédaction des parties fixes
	rédaction de l'acticle annonçant la publication
finir la doc
	* paramètrage ssl serveur
	* arret marche du BGW
	* tests
	* nommages user et qualités
chargement sur github
annonce sur la liste et neil peters, etc

