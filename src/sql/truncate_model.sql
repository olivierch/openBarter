set search_path = ob;

truncate ob_tquality cascade;select setval('ob_tquality_id_seq',1,false);
truncate ob_towner cascade; select setval('ob_towner_id_seq',1,false);
truncate ob_tstock cascade; select setval('ob_tstock_id_seq',1,false);
truncate ob_tnoeud cascade; select setval('ob_tnoeud_id_seq',1,false);
truncate ob_trefused cascade;
truncate ob_tdraft cascade; select setval('ob_tdraft_id_seq',1,false);
truncate ob_tcommit cascade; select setval('ob_tcommit_id_seq',1,false);
truncate ob_tmvt cascade; select setval('ob_tmvt_id_seq',1,false);
truncate ob_towner cascade; select setval('ob_towner_id_seq',1,false);
insert into ob_towner (name) values ('market');
