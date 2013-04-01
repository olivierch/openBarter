#!/usr/bin/env python
# -*- coding: iso-8859-1 -*-
import sys,os,time
import os.path
import consts
import daemonize
import batchObIn
import psycopg2
import psycopg2.extensions

'''
les données de travail sont dans le répertoire consts.workdir
ce sont les fichiers suivants:
	batchOb.log
	time
	pid
pid contient le numéro de process lançé.
Le process ne peut pas être relancé si ce fichier est présent
Pour le terminer, faire kill -15 pid (SIGTERM)
time sont les dates de début et de fin. Cette dernière n'est renseignée
que si le process est terminé.

Une erreur envoie un email et termine
le SIGTERM envoie un email et termine.

voir http://code.activestate.com/recipes/66012/
'''

def writePid(stri):
	pathPid = os.path.join(consts.workdir,'pid')
	fpid = open(pathPid,'w')
	fpid.write(stri)
	fpid.close()
	
def begin():
	pathPid = os.path.join(consts.workdir,'pid')
	if(os.path.exists(pathPid)):
		print "The file %s was found. The process is probably running" % pathPid
		sys.exit(1)
	writePid('\n')
	write_time('Start')
	
	strconn = "dbname='%s' user='%s' password='%s' host='%s' port='%s'" % (consts.dbName,consts.dbLogin,consts.dbPassword,consts.dbHost,consts.dbPort)
	try:
		batchObIn.tryConn(strconn)
	except Exception, e:
		print e
		print "could not connect to the database with %s." % strconn
		finish()

	return strconn
		
def finish():
	write_time('Stop')		
	os.remove(os.path.join(consts.workdir,'pid'))
	sys.exit(0)
	
def write_time(msg):
	pathTime = os.path.join(consts.workdir,'time')
	ftime = open(pathTime,'a+')
	ftime.write(('[%s] %s\n' % (time.ctime(),msg)))
	ftime.close()
	return

def setSigterm():
	import signal
	import time

	def handler(signum, frame):
		daemonize.send_error('daemon stopped','Daemon stopped with SIGTERM',True)
		finish()

	signal.signal(signal.SIGTERM, handler)

def batchOb():	

	
	strconn = begin()
	setSigterm()
	
	log = os.path.join(consts.workdir,consts.logfile)
	daemonize.daemonize('dev/null',log,log)
		
	msg = 'Daemon started with pid %i' % (os.getpid(),)
	dosendmail = daemonize.send_error('daemon started',msg,True);
	writePid('%d\n' % os.getpid())
	
	try:
		batchObIn.batchWrap(strconn)
	except Exception, e:
		msg = 'Daemon stopped with exception:\n %s\n'% (str(e),)
		daemonize.send_error('daemon crashed',msg,dosendmail)
	finish()



if __name__ == "__main__":
	batchOb()
	

