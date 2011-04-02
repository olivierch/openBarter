#!/usr/bin/python
#-*- coding: utf8 -*-

import daemon
import settings
import logger
from write_load_path import write_path
import json
import psycopg2
import psycopg2.extras
import sys

MAXNODES = 30
MAXLINKS = MAXNODES * MAXNODES

def automate():
	retCode = 0 #daemon.createDaemon()
	log = logger.getLogger(name="crPrices")
	with db.connection(log) as conn:
		try:
			matrixPrices_json(conn,log)
			# prices_json(conn,log)
		except Exception,e:
			log.error("Exception %s occured" % str(e))
		else:	
			log.info("done")

	return retCode
	
def matrixPrices_json(conn,log):
	""" builds datas of the graph matrix.
	This matrix has MAXLINKS dots """
	dir_name = settings.JSONDIR
	if(not path.isdir(dir_name)):
		raise Exception, "the path %s should exist" % dir_name

	sqlGraph = """
	select qr.id,qr.name,qr.own,qf.id,qf.name,qf.own,count(lo.*) 
		from ob_tlomega lo 
		inner join ob_tquality qr on (qr.id=lo.nr) 
		inner join ob_tquality qf on (qf.id=lo.nf) 
		group by qr.name,qf.name,qr.id,qf.id,qr.own,qf.own order by count(lo.*) desc 
		limit %i
	"""
	row_count = 0
	links = []
	dict_nodes = {}
	with db.Cursor as cursor:
		cursor.execute(sqlGraph,[MAXLINKS])
		for qr_id,qr_name,qr_own,qf_id,qf_name,qf_own,count in cursor:
			links.append((qr_id,qf_id,count))
			dict_nodes[qr_id]= (qr_name,qr_own)
			dict_nodes[qf_id]= (qf_name,qf_own)
			
	for i,(key,value) in enumerate(dict_nodes.iteritems()):
		dict_nodes[key] = value+(i,)
	links = [ {"source":dict_nodes[src][2],"target":dict_nodes[dst][2],"value":count} 
		for src,dst,count in links if (dict_nodes[src][2]< MAXNODES and dict_nodes[dst][2]< MAXNODES) ]
	nodes = [ {"group":own,"nodeName":name} for name,own,n in dict_nodes.itervalues() if n < MAXNODES ]
	res = {"links":links,"nodes":nodes}	
	json_str = json.dumps(res)
	write_path(dir_name+"matrixPrices.json",json_str,log=log)	
	log.info("matrixPrices done")
	return

def prices_json(conn,log):
	""" pour faire une moyenne sur les (volumes,prix) on fait sum(prix*volume)/sum(volume)
	soit M(X,Y) = sum(X*Y)/sum(Y)
	pour cela, on a:
		regr_sxy(X, Y) = sum(X*Y) - sum(X) * sum(Y)/N  
		regr_count(Y, X) = N
		M(X,Y) = (regr_sxy(X,Y)+sum(X)*sum(Y)/regr_count(X,Y))/sum(Y)
		prix=qttf/qttr,volume=qttf =>prix*volume=qttf*qttf/qttr
		test:
		insert into ob_tlomega (qttr,qttf,nr,nf,flags,created) values (10,10,2,2,0,now());
		select 
	"""
	from datetime import datetime,timedelta
	from os import path
	
	dir_name = settings.JSONDIR+"prices/"
	if(not path.isdir(dir_name)):
		raise Exception, "the path %s should exist" % dir_name
	nb = 0
	with db.DBCursor(conn,"prices_cursor") as cursor:

		sql = """
			SELECT ol.nr,ol.nf,o.scale,o.name,qf.name,qf.own,qr.name,qr.own from ob_tlomega ol 
				inner join ob_tomega o on (ol.nr=o.nr and ol.nf=o.nf)
				inner join ob_tquality qf on (qf.id=ol.nr)
				inner join ob_tquality qr on (qr.id = ol.nf)
			where ((now() - ol.created)< '7 days'::INTERVAL) group by ol.nr,ol.nf,o.scale,o.name,qf.name,qf.own,qr.name,qr.own
			"""
		cursor.execute(sql)
		for row in cursor:
			ol_nr,ol_nf,o_scale,o_name,qf_name,qf_own,qr_name,qr_own = row
			res = []
			with db.DBCursor(conn,"prices_cursor2") as cursor2:
				sql = """
					SELECT sum(qttf),
						(regr_sqttf/qttrqttf(qttf/qttr,qttf)+sum(qttf/qttr)*sum(qttf)/regr_count(qttf/qttr,qttf))/sum(qttf),
						date_trunc('hour',created) 
					from ob_tlomega where nr = %s and nf = %s 
					and ((now() - created)< '7 days'::INTERVAL) 
					group by qttf,qttr,date_trunc('hour',created)
					order by date_trunc('hour',created) asc """
				cursor2.execute(sql,ol_nr,ol_nf)
				for row in cursor2:
					volume,price_moy,date_heure = row
					res.append([volume,mean_price,date_hour])
			json_str = json.dumps(res)
			fic_name = ".".join(qr_name,qf_name,'json')
			write_path(dir_name+fic_name,json_str,log=log)	
		nb +=1
	log.info("prices_json - %i files written" % nb)
	return
	
if __name__ == "__main__":
	retCode = automate()
	sys.exit(retCode)

