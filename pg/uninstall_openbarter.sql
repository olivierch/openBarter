/* model */
DROP FUNCTION IF EXISTS ob.fquality_created() CASCADE;
DROP FUNCTION IF EXISTS ob.ftime_created() CASCADE;
DROP FUNCTION IF EXISTS ob.ftime_updated() CASCADE;
DROP FUNCTION IF EXISTS ob.ins_version() CASCADE;
	
DROP SEQUENCE IF EXISTS ob.tquality_id_seq,ob.towner_id_seq,ob.tdraft_id_seq,ob.tstock_id_seq,
	ob.tnoeud_id_seq,ob.tcommit_id_seq,ob.tmvt_id_seq CASCADE;


/* functions */
DROP TYPE IF EXISTS ob.tlmvt CASCADE; --used evrywhere
DROP FUNCTION IF EXISTS ob.fbatch_omega() CASCADE;
DROP FUNCTION IF EXISTS ob.fread_omega(int8,int8) CASCADE;
DROP FUNCTION IF EXISTS ob.finsert_sbid(int8,int8,int8,text) CASCADE;
DROP FUNCTION IF EXISTS ob.finsert_bid(text,text,int8,int8,text) CASCADE;
DROP FUNCTION IF EXISTS ob.finsert_bid_int(int8,int8,int8,text) CASCADE;
DROP FUNCTION IF EXISTS ob.faccept_draft(int8,text) CASCADE;
DROP FUNCTION IF EXISTS ob.frefuse_draft(int8,text) CASCADE;
DROP FUNCTION IF EXISTS ob.frefuse_draft_int(int8,int8) CASCADE;
DROP FUNCTION IF EXISTS ob.fdelete_bid(int8) CASCADE;
DROP FUNCTION IF EXISTS ob.fdelete_bid_int(int8) CASCADE;
DROP FUNCTION IF EXISTS ob.finsert_das(ob.tstock,bigint,char) CASCADE;
DROP FUNCTION IF EXISTS ob.fremove_das(int8) CASCADE;
DROP FUNCTION IF EXISTS ob.fsub_account(text,text,int8) CASCADE;
DROP FUNCTION IF EXISTS ob.fadd_account(text,text,int8) CASCADE;
DROP FUNCTION IF EXISTS ob.finsert_omega(int8, int8, int8, int8, int8, int8) CASCADE;
DROP FUNCTION IF EXISTS ob.fomega_draft( int8) CASCADE;
DROP FUNCTION IF EXISTS ob.finsert_omega_int( int8, int8) CASCADE;
DROP FUNCTION IF EXISTS ob.finsert_omegap( int8, int8) CASCADE;
DROP FUNCTION IF EXISTS ob.fexecute_commit( ob.tcommit, ob.tcommit) CASCADE; 
DROP FUNCTION IF EXISTS ob.fexecute_draft( int8) CASCADE;
DROP FUNCTION IF EXISTS ob.fread_status_draft( ob.tdraft)  CASCADE;
DROP FUNCTION IF EXISTS ob.fupdate_status_commits( int8, int8, int4, int4) CASCADE;
DROP TYPE IF EXISTS ob.tret_stats CASCADE;
DROP FUNCTION IF EXISTS ob.fstats() CASCADE;

DROP FUNCTION IF EXISTS ob.fdelete_draft(int8) CASCADE;
DROP FUNCTION IF EXISTS ob.fcurrval_tdraft() CASCADE;
DROP FUNCTION IF EXISTS ob.fget_user() CASCADE;
DROP FUNCTION IF EXISTS ob.fcreate_quality(text) CASCADE;

DROP VIEW IF EXISTS ob.vowned,ob.vbalance,ob.vmvt,ob.vdraft,ob.vbid CASCADE;


DROP TABLE IF EXISTS ob.tquality,ob.towner,ob.tstock,ob.tnoeud,ob.tdraft,
	ob.tcommit,ob.tldraft,ob.tomega,ob.tlomega,ob.tmvt,ob.tconnectdesc CASCADE;
DROP SCHEMA IF EXISTS ob;
/* roles */
-- DROP ROLE IF EXISTS market,depositary;

	
