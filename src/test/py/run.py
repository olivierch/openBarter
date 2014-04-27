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
    sql/reset_market.sql
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
import test_ti

import sys

PARLEN=80
prtest = utilt.PrTest(PARLEN,'=')

def tests_tu(options):
    titre_test = "UNDEFINED"  
    
    curdir,sqldir,resultsdir,expecteddir = utilt.get_paths()

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
        _fte = os.path.join(resultsdir,file_result)
        _fre = os.path.join(expecteddir,file_result)
        
        with open(_fte,'w') as f:        
            cur = None

            dump = utilt.Dumper(srvob_conf.dbBO,options,None)
            titre_test = utilt.exec_script(dump,sqldir,'reset_market.sql')
            dump = utilt.Dumper(srvob_conf.dbBO,options,f)
            titre_test = utilt.exec_script(dump,sqldir,file_test)

            utilt.wait_for_true(srvob_conf.dbBO,20,"SELECT market.fstackdone()")

            conn = molet.DbData(srvob_conf.dbBO)
            try:
                with molet.DbCursor(conn) as cur:
                    dump.torder(cur)
                    dump.tmsg(cur)

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

'''---------------------------------------------------------------------------
arguments
---------------------------------------------------------------------------'''
from optparse import OptionParser
import os
           
def main():
    #global options

    usage = """usage: %prog [options]
                tests  """ 
    parser = OptionParser(usage)
    parser.add_option("-t","--test",action="store",type="string",dest="test",help="test",
        default= None)
    parser.add_option("-v","--verbose",action="store_true",dest="verbose",help="verbose",default=False)
    parser.add_option("-b","--build",dest="build",type="int",help="generates random test cases for test_ti",default=0)
    parser.add_option("-i","--ti",action="store_true",dest="test_ti",help="execute test_ti",default=False)
    parser.add_option("-r","--reset",action="store_true",dest="test_ti_reset",help="clean before execution test_ti",default=False)

   
    (options, args) = parser.parse_args()

    # um = os.umask(0177) # u=rw,g=,o=
    if options.build:
        test_ti.build_ti(options)
    elif options.test_ti:
        test_ti.test_ti(options)
    else:
        tests_tu(options)           


if __name__ == "__main__":
    main()
    
