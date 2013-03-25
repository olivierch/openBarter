#!/usr/bin/python
# -*- coding: utf8 -*-

import psycopg2
import psycopg2.extras


def getSelect(cursor,sql,pars=[]):
	cursor.execute(sql,pars)	
	return [e for e in cursor]	

def getCycles(cursor,idmvt):	
	sql = """SELECT nb,count(*) as cnt from (
		SELECT gid,max(nb) as nb FROM (
			SELECT max(id) over(partition by created,grp) as gid,nb as nb from tmvt where id>%s
		) as t2 group by gid
	) as t group by nb order by nb asc"""
	r = const.FLOW_MAX_DIM*[0]
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
				
#############################################################################	
from datetime import datetime

class SimuException(Exception):
	pass 

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
				
		
	
