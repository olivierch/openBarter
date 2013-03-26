#!/usr/bin/python
# -*- coding: utf8 -*-
"""
objectifs: Analyse de liquidité
Voir à partir de quel volume l'order book devient liquide.

Constantes dimensionnantes: dans cliquid.py

Principes:
l'ob est rempli avec des ordres
passer des trocs

mvt[i].qtt est la somme des quantités des mvts pour une qualité donnée i
troc[.].qtt est la comme des quantités des mvts pour une qualité donnée i
 
liquidité = sum(mvt[.].qtt) / sum(troc[.].qtt)

détail:

1) créer towner.sql avec 10000 owner
2) pour chaque config, 
    un fichier config_orderbook.sql contenant torder
    un fichier config_stack.sql contenant tstack
3) liquid.py
    pour chaque volume
        charger une partie de config_orderbook.sql
        charger config_stack.sql
        vider le stack
        calculer la liquidité
    enregister les res
    
les configs sont dans des liquid_conf.py (import liquid_conf as conf)
les *.sql sont dans cliquid.PATH_DATA

les fichiers sont gégérés directement en python par gen.py.

import prims
import sys
import const
import util
import random
import psycopg2
import sys
# import curses
import logging
import scenarii

logging.basicConfig(level=logging.DEBUG,
                    format='(%(threadName)-10s) %(message)s',
                    )

"""
import cliquid
import cliquid_basic as config
import gen
def simu(options):
    if(options.generate):
        gen.generate()
        return
    if(options.test):
        gen.perftests()
	return

from optparse import OptionParser
def main():
	usage = """usage: %prog [options]
	            to change config, modify the import in gen.py"""
	parser = OptionParser(usage)

	parser.add_option("-g", "--generate",action="store_true", dest="generate",help="generate files",default=False)
	parser.add_option("-t", "--test",action="store_true", dest="test",help="make the test",default=False)

	(options, args) = parser.parse_args()
	
	simu(options)

if __name__ == "__main__":
	main()
	
"""
base simu_r1
 ./simu.py -i 10000 -t 10
done: {'nbAgreement': 75000L, 'nbMvtAgr': 240865L, 'nbMvtGarbadge': 11152L, 'nbOrder': 13836L} 
simu terminated after 28519.220312 seconds (0.285192 secs/oper)
"""

"""		
parser.add_option("-i", "--iteration",type="int", dest="iteration",help="number of iteration",default=0)	
parser.add_option("-r", "--reset",action="store_true", dest="reset",help="database is reset",default=False)
parser.add_option("-v", "--verif",action="store_true", dest="verif",help="fgeterrs run after",default=False)
parser.add_option("-m", "--maxparams",action="store_true", dest="maxparams",help="print max parameters",default=False)
parser.add_option("-t", "--threads",type="int", dest="threads",help="number of threads",default=1)
parser.add_option("--seed",type="int",dest="seed",help="reset random seed",default=0)
parser.add_option("--MAXCYCLE",type="int",dest="MAXCYCLE",help="reset MAXCYCLE")
parser.add_option("--MAXTRY",type="int",dest="MAXTRY",help="reset MAXTRY")
parser.add_option("--MAXPATHFETCHED",type="int",dest="MAXPATHFETCHED",help="reset MAXPATHFETCHED")
parser.add_option("--CHECKQUALITYOWNERSHIP",action="store_true",dest="CHECKQUALITYOWNERSHIP",help="set CHECK_QUALITY_OWNERSHIP",default=False)
parser.add_option("-s","--scenario",type="string",action="store",dest="scenario",help="the scenario choosen",default="basic")
"""	

