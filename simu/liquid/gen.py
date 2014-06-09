#!/usr/bin/python
# -*- coding: utf8 -*-
import cliquid
import os
#import cliquid_basic as conf
import random
import distrib
import molet
"""
pour modifier la conf, modifier l'import


"""

def generate(config):
    ''' dépend de cliquid et conf
    produit trois fichiers
    '''
    conf = config()
    # towner
    molet.mkdir(cliquid.PATH_DATA,ignoreWarning=True)
    fn = os.path.join(cliquid.PATH_DATA,'towner.sql')
    if(not os.path.exists(fn)):
        with open(fn,'w') as f:
            for i in range(cliquid.MAX_TOWNER):
                j = i+1
                f.write('%i\town%i\t2013-02-10 16:24:01.651649\t\N\n' % (j,j))
      
    # torder     
    fn = os.path.join(cliquid.PATH_DATA,'torder_'+conf.CONF_NAME+'.sql')
    with open(fn,'w') as f:
        for i in range(cliquid.MAX_TORDER):
            j = i+1
            w = random.randint(1,conf.MAX_OWNER)
            qlt_prov,qlt_requ = conf.coupleQlt(conf.distribQlt,conf.MAX_QLT)
            r = random.random()+0.5
            qtt_requ = int(cliquid.QTT_PROV * r) # proba(QTT_PROV/qtt_requ < 1) = 0.5
            #line = "%s\t(1,%i,%i,%i,%i,qlt%i,%i,qlt%i,%i)\t2013-02-10 16:24:01.651649\t\N\n"    
            line = "%s\t(2,%i,%i,%i,%i,qlt%i,%i,qlt%i,%i,\"(0,0),(0,0)\",\"(0,0),(0,0)\",0,\"(1.5707963267949,3.14159265358979),(-1.5707963267949,-3.14159265358979)\")\t2014-04-29 19:40:44.382527\t2014-04-29 19:40:44.448502\n"
            f.write(line % (cliquid.DB_USER,j,w,j,qtt_requ,qlt_requ,cliquid.QTT_PROV,qlt_prov,cliquid.QTT_PROV))
    # tstack
    fn = os.path.join(cliquid.PATH_DATA,'tstack_'+conf.CONF_NAME+'.sql')
    with open(fn,'w') as f:
        for i in range(cliquid.MAX_TSTACK):    
            j = i+1+cliquid.MAX_TORDER
            w = random.randint(1,conf.MAX_OWNER)
            qlt_prov,qlt_requ = conf.coupleQlt(conf.distribQlt,conf.MAX_QLT)
            r = random.random()+0.5
            qtt_requ = int(cliquid.QTT_PROV * r) # proba(QTT_PROV/qtt_requ < 1) = 0.5
            line = "%i\t%s\town%i\t\N\t1\tqlt%i\t%i\tqlt%i\t%i\t%i\t100 year\t2013-03-24 22:50:08.300833\n" 
            f.write(line % (j,cliquid.DB_USER,w,qlt_requ,qtt_requ,qlt_prov,cliquid.QTT_PROV,cliquid.QTT_PROV)) 
            
    print "conf \'%s\' generated" % (conf.CONF_NAME,)           
        
