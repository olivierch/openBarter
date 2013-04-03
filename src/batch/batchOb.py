#!/usr/bin/env python
# -*- coding: iso-8859-1 -*-
import sys,os,time
import os.path
import consts
import daemonize
import batchObIn
import psycopg2
import psycopg2.extensions
from optparse import OptionParser
import signal
import time

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
def getStrConn():
    return "dbname='%s' user='%s' password='%s' host='%s' port='%s'" % (consts.dbName,consts.dbLogin,consts.dbPassword,consts.dbHost,consts.dbPort)
    
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
    
    strconn = getStrConn() #"dbname='%s' user='%s' password='%s' host='%s' port='%s'" % (consts.dbName,consts.dbLogin,consts.dbPassword,consts.dbHost,consts.dbPort)
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


    def handler(signum, frame):
        daemonize.send_error('daemon stopped','Daemon stopped with SIGTERM',True)
        finish()

    signal.signal(signal.SIGTERM, handler)

def start():    
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
    
def getPid():
    pathPid = os.path.join(consts.workdir,'pid')
    if(os.path.exists(pathPid)):
        with open(pathPid,'r') as f:
            r = f.readline()
            i = int(r)
            return i
    else:
        return None
        
def status(pid):
    pid = getPid()
    if(pid): 
        print "running with pid=%i" % (pid,)
    else:
        print "stopped"
    print "on bd %s on host %s:%s" % (consts.dbName,consts.dbHost,consts.dbPort)
    print "working directory: %s" % consts.workdir 
        
    
    
def stop(pid):
    os.kill(pid,signal.SIGTERM)
        


def batchOb():

    usage = """usage: %prog [options]
                manage de daemon openBarter for: """ + consts.dbName
    parser = OptionParser(usage)
    parser.add_option("-s","--start",action="store_true",dest="start",help="start openbarter",default=False)
    parser.add_option("-t","--stop",action="store_true",dest="stop",help="stop openbarter",default=False)
    parser.add_option("-r","--restart",action="store_true",dest="restart",help="restart openbarter",default=False)
    parser.add_option("-u","--status",action="store_true",dest="status",help="status openbarter",default=False)

    (options, args) = parser.parse_args()

    pid = getPid()
    if(options.status):
        status(pid) 
    elif(options.start):
        if(pid):
            print "Already running on pid %i" % pid
        else:
            start()
            
    elif(options.stop):
        if(pid):
            stop(pid)
            print "Stopped"
        else:
            print "Not running"

    elif(options.restart):
        if(pid):
            print"Restarting..."
            stop(pid)
            time.sleep(2)
            start()
        else:
            print"Not running, starting..."
            start()        
    else:
        print usage    
    
if __name__ == "__main__":
    batchOb()
    

