#include "postgres.h"
#include <math.h>
#include "wolf.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif
/***************************************************************************
submitorder(..,_pos_requ point,..,_pos_prov point,_dist float8,..)

sqltype yorder contains
    pos_requ cube = earth_get_cube_s0(_pos_requ) == cube_s0(pos_requ)
	pos_prov cube = earth_get_cube_s0(_pos_prov) == cube_s0(pos_prov)
    dist	float = _dist
 	carre_prov cube = earth_get_square(_pos_prov,_dist) 
 	                == cube((prov_lat-dlat,prov_lon-dlon),(prov_lat+dlat,prov_lon+dlon))
 	
c type Torder contains 
    Point   pos_requ
    Point   pos_prov 
    double dist
    
test on matching:
    (prev).carre_prov @> (next).pos_requ
        carre_prov contains cube_s0
    yorder_match(Torder *prev,Torder *next)
        prev->dist >= earth_points_distance(&prev->pos_prov,&next->pos_requ)


***************************************************************************/

// PG_MODULE_MAGIC;



/* Earth's radius is in statute Km. */
static const double EARTH_RADIUS = 6371.009;
static const double TWO_PI = 2.0 * M_PI;
static const double HALF_PI = M_PI/2.0;

#define EARTHC_LAT_MAX  (90.0 * (1.0 - OB_PRECISION))
static const double EARTH_LAT_MAX = EARTHC_LAT_MAX;
static const double EARTH_LAT_MIN = -EARTHC_LAT_MAX;
static const double EARTH_LON_MAX = 2.0 * EARTHC_LAT_MAX;
static const double EARTH_LON_MIN = -2.0 * EARTHC_LAT_MAX;


#define DEGTORAD(degrees) ((degrees) * TWO_PI / 360.0 )
#define RADTODEG(radians) ((radians) * 360.0 / TWO_PI )
#define CORRECTMINMAX(min,v,max) ((v)<(min)?(min):((v)>(max)?(max):(v))) 
#define CORRECTLAT(lat) CORRECTMINMAX(EARTH_LAT_MIN,lat,EARTH_LAT_MAX)
#define CORRECTLON(lon) CORRECTMINMAX(EARTH_LON_MIN,lon,EARTH_LON_MAX)
/******************************************************
 *
 * earth_distance_internal - distance between points
 *
 * args: can be a pair of Point or of cube_s0
 *	 a pair of points - for each point,
 *	   y-coordinate is longitude in degrees west of Greenwich
 *	   x-coordinate is latitude in degrees above equator
 *
 * returns: double
 *	 distance between the points in km on earth's surface

Computes the arc, in radian, between two positions.
  *
  * The result is equal to Distance(from,to)
  *    = 2*asin(sqrt(h(d)))
  *
  * where:
  *    d is the distance in meters between 'from' and 'to' positions.
  *    h is the haversine function: h(x)=sin²(x/2)
  *
  * The haversine formula gives:
  *    h(d/R) = h(from.lat-to.lat)+h(from.lon-to.lon)+cos(from.lat)*cos(to.lat)
  *
  *  http://en.wikipedia.org/wiki/Law_of_haversines
 ******************************************************/

double
earth_points_distance(Point *from, Point *to) {

    double from_latitude,from_longitude,to_latitude,to_longitude;
    double latitudeArc,longitudeArc,latitudeH,lontitudeH,tmp;
    
    if(!( (earth_check_point(from) == 0) && (earth_check_point(to) == 0))) 
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("attempt to get a distance form a point out of range")));

	/* convert degrees to radians */
	to_latitude = DEGTORAD(CORRECTLAT(to->x));
	to_longitude = DEGTORAD(CORRECTLON(to->y));
	
	from_latitude = DEGTORAD(CORRECTLAT(from->x));
	from_longitude = DEGTORAD(CORRECTLON(from->y));
    
    latitudeArc  = (from_latitude - to_latitude);
    longitudeArc = (from_longitude - to_longitude);
    
    latitudeH = sin(latitudeArc * 0.5);
    latitudeH *= latitudeH; // h(latitudeArc)
    
    lontitudeH = sin(longitudeArc * 0.5);
    lontitudeH *= lontitudeH; // h(longitudeArc)
    
    tmp = cos(from_latitude) * cos(to_latitude);
    
    return (2.0 * asin(sqrt(latitudeH + tmp*lontitudeH))) * EARTH_RADIUS;
}

