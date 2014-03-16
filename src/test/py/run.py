# -*- coding: utf-8 -*-
'''
Framework de tests 
***************************************************************************

execution:
reset_market.sql
soumis:
    list de primitives t_*.sql
résultats:
    état de l'order book
    état de tmsg
comparaison attendu/obtenu

dans src/test/
run.py
reset_market.sql
t_*.sql
expected/t_*.res
obtained/t_*.res

boucle pour chaque t_*.sql:
    reset_market.sql
    exécuter t_*.sql
    dumper les résultats dans obtained/t_.res
    comparer expected et obtained
'''
import sys,os,time,logging
import psycopg2
import psycopg2.extensions
import traceback

import srvob_conf
import molet

PARLEN=80

titre_test = "UNDEFINED"
options = None

def tests():
    global titre_test    
    
    curdir = os.path.abspath(__file__)
    curdir = os.path.dirname(curdir)
    curdir = os.path.dirname(curdir)
    molet.mkdir(os.path.join(curdir,'results'),ignoreWarning = True)
    molet.mkdir(os.path.join(curdir,'expected'),ignoreWarning = True)

    wait_for_true(0.1,"SELECT value=102,value FROM market.tvar WHERE name='OC_CURRENT_PHASE'",
        msg="Waiting for market opening")

    if options.test is None:
        _fts = [f for f in os.listdir(curdir) if f.startswith('tu_') and f[-4:]=='.sql']
        _fts.sort(lambda x,y: cmp(x,y))
    else:
        _nt = options.test + '.sql'
        _fts = os.path.join(curdir,_nt)
        if not os.path.exists(_fts):
            print 'This test \'%s\' was not found' % _fts
            return
        else:
            _fts = [_nt]

    _tok,_terr,_num_test = 0,0,0
    print '-'*PARLEN
    
    print '\tstatus: failed (F) expected undefined(?) exp==res (Y) exp!=res (N)'
    print 'Num\t\tName'
    print ''
    for file_test in _fts: # itération on test cases
        _nom_test = file_test[:-4]
        _terr +=1
        _num_test +=1
        
        file_result = file_test[:-4]+'.res'
        _fte = os.path.join(curdir,'results',file_result)
        _fre = os.path.join(curdir,'expected',file_result)
        
        with open(_fte,'w') as f:        
            cur = None

            exec_script(cur,'reset_market.sql',None)
            exec_script(cur,file_test,f)

            wait_for_true(20,"SELECT market.fstackdone()")

            conn = molet.DbData(srvob_conf.dbBO)
            try:
                with molet.DbCursor(conn) as cur:
                    dump_torder(cur,f)
                    dump_tmsg(cur,f)

            finally:
                conn.close()

        if(os.path.exists(_fre)):
            if(files_clones(_fte,_fre)):
                _tok +=1
                _terr -=1
                print '%i\tY:\t%s\t%s' % (_num_test,_nom_test,titre_test)
            else:
                print '%i\tN:\t%s\t%s' % (_num_test,_nom_test,titre_test)
        else:
            print '%i\t?:\t%s\t%s' % (_num_test,_nom_test,titre_test)

    # display global results
    print '-'*PARLEN
    if(_terr == 0):
        print '\tAll %i tests passed' % _tok
    else:
        print '\t%i tests KO, %i passed' % (_terr,_tok)
    print '-'*PARLEN

def get_prefix_file(fm):
    return '.'.join(fm.split('.')[:-1])

SEPARATOR = '\n'+'-'*PARLEN +'\n' 

def exec_script(cur,fn,fdr):
    global titre_test
   
    if( not os.path.exists(fn)):
        raise ValueError('The script %s is not found' % fn)

    cur_login = 'admin'
    titre_test = None

    with open(fn,'r') as f:        
        for line in f:
            line = line.strip()
            if len(line) == 0:
                continue

            if line.startswith('--'):
                if titre_test is None:
                    titre_test = line
                elif line.startswith('--USER:'):
                    cur_login = line[7:].strip()
                if fdr:
                    fdr.write(line+'\n')
            else:

                if fdr:
                    fdr.write(line+'\n')
                execinst(cur_login,line,fdr,cur)
    return 

def execinst(cur_login,sql,fdr,cursor):
    if cur_login == 'admin':
        cur_login = None
    conn = molet.DbData(srvob_conf.dbBO,login = cur_login)
    try:
        with molet.DbCursor(conn,exit = True) as _cur:
            _cur.execute(sql)
            if fdr:
                dump_cur(_cur,fdr)
    finally:
        conn.close()
'''
yorder not shown:
    pos_requ box, -- box (point(lat,lon),point(lat,lon))
    pos_prov box, -- box (point(lat,lon),point(lat,lon))
    dist    float8,
    carre_prov box -- carre_prov @> pos_requ 
'''

def dump_torder(cur,fdr):
    fdr.write(SEPARATOR)
    fdr.write('table: torder\n')
    cur.execute('SELECT * FROM market.vord order by id asc')
    dump_cur(cur,fdr)

def dump_cur(cur,fdr,_len=10):
    if(cur is None): return
    cols = [e.name for e in cur.description]
    row_format = ('{:>'+str(_len)+'}')*len(cols)
    fdr.write(row_format.format(*cols)+'\n')
    fdr.write(row_format.format(*(['+'+'-'*(_len-1)]*len(cols)))+'\n')
    for res in cur:
        fdr.write(row_format.format(*res)+'\n')
    return

import json

def dump_tmsg(cur,fdr):
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
        if options.verbose:
            print jso
    return

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

def wait_for_true(delai,sql,msg=None):
    _i = 0;
    _w = 0;

    while True:
        _i +=1

        conn = molet.DbData(srvob_conf.dbBO)
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

'''---------------------------------------------------------------------------
arguments
---------------------------------------------------------------------------'''
from optparse import OptionParser
import os
           
def main():
    global options

    usage = """usage: %prog [options]
                tests  """ 
    parser = OptionParser(usage)
    parser.add_option("-t","--test",action="store",type="string",dest="test",help="test",
        default= None)
    parser.add_option("-v","--verbose",action="store_true",dest="verbose",help="verbose",default=False)

    (options, args) = parser.parse_args()

    # um = os.umask(0177) # u=rw,g=,o=

    tests()           


if __name__ == "__main__":
    main()
    
