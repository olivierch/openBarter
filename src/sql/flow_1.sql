-----------------------------------------------------------------------
drop extension if exists flow cascade;
create extension flow;
select '[]'::flow;
-- id,nr,qtt_prov,qtt_requ,own,qtt,np
select '[(1,2,3,4,5,6,7)]'::flow as flow;
select '[(1,2,3,4,5,6,7),(9,7,11,12,13,14,15)]'::flow as flow;

-- it's not a loop; expected: 0
select flow_refused('[(1,2,3,4,5,6,7),(9,7,11,12,13,14,15)]'::flow);
-- agreement without barter ;expected: -1
select flow_refused('[(100,2,20,30,110,20,1),(101,1,30,20,111,30,2)]'::flow);
-- agreement with long barter ;expected: -1
select flow_refused('[(100,2,20,30,110,20,1),(101,1,30,10,111,30,2)]'::flow);
-- agreement with short barter ;expected: != -1
select flow_refused('[(100,2,20,30,110,20,1),(101,1,30,25,111,30,2)]'::flow);

--select flow_status('[(1,2,3,4,5,6,7)]'::flow);
--select flow_omega('[(1,2,3,4,5,6,7,8)]'::flow);
select flow_omegay('[(1,2,3,4,5,6,7)]'::flow,'[(1,2,3,4,5,6,7)]'::flow,2,1);
select flow_cat('[(1,2,3,4,5,6,7)]'::flow,9,7,11,12,13,14,15);
select flow_proj('[(1,2,3,4,5,6,7),(8,7,10,11,12,13,14)]'::flow,1);
select flow_proj('[(1,2,3,4,5,6,7),(8,7,10,11,12,13,14)]'::flow,2);
select flow_proj('[(1,2,3,4,5,6,7),(8,7,10,11,12,13,14)]'::flow,8);
select flow_dim('[(1,2,3,4,5,6,7),(8,7,10,11,12,13,14)]'::flow);
select flow_to_matrix('[(1,2,3,4,5,6,7),(8,7,10,11,12,13,14)]'::flow);
-- cycle 3 nodes, 3 stocks
-- id,nr,qtt_prov,qtt_requ,own,qtt,np
-- result {20,80,40}
select flow_proj('[(1,3,1,1,1,20,1),(2,1,8,1,2,80,2),(3,2,1,1,3,120,3)]'::flow,8);

-- cycle 3 nodes, 3 stocks - all stock exhausted
-- id,nr,qtt_prov,qtt_requ,,own,qtt,np
-- result {20,80,40}
select flow_proj('[(1,3,1,1,1,20,1),(2,1,8,1,2,80,2),(3,2,1,1,3,40,3)]'::flow,8);

-- cycle 2 nodes, 2 stocks,2 owners
-- id,nr,qtt_prov,qtt_requ,sid,own,qtt,np
-- result {20,20}
select flow_proj('[(1,2,2,1,1,20,1),(2,1,2,1,2,120,2)]'::flow,8);

-- flow 8 nodes, 8 stocks, 8 owners
select flow_proj('[
(1,8,1,1,1, 10,1),
(2,1,1,1,2, 100,2),
(3,2,1,1,3, 100,3),
(4,3,1,1,4, 100,4),
(5,4,1,1,5, 100,5),
(6,5,1,1,6, 100,6),
(7,6,1,1,7, 100,7),
(8,7,1,1,8, 100,8)]'::flow,8);

/* flow 9 nodes produces an error */
select flow_proj('[
(1,9,1,1,1, 10,1),
(2,1,1,1,2, 10,2),
(3,2,1,1,3, 10,3),
(4,3,1,1,4, 10,4),
(5,4,1,1,5, 10,5),
(6,5,1,1,6, 10,6),
(7,6,1,1,7, 10,7),
(8,7,1,1,8, 10,8),
(9,8,1,1,9, 10,9)]'::flow,8); 


