/* model */
DROP FUNCTION IF EXISTS ob_fquality_created() CASCADE;
DROP FUNCTION IF EXISTS ob_ftime_created() CASCADE;
DROP FUNCTION IF EXISTS ob_ftime_updated() CASCADE;
DROP FUNCTION IF EXISTS ob_ins_version() CASCADE;
	
DROP SEQUENCE IF EXISTS ob_tquality_id_seq,ob_towner_id_seq,ob_tdraft_id_seq,ob_tstock_id_seq,
	ob_tnoeud_id_seq,ob_tcommit_id_seq,ob_tmvt_id_seq CASCADE;


/* functions */
DROP TYPE IF EXISTS ob_tlmvt CASCADE; --used evrywhere
DROP FUNCTION IF EXISTS ob_fbatch_omega() CASCADE;
DROP FUNCTION IF EXISTS ob_fread_omega(int8,int8) CASCADE;
DROP FUNCTION IF EXISTS ob_finsert_sbid(int8,int8,int8,text) CASCADE;
DROP FUNCTION IF EXISTS ob_finsert_bid(text,text,int8,int8,text) CASCADE;
DROP FUNCTION IF EXISTS ob_finsert_bid_int(int8,int8,int8,text) CASCADE;
DROP FUNCTION IF EXISTS ob_faccept_draft(int8,text) CASCADE;
DROP FUNCTION IF EXISTS ob_frefuse_draft(int8,text) CASCADE;
DROP FUNCTION IF EXISTS ob_frefuse_draft_int(int8,int8) CASCADE;
DROP FUNCTION IF EXISTS ob_fdelete_bid(int8) CASCADE;
DROP FUNCTION IF EXISTS ob_fdelete_bid_int(int8) CASCADE;
DROP FUNCTION IF EXISTS ob_finsert_das(ob_tstock,bigint,char) CASCADE;
DROP FUNCTION IF EXISTS ob_fremove_das(int8) CASCADE;
DROP FUNCTION IF EXISTS ob_fsub_account(text,text,int8) CASCADE;
DROP FUNCTION IF EXISTS ob_fadd_account(text,text,int8) CASCADE;
DROP FUNCTION IF EXISTS ob_finsert_omega(int8, int8, int8, int8, int8, int8) CASCADE;
DROP FUNCTION IF EXISTS ob_fomega_draft( int8) CASCADE;
DROP FUNCTION IF EXISTS ob_finsert_omega_int( int8, int8) CASCADE;
DROP FUNCTION IF EXISTS ob_finsert_omegap( int8, int8) CASCADE;
DROP FUNCTION IF EXISTS ob_fexecute_commit( ob_tcommit, ob_tcommit) CASCADE; 
DROP FUNCTION IF EXISTS ob_fexecute_draft( int8) CASCADE;
DROP FUNCTION IF EXISTS ob_fread_status_draft( ob_tdraft)  CASCADE;
DROP FUNCTION IF EXISTS ob_fupdate_status_commits( int8, int8, int4, int4) CASCADE;
DROP TYPE IF EXISTS ob_tret_stats CASCADE;
DROP FUNCTION IF EXISTS ob_fstats() CASCADE;

DROP FUNCTION IF EXISTS ob_fdelete_draft(int8) CASCADE;
DROP FUNCTION IF EXISTS ob_fcurrval_tdraft() CASCADE;
DROP FUNCTION IF EXISTS ob_fget_user() CASCADE;
DROP FUNCTION IF EXISTS ob_fcreate_quality(text) CASCADE;

DROP VIEW IF EXISTS ob_vowned,ob_vbalance,ob_vmvt,ob_vdraft,ob_vbid CASCADE;


DROP TABLE IF EXISTS ob_tquality,ob_towner,ob_tstock,ob_tnoeud,ob_tdraft,
	ob_tcommit,ob_tldraft,ob_tomega,ob_tlomega,ob_tmvt,ob_tconnectdesc CASCADE;

/* roles */
-- DROP ROLE IF EXISTS market,depositary;

	
