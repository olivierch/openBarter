#include "postgres.h"
#include <math.h>
#include "utils/geo_decls.h"	/* for Point */
#include "wolf.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif


// PG_MODULE_MAGIC;

Datum
earth_get_carre(PG_FUNCTION_ARGS);

/* Earth's radius is in statute Km. */
static const double EARTH_RADIUS = 6371.009;//3958.747716;
static const double TWO_PI = 2.0 * M_PI;
static const double HALF_PI = M_PI/2.0;
#define DEGTORAD(degrees) ((degrees) * TWO_PI / 360.0 )
#define RADTODEG(degrees) ((degrees) * 360.0 / TWO_PI )
#define CORRECTMINMAX(min,v,max) ((v)<(min)?(min):((v)>(max)?(max):(v))) 
#define CORRECTLAT(lat) CORRECTMINMAX(-90.0,lat,+90)
#define CORRECTLON(lon) CORRECTMINMAX(-180.0,lon,+180)
/******************************************************
 *
 * earth_distance_internal - distance between points
 *
 * args:
 *	 a pair of points - for each point,
 *	   x-coordinate is longitude in degrees west of Greenwich
 *	   y-coordinate is latitude in degrees above equator
 *
 * returns: double
 *	 distance between the points in miles on earth's surface
 ******************************************************/

double
earth_distance_internal(Tpoint *pt1, Tpoint *pt2)
{
	double		long1,
				lat1,
				long2,
				lat2;
	double		longdiff;
	double		sino;

	/* convert degrees to radians */

	long1 = DEGTORAD(CORRECTLON(pt1->x));
	lat1 = DEGTORAD(CORRECTLAT(pt1->y));

	long2 = DEGTORAD(CORRECTLON(pt2->x));
	lat2 = DEGTORAD(CORRECTLAT(pt2->y));

	/* compute difference in longitudes - want < 180 degrees */
	longdiff = fabs(long1 - long2);
	if (longdiff > M_PI)
		longdiff = TWO_PI - longdiff;

	sino = sqrt(sin(fabs(lat1 - lat2) / 2.) * sin(fabs(lat1 - lat2) / 2.) +
			cos(lat1) * cos(lat2) * sin(longdiff / 2.) * sin(longdiff / 2.));
	if (sino > 1.)
		sino = 1.;

	return 2. * EARTH_RADIUS * asin(sino);
}


/*****************************************************
for pt->x latitude, pt->y longitude
and dist in Km,
returns Tcarre
*****************************************************/

static Tcarre *earth_get_carre_internal(Tpoint *pt,double dist) {
	
	double c;
	double dlat,dlon,lat,lon;
	Tcarre *carre;
	
	carre = (Tcarre *) palloc(sizeof(Tcarre));
	carre->latmin =  -90.0;
	carre->latmax =  +90.0;
	carre->lonmin = -180.0;
	carre->lonmax = +180.0;
	
	
	if(dist <= 0.0)
		return carre;
	if(dist > (EARTH_RADIUS/2.0))
		return carre;
	dlat = dist/EARTH_RADIUS;
	
	lat = DEGTORAD(CORRECTLAT(pt->x));
	lon = DEGTORAD(CORRECTLON(pt->y));
	
	
	if(dlat < HALF_PI) {
		c = RADTODEG(lat + dlat);
		if(c < 90.0) 
			carre->latmax = c;
		
		c = RADTODEG(lat - dlat);
		if(c > -90.0) 
			carre->latmin = c;
	}
				
	c = cos(lat); // >= 0 since lat in [-90,+90]
	if(c > 1.0E-15) {
		dlon = dlat/c;
		if(dlon < HALF_PI) {
			c = RADTODEG(lon + dlon);
			if(c < 180.0) 
				carre->latmax = c;
		
			c = RADTODEG(lon - dlon);
			if(c > -180.0) 
				carre->latmin = c;
		}
	} 
	
	return carre;
}
/* 
CREATE FUNCTION earth_get_carre(cube, float8)
    RETURNS cube
    AS 'MODULE_PATHNAME'
    LANGUAGE C IMMUTABLE STRICT;
*/
/* returns a cube with dim=2 */
Datum
earth_get_carre(PG_FUNCTION_ARGS)
{
	Tpoint	   *pt = (Tpoint *)PG_DETOAST_DATUM(PG_GETARG_DATUM(0));
	double	   dist = PG_GETARG_FLOAT8(1);
	Tcarre	   *result;
	
	if(pt->dim !=1) 
				ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("in earth_get_carre, dim=%i",pt->dim)));
	result = earth_get_carre_internal(pt, dist);

	// Tcarre looks like cube with dim=2
	SET_VARSIZE(result, sizeof(Tcarre));
	result->dim = 2;

	PG_RETURN_POINTER(result);
}


