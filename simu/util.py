#!/usr/bin/python
# -*- coding: utf8 -*-

import psycopg2
import psycopg2.extras
import const

class SimuException(Exception):
	pass 

#############################################################################
import random	# random.randint(a,b) gives N such as a<=N<=b
	
def getRandQtt():
	max_qtt = 10000 #sys.maxint = pow(2,63)-1
	#qtt = random.randint(max_qtt,max_qtt*2)
	qtt = random.randint(1,max_qtt)
	return qtt

def getMediumQtt():
	return 9973 # biggest prime number < 10 000
getMediumQtt.const = True
		
def getRandOwner():
	return 'w'+str(random.randint(1,const.MAX_OWNER))

def nameUser(i):
	# i should be in [0,const.MAX_USER]
	j = i % const.MAX_USER
	return 'user'+str(j)

def nameUsers():
	for j in range(const.MAX_USER):
		yield nameUser(j)

def nameUserRand():
	return nameUser(random.randint(1,const.MAX_USER)-1)
	
def getQltName(user,i):
	q = 'q'+str(i)
	if(user is None):
		return q
	q = user+'/'+q
	return q


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
                    
def getParameters(options,user):
	owner = getRandOwner()
	qtt_p = getMediumQtt() 
	qtt_r = getRandQtt()
	
	# define a couple (nr,np) such as nr != np
	_user,_other = None,None

	if(options.CHECKQUALITYOWNERSHIP):
		_user = user
		_other = nameUser(random.randint(0,options.maxUser-1))
		maxQlt = const.MAX_QLT //options.maxUser
	else:
		maxQlt = const.MAX_QLT		
	if(maxQlt <2):
		sys.exit(-1)

	np = getQltName(_user,random.randint(0,maxQlt-1))
	nr = np
	while np == nr:
		nr = getQltName(_other,random.randint(0,maxQlt-1))
		
	return (owner,np,qtt_p,qtt_r,nr)
	

def writeMaxOptions(cursor,options):
	""" maxoptions are written if redefined 
	"""	
	sql = "UPDATE tconst SET value=%i WHERE name=\'%s\'"
	if(not options.MAXCYCLE is None):
		cursor.execute(sql % (int(options.MAXCYCLE),"MAXCYCLE"))
	if(not options.MAXTRY is None):
		cursor.execute(sql % (int(options.MAXTRY),"MAXTRY"))
	if(not options.MAXPATHFETCHED is None):
		cursor.execute(sql % (int(options.MAXPATHFETCHED),"MAXPATHFETCHED"))
		
def setQualityOwnership(cursor,check=True):
	val =0
	if(check): val =1
	sql = "UPDATE tconst SET value=%i WHERE name=\'CHECK_QUALITY_OWNERSHIP\'"
	cursor.execute(sql % (val,))	

def readMaxOptions(cursor):
	r = []
	for n in ("MAXCYCLE","MAXTRY","MAXPATHFETCHED"):
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

	
def getSelect(cursor,sql,pars=[]):
	cursor.execute(sql,pars)	
	return [e for e in cursor]	

def getCycles(cursor,idmvt):	
	sql = """SELECT nb,count(*) as cnt from (
		SELECT gid,max(nb) as nb FROM (
			SELECT max(id) over(partition by created,grp) as gid,nb as nb from tmvt where id>%s
		) as t2 group by gid
	) as t group by nb order by nb asc"""
	r = 8*[0]
	res = getSelect(cursor,sql,[idmvt])
	for nb,cnt in res:
		r[nb-1]=cnt
	return r
	
def getVolumes(cursor):
	""" for each quality, sum of(tmvt,tvmtremoved,torder) """
	_volumes = getSelect(cursor,"""SELECT q.name,sum(m.qtt) FROM (
		SELECT qtt,nat from tmvt 
		UNION ALL SELECT qtt,nat from tmvtremoved
		UNION ALL SELECT qtt as qtt,np as nat from torder
	) m INNER JOIN tquality q ON(q.id=m.nat) GROUP BY q.name ORDER BY q.name""")
	#print _volumes
	return _volumes	

def getAvct(begin):

	def _getAvct(cursor):
		avct={}
		res = getSelect(cursor,"SELECT count(*),count(distinct grp) FROM tmvt WHERE nb != 1")
		res = res[0]
		avct["nbMvt"] = res[0]
		avct["nbAgreement"] = res[1]

		res = getSelect(cursor,"SELECT count(*) FROM tmvt WHERE nb = 1")
		avct["nbMvtGarbadge"] = res[0][0]
		
		res = getSelect(cursor,"SELECT max(id) FROM tmvt ")
		res = res[0][0]
		if(res is None): res = 0
		avct["maxMvtId"] = res

		res = getSelect(cursor,"SELECT max(id) FROM torder ")
		res = res[0][0]
		if(res is None): res = 0
		avct["nbOrder"] = res
	
		return avct
		
	
	with DbConn(const) as dbcon:
		with DbCursor(dbcon) as cursor:
			res = {}
			if(begin is None):
				res =  _getAvct(cursor)
			else:
				end = _getAvct(cursor)
				for k,v in begin.iteritems():
					res[k] = end[k] - v
				res["cycles"] = getCycles(cursor,begin["maxMvtId"])
				del(begin["maxMvtId"])
				print "done: %s " % res	

	return res

	
def getDictInt(obj):
	""" retourne un dico qui représente les attributs entiers de l'objet """
	res ={}
	for k, v in [(x, getattr(obj, x)) for x in dir(obj) if not x.startswith('_')]:	
		if(not isinstance(v,int)): continue
		if(isinstance(v,bool)):
			if(v): v = 1
			else: v = 0
		res[k]=v
	return res
	
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
				
				
				
		
	
