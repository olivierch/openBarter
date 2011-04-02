#!/usr/bin/python
# settings of the deamon
WORKDIR = "/home/olivier/project/dja/mp/"
PGSQLOBDIR = "/home/olivier/project/pgsql/contrib/openbarter/"
MAXFD = 1024

#logger
LOGGINGDIR = WORKDIR+"logs/"
LOGGINGmaxBytes = 1000 * 1000
LOGGINGbackupCount=5

#output
JSONDIR = WORKDIR + "media/json/"

#database
DATABASE_NAME = 'mp'
DATABASE_USER = 'olivier'         
DATABASE_PASSWORD = '' 
DATABASE_HOST = 'localhost'     
DATABASE_PORT = '5432'            
