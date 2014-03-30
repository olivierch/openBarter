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
import simplejson
import sys

MAX_ORDER = 100
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
    def gen(nborders,frs):
        for i in range(nborders):
            w = random.randint(1,MAX_OWNER)
            qlt_prov,qlt_requ = distrib.couple(distrib.uniformQlt,MAX_QLT)
            r = random.random()+0.5
            qtt_requ = int(QTT_PROV * r)
            lb= 'limit' if (random.random()>0.9) else 'best'
            frs.writerow(['admin',lb,'w%i'%w,'q%i'%qlt_requ,qtt_requ,'q%i'%qlt_prov,QTT_PROV])

    with open(_frs,'w') as f:
        spamwriter = csv.writer(f)
        gen(MAX_ORDER,spamwriter)

    molet.removeFile(os.path.join(expecteddir,'test_ti.res'),ignoreWarning = True)
    prtest.center('done, test_ti.res removed')
    prtest.line()

def test_ti(options):

    _reset,titre_test = options.test_ti_reset,''

    curdir,sqldir,resultsdir,expecteddir = get_paths()
    prtest.title('running test_ti on database "%s"' % (srvob_conf.DB_NAME,))

    dump = utilt.Dumper(srvob_conf.dbBO,options,None)
    if _reset:
        print '\tReset: Clearing market ...'
        titre_test = utilt.exec_script(dump,sqldir,'reset_market.sql')
        print '\t\tDone'

    fn = os.path.join(sqldir,'test_ti.csv')
    if( not os.path.exists(fn)):
        raise ValueError('The data %s is not found' % fn)

    with open(fn,'r') as f:
        spamreader = csv.reader(f)
        values_prov = {}
        _nbtest = 0
        for row in spamreader:
            _nbtest +=1 
            qua_prov,qtt_prov = row[5],row[6]
            if not qua_prov in values_prov.keys():
                values_prov[qua_prov] = 0
            values_prov[qua_prov] = values_prov[qua_prov] + int(qtt_prov)

    #print values_prov

    cur_login = None
    titre_test = None

    inst = utilt.ExecInst(dump)

    
    user = None
    fmtorder = "SELECT * from market.fsubmitorder('%s','%s','%s',%s,'%s',%s)" 
    fmtquote = "SELECT * from market.fsubmitquote('%s','%s','%s',%s,'%s',%s)"

    fmtjsosr  = '''SELECT jso from market.tmsg 
        where json_extract_path_text(jso,'id')::int=%i and typ='response' '''

    fmtjsose  = """SELECT json_extract_path_text(jso,'orde','id')::int id,
        sum(json_extract_path_text(jso,'mvt_from','qtt')::bigint) qtt_prov,
        sum(json_extract_path_text(jso,'mvt_to','qtt')::bigint) qtt_requ
        from market.tmsg 
        where json_extract_path_text(jso,'orig')::int=%i
        and json_extract_path_text(jso,'orde','id')::int=%i
        and typ='exchange' group by json_extract_path_text(jso,'orde','id')::int """
    '''
    the order that produced the exchange has the qualities expected 
    '''
    i= 0
    if _reset:
        print '\tSubmission: sending a series of %i tests where a random set of arguments' % _nbtest
        print '\t\tis used to submit a quote, then an order'
        with open(fn,'r') as f:
            
            spamreader = csv.reader(f)
            
            compte = utilt.Delai()
            for row in spamreader:
                user = row[0]
                params = tuple(row[1:])
                

                cursor = inst.exe( fmtquote % params,user)
                cursor = inst.exe( fmtorder % params,user)
                i +=1
                if i % 100 == 0:
                    prtest.progress(i/float(_nbtest))

        delai = compte.getSecs()

        print '\t\t%i quote & order primitives in %f seconds' % (_nbtest*2,delai)
        print '\tExecution: Waiting for end of execution ...'
        #utilt.wait_for_true(srvob_conf.dbBO,1000,"SELECT market.fstackdone()",prtest=prtest)
        utilt.wait_for_empty_stack(srvob_conf.dbBO,prtest)
        delai = compte.getSecs()
        print '\t\t Done: mean time per primitive %f seconds' % (delai/(_nbtest*2),) 
        
    fmtiter = '''SELECT json_extract_path_text(jso,'id')::int id,json_extract_path_text(jso,'primitive','type') typ 
        from market.tmsg where typ='response' and json_extract_path_text(jso,'primitive','kind')='quote' 
        order by id asc limit 10 offset %i''' 
    i = 0
    _notnull,_ko,_limit,_limitko = 0,0,0,0
    print '\tChecking: identity of quote result and order result for each %i test cases' % _nbtest
    print '\t\tusing the content of market.tmsg'
    while True:   
        cursor = inst.exe( fmtiter % i,user)
       
        vec = []
        for re in cursor:
            vec.append(re)
            
        l = len(vec)

        if l == 0: 
            break

        for idq,_type in vec:
            i += 1
            if _type == 'limit':
                _limit += 1

            # result of the quote for idq
            _cur = inst.exe(fmtjsosr %idq,user)
            res = _cur.fetchone() 
            res_quote =simplejson.loads(res[0])
            expected = res_quote['result']['qtt_give'],res_quote['result']['qtt_reci']

            #result of the order for idq+1
            _cur = inst.exe(fmtjsose %(idq+1,idq+1),user) 
            res = _cur.fetchone()

            if res is None:
                result = 0,0
            else:
                ido_,qtt_prov_,qtt_reci_ = res
                result = qtt_prov_,qtt_reci_
                _notnull +=1
                if _type == 'limit':
                    if float(expected[0])/float(expected[1]) < float(qtt_prov_)/float(qtt_reci_):
                        _limitko +=1

            if result != expected:
                _ko += 1
                print idq,res,res_quote

            if i %100 == 0:
                prtest.progress(i/float(_nbtest))
                '''
                if i == 100:
                    print '\t\t.',
                else:
                    print '.',
                sys.stdout.flush()
                
                if(_ko != 0): _errs = ' - %i errors' %_ko
                else: _errs = ''
                print ('\t\t%i quote & order\t%i quotes returned a result %s' % (i-_ko,_notnull,_errs))
                '''
    _valuesko = check_values(inst,values_prov,user)
    prtest.title('Results checkings')

    print ''
    print '\t\t%i\torders returned a result different from the previous quote' % _ko
    print '\t\t\twith the same arguments\n'

    print '\t\t%i\tlimit orders returned a result where the limit is not observed\n' % _limitko
    print '\t\t%i\tqualities where the quantity is not preserved by the market\n' % _valuesko

    prtest.line()

    if(_ko == 0 and _limitko == 0 and _valuesko == 0):
        prtest.center('\tAll %i tests passed' % i)
    else:
        prtest.center('\tSome of %i tests failed' % (i,))
    prtest.line() 
    
    inst.close()
    return titre_test

