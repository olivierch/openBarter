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
	def __init__(self,w):
		self.cdes = []
		self.params = self.getParams()
		if(w is not None):
			self.secs = w.getDelay()
			self.iOper = w.getIOper()
		else:
			self.secs = 0.
			self.iOper = 0
	
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
			"""
			cde = prims.GetQuote(self.params)
			cde.execute(cursor)
			self.secs += cde.getDelay()
			
			if(cde.getIdQuote()!=0):
				cde2 = prims.ExecQuote(cde.getOwner(),cde.getIdQuote())
				cde2.execute(cursor)
			else:
				cde2 = prims.InsertOrder(self.params)
				cde2.execute(cursor)
			"""
			cde2 = prims.InsertOrder(self.params)
			cde2.execute(cursor)	
			self.secs += cde2.getDelay()
			
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
		
def iterer(cursor,options):
	if(not options.seed is None):
		random.seed(options.seed) #for reproductibility of playings
	
	w = None
	begin = util.getAvct(cursor)
	while True:
		w = Work(w)
		if(w.getIOper() >= options.iteration):
			"""
			print 'Ended before:\n%s'% (str(w),)
			print "next command would be:"
			print "SELECT * from fgetquote(\'%s\',\'%s\',%i,%i,\'%s\')" % w.params
			"""
			break
		w.execute(cursor)

	if options.maxparams:
		print "max_options:%s, nbAgr:%i " % (util.readMaxOptions(cursor),prims.getNbAgreement(cursor))
	if(w.getIOper()!=0):
		end =util.getAvct(cursor)
		res = {}
		for k,v in begin.iteritems():
			res[k] = end[k] - v
		print "done: %s " % res
	return w
		
def simu(options):
	if(options.reset):
		if(not prims.initDb()):
			raise util.SimuException("Market not opened")
		
	dbcon = util.connect()
	cursor = dbcon.cursor()
	if(options.reset):
		cursor.execute("SELECT fcreateuser(%s)",[const.DB_USER])
	util.writeMaxOptions(cursor,options)

	w = None
	
	try:
		w = iterer(cursor,options)
		if(options.verif):
			util.runverif(cursor)
		
	except KeyboardInterrupt:
		print 'interrupted by user' 
		
	except util.PrimException,se:
		w = se.getWork()
		cde = se.getCmd()
		print 'Failed on command: %s' % (str(se.getCmd()),)	
		"""		
		except Exception,e:
			print "Unidentified Exception:",e
		"""
	finally:
		
		try:
			cursor.close()
			# print "cursor closed"
		except Exception,e:
			print "Exception while closing the cursor"
		finally:
			try:
				dbcon.close()
				# print "DB close"
			except Exception,e:
				print "Exception while closing the connexion"
		
	if(w is not None):
		d = w.getDelay()
		n = w.getIOper()
		if(n!=0):
			print 'simu terminated after %.6f seconds (%.6f secs/oper)' % (d,d/w.getIOper())
	
	return 
	

from optparse import OptionParser
def main():
	usage = "usage: %prog [options]"
	parser = OptionParser(usage)
	
	parser.add_option("-i", "--iteration",type="int", dest="iteration",help="number of iteration",default=0)	
	parser.add_option("-r", "--reset",action="store_true", dest="reset",help="database is reset",default=False)
	parser.add_option("-v", "--verif",action="store_true", dest="verif",help="fgeterrs run after",default=False)
	parser.add_option("-m", "--maxparams",action="store_true", dest="maxparams",help="print max parameters",default=False)
	parser.add_option("--seed",type="int",dest="seed",help="reset random seed")
	parser.add_option("--MAXCYCLE",type="int",dest="MAXCYCLE",help="reset MAXCYCLE")
	parser.add_option("--MAXTRY",type="int",dest="MAXTRY",help="reset MAXTRY")
	parser.add_option("--MAXORDERFETCH",type="int",dest="MAXORDERFETCH",help="reset MAXORDERFETCH")
		
	(options, args) = parser.parse_args()
	simu(options)

if __name__ == "__main__":
	main()

