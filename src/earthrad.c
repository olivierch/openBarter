#include "postgres.h"
#include <math.h>
#include "wolf.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif
/***************************************************************************
distance, latitude and longitude are in radians.
    distance is [0,PI[
    latitude in [-PI/2,+PI/2[
    longitude in [-PI,+PI[

a position is represented by a Point x latitude, y longitude

a spherical cap is represented by a position and a radius. 
The maximum radius is PI (half turn).

a 'box' is defined by (lat_min,lat_max,lon_min,lon_max)
on a domain [-PI/2,+PI/2[ * [-PI,+PI[,

the box associated to a spherical cap is the smallest rectangle containing the cap

we use box object to represent a rectangle

to know if a position is in a spherical cap, we test 
1) earth_get_square(cap->center,cap->radius) @> box(position,position) 
2) cap->radius > distance(cap->center,cap->position) 

the first test use gist(box) indexing

When the radius of the cap == 0, the square contain all the domain
****************************************************************************


submitorder(..,_pos_requ point,..,_pos_prov point,_dist float8,..)

sqltype yorder contains:
    pos_requ = box(_pos_requ,_pos_requ)
	pos_prov = box(_pos_prov,_pos_prov)
    dist	float = _dist
 	square_prov box = earth_get_square(_pos_prov,_dist) 
 	                == box((prov_lat-dlat,prov_lon-dlon),(prov_lat+dlat,prov_lon+dlon))
 	
c type Torder contains 
    Point   pos_requ
    Point   pos_prov 
    double dist
    
test on matching:
    (prev).square_prov @> (next).pos_requ
        square_prov contains cube_s0
    yorder_match(Torder *prev,Torder *next)
        prev->dist >= earth_points_distance(&prev->pos_prov,&next->pos_requ)
        or prev->dist == 0


***************************************************************************/

/* distance is in radian. */
static const double TWO_PI = 2.0 * M_PI;
static const double HALF_PI = M_PI/2.0;

// latc =  ((lat+PI/2) mod PI)-PI/2
#define CORRECTLAT(lat,latc) do {\
    latc = ((lat)/M_PI) + 0.5; \
    latc = latc - floor(latc); \
    latc = (latc - 0.5) * M_PI; \
} while (false);

// lonc =  ((lon+PI) mod 2*PI)-PI
#define CORRECTLON(lon,lonc) do {\
    lonc = ((lon)/TWO_PI) + 0.5; \
    lonc = lonc - floor(lonc); \
    lonc = (lonc - 0.5) * TWO_PI; \
} while (false);

// dic =  dist mod PI
#define CORRECTDIST(di,dic) {\
    dic = (di) / M_PI; \
    dic = dic - floor(dic); \
    dic = dic * M_PI; \
} while (false);
    
/*********************************************************************
returns 0 when both:
 p->x latitude in [-PI/2,+PI/2[
 p->y logitude in [-PI,+PI[
*********************************************************************/
int earth_check_point(Point *p) 
{
	double lon,lat,err;

	// lat in [-PI/2,+PI/2[
	CORRECTLAT(p->x,lat);
	err = lat - p->x;
	err = err>0.0?err:-err;
	if(err > OB_PRECISION) {
	    //ereport(ERROR,
		//	    (errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
		//	    errmsg("lat %.20f corrected %.20f",p->x,lat)));
	    return 1;
	}

	// lon in [-PI,+PI[
	CORRECTLON(p->y,lon);
	err = lon - p->y;
	err = err>0.0?err:-err;
	if(err > OB_PRECISION) {
	    // ereport(ERROR,
		//	    (errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
		//	    errmsg("lon %.20f corrected %.20f",p->y,lon)));
	    return 1;
	}
	
	return 0;
}
/*********************************************************************
returns 0 if distance in [0,PI[
*********************************************************************/
int earth_check_dist(double dist) 
{
    double _dist,_err;
    
    if(dist < 0.0 ) return -1;
    // dist in [0,PI[
    CORRECTDIST(dist,_dist);
    _err = dist - _dist;
    _err = _err>0.0?_err:-_err;
    
    if(_err > OB_PRECISION) return 1;
	return 0;	
}
/*********************************************************************
 *
 * earth_distance - distance between points
 *
 * args: can be a pair of Point or of cube_s0
 *	 a pair of points - for each point,
 *	   y-coordinate is longitude in radians west of Greenwich
 *	   x-coordinate is latitude in radians above equator
 *
 * returns: double
 *	 distance between the points in km on earth's surface

Computes the arc, in radian, between two positions.
  *
  * The result is equal to Distance(from,to)
  *    = 2*asin(sqrt(h(d)))
  *
  * where:
  *    d is the distance in radians between 'from' and 'to' positions.
  *    h is the haversine function: h(x)=sin²(x/2)
  *
  * The haversine formula gives:
  *    h(d) = h(from.lat-to.lat)+h(from.lon-to.lon)+cos(from.lat)*cos(to.lat)
  *
  *  http://en.wikipedia.org/wiki/Law_of_haversines 
*********************************************************************/

