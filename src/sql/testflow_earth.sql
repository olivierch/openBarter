--drop extension if exists hstore cascade;
--create extension hstore;
drop extension if exists flowf cascade;
create extension flowf with version '1.1';

RESET client_min_messages;
RESET log_error_verbosity;
SET client_min_messages = notice;
SET log_error_verbosity = terse;

/*
(48.670828,1.874488)deg ici (0.849466198,0.032715987)rad
48.670389,1.87415  mimi
(48.670389,1.87415)deg mimi (0.849458536,0.032710088)rad
*/

--select earth_dist_points('(48.670828,1.874488)'::point,'(48.670389,1.87415)'::point);
select earth_dist_points('(0.849466198,0.032715987)'::point,'(0.849458536,0.032710088)'::point);
--  0.0547622024263353 km = a*6371.009 (Rterre) => a = 0.0547622024263353/6371.009 = 0,000008596 radians
-- select earth_dist_points('(-91.0,0.0)'::point,'(-30.0,0.0)'::point);
select earth_dist_points('(-1.588249619,0.0)'::point,'(-0.523598776,0.0)'::point);

-- select earth_get_square('(48.670828,1.874488)'::point,1.0);
-- select earth_get_square('(48.670828,1.874488)'::point,0.0);
select earth_get_square('(0.849466198,0.032715987)'::point,1.0/6371.009);
select earth_get_square('(0.849466198,0.032715987)'::point,0.0);

-- d in [0,EARTH_RADIUS * PI/2.[
-- select earth_get_square('(48.670828,1.874488)'::point,(6371.009 * 3.1415926535 *1.001 / 2.0));
-- select earth_get_square('(48.670828,1.874488)'::point,-1.0);
-- d in [0,PI[
select earth_get_square('(0.849466198,0.032715987)'::point,(3.14159265358979323846 *1.00001));
select earth_get_square('(0.849466198,0.032715987)'::point,-1.0);

