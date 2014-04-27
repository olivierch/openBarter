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

class Exec1:
    def __init__(self):
        self.NAME = "X1"
        # model
        self.MAXCYCLE=64
        self.MAXPATHFETCHED=1024*5
        self.MAXMVTPERTRANS=128


class Exec2:
    def __init__(self):
        self.NAME = "X2"
        # model
        self.MAXCYCLE=32
        self.MAXPATHFETCHED=1024*10
        self.MAXMVTPERTRANS=128
        

class Exec3:
    def __init__(self):
        self.NAME = "X3"
        # model
        self.MAXCYCLE=64
        self.MAXPATHFETCHED=1024*10
        self.MAXMVTPERTRANS=128


class Exec4:
    def __init__(self):
        self.NAME = "X4"
        # model
        self.MAXCYCLE=64
        self.MAXPATHFETCHED=1024*10
        self.MAXMVTPERTRANS=256


class Exec5:
    def __init__(self):
        self.NAME = "E5_Y2P1024_10M256"
        # model
        self.MAXCYCLE=2
        self.MAXPATHFETCHED=1024*10
        self.MAXMVTPERTRANS=256
                               
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


