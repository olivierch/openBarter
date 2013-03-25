#!/usr/bin/python
# -*- coding: utf8 -*-

import prims
import util
import random
import const

def threadAllowed(scenario):
	return scenario in ["basic"]
	
def simuInt(args):
	options,user = args
	random.seed(options.seed) #for reproductibility of playings
		
	try:
		if(options.scenario == "quote"):
			scenQuote(options,user)

		elif(options.scenario == "basic"):
			scenBasic(options,user)
			
		else:
			raise Exception("Scenario undefined")

	except KeyboardInterrupt:
		print 'Work interrupted by user' 
	return 
	
#####################################################################
# scen* scenarii

def scenBasic(options,user):

	with util.DbConn(const,user) as dbcon:
		with util.DbCursor(dbcon) as cursor:
			for iOper in range(options.iteration):
				params = util.getParameters(options,user)
				cde2 = prims.InsertOrder(params)
				cde2.execute(cursor)
	return
		
def scenQuote(options,user):

	with util.DbConn(const,user) as dbcon:
		with util.DbCursor(dbcon) as cursor:
			for iOper in range(options.iteration):
				params = util.getParameters(options,user)
				cde = prims.GetQuote(params)
				cde.execute(cursor)

				if(cde.getIdQuote()!=0):
					cde2 = prims.ExecQuote(cde.getOwner(),cde.getIdQuote())
					cde2.execute(cursor)
				else:
					cde2 = prims.InsertOrder(params)
					cde2.execute(cursor)
	return
