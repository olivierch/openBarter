#!/usr/bin/python
# -*- coding: utf8 -*-

import prims
import sys
import const
import util
import random
import psycopg2
import sys
# import curses



def testExec(options):
	with util.DbConn(const) as con:
		with util.DbCursor(con) as cursor:
		
			cursor.execute("SELECT count(*) from tuser where name=%s",[const.DB_USER])
			res = [e for e in cursor]
			print res
			cursor.callproc("fgetconst",["MAXORDERFETCH"])
			res = [e for e in cursor]
			print res	
			try:		
				cursor.callproc("fgetconst",["MAXORDERFETCHAAAA"])
				res = [e for e in cursor]
				print res
			except StandardError,e: # psycopg2.DatabaseError
				print "Exception:", sys.exc_info()
				print e.pgcode	# le code de l'erreur	
				print e.pgerror
	

from optparse import OptionParser
def main():
	usage = "usage: %prog [options]"
	parser = OptionParser(usage)
		
	(options, args) = parser.parse_args()

	testExec(options)

if __name__ == "__main__":
	main()

