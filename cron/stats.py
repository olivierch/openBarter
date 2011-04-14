#!/usr/bin/python
#-*- coding: utf8 -*-

import settings
from contextlib import closing
import db
import os
	
def exitError(log,msg,ret_code=-1):
	log.error("\t%s with the following stack:" % msg,exc_info=True)
	log.error("# END ################################################")
	os._exit(ret_code)
	
def statMarket(conn):
	sql = 'SELECT * from ob_fstats()'
	res = None
	with closing(conn.cursor()) as cursor:
		cursor.execute(sql)
		res = [d for d in db.getDictsFromCursor(cursor)]
		res = res[0]
		errs = {}
		for k,v in res.iteritems():
			if k in ('unbalanced_qualities','corrupted_draft','corrupted_stock_s','corrupted_stock_a'):
					if v!=0:
						errs[k] = v
	return res,errs

def statVolume(conn):
	res = {};errs = {}
	with closing(conn.cursor()) as cursor:
		cursor.execute('select count(*) from ob_tmvt where own_src!=1 and own_dst!=1')
		res["mvts between owners"] = cursor.fetchone()[0]
		cursor.execute('select count(*) from ob_tmvt where own_src!=1 and own_dst!=1')
		res["mvts between owners"] = cursor.fetchone()[0]		
		cursor.execute('select count(*) from ob_tomega')
		res["ob_tomega"] = cursor.fetchone()[0]
		cursor.execute('select count(*) from (select nr,nf from ob_tomega group ny nr,nf) as t')
		res["(nr,nf) in ob_tomega"] = cursor.fetchone()[0]
		cursor.execute('select count(*) from ob_tnoeud n1,ob_tnoeud n2 where n1.nf=n2.nr')
		res["connected bids"] = cursor.fetchone()[0]
		cursor.execute('select count(*) from ob_tcommit')
		res1 = cursor.fetchone()[0]
		res["count(ob_tcommit)"] = res1
		cursor.execute('select sum(nbnoeud) from ob_tdraft')
		res2 = cursor.fetchone()[0]
		res["sum(ob_tdraft.nbnoeud)"] = res2
		if(res1 != res2):
			errs['draft and commit disagree'] = res2-res1
		
	return res,errs
		
def statBdb():
	""" stats of berkeleydb """
	os.execv('/usr/bin/db_stat',['db_stat','-h',settings.BDB_HOME])
	return 
	
def printResErr(res,errs):
	for k,v in res:
		print "%s\t%s" % (k,str(v))
	err =False
	for k,v in res:
		if(not err):
			print "#############"
			print "Errors found:"
			print "#############"
			err = True
		print "%s\t%s" % (k,str(v))
	
if __name__ == "__main__":
	
	statBdb()
	with db.Connection(log) as conn:
		res,errs = statMarket(conn)
		printResErr(res,errs)
		res,errs = statVolume(conn)
		printResErr(res,errs)		


