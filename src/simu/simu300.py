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
owner_max = 20
quality_max = 20

def connect():
	dbcon = psycopg2.connect(
				database  = 'test5',
				password  = '',
				user = cur_user,
				host = 'localhost',
				port = 5432
	)
	dbcon.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
	return dbcon
	
def boulot(cursor,stop = False):
	todo = "Undefined";
	try:
		owner = 'w'+str(random.randint(1,owner_max))
		max_qtt = 10000 #sys.maxint
		qtt_r = random.randint(1,max_qtt)
		qtt_p = random.randint(1,max_qtt)
	
		# a couple (inr,inp) such as inr != inp
		inr = random.randint(1,quality_max)
		inp = inr
		while inp == inr:
			inp = random.randint(1,quality_max)
		nr = cur_user+'/q'+str(inr)
		np = cur_user+'/q'+str(inp)
		todo = 'SELECT finsertorder(\'%s\',\'%s\',%i,%i,\'%s\',%i);' % (owner,nr,qtt_r,qtt_p,np,-1)
		if (stop):
			return 0,todo

		cursor.callproc('finsertorder',[owner,nr,qtt_r,qtt_p,np,-1])
		res = [e[0] for e in cursor]
		# print res
		return res[0],todo
	except Exception,e:
		print 'In execution of cde: %s\n Exception: %s' % (todo,str(e))
		raise e
	
def verif(cursor):
	cursor.callproc('fgetconnected',[1])
	res = [e[0] for e in cursor]
	l = len(res)
	if(l !=0):
		print '%i = fgetconnected()' % (len(res),)
	return l
	
def isOpened(cursor):
	cursor.execute("SELECT state FROM vmarket ")
	res = [e[0] for e in cursor]
	# print res[0]	
	return (res[0] == "OPENED")

def getDelai(time):
	duration = datetime.now() -time
	secs = duration.seconds + duration.microseconds/1000000.
	return secs

def simu(itera):
	random.seed(0) #for reproductibility of playings
	nbOper = 0
	start = datetime.now()
	dbcon = connect()
	cursor = dbcon.cursor()
	cursor.execute("SET search_path='t' ")
	cursor.execute("TRUNCATE torder RESTART IDENTITY CASCADE")
	cursor.execute("TRUNCATE torderempty RESTART IDENTITY CASCADE")
	cursor.execute("UPDATE tquality SET qtt=0")
	print "torder and torderempty truncated"
	phase = -1
	if(False): #not isOpened(cursor)):
		print "Market not opened"		
	else:
		try:
			cursor.execute("insert into tuser(name) values (%s)",[cur_user]);
		except psycopg2.IntegrityError:
			print "User '%s' already inserted, skipping" % cur_user
		while True:
			try:
				begin = datetime.now()
				#res = boulot(cursor,False)
				
				if(nbOper < itera):
					res,done = boulot(cursor)
					if(res):
						print '%i agreement found in %.6f' % (res,getDelai(begin))
					errs = 0 #verif(cursor)
					if(errs !=0):
						print '%i errors'% errs
						print 'after nbOper=%i:\n%s' % (nbOper,done)
						break 
				else:
					errs = verif(cursor)
					if(errs == 0):
						print 'No error'
					else:
						print '%i Errors' %(errs,) 
					nbOper -=1
					res,todo = boulot(cursor,stop=True)
					print 'Terminated just before nbOper=%i:\n%s'% (nbOper,todo)
					break 
				nbOper +=1

			except KeyboardInterrupt:
				break
			except Exception,e:
				break
				
	print "last oper in %f seconds" % getDelai(begin)
	secs = getDelai(start)
	print "Total %f seconds" % secs
	if nbOper>0:
		print "Mean %.6f seconds" % (secs/nbOper,)
	try:
		cursor.close()
		# print "cursor closed"
	except Exception,e:
		print "Exception while trying to close the cursor"
	try:
		dbcon.close()
		# print "DB close"
	except Exception,e:
		print "Exception while trying to close the connexion"
	
		

if __name__ == "__main__":
	itera = 100
	l = len(sys.argv)
	if(l==2):
		itera = int(sys.argv[1])
		simu(itera)
		print 'simu(%i) terminated' % (itera)
	else:
		print 'usage %s(iteration)' % (sys.argv[0],)
