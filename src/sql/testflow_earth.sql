drop extension if exists cube cascade;
drop extension if exists flowf cascade;

create extension cube with version '1.0';
create extension flowf with version '0.8';

RESET client_min_messages;
RESET log_error_verbosity;
SET client_min_messages = notice;
SET log_error_verbosity = terse;

/*
48.670828,1.874488 ici
48.670389,1.87415  mimi
*/

select earth_dist_points('(48.670828,1.874488)'::point,'(48.670389,1.87415)'::point);
select earth_dist_points('(-91.0,0.0)'::point,'(-30.0,0.0)'::point);

select earth_get_square('(48.670828,1.874488)'::point,1.0);
select earth_get_square('(48.670828,1.874488)'::point,0.0);

-- d in [0,EARTH_RADIUS * PI/2.[
select earth_get_square('(48.670828,1.874488)'::point,(6371.009 * 3.1415926535 *1.001 / 2.0));
select earth_get_square('(48.670828,1.874488)'::point,-1.0);


