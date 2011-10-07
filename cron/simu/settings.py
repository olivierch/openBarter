#!/usr/bin/python
import os
# settings of the deamon
OBDIR = os.path.abspath("../..") #"contrib/openBarter/"
WORKDIR = os.path.join(OBDIR,"cron/simu") ##"contrib/openBarter/cron/simu"
PGSQLOBDIR = os.path.join(OBDIR,"pg") #"contrib/openBarter/pg"
MAXFD = 1024

#logger
LOGGINGDIR = os.path.join(WORKDIR,"logs/")
LOGGINGmaxBytes = 1000 * 1000
LOGGINGbackupCount = 5

# simulation
NBQUALITY = 3
NBDEPOS = 5
NBOWNER = 5

#output
JSONDIR = os.path.join(WORKDIR,"media/json/")


if(__name__=="__main__"):
	
	def makedir(direc):
		if not os.path.exists(direc):
			os.makedirs(direc,0777)
			print direc," created"	
	if(not os.path.exists(os.path.join(PGSQLOBDIR,"openbarter.sql"))):
		print "should exist"
		exit(0)
	makedir(JSONDIR)
	makedir(LOGGINGDIR)
	
		

        
