#!/usr/bin/python
# -*- coding: utf8 -*-

import util
import const
		
class GetQuote(util.Cmde):
	def __init__(self,params):
		owner,np,qtt_p,qtt_r,nr = params
		super(util.Cmde)
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

class ExecQuote(util.Cmde):
	def __init__(self,owner,idQuote):
		super(util.Cmde)
		self.params = [owner,idQuote]
		self.str = 'SELECT fexecquote(\'%s\',%i);'
		self.proc = 'fexecquote'
		self.res = None
		
	def execute(self,cursor):
		self.execproc(cursor)
		self.res = [e for e in cursor]
		return self.res

class InsertOrder(util.Cmde):
	def __init__(self,params):
		owner,np,qtt_p,qtt_r,nr = params
		super(util.Cmde)
		self.params = [owner,np,qtt_p,qtt_r,nr]
		self.str = 'SELECT finsertorder(\'%s\',\'%s\',%i,%i,\'%s\');'
		self.proc = 'finsertorder'
		self.res = None
		
	def execute(self,cursor):
		self.execproc(cursor)
		self.res = [e for e in cursor]
		return self.res
		
#################################################################################		
def getErrs(cde,cursor):
	cursor.execute("SELECT * from fgeterrs(true) ")
	for e in cursor:
		if(e[1] != 0):
			ex = Exception("fgeterrs(true) -> %s:%i"% tuple(e) )
			raise util.PrimException(cde,ex)
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
	
def getSelect(cursor,sql,pars):
	cursor.execute(sql,pars)	
	return [e for e in cursor]
	
