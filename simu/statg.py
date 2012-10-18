#!/usr/bin/python
# -*- coding: utf8 -*-
"""
paramètre influant sur le comportement de la place de marché:
	MAXCYCLE
	MAXTRY
	MAXORDERFETCH
	
caractéristiques statistiques des ordres:
	distribution du stock d'ordres sur les couples (np,nr)
	
critères de performance de la PM:
liquidité
	flux d'ordre entrant
	stock d'ordres
	flux de mouvement sortant
	fuites (flux de rejet d'ordres)
	
vitesse
	temps moyen d'exécution d'un ordre

exhaustivité de la mise en concurrence


"""
import sys
import util
import prims

# diviser le temps en intervalles
def getIntTime(c):
	def union(a,b):
		r = [None,None]
		if(a[0] < b[0]): r[0] = a[0]
		else: r[0] = b[0]
		if(a[1] > b[1]): r[1] = a[1]
		else: r[1] = b[1]
		return r		
	res1 = prims.getSelect(c,"SELECT min(created),max(created) FROM tmvt",[])
	res2 = prims.getSelect(c,"SELECT min(created),max(created) FROM torder",[])
	return union(res1[0],res2[0])

# pour chaque intervalle:
def genIntervals(c,options):
	""" usage:
		intervals = genIntervals(cursor,options)
		for i,mini,maxi in intervals:
			print i,mini,maxi
	"""
	mini,maxi = getIntTime(c)
	
	delta = (maxi-mini)//options.INTERVALS
	for i in range(options.INTERVALS):
		yield i,mini +(delta * i),mini+(delta * (i+1))
	 
import csv
def getWriter(fic):
	return csv.writer(fic, delimiter=';',
                        quotechar='"', quoting=csv.QUOTE_MINIMAL)
                        
# cumuler les valeurs sur l'intervalle

def stat(cursor,options):
	intervals = genIntervals(cursor,options)
	fic = open(options.filename, 'w')
	writer = getWriter(fic)
	cols = None
	for i,mini,maxi in intervals:
		# print mini,maxi
		cursor.callproc('fgetstats',[mini,maxi])
		res = [e for e in cursor]
		if(i==0):
			cols = [a[0] for a in res]
			writer.writerow(cols)
		writer.writerow([a[1] for a in res])
		#print res
	fic.close()
	return cols
			
		#print i,mini,maxi
	
def statg(options):
	prims.execSql('statg.sql')
	dbcon = util.connect()
	cursor = dbcon.cursor()
	cols = None
	try:
		cols = stat(cursor,options)
		
	except KeyboardInterrupt:
		print 'interrupted by user' 	

	finally:
		try:
			cursor.close()
			# print "cursor closed"
		except Exception,e:
			print "Exception while trying to close the cursor"
		try:
			dbcon.close()
			# print "DB close"
		except Exception,e:
			print "Exception while trying to close the connexion"
		
	print 'file %s written with %i intervals' %(options.filename,options.INTERVALS) 
	print 'and cols: %s' % cols
	return

import os.path
import random
def gettmpfile():
	found = False
	while(not found):
		fil = '/tmp/statg'+str(int(random.random()*10000000))+'.csv'	
		if(not os.path.exists(fil)): found = True
	return fil
	
from optparse import OptionParser
import tempfile
def main():
	usage = "usage: %prog [options]"
	parser = OptionParser(usage)

	parser.add_option("--INTERVALS",type="int",dest="INTERVALS",help="define the number of intervals [100]",default=100)
	parser.add_option("-f","--file",type="string",action="store",dest="filename",help="file name for the result [test.csv]",default=None)
		
	(options, args) = parser.parse_args()
	if(options.filename is None):
		options.filename = gettmpfile()
		
	statg(options)

if __name__ == "__main__":
	main()

