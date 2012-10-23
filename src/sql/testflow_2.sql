

CREATE FUNCTION 
	fq(_quality_name text) 
	RETURNS text AS $$
BEGIN
	RETURN session_user || '/' || _quality_name;
END;
$$ LANGUAGE PLPGSQL;

CREATE FUNCTION 
	fs(_quality_name text) 
	RETURNS text AS $$
BEGIN
	RETURN substring(_quality_name from position ('/' in _quality_name)+1);
END;
$$ LANGUAGE PLPGSQL;

select fcreateuser(session_user);
-- own,qual_prov,qtt_prov,qtt_requ,qual_requ

select * from finsertorder('u',fq('b'),1000,1000,fq('a'));
select * from finsertorder('v',fq('c'),1000,1000,fq('b'));
select id,nr,qtt_requ,np,qtt_prov,qtt_in,qtt_out,flows from fgetquote('w',fq('a'),1000,1000,fq('c')); 
select id,nr,qtt_requ,np,qtt_prov,qtt_in,qtt_out,flows from fexecquote('w',1);
select id,uuid,nb,oruuid,grp,provider,fs(quality),qtt,receiver from vmvt order by uuid;
select * from fremovemvt('1-1');
select * from fremovemvt('1-2');
select * from fremovemvt('1-3');

select * from finsertorder('u',fq('b'),2000,1000,fq('a'));
select * from finsertorder('v',fq('c'),2000,1000,fq('b'));
select id,nr,qtt_requ,np,qtt_prov,qtt_in,qtt_out,flows from fgetquote('w',fq('a'),500,2000,fq('c'));
select id,nr,qtt_requ,np,qtt_prov,qtt_in,qtt_out,flows from fexecquote('w',2);
select id,uuid,nb,oruuid,grp,provider,fs(quality),qtt,receiver from vmvt order by uuid;
select * from fremovemvt('1-4');
select * from fremovemvt('1-5');
select * from fremovemvt('1-6');

select id,nr,qtt_requ,np,qtt_prov,qtt_in,qtt_out,flows from fgetquote('w',fq('a'),500,1000,fq('b'));
select id,nr,qtt_requ,np,qtt_prov,qtt_in,qtt_out,flows from fexecquote('w',3);
select id,uuid,nb,oruuid,grp,provider,fs(quality),qtt,receiver from vmvt order by uuid;
select * from fremovemvt('1-7');
select * from fremovemvt('1-8');

select * from fgetstats(true);
select * from fgeterrs();
