#!/usr/bin/python
"""
"""
import logging
import logging.handlers
from datetime import datetime
import os
logger_time_start = None

LOG_FORMAT = "%(delay)-15s-pid%(pid)-5s - %(levelname)-8s - %(message)s"

class DelayInfo:
	def __getitem__(self,name):
		global logger_time_start
		if name == 'delay':
			result = str(datetime.now()-logger_time_start)
		elif name == 'pid':
			result =os.getpid()
		else:
			result = self.__dict__.get(name,'?')
		return result
	def __iter__(self):
		keys = ['delay','pid']
		keys.extend(self.__dict__.keys())
		return keys.__iter__()
	
def getLogger(name="to_be_named"):
	# create logger

	logger = logging.LoggerAdapter(logging.getLogger(name), DelayInfo())
	#logger = logging.LoggerAdapter(logger,DelayInfo())
	return logger

def start(name="to_be_named",direct = "./",maxBytes = 1000*1000, backupCount= 5):
	global logger_time_start
	
	if not os.path.exists(direct):
		os.makedirs(direct,0777)
	logger_time_start = datetime.now()
	logger = logging.getLogger()
	logger.setLevel(logging.DEBUG)
	formatter = logging.Formatter(LOG_FORMAT)
	# Add the log message handler to the logger
	handler = logging.handlers.RotatingFileHandler(direct+name+".log",maxBytes=maxBytes, backupCount=backupCount)
	handler.setFormatter(formatter)
	logger.addHandler(handler)
	return
	
if __name__ == "__main__":
	import glob
	import sys
	
	start(name="toto",direct='./',maxBytes = 20,backupCount=5)
	my_logger = getLogger('toto')
	# Log some messages
	for i in range(20):
		my_logger.debug('i = %d' % i)

	# See what files are created
	logfiles = glob.glob('%s*' % './toto')

	for filename in logfiles:
		print filename


	sys.exit(0)
