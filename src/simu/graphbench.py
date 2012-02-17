#!/usr/bin/python
# -*- coding: utf8 -*-

"""
usage: 
	$graphbench.y | fdp -Tpng > bench.png
	$graphbench.y | circo -Tpng > bench.png

en remplacant getgraphQ par getgraph dans simu() on a le gros graph des connexions 
(attention, dot plante avec, mais pas fdp)
	
GRAPHVIZ
********
NAME
       dot - filter for drawing directed graphs
       neato - filter for drawing undirected graphs
       twopi - filter for radial layouts of graphs
       circo - filter for circular layout of graphs
       fdp - filter for drawing undirected graphs

SYNOPSIS
       dot [-(G|N|E)name=value] [-Tlang] [-l libfile] [-o outfile] [-v] [-V] [files]
       neato [-(G|N|E)name=value] [-Tlang] [-l libfile] [-n[1|2]] [-o outfile] [-v] [-V] [files]
       twopi [-(G|N|E)name=value] [-Tlang] [-l libfile] [-o outfile] [-v] [-V] [files]
       circo [-(G|N|E)name=value] [-Tlang] [-l libfile] [-o outfile] [-v] [-V] [files]
       fdp [-(G|N|E)name=value] [-Tlang] [-l libfile] [-o outfile] [-v] [-V] [files]


le dot plante car out of memory
fdp -Tsvg gr_test1.tst
fdp -Tpng gr_test1.tst

"""

import random	# random.randint(a,b) gives N such as a<=N<=b
import psycopg2
import psycopg2.extras
from datetime import datetime
import sys
# import curses

#stdscr = curses.initscr()
cur_user = 'olivier'

def connect():
	dbcon = psycopg2.connect(
				database  = 'test2',
				password  = '',
				user = cur_user,
				host = 'localhost',
				port = 5432
	)
	dbcon.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
	return dbcon
	
def isOpened(cursor):
	return True
	cursor.execute("SELECT state FROM vmarket ")
	res = [e[0] for e in cursor]
	return (res[0] == "OPENED")
	
def getOne(cursor,sql):
	cursor.execute(sql)
	res = [e[0] for e in cursor]
	return res[0]

	
def getgraph(cursor):
	colors = ['black','seashell','gray','white','maroon','red','purple','deeppink','green','limegreen','olivedrab','yellow','navy','blue','tan','aquamarine']
	print 'digraph database {'
	pref = '    '
	print pref+'ratio=1'
	sql ='select x.id as a,y.id as b,x.np as q from torder x,torder y where x.np=y.nr and x.qtt!=0 and y.qtt!=0 and flow_maxdimrefused(y.refused,30) and flow_maxdimrefused(x.refused,30) AND NOT(y.id=ANY(x.refused))'
	cursor.execute(sql)
	for e in cursor:
		color = colors[e[2] % len(colors)]
		#print pref+'%i -> %i [label=q%i,color=%s]'%(e[0],e[1],e[2],color)
		print pref+'%i -> %i [label=q%i]'%(e[0],e[1],e[2])
	print '}'

def getgraphQ(cursor):
	colors = ['black','seashell','gray','white','maroon','red','purple','deeppink','green','limegreen','olivedrab','yellow','navy','blue','tan','aquamarine']
	print 'digraph database {'
	pref = '    '
	print pref+'ratio=1'
	sql ='select q.id from tquality q'
	cursor.execute(sql)
	for e in cursor:		
		print pref+'%i [label=q%i]'%(e[0],e[0])
	sql ='select x.np as a,x.nr as b,x.own,x.id from torder x where x.qtt!=0'
	cursor.execute(sql)
	for e in cursor:
		color = colors[e[2] % len(colors)]
		print pref+'%i -> %i [color=%s,label="%i"]'%(e[0],e[1],color,e[3])
	print '}'		
	

def simu():
	random.seed(0) #for reproductibility of playings
	nbOper = 0
	start = datetime.now()
	dbcon = connect()
	cursor = dbcon.cursor()
	cursor.execute("SET search_path='t' ")
	if(not isOpened(cursor)):
		print >>sys.stderr,"Market not opened"		
	else:
		try:
			getgraph(cursor)
		except Exception,e:
			print >>sys.stderr,"Exception inattendue"
			print >>sys.stderr,e
	try:
		cursor.close()
		# print "cursor closed"
	except Exception,e:
		print >>sys.stderr,"Exception while trying to close the cursor"
	try:
		dbcon.close()
		# print "DB close"
	except Exception,e:
		print >>sys.stderr,"Exception while trying to close the cursor"
		

if __name__ == "__main__":
	simu()
