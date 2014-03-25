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

import sys
sys.path = [os.path.abspath(os.path.join(os.path.abspath(__file__),"../../../../simu/liquid"))]+ sys.path
#print sys.path
import distrib

PARLEN=80
prtest = utilt.PrTest(PARLEN,'=')

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

def tests_tu(options):
    titre_test = "UNDEFINED"  
    
    curdir,sqldir,resultsdir,expecteddir = get_paths()

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

import random
import csv
MAX_ORDER = 1000
def build_ti(options):
    ''' build a .sql file with a bump of submit
    '''
    #conf = srvob_conf.dbBO
    curdir,sqldir,resultsdir,expecteddir = get_paths()
    _frs = os.path.join(sqldir,'test_ti.csv')

    MAX_OWNER = 10
    MAX_QLT = 20
    QTT_PROV = 10000

    prtest.title('generating tests cases for quotes')
    def gen(nborders,frs,withquote):
        for i in range(nborders):
            w = random.randint(1,MAX_OWNER)
            qlt_prov,qlt_requ = distrib.couple(distrib.uniformQlt,MAX_QLT)
            r = random.random()+0.5
            qtt_requ = int(QTT_PROV * r)
            lb= 'limit' if (random.random()>0.2) else 'best'
            frs.writerow(['admin',lb,'w%i'%w,'q%i'%qlt_requ,qtt_requ,'q%i'%qlt_prov,QTT_PROV])

    with open(_frs,'w') as f:
        spamwriter = csv.writer(f)
        gen(MAX_ORDER,spamwriter,False)
        gen(30,spamwriter,True)

    molet.removeFile(os.path.join(expecteddir,'test_ti.res'),ignoreWarning = True)
    prtest.center('done, test_ti.res removed')
    prtest.line()

def test_ti(options):

    curdir,sqldir,resultsdir,expecteddir = get_paths()
    prtest.title('running tests on database "%s"' % (srvob_conf.DB_NAME,))

    dump = utilt.Dumper(srvob_conf.dbBO,options,None)
    titre_test = utilt.exec_script(dump,sqldir,'reset_market.sql')

    fn = os.path.join(sqldir,'test_ti.csv')
    if( not os.path.exists(fn)):
        raise ValueError('The data %s is not found' % fn)

    cur_login = None
    titre_test = None

    inst = utilt.ExecInst(dump)
    quote = False

    with open(fn,'r') as f:
        spamreader = csv.reader(f)
        i= 0
        usr = None
        fmtorder = "SELECT * from market.fsubmitorder('%s','%s','%s',%s,'%s',%s)" 
        fmtquote = "SELECT * from market.fsubmitquote('%s','%s','%s',%s,'%s',%s)"
        for row in spamreader:
            i += 1
            
            if i < 20: #i < MAX_ORDER:
                cursor = inst.exe( fmtorder % tuple(row[1:]),row[0])
            else:
                cursor = inst.exe( fmtquote % tuple(row[1:]),row[0])
                id,err = cursor.fetchone()
                if err != '(0,)':
                    raise ValueError('Order returned an error "%s"' % err)
                utilt.wait_for_true(srvob_conf.dbBO,20,"SELECT market.fstackdone()")
                print id
                cursor = inst.exe('SELECT * from market.tmsg')
                print cursor.fetchone()

            if i >30:
                break


    inst.close()
    return titre_test

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
    parser.add_option("-b","--build",action="store_true",dest="build",help="build",default=False)
    parser.add_option("-i","--ti",action="store_true",dest="test_ti",help="execute test_ti",default=False)
    (options, args) = parser.parse_args()

    # um = os.umask(0177) # u=rw,g=,o=
    if options.build:
        build_ti(options)
    elif options.test_ti:
        test_ti(options)
    else:
        tests_tu(options)           


if __name__ == "__main__":
    main()
    