/*****************************************************
checks
*****************************************************/
int earth_check_point(Point *p) 
{
	double lon,lat;

	// lat in ]-90,+90[
	lat = CORRECTLAT(p->x);
	if(lat != p->x) return 1;

	// lon in ]-180,+180[
	lon = CORRECTLON(p->y);
	if(lon != p->y) return 1;
	
	return 0;
}

int earth_check_dist(Point *p,double dist) 
// check point is OK
{
    double _dlat,_dlon;
    
    if(dist < 0.0 ) return -1;
    
    _dlat = dist/EARTH_RADIUS;
	// latitude in [0,EARTH_RADIUS * PI/2.[
	if(_dlat >= (HALF_PI *(1.0 - OB_PRECISION))) return 1;
	
	_dlon = _dlat/cos(DEGTORAD(p->x));
	if(_dlon >= (HALF_PI *(1.0 - OB_PRECISION))) return 1;
	
	return 0;	
}

/*****************************************************
for pt->x latitude, pt->y longitude
and dist in Km,
    dlat = dist/EARTH_RADIUS
    dlon = dlat/cos(lat)
returns Tcarre(lat-dlat,lon-dlon,lat+dlat,lon+dlon)
if dist == 0 Tcarre == all earth
*****************************************************/
static Tsquare *earth_get_square_internal(Point *pt,double dist) {
	
	double c,res;
	double dlat,dlon,lat,lon;
	Tsquare *carre;
	
	carre = (Tsquare *) palloc(sizeof(Tsquare));
	
	carre->dim = 2;
	carre->latmin =  EARTH_LAT_MIN;
	carre->lonmin = EARTH_LON_MIN;
	
	carre->latmax =  EARTH_LAT_MAX;
	carre->lonmax = EARTH_LON_MAX;
	
	
    if(earth_check_point(pt) != 0) 
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("attempt to get a square form a point:(lat=%f, lon=%f) out of range",pt->x,pt->y)));
	
    if(earth_check_dist(pt,dist) != 0) 
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("attempt to get a square form a dist:%f km for a point:(lat=%f, lon=%f) out of range",dist,pt->x,pt->y)));
	    
	if(dist == 0.0)  /* all */
	    return carre;	    

	dlat = dist/EARTH_RADIUS;
	
	lat = DEGTORAD(pt->x);
	lon = DEGTORAD(pt->y);
	
	if(dlat < HALF_PI) {
		res = RADTODEG(lat + dlat);
		if(res < EARTH_LAT_MAX) 
			carre->latmax = res;
	    // else carre->latmax =  EARTH_LAT_MAX unchanged 
		
		res = RADTODEG(lat - dlat);
		if(res > EARTH_LAT_MIN) 
			carre->latmin = res;
	    // else carre->latmin =  EARTH_LAT_MIN unchanged
	}
				
	c = cos(lat); // > 0 since lat in ]-90,+90[
	if(c > OB_PRECISION) { // just in case

		dlon = dlat/c;
		if(dlon < HALF_PI) {
			res = RADTODEG(lon + dlon);
			if(res < EARTH_LON_MAX)
				carre->lonmax = res;
		    // else carre->lonmax =  EARTH_LON_MAX unchanged
		
			res = RADTODEG(lon - dlon);
			if(res > EARTH_LON_MIN) 
				carre->lonmin = res;
			// else carre->lonmin =  EARTH_LON_MIN unchanged
		}
	} // else latitude near +/-90, no limit on longitude
	
	return carre;
}
/* wrapper for:
    CREATE FUNCTION earth_get_square(point, float8)
        RETURNS cube
        AS 'MODULE_PATHNAME'
        LANGUAGE C IMMUTABLE STRICT;
*/

PG_FUNCTION_INFO_V1(earth_get_square);
Datum earth_get_square(PG_FUNCTION_ARGS);

