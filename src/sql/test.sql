drop table trefused;
drop table torder;
drop table _tmp;
create table torder(id,qtt,nr,np,qtt_prov,qtt_requ,own) 
as select s::int8,s*100,(random()*100000)::int8,(random()*100000)::int8,s*100,s*100,s from generate_series(1,200000) s; 

alter table torder add primary key(id);
create table trefused ( 
    x int8 references torder(id) not NULL , 
    y int8 references torder(id) not NULL ,
    PRIMARY KEY (x,y),UNIQUE(x,y)
);

	CREATE TEMP TABLE _tmp AS (
		WITH RECURSIVE search_backward(id,nr,qtt_prov,qtt_requ,
						own,qtt,np,
						depth) AS (
			SELECT b.id, b.nr,b.qtt_prov,b.qtt_requ,
				b.own,b.qtt,b.np,
				2
				FROM torder b
				WHERE 	b.np = 1 -- v->pivot
					AND b.qtt != 0
			UNION 
			SELECT Xb.id, Xb.nr,Xb.qtt_prov,Xb.qtt_requ,
				Xb.own,Xb.qtt,Xb.np,
				Y.depth + 1
				FROM torder Xb, search_backward Y 
				WHERE 	Xb.np = Y.nr -- X->Y
					-- AND Xb.sid = Xv.id 
					AND Xb.qtt !=0 
					AND Y.depth < 8
					AND NOT EXISTS (
						SELECT * FROM trefused WHERE Xb.id=x and Y.id=y)
		)
		SELECT id,nr,qtt_prov,qtt_requ,own,qtt,np,NULL::int as flow,0 as valid,depth 
		FROM search_backward
	);
-- pour faire une mesure de temps \timing
