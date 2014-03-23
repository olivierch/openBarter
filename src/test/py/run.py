# -*- coding: utf-8 -*-
'''
Framework de tests tu_*
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
    sql/t_*.sql
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
import utilt

PARLEN=80
prtest = utilt.PrTest(PARLEN,'=')

titre_test = "UNDEFINED"
options = None

def tests():
    global titre_test    
    
    curdir = os.path.abspath(__file__)
    curdir = os.path.dirname(curdir)
    curdir = os.path.dirname(curdir)
    sqldir = os.path.join(curdir,'sql')
    molet.mkdir(os.path.join(curdir,'results'),ignoreWarning = True)
    molet.mkdir(os.path.join(curdir,'expected'),ignoreWarning = True)
    try:
        utilt.wait_for_true(srvob_conf.dbBO,0.1,"SELECT value=102,value FROM market.tvar WHERE name='OC_CURRENT_PHASE'",
            msg="Waiting for market opening")
    except psycopg2.OperationalError,e:
        print "Please adjust DB_NAME,DB_USER,DB_PWD,DB_PORT parameters of the file src/test/py/srv_conf.py"
        print "The test program could not connect to the market"
        exit(1)

    if options.test is None:
        _fts = [f for f in os.listdir(sqldir) if f.startswith('tu_') and f[-4:]=='.sql']
        _fts.sort(lambda x,y: cmp(x,y))
    else:
        _nt = options.test + '.sql'
        _fts = os.path.join(sqldir,_nt)
        if not os.path.exists(_fts):
            print 'This test \'%s\' was not found' % _fts
            return
        else:
            _fts = [_nt]

    _tok,_terr,_num_test = 0,0,0

    prtest.title('running tests on database "%s"' % (srvob_conf.DB_NAME,))
    #print '='*PARLEN
    
    
    print ''
    print 'Num\tStatus\tName'
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

            utilt.wait_for_true(srvob_conf.dbBO,20,"SELECT market.fstackdone()")

            dump = utilt.Dumper(srvob_conf.dbBO,options)

            conn = molet.DbData(srvob_conf.dbBO)
            try:
                with molet.DbCursor(conn) as cur:
                    dump.torder(cur,f)
                    dump.tmsg(cur,f)

            finally:
                conn.close()

        if(os.path.exists(_fre)):
            if(utilt.files_clones(_fte,_fre)):
                _tok +=1
                _terr -=1
                print '%i\tY\t%s\t%s' % (_num_test,_nom_test,titre_test)
            else:
                print '%i\tN\t%s\t%s' % (_num_test,_nom_test,titre_test)
        else:
            print '%i\t?\t%s\t%s' % (_num_test,_nom_test,titre_test)

    # display global results
    print ''
    print 'Test status: (Y)expected ==results, (N)expected!=results,(F)failed, (?)expected undefined'
    prtest.line()

    if(_terr == 0):
        prtest.center('\tAll %i tests passed' % _tok)
    else:
        prtest.center('\t%i tests KO, %i passed' % (_terr,_tok))
    prtest.line() 

def get_prefix_file(fm):
    return '.'.join(fm.split('.')[:-1])

SEPARATOR = '\n'+'-'*PARLEN +'\n' 

def exec_script(cur,fn,fdr):
    global titre_test

    fn = os.path.join('sql',fn)
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
    global options

    if cur_login == 'admin':
        cur_login = None
    conn = molet.DbData(srvob_conf.dbBO,login = cur_login)
    dump = utilt.Dumper(srvob_conf.dbBO,options)
    try:
        with molet.DbCursor(conn,exit = True) as _cur:
            _cur.execute(sql)
            if fdr:
                dump.cur(_cur,fdr)
    finally:
        conn.close()
'''
yorder not shown:
    pos_requ box, -- box (point(lat,lon),point(lat,lon))
    pos_prov box, -- box (point(lat,lon),point(lat,lon))
    dist    float8,
    carre_prov box -- carre_prov @> pos_requ 
'''


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
    
