set search_path = ob;
select ob_fadd_account('own1','q1',100);
select ob_fadd_account('own1','q1',200);
select ob_fsub_account('own1','q1',300);
select ob_fget_errs();
select count(*) from ob_tstock; -- no stock remains
truncate ob_tquality cascade;
