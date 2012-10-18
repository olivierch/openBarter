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
	max_qtt = 10000 #sys.maxint = pow(2,63)-1
	#qtt = random.randint(max_qtt,max_qtt*2)
	qtt = random.randint(1,max_qtt)
	return qtt

def getMediumQtt():
	return 5000
		
def getRandOwner():
	return 'w'+str(random.randint(1,const.MAX_OWNER))
	
def getRandDepository(threads):
	if(threads==1):
		return const.DB_USER
	return nameUser(random.randint(0,threads-1))

def nameUser(thread):
	return 'user'+str(thread)

def nameUsers(thread):
	for j in range(thread):
		yield nameUser(j+1)

def nameUserRand(thread):
	return nameUser(random.randint(1,thread))
	
def getQltName(user,id):
	return user+'/q'+str(id)

def getDistinctRandQlt(thread,maxQlt,user,np):
	""" return a couple (nr,np) such as:
		 nr != np
	"""
	nr = np
	while np == nr:
		nr = getQltName(nameUserRand(thread),random.randint(1,maxQlt))
	return nr

#############################################################################	
from datetime import datetime

def duree(begin,end):
	""" returns a float; the number of seconds elapsed between begin and end 
	"""
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
	""" an exception wrapping the work that was in progree when it occured 
	"""
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
#############################################################################
import logging

####################################################################################
logging.basicConfig(level=logging.DEBUG,
                    format='(%(threadName)-10s) %(message)s',
                    )
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
			#logging.debug( "execute:%s" % str(self))
		except Exception,e:
			logging.debug(e)
			raise PrimException(self,e)


			
	def __str__(self):
		res = '' #'[iOper= %i]' % self.nit
		try:
			res += self.str % tuple(self.params)
			# raise TypeError if incorrect formatting
		except TypeError,e:
			res += "ERROR: Could not format the primitive"
		return res	
#############################################################################

def writeMaxOptions(cursor,options):
	""" maxoptions are written if redefined 
	"""	
	sql = "UPDATE tconst SET value=%i WHERE name=\'%s\'"
	if(not options.MAXCYCLE is None):
		cursor.execute(sql % (int(options.MAXCYCLE),"MAXCYCLE"))
	if(not options.MAXTRY is None):
		cursor.execute(sql % (int(options.MAXTRY),"MAXTRY"))
	if(not options.MAXORDERFETCH is None):
		cursor.execute(sql % (int(options.MAXORDERFETCH),"MAXORDERFETCH"))
		
def setQualityOwnership(cursor,check):
	val =0
	if(check): val =1
	sql = "UPDATE tconst SET value=%i WHERE name=\'CHECK_QUALITY_OWNERSHIP\'"
	cursor.execute(sql % (val,))	

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
	avct["nbMvtGarbadge"] = res[0]

	cursor.execute("SELECT count(*) FROM torder ")
	res = [e[0] for e in cursor]
	avct["nbOrder"] = res[0]
	
	return avct
	
####################################################################################
import os,sys
	
class Chdir:
	""" usage:
	with Chdir(path):
		do sthing
	"""         
	def __init__( self, newPath ):
		self.path = newPath
	
	def __enter__(self):  
		self.savedPath = os.getcwd()
		os.chdir(self.path)

	def __exit__(self, type, value, traceback):
		os.chdir( self.savedPath )
		
class DbConn:
	""" usage:
	with DbConn(const) as con:
		do sthing
	"""         
	def __init__( self, params,user=None ):
		self.params = params
		self.user = user
		if(user==None):
			self.user = params.DB_USER
	
	def __enter__(self): 
		try:
			self.con = psycopg2.connect(
						database  = self.params.DB_NAME,
						password  = self.params.DB_PWD,
						user = self.user,
						host = self.params.DB_HOST,
						port = self.params.DB_PORT
			)
		except psycopg2.OperationalError,e:
			print "Cannot connect to the db %s" % const.DB_NAME
			print "ABORT"
			sys.exit(-1)
		self.con.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT) 
		
		return self.con

	def __exit__(self, type, value, traceback):	
		try:
			self.con.close()
			#print "DB close"
		except Exception,e:
			print "Exception while closing the connexion"
		return False #exception of caller propagated
		
		
class DbCursor:
	""" usage:
	with DbConn(params) as con:
		with DbCursor(con) as cur:
			do sthing
	"""         
	def __init__( self, con ):
		self.con = con
	
	def __enter__(self):  
		self.cursor = self.con.cursor()
		return self.cursor

	def __exit__(self, type, value, traceback):	
		try:
			self.cursor.close()
			#print "cursor closed"
		except Exception,e:
			print "Exception while closing the cursor"
		return False #exception of caller propagated
				
				
				
		
	
