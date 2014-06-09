#!/usr/bin/python
# -*- coding: utf8 -*-
import distrib
import os.path

DB_NAME='liquid'
DB_USER='olivier'
DB_PWD=''
DB_HOST='localhost'
DB_PORT=5432

PATH_ICI = os.path.dirname(os.path.abspath(__file__))
PATH_SRC= os.path.join(os.path.dirname(PATH_ICI),'src')
PATH_DATA=os.path.join(PATH_ICI,'data')

MAX_TOWNER=10000 # maximum number of owners in towner
MAX_TORDER=1000000 # maximum size of the order book
MAX_TSTACK=100
MAX_QLT=100  # maximum number  of qualities

#
QTT_PROV = 10000 # quantity provided

class Execu(object):
    def __init__(self,name,cycle,fetched,mvtpertrans):
        self.NAME = name
        self.MAXCYCLE = cycle
        self.MAXPATHFETCHED = fetched
        self.MAXMVTPERTRANS = mvtpertrans 

exec1 = Execu("X1",64,1024*5,128)
exec2 = Execu("X2",32,1024*10,128)
exec3 = Execu("X3",64,1024*10,128)
exec4 = Execu("X4",64,1024*10,256)
exec5 = Execu("X5",2,1024*10,256)

class EnvExec(object):
    def __init__(self,name,nbowner,qlt,distrib,pas):
        self.CONF_NAME=name

        self.MAX_OWNER=min(nbowner,MAXOWNER) # maximum number of owners
        self.MAX_QLT=nbqlt  # maximum number  of qualities

        """
        fonction de distribution des qualités
        """
        self.distribQlt = distrib
        self.coupleQlt = couple

        # etendue des tests
        self.LIQ_PAS = pas
        self.LIQ_ITER = min(30,MAX_TORDER/self.LIQ_PAS)        

envbasic10=    EnvExec('1e1uni',   100,10,distrib.uniformQlt,500) 
envbasic100=   EnvExec('1e2uni',   100,100,distrib.uniformQlt,500)   
envbasic1000=  EnvExec('B3',       100,1000,distrib.betaQlt,500) 
envbasic10000= EnvExec('1e4uni',   100,10000,distrib.betaQlt,500)  
envMoney100=   EnvExec('money100', 100,100,distrib.uniformQlt,500)
'''
class Basic10:
    def __init__(self):

        self.CONF_NAME='1e1uni'

        self.MAX_OWNER=min(100,MAX_TOWNER) # maximum number of owners
        self.MAX_QLT=10  # maximum number  of qualities

        """
        fonction de distribution des qualités
        """
        self.distribQlt = distrib.uniformQlt
        self.coupleQlt = distrib.couple

        # etendue des tests
        self.LIQ_PAS = 500
        self.LIQ_ITER = min(30,MAX_TORDER/self.LIQ_PAS)

                
class Basic100:
    def __init__(self):

        self.CONF_NAME='1e2uni'

        self.MAX_OWNER=min(100,MAX_TOWNER) # maximum number of owners
        self.MAX_QLT=100  # maximum number  of qualities

        """
        fonction de distribution des qualités
        """
        self.distribQlt = distrib.betaQlt
        self.coupleQlt = distrib.couple

        # etendue des tests
        self.LIQ_PAS = 500
        self.LIQ_ITER = min(30,MAX_TORDER/self.LIQ_PAS)
 
       
class Basic1000:
    def __init__(self):

        self.CONF_NAME='B3'

        self.MAX_OWNER=min(100,MAX_TOWNER) # maximum number of owners
        self.MAX_QLT=1000  # maximum number  of qualities

        """
        fonction de distribution des qualités
        """
        self.distribQlt = distrib.betaQlt
        self.coupleQlt = distrib.couple

        # etendue des tests
        self.LIQ_PAS = 500
        self.LIQ_ITER = min(30,MAX_TORDER/self.LIQ_PAS)

     
class Basic10000:
    def __init__(self):

        self.CONF_NAME='1e4uni'

        self.MAX_OWNER=min(100,MAX_TOWNER) # maximum number of owners
        self.MAX_QLT=10000  # maximum number  of qualities

        """
        fonction de distribution des qualités
        """
        self.distribQlt = distrib.betaQlt
        self.coupleQlt = distrib.couple

        # etendue des tests
        self.LIQ_PAS = 500
        self.LIQ_ITER = min(30,MAX_TORDER/self.LIQ_PAS)       

basic100large=EnvExec('1E4UNI',100,10000,distrib.uniformQlt,3000)                
class Basic100large:
    def __init__(self):

        self.CONF_NAME='1E4UNI'

        self.MAX_OWNER=min(100,MAX_TOWNER) # maximum number of owners
        self.MAX_QLT=10000  # maximum number  of qualities

        """
        fonction de distribution des qualités
        """
        self.distribQlt = distrib.uniformQlt
        self.coupleQlt = distrib.couple

        # etendue des tests
        self.LIQ_PAS = 3000
        self.LIQ_ITER = min(30,MAX_TORDER/self.LIQ_PAS)
        

class Money100:
    def __init__(self):

        self.CONF_NAME='money100'

        self.MAX_OWNER=min(100,MAX_TOWNER) # maximum number of owners
        self.MAX_QLT=100  # maximum number  of qualities

        """
        fonction de distribution des qualités
        """
        self.distribQlt = distrib.uniformQlt
        self.coupleQlt = distrib.couple_money

        # etendue des tests
        self.LIQ_PAS = 500
        self.LIQ_ITER = min(30,MAX_TORDER/self.LIQ_PAS)

'''
