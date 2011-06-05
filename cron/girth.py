#!/usr/bin/python
#-*- coding: utf8 -*-
""" computes the girth of the graph: shortest length of cycles
"""

import db
import sys

sqllien = """SELECT NOY.id,NOY.bf FROM ob_tnoeud NOY WHERE NOY.nr=%s """
sqlfour = """SELECT NOX.id,NOX.nf,S.qtt,NOX.loop_bf FROM ob_tnoeud NOX INNER JOIN ob_tstock S ON (NOX.sid =S.id) WHERE S.qtt!=0 and S.type='S' and NOX.bf=%s"""

def breadth_first(conn,nid):
	""" computes the smallest cycle from this node """
	depth=1
	nbf=0
	# a new column bf is (re)created default=null
	add_column(conn,"ob_tnoeud","bf","bigint")
	add_column(conn,"ob_tnoeud","loop_bf","text")
	updateNode(conn,1,nid,"%i"%nid)	
	# print "\nfor node[%i]" % (nid,)
	arcs = []
	_couche = True
	while _couche:
		_couche = False
		_str = ""
		with db.Cursor(conn,'name2') as cur2:
			cur2.execute(sqlfour,[depth])
			#for all nodes of couche=depth having stock!=0
			for (_idx,_nf,_qtt,_loop) in cur2:
				with db.Cursor(conn,'name3') as cur3:
					#for all nodes where nr=_nf
					cur3.execute(sqllien,[ _nf])
					for (_idy,_bf) in cur3:
						if(depth==1): 
							nbf +=1
							arcs.append((_qtt,_idx,_idy))
						if str(_idy) in _loop.split(","):
							#print _loop 
							return _bf+1,_loop,nbf,arcs
						_loop1 = _loop+(",%i"%_idy)
						updateNode(conn,depth+1,_idy,_loop1)
						_couche = True			
		depth +=1 
		if(False and len(_str)):
			_str = "%i: %s" % (depth-1,_str)
			print _str
	
	return None,None,nbf,arcs

def updateNode(conn,val,nid,loop):
	with db.Cursor(conn,'name4') as cur4:
		cur4.execute("update ob_tnoeud set bf=%s,loop_bf=%s where id=%s",[val,loop,nid])
	return 
	
def find_cycle(conn):
	minl = None
	mini = None
	maxi = None
	nbf = 0
	# for each ob_tnoeud
	nbBids =0
	with db.Cursor(conn,'name1') as cursor:
		cursor.execute("select id from ob_tnoeud order by id")
		for (_id,) in cursor:
			if(mini == None or mini>_id): mini = _id
			if(maxi == None or maxi<_id): maxi = _id
			nbBids +=1
			length,loop,_nbf,arcs = breadth_first(conn,_id)
			#print "from [%i] %i arcs" % (_id,_nbf)
			if(len(arcs)):
				
				print "[%i]\t"%(arcs[0][0],)+",".join(
					["%i->%i"%(idx,idy) for qtt,idx,idy in arcs])
			nbf += _nbf
			if (False and length):
				print "loop:"+loop
			if(minl == None) or (length != None and minl > length):  
				minl = length
				minloop = loop
	return minl,nbBids,minloop,mini,maxi,nbf

def printLoop(conn,length):
	return
	
def add_column(conn,table,column,typ):
	""" add a column to the table """
	
	try:
		with db.Cursor(conn,'name') as cursor:
			cursor.execute("alter table %s drop %s" % (table,column))
	except Exception,e:
		pass

	with db.Cursor(conn,'name') as cursor:
		cursor.execute("alter table %s add %s %s default null" % (table,column,typ))
	return
	
def automate():
	retCode = 0 
	with db.Connection() as conn:
		girth,nbBids,minloop,mini,maxi,nbf = find_cycle(conn)
	print "##################################### RESULT ##############################"
	print "for a graph with %i arcs and %i nodes between %i and %i " % (nbf,nbBids,mini,maxi)
	if girth == None:
		print "girth infinite"
	else:
		print "girth %i" % girth
		print minloop
	return retCode
	
if __name__ == "__main__":
	retCode = automate()
	sys.exit(retCode)

