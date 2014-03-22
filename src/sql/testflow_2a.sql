drop extension if exists flowf cascade;
create extension flowf;
	
-- yflow ''[(type,id,oid,own,qtt_requ,qtt_prov,qtt,proba), ...]''


-- (type,id,oid,own,qtt_requ,qtt_prov,qtt,proba)
select yflow_show('[(2, 8928, 8928, 72, 49263, 87732, 87732, 1.000000),(1, 515, 515, 69, 53751, 67432, 67432, 1.000000),(141, 10001, 10001, 72, 1, 1, 1, 1.000000)]'::yflow);
select yflow_show('[(2, 8928, 8928, 72, 49263, 87732, 87732, 1.000000),(1, 515, 515, 69, 53751, 67432, 67432, 1.000000),(1, 10001, 10001, 72, 67432, 30183,30183, 1.000000)]'::yflow);

