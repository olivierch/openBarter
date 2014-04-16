# -*- coding: utf-8 -*-
import string
import os.path
import time, sys
import molet


def get_paths():
    curdir = os.path.abspath(__file__)
    curdir = os.path.dirname(curdir)
    curdir = os.path.dirname(curdir)
    sqldir = os.path.join(curdir,'sql')
    resultsdir,expecteddir = os.path.join(curdir,'results'),os.path.join(curdir,'expected')
    molet.mkdir(resultsdir,ignoreWarning = True)
    molet.mkdir(expecteddir,ignoreWarning = True)
    tup = (curdir,sqldir,resultsdir,expecteddir)
    return tup 

'''---------------------------------------------------------------------------
---------------------------------------------------------------------------'''
class PrTest(object):
    ''' results printing '''
    def __init__(self,parlen,sep):
        self.parlen = parlen+ parlen%2
        self.sep = sep

    def title(self,title):
        _l = len(title)
        _p = max(_l%2 +_l,40)
        _x = self.parlen -_p
        if (_x > 2):
            print (_x/2)*self.sep + string.center(title,_p) + (_x/2)*self.sep
        else:
            print string.center(text,self.parlen)

    def line(self):
        print self.parlen*self.sep

    def center(self,text):
        print string.center(text,self.parlen)

    def progress(self,progress):
        # update_progress() : Displays or updates a console progress bar
        ## Accepts a float between 0 and 1. Any int will be converted to a float.
        ## A value under 0 represents a 'halt'.
        ## A value at 1 or bigger represents 100%
        barLength = 40 # Modify this to change the length of the progress bar
        status = ""
        if isinstance(progress, int):
            progress = float(progress)
        if not isinstance(progress, float):
            progress = 0
            status = "error: progress var must be float\r\n"
        if progress < 0:
            progress = 0
            status = "Halt...\r\n"
        if progress >= 1:
            progress = 1
            status = "Done...\r\n"
        block = int(round(barLength*progress))
        text = "\r\t\t\t[{0}] {1}% {2}".format( "#"*block + "-"*(barLength-block), progress*100, status)
        sys.stdout.write(text)
        sys.stdout.flush()

'''---------------------------------------------------------------------------
    file comparison
---------------------------------------------------------------------------'''
import filecmp
def files_clones(f1,f2):
    #res = filecmp.cmp(f1,f2)
    return (md5sum(f1) == md5sum(f2))

import hashlib
def md5sum(filename, blocksize=65536):
    hash = hashlib.md5()
    with open(filename, "r+b") as f:
        for block in iter(lambda: f.read(blocksize), ""):
            hash.update(block)
    return hash.hexdigest()

'''---------------------------------------------------------------------------
---------------------------------------------------------------------------'''
SEPARATOR = '\n'+'-'*80 +'\n'
import json

class Dumper(object):

    def __init__(self,conf,options,fdr):
        self.options =options
        self.conf = conf
        self.fdr = fdr

    def getConf(self):
        return self.conf

    def torder(self,cur):
        self.write(SEPARATOR)
        self.write('table: torder\n')
        cur.execute('SELECT * FROM market.vord order by id asc')
        self.cur(cur)
        '''
        yorder not shown:
            pos_requ box, -- box (point(lat,lon),point(lat,lon))
            pos_prov box, -- box (point(lat,lon),point(lat,lon))
            dist    float8,
            carre_prov box -- carre_prov @> pos_requ 
        '''
        return

    def write(self,txt):
        if self.fdr:
            self.fdr.write(txt)

    def cur(self,cur,_len=10):
        #print cur.description
        if(cur.description is None): return
        #print type(cur)
        cols = [e.name for e in cur.description]
        row_format = ('{:>'+str(_len)+'}')*len(cols)
        self.write(row_format.format(*cols)+'\n')
        self.write(row_format.format(*(['+'+'-'*(_len-1)]*len(cols)))+'\n')
        for res in cur:
            self.write(row_format.format(*res)+'\n')
        return

    def tmsg(self,cur):
        self.write(SEPARATOR)
        self.write('table: tmsg')
        self.write(SEPARATOR)
        
        cur.execute('SELECT id,typ,usr,jso FROM market.tmsg  order by id asc')
        for res in cur:
            _id,typ,usr,jso = res
            _jso = json.loads(jso)
            if typ == 'response':
                if _jso['error']['code']==0:
                    _msg = 'Primitive id:%i from %s: OK\n' % (_jso['id'],usr)
                else:
                    _msg = 'Primitive id:%i from %s: ERROR(%i,%s)\n' % (_jso['id'],usr,
                            _jso['error']['code'],_jso['error']['reason'])
            elif typ == 'exchange':

                _fmt = '''Cycle id:%i Exchange id:%i for %s @%s:
            \t%i:mvt_from %s @%s : %i \'%s\' -> %s @%s
            \t%i:mvt_to   %s @%s : %i \'%s\' <- %s @%s 
            \tstock id:%i remaining after exchange: %i \'%s\' \n''' 
                _dat = (
                    _jso['cycle'],_jso['id'],_jso['stock']['own'],usr,
                    _jso['mvt_from']['id'],_jso['stock']['own'],usr,_jso['mvt_from']['qtt'],_jso['mvt_from']['nat'],_jso['mvt_from']['own'],_jso['mvt_from']['usr'],
                    _jso['mvt_to']['id'], _jso['stock']['own'],usr,_jso['mvt_to']['qtt'],_jso['mvt_to']['nat'],_jso['mvt_to']['own'],_jso['mvt_to']['usr'],
                    _jso['stock']['id'],_jso['stock']['qtt'],_jso['stock']['nat'])
                _msg = _fmt %_dat
            else:
                _msg = str(res)

            self.write('\t%i:'%_id+_msg+'\n') 
            if self.options.verbose:
                print jso
        return

