NOTES modifs

TODO
----
flow_1.sql OK
lorsqu'il n'y a pas de solution, refuser la relation!

*********************************************

liste des fcts C utilisées:

flow_omegay(Y.flow,X.flow,Y.qtt_prov,Y.qtt_requ)
flow_cat(CASE WHEN Y.flow IS NULL THEN '[]'::flow ELSE Y.flow END
				   ,X.flow,Y.id,Y.nr,Y.qtt_prov,Y.qtt_requ,Y.own,Y.qtt,Y.np)-- TODO 7eme parametre supprimé
flow_dim(_flow)
_flowrs := flow_proj(_flow,9);
flow_init(t.id,t.nr,t.qtt_prov,t.qtt_requ,t.own,t.qtt,t.np) -- TODO 5eme parametre supprime
flow_to_matrix(fget_flows)
flow_to_commits(_flow)

model.sql:ob_fget_omegas
	-- TODO sid est supprimé dans _tmp, prendre own==0 au lieu de sid==0 pour savoir si le
	-- traitement à faire (calcul du flux avec ou sans prise en compte de la qtt du pivot )
	
	//int64	id,nr,qtt_prov,qtt_requ,sid,own,qtt,np,flowr;
	int64	id,nr,qtt_prov,qtt_requ,own,qtt,np,flowr;
	id 		1
	nr		2
	qtt_prov	3
	qtt_requ	4
	own		6	5
	qtt		7	6
	np		8	7
	flowr		9	8
	appliqué sur model.sql
	
OK mettre à jour quality.qtt quand le mvt est effaçé

**********************************************************
ERROR CODES
YA001	quality overflows
YA002	accounting error
YA003	internal error

YU001	ABORT

en principe, YU001 est attrappée.

RAISE NOTICE est notifié seulement au client INFO idem
	INFO information
	NOTICE attention
RAISE WARNING est notifié au client et au log
RAISE EXCEPTION 
	block rollback
	si catchée, non notifiée 
	sinon notifiée au client et sur le log
	
***********************************************************
Les droits et profils

xx	a user who has the role client
client	a role that inherit of role market when the market is opened
market	role with rights to execute primitives of market
admin	a user in charge of:
		* opening and closing market
		* recording new users
		
		


	
