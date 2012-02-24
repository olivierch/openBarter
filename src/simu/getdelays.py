#!/usr/bin/python
# -*- coding: utf8 -*-

import random	# random.randint(a,b) gives N such as a<=N<=b
import psycopg2
import psycopg2.extras
from datetime import datetime
import sys
cur_user='olivier'
dbname = 'test2'
def connect():
	dbcon = psycopg2.connect(
				database  = dbname,
				password  = '',
				user = cur_user,
				host = 'localhost',
				port = 5432
	)
	dbcon.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
	return dbcon


def getdelays():
	begin = datetime.now()
	dbcon = connect()
	cursor = dbcon.cursor()
	cursor.execute("SET search_path='t' ")
	cursor.execute("SELECT name,value FROM tconst WHERE name like 'perf_%' ORDER BY name")
	d= {}
	for name,value in cursor:
		name = name[5:]
		key = name[4:]
		if key in d:
			x = d[key]
		else:
			x = {}
		name = name[0:4]
		if(name == 'lay_'):
			x['delay'] = value
		elif(name == 'cnt_'):
			x['cnt'] = value
		d[key] = x
	print 'Execution time of modules on database "%s"' % dbname
	print 'fct	cnt	delay	total'
	print '______________________________'
	for key,x in d.iteritems():
		print '%s	%i	%f	%i' % (key,x['cnt'],x['delay']/float(x['cnt']),x['delay'])
	
	#cursor.execute("UPDATE tconst SET value=0 WHERE name like 'perf_%'")
	try:
		cursor.close()
		print "cursor closed"
	except Exception,e:
		print "Exception while trying to close the cursor"
	try:
		dbcon.close()
		print "DB close"
	except Exception,e:
		print "Exception while trying to close the connexion"
	
		

if __name__ == "__main__":
	getdelays()

