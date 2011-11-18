-----------------------------------------------------------------------
drop extension if exists flow cascade;
create extension flow;
select '[]'::flow;
-- id,nr,qtt_prov,qtt_requ,sid,own,qtt,np
select '[(1,2,3,4,5,6,7,8)]'::flow as flow;
select '[(1,2,3,4,5,6,7,8),(9,8,11,12,13,14,15,16)]'::flow as flow;
select flow_status('[(1,2,3,4,5,6,7,8)]'::flow);
select flow_omega('[(1,2,3,4,5,6,7,8)]'::flow);
select flow_cat('[(1,2,3,4,5,6,7,8)]'::flow,9,8,11,12,13,14,15,16);
select flow_proj('[(1,2,3,4,5,6,7,8),(9,8,11,12,13,14,15,16)]'::flow,1);
select flow_proj('[(1,2,3,4,5,6,7,8),(9,8,11,12,13,14,15,16)]'::flow,2);
select flow_proj('[(1,2,3,4,5,6,7,8),(9,8,11,12,13,14,15,16)]'::flow,9);
select flow_dim('[(1,2,3,4,5,6,7,8),(9,8,11,12,13,14,15,16)]'::flow);
select flow_to_matrix('[(1,2,3,4,5,6,7,8),(9,8,11,12,13,14,15,16)]'::flow);
-- cycle 3 nodes, 3 stocks,3 owners
-- id,nr,qtt_prov,qtt_requ,sid,own,qtt,np
-- result {20,80,40}
select flow_proj('[(1,3,1,1,1,1,20,1),(2,1,8,1,2,2,80,2),(3,2,1,1,3,3,120,3)]'::flow,9);

-- cycle 3 nodes, 3 stocks,3 owners - all stock exhausted
-- id,nr,qtt_prov,qtt_requ,sid,own,qtt,np
-- result {20,80,40}
select flow_proj('[(1,3,1,1,1,1,20,1),(2,1,8,1,2,2,80,2),(3,2,1,1,3,3,40,3)]'::flow,9);

-- idem with pivot.id=0 - lastIgnore
--result {10,80,10} even if the last stock has qtt=1
select flow_proj('[(1,3,1,1,1,1,20,1),(2,1,8,1,2,2,80,2),(0,2,1,1,0,3,1,3)]'::flow,9);

-- cycle 3 nodes, 3 stocks,2 owners
-- id,nr,qtt_prov,qtt_requ,sid,own,qtt,np
-- result {10,80,40}
select flow_proj('[(1,3,1,1,1,1,40,1),(2,1,16,1,2,2,80,2),(3,2,1,1,3,2,120,3)]'::flow,9);

-- cycle 2 nodes, 2 stocks,2 owners
-- id,nr,qtt_prov,qtt_requ,sid,own,qtt,np
-- result {20,20}
select flow_proj('[(1,2,2,1,1,1,20,1),(2,1,2,1,2,2,120,2)]'::flow,9);

-- cycle 4 nodes, 3 stocks,3 owners
-- id,nr,qtt_prov,qtt_requ,sid,own,qtt,np
-- result {80,80,80,80}
select flow_proj('[
(1,4,1,1,1,1,240,1),
(2,1,1,1,2,2, 80,2),
(3,2,1,1,1,1,240,1),
(4,1,1,1,3,3,120,4)]'::flow,9);

-- cycle 4 nodes, 3 stocks,3 owners
-- id,nr,qtt_prov,qtt_requ,sid,own,qtt,np
-- result {80,80,80,80}
select flow_proj('[
(1,4,2,1,1,1,240,1),
(2,1,4,1,2,2, 80,2),
(3,2,2,1,1,1,240,1),
(4,1,4,1,3,3,120,4)]'::flow,9);

-- flow_get_fim1_fi
select flow_proj('[(1,3,1,1,1,1,40,1),(2,1,16,1,2,2,80,2),(3,2,1,1,3,2,120,3)]'::flow,9);
-- result {10,80,40}
select flow_get_fim1_fi('[(1,3,1,1,1,1,40,1),(2,1,16,1,2,2,80,2),(3,2,1,1,3,2,120,3)]'::flow,0);
select flow_get_fim1_fi('[(1,3,1,1,1,1,40,1),(2,1,16,1,2,2,80,2),(3,2,1,1,3,2,120,3)]'::flow,1);
select flow_get_fim1_fi('[(1,3,1,1,1,1,40,1),(2,1,16,1,2,2,80,2),(3,2,1,1,3,2,120,3)]'::flow,2);