def test(cexec,conf,size):
    """
    truncate towner;
    copy towner from '/home/olivier/ob92/simu/liquid/data/towner.sql';
    truncate torder;
    copy torder(usr,ord,created,updated) from '/home/olivier/ob92/simu/liquid/data/torder_basic.sql';
    SELECT setval('torder_id_seq',1,false);
    truncate tstack;
    copy tstack from '/home/olivier/ob92/simu/liquid/data/tstack_basic.sql';
    SELECT setval('tstack_id_seq',10000,true);
    truncate tmvt;
    SELECT setval('tmvt_id_seq',1,false);
    """ 
    import util

    _size = min(size,cliquid.MAX_TORDER)
    fn = os.path.join(cliquid.PATH_DATA,'torder_'+conf.CONF_NAME+'.sql')
    gn = os.path.join(cliquid.PATH_DATA,'_tmp.sql')
    with open(fn,'r') as f:
        with open(gn,'w') as g:
            for i in range(_size):
                g.write(f.readline())
        
    with util.DbConn(cliquid) as dbcon:
		with util.DbCursor(dbcon) as cur:
		
		    cur.execute("UPDATE tconst SET value=%s WHERE name=%s",[cexec.MAXCYCLE,"MAXCYCLE"])
		    cur.execute("UPDATE tconst SET value=%s WHERE name=%s",[cexec.MAXPATHFETCHED,"MAXPATHFETCHED"])
		    cur.execute("UPDATE tconst SET value=%s WHERE name=%s",[cexec.MAXMVTPERTRANS,"MAXMVTPERTRANS"])
		    
		    cur.execute("truncate towner",[])
		    fn = os.path.join(cliquid.PATH_DATA,'towner.sql')
		    cur.execute("copy towner from %s",[fn])
		    
		    cur.execute("truncate torder",[])
		    cur.execute("copy torder(usr,ord,created,updated) from %s",[gn])
		    
		    cur.execute("truncate tstack",[])
		    fn = os.path.join(cliquid.PATH_DATA,'tstack_'+conf.CONF_NAME+'.sql')
		    cur.execute("copy tstack from %s",[fn])
		    cur.execute("SELECT setval('tstack_id_seq',%s,false)",[cliquid.MAX_TORDER+cliquid.MAX_TSTACK+1])
		    
		    cur.execute("truncate tmvt",[])
		    cur.execute("SELECT setval('tmvt_id_seq',1,false)",[])
		    
		    begin = util.now()
		    _cnt = 1
		    while(_cnt>=1):
		        cur.execute("SELECT * from femptystack()",[])
		        vec = cur.next()
		        _cnt = vec[0]
		    duree = util.getDelai(begin)
		    
		    duree = duree/cliquid.MAX_TSTACK
		    
		    cur.execute("SELECT sum(qtt) FROM tmvt",[])
		    vec = cur.next()
		    if(vec[0] is None): 
		        vol = 0
		    else:
		        vol = vec[0]
		    liqu = float(vol)/float(cliquid.MAX_TSTACK * cliquid.QTT_PROV)
		    		    
		    cur.execute("SELECT avg(s.nbc) FROM (SELECT max(nbc) as nbc,grp FROM tmvt group by grp) s",[])
		    vec = cur.next()
		    if(vec[0] is None): 
		        nbcm = 0
		    else:
		        nbcm = vec[0]
		        
		    cur.execute("SELECT avg(om_exp/om_rea) FROM tmvt ",[])
		    vec = cur.next()
		    if(vec[0] is None): 
		        gain = 0
		    else:
		        gain = vec[0]
		        
		    #print duree,liqu,nbcm
    
    print "test \'%s_%s\' performed with size=%i" % (conf.CONF_NAME,cexec.NAME,_size)        
    return  duree,liqu,nbcm,gain
    
def perftests():
    import concat
    cexecs = [cliquid.Exec1(),cliquid.Exec2(),cliquid.Exec3(),cliquid.Exec4()]  
    confs= [cliquid.Basic1000()] #,cliquid.Basic1000()] #,cliquid.Money100(),cliquid.Basic1000large()]
    for conf in confs:
        fn = os.path.join(cliquid.PATH_DATA,'tstack_'+conf.CONF_NAME+'.sql')
        if(not os.path.exists(fn) or True):
            generate(conf)
        for cexec in cexecs:
            fn = os.path.join(cliquid.PATH_DATA,'result_'+conf.CONF_NAME+'_'+cexec.NAME+'.txt')
            
            with open(fn,'w') as f:
                for i in range(conf.LIQ_ITER):
                    size = (i+1) * conf.LIQ_PAS
                    duree,liqu,nbcm,gain = test(cexec,conf,size)
                    f.write("%i;%f;%f;%f;%f;\n" % (size,duree,liqu,nbcm,gain))
                    
    concat.makeVis('result_')
    
def perftests2():
    import concat
  
    #confs= [(cliquid.Exec3(),cliquid.Basic100()),(cliquid.Exec5(),cliquid.Money100())] # 
    confs= [(cliquid.Exec3(),cliquid.Basic100large())] # large order book
    
    for config in confs:
        cexec,conf = config
        fn = os.path.join(cliquid.PATH_DATA,'tstack_'+conf.CONF_NAME+'.sql')
        if(not os.path.exists(fn) or True):
            generate(conf)
            
        fn = os.path.join(cliquid.PATH_DATA,'result_'+conf.CONF_NAME+'_'+cexec.NAME+'.txt')
        
        with open(fn,'w') as f:
            for i in range(conf.LIQ_ITER):
                size = (i+1) * conf.LIQ_PAS
                duree,liqu,nbcm,gain = test(cexec,conf,size)
                f.write("%i;%f;%f;%f;%f;\n" % (size,duree,liqu,nbcm,gain))
                    
    concat.makeVis('result_')


            
