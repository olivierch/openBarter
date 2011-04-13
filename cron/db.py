#!/usr/bin/python
#-*- coding: utf8 -*-

import psycopg2
import psycopg2.extras
import settings
import sys
"""
with Connection(log) as conn:
	with Cursor(conn,'name') as cursor:
		cursor.execute("select ip from clients")
		for ip in cursor:
			...
"""

class Connection():
	def __init__(self,log = None):
		self.dbcon = None
		self.log = log
		
	def __enter__(self):
		self.dbcon = None
		try:
			self.dbcon = psycopg2.connect(
				database  = settings.DATABASE_NAME,
				password  = settings.DATABASE_PASSWORD,
				user = settings.DATABASE_USER,
				host = settings.DATABASE_HOST,
				port = settings.DATABASE_PORT
			)
			self.dbcon.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)

		except psycopg2.Error,e:
			self.error("could not connect to the database")
			raise e
		return self.dbcon
	
	def __exit__(self, type, value, tb):
		if(type):
			self.error("An error %s occured" % (str( type),))
		self.dbcon.close()
		self.dbcon = None
		return False
		
	def error(str):
		if(self.log):
			self.log.error(str)	
		else:
			print >> sys.stderr,str
			
class Cursor():
	"""
	includes a transaction
	"""
	def __init__(self,conn,log):
		self.conn = conn
		# self.name = name
		self.log = log
	def __enter__(self):
		self.cursor = self.conn.cursor()
		# self.cursor.execute("BEGIN")
		# self.log.info("BEGIN")
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
		"""
		if(exc_type==None):
			self.cursor.execute("COMMIT")
			# self.log.info("COMMIT")
		else:
			self.cursor.execute("ROLLBACK")
			self.log.error("ROLLBACK",exc_info=True)

		"""
		if(exc_type == psycopg2.Error):
			self.log.error(exc_val.pgerror)
		self.cursor.close()
		return False # exception is propagated
		
def getDictsFromCursor(cursor):
	""" usage:
	for d in getDictsFromCursor(cursor):
		print d
	"""
	while True:
		nextRow = cursor.fetchone()
		if not nextRow: break
		d = {}
		for (i,coldesc) in enumerate(cursor.description):
			d[coldesc[0]] = nextRow[i]
		yield d
