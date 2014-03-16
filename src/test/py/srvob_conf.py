# -*- coding: utf-8 -*-

import os.path,logging

PATH_ICI = os.path.dirname(os.path.abspath(__file__))

class DbInit(object):
    def __init__(self,name,login,pwd,host,port,schema = None):
        self.name = name
        self.login = login
        self.password = pwd
        self.host = host
        self.port = port
        self.schema = schema
    def __str__(self):
        return self.name+" "+self.login

DB_NAME='test'
DB_USER='olivier'
DB_PWD=''
DB_HOST='localhost'
DB_PORT=5432

dbBO = DbInit(DB_NAME,DB_USER,DB_PWD,DB_HOST,DB_PORT)

LOGFILE = 'logger.log'







