#!/usr/bin/python
# -*- coding: utf8 -*-
import db
import logger
from simu import loopSimu

def simu():
	logger.start("simu2")
	log = logger.getLogger(name="simu2")
	try:
		with db.Connection(log) as conn:
			loopSimu(conn,log)
		log.info("Db connection closed")
		
	except Exception,e:
		exitError(log,"Abnormal termination")

if __name__ == "__main__":
	simu()
	
	
