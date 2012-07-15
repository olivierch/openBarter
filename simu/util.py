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
	duration = end - begin
	secs = duration.seconds + duration.microseconds/1000000.
	return secs
	
def now():
	return datetime.now()
		
def getDelai(time):
	return duree(now(),time)

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
	
class Cmde(Object):
	def __init__(self):
		self.start = None
		self.stop = None
		self.params = None
		self.proc = None
		self.str = None

		
	def getDelay(self):
		if(self.start is None or self.stop is None):
			return 0.
		return duree(self.start,self.stop)
	
	def execproc(self,cursor):
		self.begin = now()
		
		if(self.params id None or self.proc is None):
			raise PrimException(self,None)
		try:
			cursor.callproc(self.proc,self.params)
		except Exception,e:
			raise PrimException(self,e)
		finally:
			self.stop = now()

			
	def __str__(self):
		res = '[iOper= %i]' % self.nit
		try:
			res += self.str % tuple(self.params)
			# raise TypeError if incorrect formatting
		except TypeError,e:
			res += "ERROR: Could not format the primitive"
		return res	

	