def check_values(inst,values_input,user):
    '''
    Values_input is for each quality, the sum of quantities submitted to the market
    Values_remain is for each quality, the sum of quantities remaining in the order book
    Values_output is for each quality, the sum of quantities of mvt_from.qtt of tmsg
    Checks that for each quality q:
        Values_input[q] ==  Values_remain[q] + Values_output[q]
    '''
    sql = "select (ord).qua_prov,sum((ord).qtt) from market.torder where (ord).oid=(ord).id group by (ord).qua_prov"
    cursor = inst.exe( sql,user)
    values_remain = {}
    for qua_prov,qtt in cursor:
        values_remain[qua_prov] = qtt

    sql = '''select json_extract_path_text(jso,'mvt_from','nat'),sum(json_extract_path_text(jso,'mvt_from','qtt')::bigint)
    from market.tmsg where typ='exchange'
    group by json_extract_path_text(jso,'mvt_from','nat')
    '''
    cursor = inst.exe( sql,user)
    values_output = {}
    for qua_prov,qtt in cursor:
        values_output[qua_prov] = qtt
    
    _errs = 0
    for qua,vin in values_input.iteritems():
        vexpect = values_output.get(qua,0)+values_remain.get(qua,0)
        if vin != vexpect:
            print qua,vin,values_output.get(qua,0),values_remain.get(qua,0)
            _errs += 1
    # print '%i errors'% _errs
    return _errs

def test_ti_old(options):

    curdir,sqldir,resultsdir,expecteddir = get_paths()
    prtest.title('running test_ti on database "%s"' % (srvob_conf.DB_NAME,))

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
        fmtjsosr  = "SELECT jso from market.tmsg where json_extract_path_text(jso,'id')::int=%i and typ='response'"
        fmtjsose  = """SELECT json_extract_path_text(jso,'orde','id')::int id,
            sum(json_extract_path_text(jso,'mvt_from','qtt')::bigint) qtt_prov,
            sum(json_extract_path_text(jso,'mvt_to','qtt')::bigint) qtt_requ
            from market.tmsg 
            where json_extract_path_text(jso,'orde','id')::int=%i 
            and typ='exchange' group by json_extract_path_text(jso,'orde','id')::int """
        '''
        the order that produced the exchange has the qualities expected 
        '''
        _notnull,_ko = 0,0
        for row in spamreader:
            i += 1
            user = row[0]
            params = tuple(row[1:])

            cursor = inst.exe( fmtquote % params,user)
            idq,err = cursor.fetchone()
            if err != '(0,)':
                raise ValueError('Quote returned an error "%s"' % err)
            utilt.wait_for_true(srvob_conf.dbBO,20,"SELECT market.fstackdone()")
            cursor = inst.exe(fmtjsosr %idq,user)
            res = cursor.fetchone() # result of the quote
            res_quote =simplejson.loads(res[0])
            expected = res_quote['result']['qtt_give'],res_quote['result']['qtt_reci']
            #print res_quote
            #print ''

            cursor = inst.exe( fmtorder % params,user)
            ido,err = cursor.fetchone()
            if err != '(0,)':
                raise ValueError('Order returned an error "%s"' % err)
            utilt.wait_for_true(srvob_conf.dbBO,20,"SELECT market.fstackdone()")
            cursor = inst.exe(fmtjsose %ido,user)
            res = cursor.fetchone()

            if res is None:
                result = 0,0
            else:
                ido_,qtt_prov_,qtt_reci_ = res
                result = qtt_prov_,qtt_reci_
                _notnull +=1

            if result != expected:
                _ko += 1
                print qtt_prov_,qtt_reci_,res_quote

            if i %100 == 0:
                if(_ko != 0): _errs = ' - %i errors' %_ko
                else: _errs = ''
                print ('\t%i quote & order - %i quotes returned a result %s' % (i-_ko,_notnull,_errs))

    if(_ko == 0):
        prtest.title(' all %i tests passed' % i) 
    else:
        prtest.title('%i checked %i tests failed' % (i,_ko)) 


    inst.close()
    return titre_test



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
    parser.add_option("-b","--build",action="store_true",dest="build",help="generates random test cases for test_ti",default=False)
    parser.add_option("-i","--ti",action="store_true",dest="test_ti",help="execute test_ti",default=False)
    parser.add_option("-r","--reset",action="store_true",dest="test_ti_reset",help="clean before execution test_ti",default=False)
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
    
