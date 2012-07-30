#!/usr/bin/python
# -*- coding: utf8 -*-
import util
		
class GetQuote(util.Cmde):
	def __init__(self,params):
		owner,nr,qtt_r,qtt_p,np = params
		super(util.Cmde)
		self.params = [owner,nr,qtt_r,qtt_p,np]
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
		owner,nr,qtt_r,qtt_p,np = params
		super(util.Cmde)
		self.params = [owner,nr,qtt_r,qtt_p,np]
		self.str = 'SELECT finsertorder(\'%s\',\'%s\',%i,%i,\'%s\');'
		self.proc = 'finsertorder'
		self.res = None
		
	def execute(self,cursor):
		self.execproc(cursor)
		self.res = [e for e in cursor]
		return self.res		
	
def initDb():
	import subprocess
	import const

	subprocess.call(['dropdb',const.DB_NAME])
	subprocess.call(['createdb',const.DB_NAME])
	p1 = subprocess.Popen(['more','../src/sql/model.sql'], stdout=subprocess.PIPE)
	p2 = subprocess.Popen(['psql', const.DB_NAME], stdin=p1.stdout,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
	p2.communicate()
	# print 'done'
	return p2.returncode == 0

	# subprocess.Popen(['psql '+ const.DB_NAME +' < ../src/sql/model.sql'],shell=True)

	
			
def initDbOld(cursor,obCMAXCYCLE,MAX_REFUSED):
	cursor.execute("SET search_path='t' ")
	cursor.execute("TRUNCATE torder RESTART IDENTITY CASCADE")
	cursor.execute("TRUNCATE torderempty RESTART IDENTITY CASCADE")
	cursor.execute("TRUNCATE tmvt RESTART IDENTITY CASCADE")
	cursor.execute("UPDATE tquality SET qtt=0")
	cursor.execute("UPDATE tconst SET value=%s WHERE name=%s",[obCMAXCYCLE,'obCMAXCYCLE'])
	cursor.execute("UPDATE tconst SET value=%s WHERE name=%s",[MAX_REFUSED,'MAX_REFUSED'])
	cursor.execute("VACUUM ANALYZE")
	
	cursor.execute("SELECT fcreateuser(%s)",[const.DB_USER])

	# print "torder and torderempty truncated"
	return isOpened(cursor)

	
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
	
