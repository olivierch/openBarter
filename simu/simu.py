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

class Work(object):
	def __init__(self,w,options,user,maxUser):
		self.cdes = []
		self.options = options
		self.user = user
		self.maxUser = maxUser
		
		if(w is not None):
			self.secs = w.getDelay()
			self.iOper = w.getIOper()
		else:
			self.secs = 0.
			self.iOper = 0
		self.params = self.getParams()

	def getParams(self):
		owner = util.getRandOwner()
		qtt_p = util.getMediumQtt() # 5000
		qtt_r = util.getRandQtt()
		
		# define a couple (nr,np) such as nr != np
		_user,_other = None,None
		maxQlt = const.MAX_QLT
		if(self.options.CHECKQUALITYOWNERSHIP):
			_user = self.user
			_other = util.nameUser(random.randint(0,self.maxUser-1))
			maxQlt = const.MAX_QLT //self.maxUser
			
		if(maxQlt <2):
			sys.exit(-1)
	
		np = util.getQltName(_user,random.randint(0,maxQlt-1))
		nr = np
		while np == nr:
			nr = util.getQltName(_other,random.randint(0,maxQlt-1))
		#####
		
		return (owner,np,qtt_p,qtt_r,nr)
		
	def execute(self,cursor):
		try:
			begin = util.now()
			if(self.options.scenario == "quote"):
				cde = prims.GetQuote(self.params)
				cde.execute(cursor)
			
				if(cde.getIdQuote()!=0):
					cde2 = prims.ExecQuote(cde.getOwner(),cde.getIdQuote())
					cde2.execute(cursor)
				else:
					cde2 = prims.InsertOrder(self.params)
					cde2.execute(cursor)
			
			if(self.options.scenario == "basic"):
				# print self.iOper
				cde2 = prims.InsertOrder(self.params)
				cde2.execute(cursor)	

			self.secs += util.duree(begin,util.now())
			self.iOper +=1
			
			return
			
		except util.PrimException, e:
			e.setWork(self)
			raise e
	
	def getIOper(self):
		return self.iOper
		
	def getDelay(self):
		return self.secs
		
	def __str__(self):
		return "[work iOper=%i]"%self.iOper

def createUser(cursor,user=const.DB_USER):
	try:
		cursor.execute("SELECT fcreateuser(%s)",[user])
	except StandardError,e:
		if e.pgcode!="YU001":
			raise e
	return
	

def simuInt(args):
	options,user,maxUser = args
	
	if(not options.seed is None):
		random.seed(options.seed) #for reproductibility of playings
		
	with util.DbConn(const,user) as dbcon:
		with util.DbCursor(dbcon) as cursor:
			w = None
			try:
				while True:
					w = Work(w,options,user,maxUser)
					if(w.getIOper() >= options.iteration):
						break
					w.execute(cursor)

				if options.maxparams:
					print "max_options:%s, nbAgr:%i " % (util.readMaxOptions(cursor),prims.getNbAgreement(cursor))

				if(options.verif):
					util.runverif(cursor)
		
			except KeyboardInterrupt:
				print 'interrupted by user' 
		
			except util.PrimException,se:
				w = se.getWork()
				cde = se.getCmd()
				print 'Failed on command: %s' % (str(se.getCmd()),)	

	return 
		
import threa
def simu(options):
	itera = 0
	_begin = util.now()
	if(options.reset):
		if(not prims.initDb()):
			raise util.SimuException("Market is not opened")

	with util.DbConn(const) as dbcon:
		with util.DbCursor(dbcon) as cursor:
		
			util.writeMaxOptions(cursor,options)
			begin = util.getAvct(cursor)

			for user in util.nameUsers():
				createUser(cursor,user)
				
			if(options.CHECKQUALITYOWNERSHIP):
				util.setQualityOwnership(cursor,True)
	
	if(options.threads==1):		
		simuInt((options,util.nameUser(0),1))
	else:
		# run in theads		
		ts = []	
		for i in range(options.threads):
			user = util.nameUser(i)
			maxUser = options.threads
			t = threa.ThreadWithArgs(func=simuInt,args=(options,user,maxUser),name=user)
			t.start()
			ts.append(t)
		for t in ts:
			t.join()
			
	itera = options.iteration * options.threads
		
	class Results:
		pass
			
	if(itera):
		res = {}
		with util.DbConn(const) as dbcon:
			with util.DbCursor(dbcon) as cursor:
				end =util.getAvct(cursor)
				for k,v in begin.iteritems():
					res[k] = end[k] - v
				print "done: %s " % res
		secs = util.duree(_begin,util.now())	
		print 'simu terminated after %.6f seconds (%.6f secs/oper)' % (secs,secs/itera)
		
		results = Results()
		res['dureeSecs'] = int(secs)
		res['nbOper'] = itera
		for k,v in res.iteritems():
			setattr(results,k,v)
		storeOptions('options',options)
		storeOptions('results',results)
			
	return
	
def storeOptions(prefix,options):
	with util.DbConn(const) as dbcon:
		with util.DbCursor(dbcon) as cursor:
			for k, v in [(x, getattr(options, x)) for x in dir(options) if not x.startswith('_')]:	
				if(not isinstance(v,int)): continue
				if(isinstance(v,bool)):
					if(v): v = 1
					else: v = 0
				
				name = prefix+'.'+k
				try:
					cursor.execute('INSERT INTO tconst (name,value) VALUES (%s,%s)',[name,v])
				except Exception,e:
					cursor.execute("UPDATE tconst SET value=%s WHERE name=%s",[v,name])
	

from optparse import OptionParser
def main():
	usage = "usage: %prog [options]"
	parser = OptionParser(usage)
	
	parser.add_option("-i", "--iteration",type="int", dest="iteration",help="number of iteration",default=0)	
	parser.add_option("-r", "--reset",action="store_true", dest="reset",help="database is reset",default=False)
	parser.add_option("-v", "--verif",action="store_true", dest="verif",help="fgeterrs run after",default=False)
	parser.add_option("-m", "--maxparams",action="store_true", dest="maxparams",help="print max parameters",default=False)
	parser.add_option("-t", "--threads",type="int", dest="threads",help="number of threads",default=1)
	parser.add_option("--seed",type="int",dest="seed",help="reset random seed")
	parser.add_option("--MAXCYCLE",type="int",dest="MAXCYCLE",help="reset MAXCYCLE")
	parser.add_option("--MAXTRY",type="int",dest="MAXTRY",help="reset MAXTRY")
	parser.add_option("--MAXORDERFETCH",type="int",dest="MAXORDERFETCH",help="reset MAXORDERFETCH")
	parser.add_option("--CHECKQUALITYOWNERSHIP",action="store_true",dest="CHECKQUALITYOWNERSHIP",help="set CHECK_QUALITY_OWNERSHIP",default=False)
	parser.add_option("-s","--scenario",type="string",action="store",dest="scenario",help="the scenario choosen",default="basic")
		
	(options, args) = parser.parse_args()
	
	possible_scenario = ["basic","quote"]	
	if(options.scenario not in possible_scenario):
		raise Exception("The scenario does'nt exist")
		
	#provisoire
	options.CHECKQUALITYOWNERSHIP = True
	
	simu(options)

if __name__ == "__main__":
	main()
	
"""
base simu_r1
 ./simu.py -i 10000 -t 10
done: {'nbAgreement': 75000L, 'nbMvtAgr': 240865L, 'nbMvtGarbadge': 11152L, 'nbOrder': 13836L} 
simu terminated after 28519.220312 seconds (0.285192 secs/oper)
"""

