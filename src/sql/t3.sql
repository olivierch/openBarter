DROP TABLE IF EXISTS _tmp;
CREATE TEMP TABLE _tmp /* ON COMMIT DROP */ AS (
		WITH RECURSIVE search_backward(id,nr,qtt_prov,qtt_requ,refused,
						own,qtt,np,
						depthb) AS (
			SELECT b.id, b.nr,b.qtt_prov,b.qtt_requ,b.refused,
				b.own,b.qtt,b.np,
				1
				FROM torder b
				WHERE 	b.id = 3 AND b.qtt > 0 
					AND (array_length(b.refused,1) IS NULL
						OR array_length(b.refused,1) < 30)			
			UNION 
			SELECT X.id, X.nr,X.qtt_prov,X.qtt_requ,X.refused,
				X.own,X.qtt,X.np,
				Y.depthb + 1 -- depthb in [1,_obCMAXCYCLE] 
				FROM torder X, search_backward Y
				WHERE 	X.qtt > 0 
					AND X.id != 3
					AND X.np = Y.nr AND NOT (Y.id = ANY(X.refused)) -- X->Y
					AND (array_length(Y.refused,1) IS NULL
						OR array_length(Y.refused,1) < 30)
					AND Y.depthb < 8 
					
		)
		SELECT id,nr,qtt_prov,qtt_requ,own,qtt,np,NULL::flow as flow,0 as cntgraph,depthb,0 as depthf,refused 
		FROM search_backward
	);