'''---------------------------------------------------------------------------
wait until a command returns true with timeout
---------------------------------------------------------------------------'''
import molet
import time
def wait_for_true(conf,delai,sql,msg=None):
    _i = 0;
    _w = 0;

    while True:
        _i +=1

        conn = molet.DbData(conf)
        try:
            with molet.DbCursor(conn) as cur:
                cur.execute(sql)
                r = cur.fetchone()
                if r[0] == True:
                    break
        finally:
            conn.close()

        if msg is None:
            pass
        elif(_i%10)==0:
            print msg

        _a = 0.1;
        _w += _a;

        if _w > delai: # seconds
            raise ValueError('After %f seconds, %s != True' % (_w,sql))
        time.sleep(_a)
'''---------------------------------------------------------------------------
wait for stack empty
---------------------------------------------------------------------------'''
def wait_for_empty_stack(conf,prtest):
    _i = 0;
    _w = 0;
    sql = "SELECT name,value FROM market.tvar WHERE name in ('STACK_TOP','STACK_EXECUTED')"
    while True:
        _i +=1
        conn = molet.DbData(conf)
        try:
            with molet.DbCursor(conn) as cur:
                cur.execute(sql)
                re = {}
                for r in cur:
                    re[r[0]] = r[1]

                prtest.progress(float(re['STACK_EXECUTED'])/float(re['STACK_TOP']))

                if re['STACK_TOP'] == re['STACK_EXECUTED']:
                    break
        finally:
            conn.close()
        time.sleep(2)

'''---------------------------------------------------------------------------
executes a script 
---------------------------------------------------------------------------'''
def exec_script(dump,dirsql,fn):

    fn = os.path.join(dirsql,fn)
    if( not os.path.exists(fn)):
        raise ValueError('The script %s is not found' % fn)

    cur_login = None
    titre_test = None

    inst = ExecInst(dump)

    with open(fn,'r') as f:        
        for line in f:
            line = line.strip()
            if len(line) == 0:
                continue

            dump.write(line+'\n')

            if line.startswith('--'):
                if titre_test is None:
                    titre_test = line
                elif line.startswith('--USER:'):
                    cur_login = line[7:].strip()
                
            else:
                cursor = inst.exe(line,cur_login)
                dump.cur(cursor)

    inst.close()
    return titre_test

'''---------------------------------------------------------------------------
---------------------------------------------------------------------------'''
class ExecInst(object):

    def __init__(self,dump):
        self.login = None
        self.conn = None
        self.cur = None
        self.dump = dump

    def exe(self,sql,login):
        #print login
        if self.login != login:
            self.close()

        if self.conn is None:
            self.login = login
            _login = None if login == 'admin' else login
            self.conn = molet.DbData(self.dump.getConf(),login = _login)
            self.cur = self.conn.con.cursor()

        # print sql
        self.cur.execute(sql)

        return self.cur 

    def close(self):     
        if not(self.conn is None):
            if not(self.cur is None):
                self.cur.close()
            self.conn.close()
            self.conn = None


def execinst(dump,cur_login,sql):

    if cur_login == 'admin':
        cur_login = None
    conn = molet.DbData(dump.getConf(),login = cur_login)
    try:
        with molet.DbCursor(conn,exit = True) as _cur:
            _cur.execute(sql)
            dump.cur(_cur)
    finally:
        conn.close()


'''---------------------------------------------------------------------------
---------------------------------------------------------------------------'''   
from datetime import datetime

class Delai(object):
    def __init__(self):
        self.debut = datetime.now()

    def getSecs(self):
        return self._duree(self.debut,datetime.now())

    def _duree(self,begin,end):
        """ returns a float; the number of seconds elapsed between begin and end 
        """
        if(not isinstance(begin,datetime)): raise ValueError('begin is not datetime object')
        if(not isinstance(end,datetime)): raise ValueError('end is not datetime object')
        duration = end - begin
        secs = duration.days*3600*24 + duration.seconds + duration.microseconds/1000000.
        return secs
    
