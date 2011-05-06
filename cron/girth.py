#!/usr/bin/python
#-*- coding: utf8 -*-
""" computes the girth of the graph: shortest length of cycles
"""

import db
import sys

conn = None
sqllien = """SELECT NOY.id,NOY.bf FROM ob_tnoeud NOY WHERE NOY.nr=%s """
sqlfour = """SELECT NOX.id,NOX.nf,S.qtt FROM ob_tnoeud NOX INNER JOIN ob_tstock S ON (NOX.sid =S.id) WHERE S.qtt!=0 and S.type='S' and NOX.bf=%s"""

def breadth_first(nid):
	""" computes the smallest cycle from this node """
	depth=1
	add_column("ob_tnoeud","bf")
	updateNode(1,nid)	
	_couche = True
	while _couche:
		_couche = False
		with db.Cursor(conn,'name2') as cur2:
			cur2.execute(sqlfour,[depth])
			for (_idx,_nf,_qtt) in cur2:
				with db.Cursor(conn,'name3') as cur3:
					cur3.execute(sqllien,[ _nf])
					for (_idy,_bf) in cur3:
						if _bf != None: 
							return _bf
						print "%i :%i->%i" % (_qtt,_idx,_idy)
						updateNode(depth+1,_idy)
						_couche = True			
		depth +=1 
	print "depth %i" % (depth-1,)
	return None

def updateNode(val,nid):
	with db.Cursor(conn,'name4') as cur4:
		cur4.execute("update ob_tnoeud set bf=%s where id=%s",[val,nid])
	return 
	
def find_cycle():
	global conn
	maxl = None
	# for each ob_tnoeud
	with db.Cursor(conn,'name1') as cursor:
		cursor.execute("select id from ob_tnoeud")
		for (_id,) in cursor:
			length = breadth_first(_id)
			if(maxl == None): maxl = length
			elif (length != None and maxl < length): maxl = length
	if maxl == None:
		print "girth infinite"
	else:
		print "girth %i" % maxl
	
def add_column(table,column):
	""" add a column to the table """
	global conn
	
	try:
		with db.Cursor(conn,'name') as cursor:
			cursor.execute("alter table %s drop %s" % (table,column))
	except Exception,e:
		pass

	with db.Cursor(conn,'name') as cursor:
		cursor.execute("alter table %s add %s bigint default null" % (table,column))
	return
	
def automate():
	global conn
	retCode = 0 
	with db.Connection() as conn:
		find_cycle()
		"""
		try:
			find_cycle()
		except Exception,e:
			print("Exception %s occured" % str(e))
		else:	
			print("done")
		"""
	return retCode
	
if __name__ == "__main__":
	retCode = automate()
	sys.exit(retCode)

