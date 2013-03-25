#!/usr/bin/python
# -*- coding: utf8 -*-

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
                    
def verifyVolumes(cursor):
	""" gives a good response when no records of tmvtremoved
	are deleted """
	if (not util.getMediumQtt.const): 
		print "Volumes could not be verified"
		return 

	volumes = util.getVolumes(cursor)
	for nat,qtt in volumes:
		if((qtt % util.getMediumQtt()) != 0):
			print "verifyVolumes failed KO !!!!!!!!!!"
			return
	print "verifyVolumes Ok"
	return

		
import threa 
def simu(options):
	itera = 0
	
	#################################
	# Begin simu
	if(options.reset):
		if(not prims.initDb()):
			raise util.SimuException("Market is not opened")
			
	begin = util.getAvct(None)
	with util.DbConn(const) as dbcon:
		with util.DbCursor(dbcon) as cursor:
		
			util.writeMaxOptions(cursor,options)
			
			for user in util.nameUsers():
				prims.createUser(cursor,user)
				
			if(options.CHECKQUALITYOWNERSHIP):
				util.setQualityOwnership(cursor,True)
	
	##################################
	if((not scenarii.threadAllowed(options.scenario)) and options.threads>1):
		raise Exception("This scenario cannot be run in thread")
		
	_begin = util.now()
	if(options.threads==1):	
		user = util.nameUser(0)
		scenarii.simuInt((options,user))
	else:
		# run in theads		
		ts = []	
		for i in range(options.threads):
			user = util.nameUser(i)
			t = threa.ThreadWithArgs(func=scenarii.simuInt,args=(options,user),name=user)
			t.start()
			ts.append(t)
		for t in ts:
			t.join()
			
	itera = options.iteration * options.threads
	
	duree = util.duree(_begin,util.now())
	##################################
	# Terminate simu
	
	terminate(begin,duree,itera,options)
	return
	
def terminate(begin,duree,itera,options):

	if(itera):
		res = util.getAvct(begin)
		res['dureeSecs'] = int(duree)
		res['nbOper'] = itera
		prims.storeOptions('results',res)
		prims.storeOptions('options',util.getDictInt(options))
		
		print '%i oper terminated after %.6f seconds (%.6f secs/oper)' % (itera,duree,duree/itera)
		
	with util.DbConn(const) as dbcon:
		with util.DbCursor(dbcon) as cursor:
			
			verifyVolumes(cursor)
		
			if options.maxparams:
				print "max_options:%s " % (util.readMaxOptions(cursor),)

			if(options.verif):
				util.runverif(cursor)
			
	return

from optparse import OptionParser
def main():
	usage = "usage: %prog [options]"
	parser = OptionParser(usage)
	
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
		
	(options, args) = parser.parse_args()
		
	#provisoire
	options.CHECKQUALITYOWNERSHIP = True
	options.maxUser = options.threads
	
	simu(options)

if __name__ == "__main__":
	main()
	
"""
base simu_r1
 ./simu.py -i 10000 -t 10
done: {'nbAgreement': 75000L, 'nbMvtAgr': 240865L, 'nbMvtGarbadge': 11152L, 'nbOrder': 13836L} 
simu terminated after 28519.220312 seconds (0.285192 secs/oper)
"""

