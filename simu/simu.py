#!/usr/bin/python
# -*- coding: utf8 -*-

import prims
import sys
import const
import util
import random
# import curses

#stdscr = curses.initscr()

class Work(object):
	def __init__(self,iOper):
		self.cdes = []
		self.iOper = iOper
		self.params = self.getParams()
	
	def getParams(self):
		owner = util.getRandOwner()
		qtt_r = util.getRandQtt()
		qtt_p = util.getRandQtt()

		# a couple (inr,inp) such as inr != inp
		inr,inp = util.getDistinctRandQlt()
		nr = util.getQltName(const.DB_USER,inr)
		np = util.getQltName(const.DB_USER,inp)
		return (owner,nr,qtt_r,qtt_p,np)
		
	def execute(self,cursor):
		try:
			cde = prims.GetQuote(self.params)
			cde.execute(cursor)
			if(cde.getIdQuote()!=0):
				cde2 = prims.ExecQuote(cde.getOwner(),cde.getIdQuote())
				cde2.execute(cursor)
			else:
				cde2 = prims.InsertOrder(self.params)
				cde2.execute(cursor)
			
		except util.PrimException, e:
			e.setWork(self)
			raise e
			
	def getIOper(self):
		return self.iOper
		
	def __str__(self):
		return "[work iOper=%i]"%self.iOper
		
		
def iterer(cursor,iteration,obCMAXCYCLE=7,MAX_REFUSED=10):
	random.seed(0) #for reproductibility of playings
	
	iOper = 0
	while True:
		w = Work(iOper)
		if(iOper >= iteration):
			print 'Stopped before:\n%s'% (str(w),)
			break
		w.execute(cursor)
		iOper +=1

	print "Finished"
	print "Totalseconds;operations;obCMAXCYCLE;MAX_REFUSED;NbAgreement"
	print "%i;%i;%i;%i;" % (iOper,obCMAXCYCLE,MAX_REFUSED,prims.getNbAgreement(cursor))
	return 
	

def simu(iteration):
	
	if(not prims.initDb()):
		raise util.SimuException("Market not opened")
	#print 'debut simu'
		
	dbcon = util.connect()
	cursor = dbcon.cursor()
	cursor.execute("SELECT fcreateuser(%s)",[const.DB_USER])
	start = util.now()
	try:
		iterer(cursor,iteration)
		
	except KeyboardInterrupt:
		print 'interrupted by user' 
		
	except util.PrimException,se:
		cde = se.getCmd()
		print 'Failed on iter: %i' % (se.getWork().getIOper(),)
		print 'On command: %s' % (str(se.getCmd()),)	
			
	except Exception,e:
		print "Exception:",e

	finally:
		try:
			cursor.close()
			# print "cursor closed"
		except Exception,e:
			print "Exception while trying to close the cursor"
		try:
			dbcon.close()
			# print "DB close"
		except Exception,e:
			print "Exception while trying to close the connexion"
		
	secs = util.getDelai(start)
	
	print 'simu(%i) terminated after %.6f seconds' % (iteration,secs)
	
	return 
	

if __name__ == "__main__":
	l = len(sys.argv)
	if(l==2):
		iteration = int(sys.argv[1])
		if(iteration > 0):
			simu(iteration)
	else:
		print 'usage %s(iteration)' % (sys.argv[0],)
