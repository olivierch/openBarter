-----------------------------------------------------------------------
set search_path='t';
drop extension if exists flow cascade;
create extension flow;
select '[]'::flow;
-- id,nr,qtt_prov,qtt_requ,own,qtt,np
select '[f,(1,2,3,4,5,6,7)]'::flow as flow;
select '[f,(1,2,3,4,5,6,7),(9,7,11,12,13,14,15)]'::flow as flow;

-- it's not a loop; expected: error
-- select flow_refused('[f,(1,2,3,4,5,6,7),(9,7,11,12,13,14,15)]'::flow);
-- agreement without barter ;expected: -1
select flow_refused('[f,(100,2,20,30,110,20,1),(101,1,30,20,111,30,2)]'::flow);
-- agreement with long barter ;expected: -1
select flow_refused('[f,(100,2,20,30,110,20,1),(101,1,30,10,111,30,2)]'::flow);
-- agreement with short barter ;expected: != -1
select flow_refused('[f,(100,2,20,30,110,20,1),(101,1,30,25,111,30,2)]'::flow);

--select flow_status('[(1,2,3,4,5,6,7)]'::flow);

select flow_omegaz('[f,(1,2,3,4,5,6,7)]'::flow,'[f,(100,2,3,4,5,6,7)]'::flow,9,7,11,12,13,14,15,array[1,2]::int8[],array[1,2]::int8[]);
select flow_catt('[f,(100,2,3,4,5,6,7)]'::flow,9,7,11,12,13,14,15,array[1,2]::int8[]);

-- flow 8 nodes, 8 stocks, 8 owners
select flow_proj('[f,
(1,8,1,1,1, 10,1),
(2,1,1,1,2, 100,2),
(3,2,1,1,3, 100,3),
(4,3,1,1,4, 100,4),
(5,4,1,1,5, 100,5),
(6,5,1,1,6, 100,6),
(7,6,1,1,7, 100,7),
(8,7,1,1,8, 100,8)]'::flow,8);

