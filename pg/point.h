/* $Id: point.h 22 2010-01-15 16:00:22Z olivier.chaussavoine $ */
/*
    openbarter - The maximum wealth for the minimum collective effort
    Copyright (C) 2008 olivier Chaussavoine

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

    olivier.chaussavoine@openbarter.org
*/
#ifndef defined__point_h
#define defined__point_h
#include "openbarter.h"
#include "flux.h"

size_t ob_point_getsizePoint(ob_tPoint *point);
int ob_point_getPoint(DB *db,ob_tId *oid,ob_tPoint *point);
// int ob_point_put_stocktemp(DB_ENV *env,DB_TXN *txn, ob_tStock *pstock);
int ob_point_get_version(DB_TXN *txn,ob_tId *version);
int ob_point_pas_accepte(DB_ENV *env,DB_ENV *envt,DB_TXN *txn,
		ob_tId *Xoid,ob_tId *Yoid,bool *refuse);
int ob_point_new_trait(DB_ENV *envt,
	ob_tNoeud *offreX,ob_tNoeud *offreY);
int ob_point_initPoint(ob_tPrivateTemp *privt, ob_tPoint *point);
int ob_point_loop_trait(ob_tPrivateTemp *envit,
		ob_tNoeud *offreX,ob_tNoeud *offreY,int couche,int nbCouche);
int ob_point_getErrorOffreStock(ob_tNoeud *o,ob_tStock *s);

void ob_point_voirStock(ob_tStock *ps);
void ob_point_voirNoeud(ob_tNoeud *pn);
void ob_point_voirInterdit(ob_tInterdit *pi);




//extern ob_tGlobal global;



#endif /*defined__point_h*/
