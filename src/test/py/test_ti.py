# -*- coding: utf-8 -*-
'''
Packages required
 apt-get install python-psycopg2
 sudo easy_install simplejson
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
   

import random
import csv
import simplejson
import sys

def build_ti(options):
    ''' build a .sql file with a bump of submit
    options.build is the number of tests to be generated
    '''
    #print options.build
    #return
    #conf = srvob_conf.dbBO
    curdir,sqldir,resultsdir,expecteddir = utilt.get_paths()
    _frs = os.path.join(sqldir,'test_ti.csv')

    MAX_OWNER = 10
    MAX_QLT = 20
    QTT_PROV = 10000

    prtest.title('generating tests cases for quotes')
    def gen(nborders,frs):
        for i in range(nborders):

            # choose an owner
            w = random.randint(1,MAX_OWNER)

            # choose a couple of qualities
            qlt_prov,qlt_requ = distrib.couple(distrib.uniformQlt,MAX_QLT)

            # choose an omega between 0.5 and 1.5
            r = random.random()+0.5
            qtt_requ = int(QTT_PROV * r)

            # 10% of orders are limit
            lb= 'limit' if (random.random()>0.9) else 'best'

            frs.writerow(['admin',lb,'w%i'%w,'q%i'%qlt_requ,qtt_requ,'q%i'%qlt_prov,QTT_PROV])

    with open(_frs,'w') as f:
        spamwriter = csv.writer(f)
        gen(options.build,spamwriter)

    if(molet.removeFile(os.path.join(expecteddir,'test_ti.res'),ignoreWarning = True)):
        prtest.center('test_ti.res removed')
        
    prtest.center('done')
    prtest.line()

def test_ti(options):

    _reset,titre_test = options.test_ti_reset,''

    curdir,sqldir,resultsdir,expecteddir = utilt.get_paths()
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
        _out = values_output.get(qua,None)
        _remain = values_remain.get(qua,None)
        if _out is None or _remain is None:
            _errs += 1
            continue

        if vin != (_out+ _remain):
            print qua,vin,_out,_remain
            _errs += 1

    return _errs
