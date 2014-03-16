-- Titre de reset Market
--USER:admin

truncate market.torder;
truncate market.tstack;
--ici
select setval('market.tstack_id_seq',1,false);

select setval('market.tmvt_id_seq',1,false);

truncate market.towner;
select setval('market.towner_id_seq',1,false);

truncate market.tmsg;
select setval('market.tmsg_id_seq',1,false);

select setval('market.tstack_id_seq',1,false);

select market.fsetvar('STACK_TOP',0);
select market.fsetvar('STACK_EXECUTED',0);
