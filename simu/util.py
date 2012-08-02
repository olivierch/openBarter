#!/usr/bin/python
# -*- coding: utf8 -*-

import psycopg2
import psycopg2.extras
import const

class SimuException(Exception):
	pass 

		

def connect():
	dbcon = psycopg2.connect(
				database  = const.DB_NAME,
				password  = const.DB_PWD,
				user = const.DB_USER,
				host = const.DB_HOST,
				port = const.DB_PORT
	)
	dbcon.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
	return dbcon


#############################################################################
import random	# random.randint(a,b) gives N such as a<=N<=b
	
def getRandQtt():
	max_qtt = 10000 #sys.maxint
	#qtt = random.randint(max_qtt,max_qtt*2)
	qtt = random.randint(1,max_qtt)
	return qtt
	
def getRandOwner():
	return 'w'+str(random.randint(1,const.MAX_OWNER))
	
def getQltName(user,id):
	return user+'/q'+str(id)

	
def getDistinctRandQlt():
	# a couple (inr,inp) such as inr != inp
	inr = random.randint(1,const.MAX_QLT)
	inp = inr
	while inp == inr:
		inp = random.randint(1,const.MAX_QLT)
	return inp,inr

#############################################################################	
from datetime import datetime

def duree(begin,end):
	if(not isinstance(begin,datetime)): raise SimuException('begin is not datetime object')
	if(not isinstance(end,datetime)): raise SimuException('end is not datetime object')
	duration = end - begin
	secs = duration.days*3600*24 + duration.seconds + duration.microseconds/1000000.
	return secs
	
def now():
	return datetime.now()
		
def getDelai(time):
	return duree(time,now())

#############################################################################

class PrimException(SimuException):
	def __init__(self,cmd,e):
		self.work = None
		self.cmd = cmd
		self.e = e
	
	def getCmd(self):
		return self.cmd
		
	def setWork(self,work):
		self.work = work
	
	def getWork(self):
		return self.work
	
class Cmde(object):
	def __init__(self):
		# start and stop time when done
		self.start = None
		self.stop = None
		
		self.params = None # vector of params
		self.proc = None # primitive name
		self.str = None # string format of params

		
	def getDelay(self):
		if(self.start is None or self.stop is None):
			return 0.
		return duree(self.start,self.stop)
	
	def execproc(self,cursor):
		self.start = now()
		
		if(self.params is None or self.proc is None):
			raise PrimException(self,None)
		try:
			cursor.callproc(self.proc,self.params)
		except Exception,e:
			raise PrimException(self,e)
		finally:
			self.stop = now()

			
	def __str__(self):
		res = '' #'[iOper= %i]' % self.nit
		try:
			res += self.str % tuple(self.params)
			# raise TypeError if incorrect formatting
		except TypeError,e:
			res += "ERROR: Could not format the primitive"
		return res	


def writeMaxOptions(cursor,options):	
	sql = "UPDATE tconst SET value=%i WHERE name=\'%s\'"
	if(not options.MAXCYCLE is None):
		cursor.execute(sql % (int(options.MAXCYCLE),"MAXCYCLE"))
	if(not options.MAXTRY is None):
		cursor.execute(sql % (int(options.MAXTRY),"MAXTRY"))
	if(not options.MAXORDERFETCH is None):
		cursor.execute(sql % (int(options.MAXORDERFETCH),"MAXORDERFETCH"))

def readMaxOptions(cursor):
	r = []
	for n in ("MAXCYCLE","MAXTRY","MAXORDERFETCH"):
		cursor.execute("SELECT value FROM tconst WHERE name=%s",[n])
		res = [e[0] for e in cursor]
		r.append((n,res[0]))
	return r
	
def runverif(cursor):
	sql = "SELECT * from fgeterrs(true) WHERE cnt != 0"
	cursor.execute(sql,[])
	res = [e for e in cursor]
	if(len(res)):
		print "fgeterrs Errors found: %s" % res
	else:
		print "fgeterrs No errors found"
		
	
def getAvct(cursor):
	#nbAgreements
	avct={}
	cursor.execute("SELECT count(*),count(distinct grp) FROM tmvt WHERE nb != 1")
	res = [e for e in cursor]
	res = res[0]
	avct["nbMvtAgr"] = res[0]
	avct["nbAgreement"] = res[1]

	cursor.execute("SELECT count(*) FROM tmvt WHERE nb = 1")
	res = [e[0] for e in cursor]
	avct["nbMvtLeak"] = res[0]

	cursor.execute("SELECT count(*) FROM torder ")
	res = [e[0] for e in cursor]
	avct["nbOrder"] = res[0]
	
	return avct
		
	
