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
	def __init__(self,w,options,user):
		self.cdes = []
		self.options = options
		self.user = user
		
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

		# a couple (inr,inp) such as inr != inp
		maxQlt = const.MAX_QLT // self.options.threads
		if(maxQlt <2):
			print "const.MAX_QLT // thread not consistent"
			exit(-2)
	
		np = util.getQltName(self.user,1+(self.iOper % maxQlt))
		nr = util.getDistinctRandQlt(self.options.threads,maxQlt,self.user,np)
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
		
def iterer(cursor,options,user):
	if(not options.seed is None):
		random.seed(options.seed) #for reproductibility of playings
	
	w = None

	while True:
		w = Work(w,options,user)
		if(w.getIOper() >= options.iteration):
			break
		w.execute(cursor)

	if options.maxparams:
		print "max_options:%s, nbAgr:%i " % (util.readMaxOptions(cursor),prims.getNbAgreement(cursor))

	return w

def createUser(cursor,user=const.DB_USER):
	try:
		cursor.execute("SELECT fcreateuser(%s)",[user])
	except StandardError,e:
		if e.pgcode!="YU001":
			raise e
	return
	

def simuInt(args):
	options,user = args
	with util.DbConn(const,user) as dbcon:
		with util.DbCursor(dbcon) as cursor:
			
	
			w = None
	
			try:
				w = iterer(cursor,options,user)
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
			
	
	if(options.threads==1):		
		with util.DbConn(const) as dbcon:
			with util.DbCursor(dbcon) as cursor:
				createUser(cursor)
			simuInt((options,const.DB_USER))
			itera = options.iteration
	else:		
		with util.DbConn(const) as dbcon:
			with util.DbCursor(dbcon) as cursor:
				for user in util.nameUsers(options.threads):
					createUser(cursor,user)
				util.setQualityOwnership(cursor,True)
				
		ts = []	
		for user in util.nameUsers(options.threads):
			t = threa.ThreadWithArgs(func=simuInt,args=(options,user),name=user)
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
	parser.add_option("-s","--scenario",type="string",action="store",dest="scenario",help="the scenario choosen",default="basic")
		
	(options, args) = parser.parse_args()
	
	possible_scenario = ["basic","quote"]	
	if(options.scenario not in possible_scenario):
		raise Exception("The scenario does'nt exist")
	
	
	
	
	simu(options)

if __name__ == "__main__":
	main()
	
"""
base simu_r1
 ./simu.py -i 10000 -t 10
done: {'nbAgreement': 75000L, 'nbMvtAgr': 240865L, 'nbMvtGarbadge': 11152L, 'nbOrder': 13836L} 
simu terminated after 28519.220312 seconds (0.285192 secs/oper)
"""

