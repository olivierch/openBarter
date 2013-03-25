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

import threading
import logging
import time
import random
####################################################################################
logging.basicConfig(level=logging.DEBUG,
                    format='(%(threadName)-10s) %(message)s',
                    )

class MyThreadWithArgs(threading.Thread):

    def __init__(self, group=None, target=None, name=None,
                 args=(), kwargs=None, verbose=None):
        threading.Thread.__init__(self, group=group, target=target, name=name,
                                  verbose=verbose)
        self.args = args
        self.kwargs = kwargs
        return

    def run(self):
        logging.debug('running with %s and %s', self.args, self.kwargs)
        time.sleep(0.01*random.random())
        logging.debug('stop %s', self.args)
        return
        
def testCor(options):
	for i in range(5):
		t = MyThreadWithArgs(args=(i,), kwargs={'a':'A', 'b':'B'})
		t.start()
	

from optparse import OptionParser
def main():
	usage = "usage: %prog [options]"
	parser = OptionParser(usage)
		
	(options, args) = parser.parse_args()

	testCor(options)

if __name__ == "__main__":
	main()

