

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

select finsertorder('u',fq('b'),1000,1000,fq('a'));
select finsertorder('v',fq('c'),1000,1000,fq('b'));
select fgetquote('w',fq('a'),fq('c'));
select finsertorder('w',fq('a'),1000,1000,fq('c'));
select id,nb,oruuid,grp,provider,fs(quality),qtt,receiver from vmvt;
select fremoveagreement(1);
select id,qtt from tquality;

select finsertorder('u',fq('b'),2000,1000,fq('a'));
select finsertorder('v',fq('c'),2000,1000,fq('b'));
select fgetquote('w',fq('a'),fq('c'));
select finsertorder('w',fq('a'),500,2000,fq('c'));
select id,nb,oruuid,grp,provider,fs(quality),qtt,receiver from vmvt;
select fremoveagreement(4);

select fgetquote('w',fq('a'),fq('b'));
select finsertorder('w',fq('a'),500,1000,fq('b'));
select fremoveagreement(7);
select id,qtt from tquality;

select * from fgetstats(true);

