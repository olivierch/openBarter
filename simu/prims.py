#!/usr/bin/python
# -*- coding: utf8 -*-
import util
		
class GetQuote(util.Cmde):
	def __init__(self,params):
		owner,nr,qtt_r,qtt_p,np = params
		super(util.Cmde)
		self.params = [owner,nr,qtt_r,qtt_p,np,-1]
		self.str = 'SELECT fgetquote(\'%s\',\'%s\',%i,%i,\'%s\',%i);'
		self.proc = 'fgetquote'
		self.res = None
		
	def execute(self,cursor):
		self.execproc(cursor)
		self.res = [e for e in cursor]
		return self.res
		
	def getIdQuote(self):
		return self.res[0] #TODO

class ExecQuote(util.Cmde):
	def __init__(self,idQuote):
		super(util.Cmde)
		self.params = [idQuote]
		self.str = 'SELECT fexecquote(%i);'
		self.proc = 'execquote'
		self.res = None
		
	def execute(self,cursor):
		self.execproc(cursor)
		self.res = [e for e in cursor]
		return self.res
			
def initDb((cursor,obCMAXCYCLE,MAX_REFUSED):
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
	
