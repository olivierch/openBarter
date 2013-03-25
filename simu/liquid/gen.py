#!/usr/bin/python
# -*- coding: utf8 -*-
import cliquid
import os
import cliquid_basic as conf
import random
import distrib
"""
pour modifier la conf, modifier l'import


"""

def generate():

    # towner
    fn = os.path.join(cliquid.PATH_DATA,'towner.sql')
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
            qlt_prov,qlt_requ = conf.coupleQlt(conf.distribQlt)
            qtt_requ = random.randint(1000,1000*cliquid.QTT_PROV)
            line = "%s\t(1,%i,%i,%i,%i,qlt%i,%i,qlt%i,%i)\t2013-02-10 16:24:01.651649\t\N\n" 
            f.write(line % (cliquid.DB_USER,j,w,j,qtt_requ,qlt_requ,cliquid.QTT_PROV,qlt_prov,cliquid.QTT_PROV))   

    # tstack
    fn = os.path.join(cliquid.PATH_DATA,'tstack_'+conf.CONF_NAME+'.sql')
    with open(fn,'w') as f:
        for i in range(cliquid.MAX_TSTACK):    
            j = i+1+cliquid.MAX_TORDER
            w = random.randint(1,conf.MAX_OWNER)
            qlt_prov,qlt_requ = conf.coupleQlt(conf.distribQlt)
            qtt_requ = random.randint(1000,1000*cliquid.QTT_PROV)
            line = "%i\t%s\town%i\t\N\t1\tqlt%i\t%i\tqlt%i\t%i\t%i\t100 year\t2013-03-24 22:50:08.300833\n" 
            f.write(line % (j,cliquid.DB_USER,w,qlt_requ,qtt_requ,qlt_prov,cliquid.QTT_PROV,cliquid.QTT_PROV))            
        
def test(size):
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
		
		    cur.execute("UPDATE tconst SET value=%s WHERE name=%s",[conf.MAXCYCLE,"MAXCYCLE"])
		    cur.execute("UPDATE tconst SET value=%s WHERE name=%s",[conf.MAXPATHFETCHED,"MAXPATHFETCHED"])
		    cur.execute("UPDATE tconst SET value=%s WHERE name=%s",[conf.MAXMVTPERTRANS,"MAXMVTPERTRANS"])
		    
		    cur.execute("truncate towner",[])
		    fn = os.path.join(cliquid.PATH_DATA,'towner.sql')
		    cur.execute("copy towner from %s",[fn])
		    
		    cur.execute("truncate torder",[])
		    cur.execute("copy torder(usr,ord,created,updated) from %s",[gn])
		    # cur.execute("SELECT setval('torder_id_seq',%s,false)",[_size+1])
		    
		    cur.execute("truncate tstack",[])
		    fn = os.path.join(cliquid.PATH_DATA,'tstack_'+conf.CONF_NAME+'.sql')
		    cur.execute("copy tstack from %s",[fn])
		    cur.execute("SELECT setval('tstack_id_seq',%s,false)",[_size+cliquid.MAX_TSTACK+1])
		    
		    cur.execute("truncate tmvt",[])
		    cur.execute("SELECT setval('tmvt_id_seq',1,false)",[])
		    
		    begin = util.now()
		    cur.execute("SELECT * from femptystack()",[])
		    duree = util.getDelai(begin)
		    duree = duree/cliquid.MAX_TSTACK
		    
		    cur.execute("SELECT sum(qtt) FROM tmvt",[])
		    vec = cur.next()
		    if(vec[0] is None): 
		        vol = 0
		    else:
		        vol = vec[0]
		    liqu = float(vol)/float(cliquid.MAX_TSTACK * cliquid.QTT_PROV)
		    print duree,liqu
            
    return  duree,liqu
    
def perftests():
    fn = os.path.join(cliquid.PATH_DATA,'result_'+conf.CONF_NAME+'.txt')
    with open(fn,'w') as f:
        for i in range(conf.LIQ_ITER):
            duree,liqu = test((i+1) * conf.LIQ_PAS)
            f.write("%f;%f;" % (duree,liqu))
            
