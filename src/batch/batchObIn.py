#!/usr/bin/env python
import sys,os,time
import consts
import daemonize 
import psycopg2
import psycopg2.extensions

class ExDbNotReachable(psycopg2.Error):
    pass
    
def getConn(strconn):
    conn=psycopg2.connect(strconn)
    conn.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
    return conn

def tryConn(strconn):
    ''' try the connexion and raise an exception is something wrong happens
    '''
    conn,cur = None,None
    try:
        conn = getConn(strconn)
        cur = conn.cursor()

        if(consts.dbSchema):
            cur.execute("SET search_path TO %s" % consts.dbSchema)
        cur.execute(consts.dbsqlTry)
    finally:
        if(cur):
            cur.close()
        if(conn):
            conn.close()
    return
                          
def batchWrap(strconn):
    retry = 0
    while(True):
        try:
            batchObIn_(strconn)
        except Exception,e:
            msg = 'Exception:\n %s' % (second,str(e),)
            daemonize.send_error('daemon standby',msg,False)
            
        second = 10
        while(second):
            try:
                tryConn(strconn)
                second = 0

            except Exception,e:
                sleep(second)
                second *=2

        msg = 'The model is accessible' % (cnt,)
        cnt = 0
        daemonize.send_error('daemon restart',msg,False)
    return
    
                        
def batchObIn_(strconn):
    cnt = 0
    while(True):
        conn,cur = None,None
        try:
            conn = getConn(strconn)
            cur = conn.cursor()
            if(consts.dbSchema):
                cur.execute("SET search_path TO %s" % consts.dbSchema)
            cur.execute("SELECT count(*) from tstack")
            
            res = cur.fetchone()
            cntStack = res[0]
            # print res
            if(cntStack == 0):
                time.sleep(10)
            else:
                for i in range(cntStack):
                    cur.execute('select * from fproducemvt()')
                    cnt +=1
                    if(cnt % 1000 == 0):
                        cnt = 0
                        cur.execute('select * from cleanowners()')
        finally:
            if(cur):
                cur.close()
            if(conn):
                conn.close()
