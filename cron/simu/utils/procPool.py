#!/usr/bin/python

# from multiprocessing import Process,Lock,Value
import multiprocessing
import logging
import time
import os
import sys


"""
runs nbProc process for secs seconds
"""       
def runProcess(target,secs= None,nbProc = 5):

	def f(l,k,flag):
		logger = multiprocessing.log_to_stderr()
		logger.setLevel(logging.INFO)
		while flag.value:
			try:
				target(logger,l,k)
			except Exception,e:
				flag.value = 0
				logger.error(str(e))
			
	l = multiprocessing.Lock()
	flag = multiprocessing.Value('i', 1)
	lp = []
	for k in range(nbProc):
		p = multiprocessing.Process(target=f, args=(l,k,flag))
		p.start() # fork process
		lp.append(p)

    	if(secs):
    		time.sleep(secs)
    	else:
		# waiting for stop
		keyb = None
		while (keyb != "stop\n" and flag.value !=0):
			keyb = sys.stdin.readline()

	flag.value = 0 # stop other process
	for p in lp:
		p.join()
		
def run(target):
	logger = multiprocessing.log_to_stderr()
	logger.setLevel(logging.INFO)
	l = multiprocessing.Lock()
	target(logger,l,0)
    	
if __name__ == '__main__':

	
	def g(log,l,k):
		l.acquire()
		log.warning('bob%d %d' % (k,os.getpid()))
		l.release()			

	# runProcess(g)
	run(g)
