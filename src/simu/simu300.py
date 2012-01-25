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
	
def boulot(cursor):

	owner = 'w'+str(random.randint(1,20))
	max_qtt = 10000 #sys.maxint
	qtt_r = random.randint(1,max_qtt)
	qtt_p = random.randint(1,max_qtt)
	
	# a couple (inr,inp) such as inr != inp
	inr = random.randint(1,20)
	inp = inr
	while inp == inr:
		inp = random.randint(1,20)
	nr = cur_user+'/q'+str(inr)
	np = cur_user+'/q'+str(inp)
	# print 'finsertorder',[owner,nr,qtt_r,qtt_p,np]
	cursor.callproc('finsertorder',[owner,nr,qtt_r,qtt_p,np])
	res = [e[0] for e in cursor]
	# print res
	return res[0]
	
def isOpened(cursor):
	cursor.execute("SELECT state FROM vmarket ")
	res = [e[0] for e in cursor]
	# print res[0]	
	return (res[0] == "OPENED")

def getDelai(time):
	duration = datetime.now() -time
	secs = duration.seconds + duration.microseconds/1000000.
	return secs

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
			cursor.execute("insert into tuser(name) values (%s)",[cur_user]);
		except psycopg2.IntegrityError:
			print "User '%s' already inserted, skipping" % cur_user
		while True:
			try:
				begin = datetime.now()
				res = boulot(cursor)
				if(res):
					print '%i agreement found in %.6f' % (res,getDelai(begin))
				nbOper +=1
				if(nbOper == 300):
					break
			except KeyboardInterrupt:
				break
			except Exception,e:
				print "Exception inattendue"
				print e
				break
				
	print "End: %i operations" % nbOper
	secs = getDelai(start)
	print "Total %f seconds" % secs
	if nbOper!=0:
		print "Mean %.6f seconds" % (secs/nbOper,)
	try:
		cursor.close()
		print "cursor closed"
	except Exception,e:
		print "Exception while trying to close the cursor"
	try:
		dbcon.close()
		print "DB close"
	except Exception,e:
		print "Exception while trying to close the cursor"
		

if __name__ == "__main__":
	simu()