double
earth_points_distance(Point *from, Point *to) {

    double latitudeArc,longitudeArc,latitudeH,lontitudeH,tmp;
    
    if(!( (earth_check_point(from) == 0) && (earth_check_point(to) == 0))) 
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("attempt to get a distance form points out of range")));
    
    latitudeArc  = from->x - to->x; 
    longitudeArc = from->y - to->y; 
    
    latitudeH = sin(latitudeArc * 0.5);
    latitudeH *= latitudeH; // h(latitudeArc)
    
    lontitudeH = sin(longitudeArc * 0.5);
    lontitudeH *= lontitudeH; // h(longitudeArc)
    
    tmp = cos(from->x) * cos(to->x);//cos(from_latitude) * cos(to_latitude);
    
    return (2.0 * asin(sqrt(latitudeH + tmp*lontitudeH)));
}


/*********************************************************************
dist==0 or dist >= distance(pos_prov,pos_requ) 
*********************************************************************/

bool earth_match_position(double dist,Point *pos_prov,Point *pos_requ) {

    if (dist == 0.0 ) return true;
    if( dist >= earth_points_distance(pos_prov,pos_requ)) return true;
    return false;
    
}

/*********************************************************************
earth_get_box_internal() returns the smallest box containing the spherical cap
defined by a point pt and a distance dist.

for pt->x latitude, pt->y longitude
    dlat = dist
    dlon = dlat/cos(lat)
returns BOX(lat-dlat,lon-dlon,lat+dlat,lon+dlon)
if dist == 0 Tsquare == all earth
*********************************************************************/
static BOX *earth_get_box_internal(Point *pt,double dist) {
	
	double c,_dist;
	double dlat,dlon,lat,lon;
	BOX *box;
	
	box = (BOX *) palloc(sizeof(BOX));
	
	box->low.x  =  -HALF_PI; //lat
	box->high.x =  HALF_PI;
	
	box->low.y   = -M_PI; //lon
	box->high.y  = M_PI;
	    
	CORRECTLAT(pt->x,lat);
	CORRECTLON(pt->y,lon);
	CORRECTDIST(dist,_dist);
	    
	/* if dist was > PI, the spherical cap would contain both poles   
	 but _dist in [0,PI[ */ 
	if(_dist == 0.0)  /* all the domain */ 
	    return box;
	
	dlat = lat + _dist;
	if( dlat < HALF_PI)  
	    // the cap does not contain north pole
        box->high.x = dlat;
	
	dlat = lat - _dist;
	if (dlat > -HALF_PI)  
	    // the cap does not contain south pole
	    box->low.x = dlat;
	
	c = cos(lat); 
	if(c > OB_PRECISION) { 
		_dist = _dist/c;
		
		dlon = _dist +lon;
		if(dlon < M_PI) 
			box->high.y = dlon;
        dlon = lon - _dist;
		if(dlon > -M_PI)
		    box->low.y = dlon;
	} /* else 
	no constraint on lon when the cap is centered on pole
	*/
	return box;
}

/*********************************************************************
*********************************************************************/
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
	BOX	   *box;

    if(!( (earth_check_point(pt) == 0) && (earth_check_dist(dist) == 0))) 
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("attempt to get a box form a dist:%.10f rad for a point:(lat=%.10f, lon=%.10f) out of range",dist,pt->x,pt->y)));
	
	box = earth_get_box_internal(pt, dist);

	PG_RETURN_BOX_P(box);
}

/*********************************************************************
from point (x,y) 
returns box_s0 (latmin=x,lonmin=y,latmax=x,lonmax=y)
*********************************************************************/
/* 
CREATE FUNCTION earth_point_to_box_s0(point)
    RETURNS box
    AS 'MODULE_PATHNAME'
    LANGUAGE C IMMUTABLE STRICT;
*/
PG_FUNCTION_INFO_V1(earth_point_to_box_s0);
Datum earth_point_to_box_s0(PG_FUNCTION_ARGS);
Datum
earth_point_to_box_s0(PG_FUNCTION_ARGS)
{
	Point	   *pt = PG_GETARG_POINT_P(0);
	BOX	   *box;
	
    if(earth_check_point(pt) != 0) 
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("attempt to get a box form a point out of range")));
	
	box = palloc(sizeof(BOX));
	
	box->low.x = pt->x;
	box->low.y = pt->y;
	box->high.x = pt->x;
	box->high.y = pt->y;

	PG_RETURN_BOX_P(box);
}

/*********************************************************************
from box_s0 returns point (lat,lon)
*********************************************************************/
/* 
CREATE FUNCTION earth_box_to_point(box)
    RETURNS point
    AS 'MODULE_PATHNAME'
    LANGUAGE C IMMUTABLE STRICT;
*/
PG_FUNCTION_INFO_V1(earth_box_to_point);
Datum earth_box_to_point(PG_FUNCTION_ARGS);
Datum earth_box_to_point(PG_FUNCTION_ARGS)
{
	//Tsquare     *pc = PG_GETARG_TSQUARE(0);
	BOX        *box = PG_GETARG_BOX_P(0);
	Point	   *result;
	
	GL_CHECK_BOX_S0(box);
	
	result = palloc(sizeof(Point));
	
	result->x = box->low.x;
	result->y = box->low.y;
	
    if(earth_check_point(result) != 0) 
    		ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			errmsg("attempt to get a point form a cube_s0 out of range")));
			
	PG_RETURN_POINTER(result);
}

/*****************************************************
returns the distance between points
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



