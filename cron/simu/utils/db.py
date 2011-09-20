#!/usr/bin/python
#-*- coding: utf8 -*-

import psycopg2
import psycopg2.extras
import sys
strconnect = "dbname=test user=desktop host=176.31.243.132"

class DbError(Exception): pass


class Connection(object):
	def __init__(self,strcon = strconnect,autocommit = True):
		self.dbcon = None
		self.strcon  = strconnect
		self.autocommit = autocommit
		
	def __enter__(self):
		self.dbcon = psycopg2.connect(self.strcon)
		if(self.autocommit):
			self.dbcon.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
		return self
	
	def __exit__(self, type, value, tb):
		if(self.dbcon):
			self.dbcon.close()
			self.dbcon = None
		return False
			
class Cursor(object):
	"""
	includes a transaction
	"""
	def __init__(self,conn,cursor_factory=psycopg2.extras.RealDictCursor):
		self.conn = conn
		self.cursor_factory = cursor_factory
		#self.name = name

	def __enter__(self):

		self.cursor = self.conn.dbcon.cursor(cursor_factory = self.cursor_factory)
		if(not self.conn.autocommit):
			self.cursor.execute("BEGIN")
		# HERE IS THE IMPORTANT PART, by specifying a name for the cursor
		# psycopg2 creates a server-side cursor, which prevents all of the
		# records from being downloaded at once from the server.
		# cursor = conn.cursor()
		# self.cursor = self.conn.cursor(self.name, cursor_factory=psycopg2.extras.DictCursor)
		# Because cursor objects are iterable we can just call 'for - in' on
		# the cursor object and the cursor will automatically advance itself
		# each iteration.
		return self.cursor

	def __exit__(self,exc_type, exc_val, exc_tb):
		if(exc_type==None and not self.conn.autocommit):
			self.cursor.execute("COMMIT")
			# self.log.info("COMMIT")
		else:
			self.cursor.execute("ROLLBACK")
			# self.log.error("ROLLBACK",exc_info=True)
		self.cursor.close()
		return False # exception is propagated
		
def exec_file(conn,file_name):
	with open(file_name, 'r') as f:
		sql = f.read()
		f.close()
	with Cursor(conn) as cursor:
		cursor.executemany(sql,((),))

		
if(__name__ == "__main__"):

	with Connection(autocommit = True) as conn:
		with Cursor(conn,cursor_factory=psycopg2.extras.DictCursor) as cur:
			cur.execute("select count(*) from test")
			print cur.fetchone()
			
	with Connection(autocommit = False) as conn:
		# with transaction, using a dictionary as factory
		with Cursor(conn) as cur:
			cur.execute("select * from test")
			res = cur.fetchone()
			print res['num'],res['data']
			#
			cur.execute("select count(*) from test")
			print cur.fetchmany(10)
			cur.execute("INSERT INTO test (num, data) VALUES(%s, %s)",(100, "abc'def"))
			#raise Exception()

