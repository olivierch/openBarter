#!/usr/bin/python
# -*- coding: utf8 -*-

import random	# random.randint(a,b) gives N such as a<=N<=b
import psycopg2
import psycopg2.extras
from datetime import datetime
import sys
# import curses

#stdscr = curses.initscr()
cur_user = 'olivier'

def connect():
	dbcon = psycopg2.connect(
				database  = 'test',
				password  = '',
				user = cur_user,
				host = 'localhost',
				port = 5432
	)
	dbcon.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
	return dbcon
	
def isOpened(cursor):
	cursor.execute("SELECT state FROM vmarket ")
	res = [e[0] for e in cursor]
	return (res[0] == "OPENED")

def getOne(cursor,sql):
	cursor.execute(sql)
	res = [e[0] for e in cursor]
	return res[0]	

def getstats(cursor):
	cnts = {}
	pr = ''
	for t in ['tquality','trefused','torder','tmvt','tuser','tmarket']:
		sql = 'select count(*) from '+t
		cursor.execute(sql,[])
		res = [e[0] for e in cursor]
		pr += t+('.count(*)=%i\t' % (res[0],))
	print pr
		
	nbCommits = {}
	sql = 'select count(*),i from (select grp,count(*) i from tmvt group by grp) a group by i order by i asc'
	cursor.execute(sql,[])
	print 'cycle\tnbCommit'
	for e in cursor:
		print '%i\t%i' %(e[0],e[1])
	
	sql ='select count(*) from torder x,torder y where x.np=y.nr and x.qtt!=0 and y.qtt!=0 and not exists (select * from trefused r where x.id=r.x and y.id=r.y)'
	rels = getOne(cursor,sql)
	print 'relation between orders=%i' % (rels,)	
	sql ='select count(*) from torder where qtt!=0'
	orders = getOne(cursor,sql)
	print 'orders=%i\t relations/orders=%.2f' % (orders,rels/orders)

	sql ='select count(*)/2 from torder x,torder y where x.qtt!=0 and y.qtt!=0 and x.np=y.nr and y.np=x.nr and not exists (select * from trefused r where x.id=r.x and y.id=r.y) and not exists (select * from trefused s where x.id=s.y and y.id=s.x)';
	cycle2 = getOne(cursor,sql)
	print 'cycles_2=%i ' % (cycle2,)
	
	sql ='''select count(*)/3 from torder x,torder y,torder z where x.qtt!=0 and y.qtt!=0 and z.qtt!=0 and x.np=y.nr and not exists (select * from trefused r where x.id=r.x and y.id=r.y) and y.np=z.nr and not exists (select * from trefused s where y.id=s.x and z.id=s.y) and z.np=x.nr and not exists (select * from trefused s where z.id=s.x and x.id=s.y)'''
	cycle3 = getOne(cursor,sql)
	print 'cycles_3=%i ' % (cycle3,)

	
	
	
	
	sql = 'select count(*) from vstat where delta!=0'
	errs = getOne(cursor,sql)
	if (errs): 
		print '%i qualities in error' %(errs,)
	else:
		print 'fverify OK'
		
	

def simu():
	random.seed(0) #for reproductibility of playings
	nbOper = 0
	start = datetime.now()
	dbcon = connect()
	cursor = dbcon.cursor()
	cursor.execute("SET search_path='t' ")
	if(not isOpened(cursor)):
		print "Market not opened"		
	else:
		try:
			getstats(cursor)
		except Exception,e:
			print "Exception inattendue"
			print e
	try:
		cursor.close()
		# print "cursor closed"
	except Exception,e:
		print "Exception while trying to close the cursor"
	try:
		dbcon.close()
		# print "DB close"
	except Exception,e:
		print "Exception while trying to close the cursor"
		

if __name__ == "__main__":
	simu()