Datum earth_get_square(PG_FUNCTION_ARGS)
{
	Point	   *pt = PG_GETARG_POINT_P(0);
	double	   dist = PG_GETARG_FLOAT8(1);
	Tsquare	   *result;
	
	result = earth_get_square_internal(pt, dist);

	SET_VARSIZE(result, sizeof(Tsquare));

	PG_RETURN_POINTER(result);
}

/*********************************************************************
from point (x,y) 
returns cube (latmin=x,lonmin=y,latmax=x,lonmax=y) with dim=2
*********************************************************************/
/* 
CREATE FUNCTION earth_get_cube_s0(point)
    RETURNS cube
    AS 'MODULE_PATHNAME'
    LANGUAGE C IMMUTABLE STRICT;
*/
PG_FUNCTION_INFO_V1(earth_get_cube_s0);
Datum earth_get_cube_s0(PG_FUNCTION_ARGS);
Datum
earth_get_cube_s0(PG_FUNCTION_ARGS)
{
	Point	   *pt = PG_GETARG_POINT_P(0);
	Tsquare	   *result;
	
    if(earth_check_point(pt) != 0) 
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("attempt to get a cube form a point out of range")));
	
	result = palloc(sizeof(Tsquare));
	
	result->latmin = pt->x;
	result->lonmin = pt->y;
	result->latmax = pt->x;
	result->lonmax = pt->y;

	// Tcarre is like cube with dim=2
	SET_VARSIZE(result, sizeof(Tsquare));
	result->dim = 2;

	PG_RETURN_TSQUARE(result);
}

/*********************************************************************
from cube_s0 returns point (lat,lon)
*********************************************************************/
/* 
CREATE FUNCTION earth_get_point(cube)
    RETURNS point
    AS 'MODULE_PATHNAME'
    LANGUAGE C IMMUTABLE STRICT;
*/
PG_FUNCTION_INFO_V1(earth_get_point);
Datum earth_get_point(PG_FUNCTION_ARGS);
Datum earth_get_point(PG_FUNCTION_ARGS)
{
	Tsquare     *pc = PG_GETARG_TSQUARE(0);
	Point	   *result;
	
	if(!((pc->dim != 2) && (pc->latmin == pc->latmax) && (pc->lonmin == pc->lonmax)))
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("attempt to get a point from cube not s0")));
	
	result = palloc(sizeof(Point));
	
	result->x = pc->latmin;
	result->y = pc->lonmin;
	
    if(earth_check_point(result) != 0) 
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("attempt to get a point form a cube s0 out of range")));
			
	PG_RETURN_POINTER(result);
}

/*****************************************************
returns the distance between points or cube
*****************************************************/
/*CREATE FUNCTION earth_dist(point,point)
    RETURNS float8
    AS 'MODULE_PATHNAME'
    LANGUAGE C IMMUTABLE STRICT;
*/

PG_FUNCTION_INFO_V1(earth_dist_points);
Datum earth_dist_points(PG_FUNCTION_ARGS);
Datum earth_dist_points(PG_FUNCTION_ARGS)
{
	Point	   *p1,*p2;
	double	   result;
	
	
	p1 = PG_GETARG_POINT_P(0);
	p2 = PG_GETARG_POINT_P(1);
	
	result = earth_points_distance(p1,p2);

	PG_RETURN_FLOAT8(result);
}

PG_FUNCTION_INFO_V1(earth_dist_cubes_s0);
Datum earth_dist_cubes_s0(PG_FUNCTION_ARGS);
Datum earth_dist_cubes_s0(PG_FUNCTION_ARGS)
{
	Tsquare	   *from,*to;
	Point	   p1,p2;
	double	   result;
	
	
	from = PG_GETARG_TSQUARE(0);
	if(!((from->dim != 2) && (from->latmin == from->latmax) && (from->lonmin == from->lonmax)))
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("attempt to get a distance from cube not s0")));
	p1.x = from->latmin;
	p1.y = from->lonmin;
		
	to = PG_GETARG_TSQUARE(1);	
	if(!((to->dim != 2) && (to->latmin == to->latmax) && (to->lonmin == to->lonmax)))
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("attempt to get a distance from cube not s0")));
	p2.x = to->latmin;
	p2.y = to->lonmin;
	
	result = earth_points_distance(&p1,&p2);

	PG_RETURN_FLOAT8(result);
}


