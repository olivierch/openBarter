#!/usr/bin/python
# -*- coding: utf8 -*-

import util
import const

#############################################################################
import logging

logging.basicConfig(level=logging.DEBUG,
                    format='(%(threadName)-10s) %(message)s',
                    )

#############################################################################

class PrimException(Exception):
	""" an exception wrapping the work that was in progree when it occured 
	"""
	def __init__(self,cmd,e):
		self.cmd = cmd
		self.e = e
	
	def getCmd(self):
		return self.cmd

		
#################################################################################	
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
		return util.duree(self.start,self.stop)
	
	def execproc(self,cursor):
		self.start = util.now()
		
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
		
class GetQuote(Cmde):
	def __init__(self,params):
		owner,np,qtt_p,qtt_r,nr = params
		super(Cmde)
		self.params = [owner,np,qtt_p,qtt_r,nr]
		self.str = 'SELECT fgetquote(\'%s\',\'%s\',%i,%i,\'%s\');'
		self.proc = 'fgetquote'
		self.res = None
		
	def execute(self,cursor):
		self.execproc(cursor)
		self.res = [e for e in cursor]
		return self.res
		
	def getIdQuote(self):
		print self.res
		return self.res[0][0]
	
	def getOwner(self):
		return self.params[0]

class ExecQuote(Cmde):
	def __init__(self,owner,idQuote):
		super(Cmde)
		self.params = [owner,idQuote]
		self.str = 'SELECT fexecquote(\'%s\',%i);'
		self.proc = 'fexecquote'
		self.res = None
		
	def execute(self,cursor):
		self.execproc(cursor)
		self.res = [e for e in cursor]
		return self.res

class InsertOrder(Cmde):
	def __init__(self,params):
		owner,np,qtt_p,qtt_r,nr = params
		super(Cmde)
		self.params = [owner,np,qtt_p,qtt_r,nr]
		self.str = 'SELECT finsertorder(\'%s\',\'%s\',%i,%i,\'%s\');'
		self.proc = 'finsertorder'
		self.res = None
		
	def execute(self,cursor):
		self.execproc(cursor)
		self.res = [e for e in cursor]
		return self.res

		
#################################################################################

def createUser(cursor,user=const.DB_USER):
	res = getSelect(cursor,'SELECT * FROM tuser WHERE name=%s',[user])
	if(len(res)==0):
		cursor.execute("SELECT fcreateuser(%s)",[user])
	return

def getErrs(cde,cursor):
	cursor.execute("SELECT * from fgeterrs() ")
	for e in cursor:
		if(e[1] != 0):
			ex = Exception("fgeterrs() -> %s:%i"% tuple(e) )
			raise PrimException(cde,ex)
	return
	
def initDb():
	""" remove then creates a database with the model """ 
	import subprocess
	subprocess.call(['dropdb',const.DB_NAME])
	subprocess.call(['createdb',const.DB_NAME])
	with util.Chdir(const.PATH_SRC):
		p1 = subprocess.Popen(['more','sql/model.sql'], stdout=subprocess.PIPE)
		p2 = subprocess.Popen(['psql', const.DB_NAME], stdin=p1.stdout,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
		p2.communicate()
	print 'database was reset'
	return p2.returncode == 0

	# subprocess.Popen(['psql '+ const.DB_NAME +' < ../src/sql/model.sql'],shell=True)

def execSql(fil):
	import subprocess

	p1 = subprocess.Popen(['more',fil], stdout=subprocess.PIPE)
	p2 = subprocess.Popen(['psql', const.DB_NAME], stdin=p1.stdout,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
	p2.communicate()
	# print 'done'
	return p2.returncode == 0
	
def isOpened(cursor):
	cursor.execute("SELECT state FROM vmarket ")
	res = [e[0] for e in cursor]
	# print res[0]	
	return (res[0] == "OPENED")
	
def verif(cursor):
	cursor.callproc('fgetconnected',[1])
	res = [e[0] for e in cursor]
	
	l = len(res)
	if(l !=0):
		print '%i = fgetconnected()' % (len(res),)
	return l

def getNbAgreement(cursor):
	cursor.execute("SELECT count(distinct grp) FROM tmvt WHERE nb!=1 ")
	res = [e[0] for e in cursor]
	# print res[0]	
	return res[0]
	
def getSelect(cursor,sql,pars=[]):
	cursor.execute(sql,pars)	
	return [e for e in cursor]
	
	
def storeOptions(prefix,results):
	""" store values only if keys are not written yet """
	with util.DbConn(const) as dbcon:
		with util.DbCursor(dbcon) as cursor:
			for k,v in results.iteritems():	
				if(not isinstance(v,int)):continue			
				name = prefix+'.'+k
				res = getSelect(cursor,'SELECT * FROM tconst WHERE name=%s',[name])
				if(len(res)==0):
					cursor.execute('INSERT INTO tconst (name,value) VALUES (%s,%s)',[name,v])
				"""
				else:
					cursor.execute("UPDATE tconst SET value=%s WHERE name=%s",[v,name])
				"""
	return

	
