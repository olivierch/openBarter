# -*- coding: utf-8 -*-
import string

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

############################################################################
''' file comparison '''
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

############################################################################
SEPARATOR = '\n'+'-'*80 +'\n'
import json

class Dumper(object):

    def __init__(self,conf,options):
        self.options =options
        self.conf = conf

    def torder(self,cur,fdr):
        fdr.write(SEPARATOR)
        fdr.write('table: torder\n')
        cur.execute('SELECT * FROM market.vord order by id asc')
        self.cur(cur,fdr)
        return

    def cur(self,cur,fdr,_len=10):
        if(cur is None): return
        cols = [e.name for e in cur.description]
        row_format = ('{:>'+str(_len)+'}')*len(cols)
        fdr.write(row_format.format(*cols)+'\n')
        fdr.write(row_format.format(*(['+'+'-'*(_len-1)]*len(cols)))+'\n')
        for res in cur:
            fdr.write(row_format.format(*res)+'\n')
        return

    def tmsg(self,cur,fdr):
        fdr.write(SEPARATOR)
        fdr.write('table: tmsg')
        fdr.write(SEPARATOR)
        
        cur.execute('SELECT id,typ,usr,jso FROM market.tmsg  order by id asc')
        for res in cur:
            _id,typ,usr,jso = res
            _jso = json.loads(jso)
            if typ == 'response':
                if _jso['error']['code']==None:
                    _msg = 'Primitive id:%i from %s: OK\n' % (_jso['id'],usr)
                else:
                    _msg = 'Primitive id:%i from %s: ERROR(%i,%s)\n' % (usr,_jso['id'],
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

            fdr.write('\t%i:'%_id+_msg+'\n') 
            if self.options.verbose:
                print jso
        return

############################################################################
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
                # print r
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