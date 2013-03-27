#!/usr/bin/python
# -*- coding: utf8 -*-
import distrib

DB_NAME='liquid'
DB_USER='olivier'
DB_PWD=''
DB_HOST='localhost'
DB_PORT=5432

PATH_SRC="/home/olivier/Bureau/ob92/src"
PATH_DATA="/home/olivier/Bureau/ob92/simu/liquid/data"

MAX_TOWNER=10000 # maximum number of owners in towner
MAX_TORDER=1000000 # maximum size of the order book
MAX_TSTACK=1000
MAX_QLT=100  # maximum number  of qualities

#
QTT_PROV = 10000 # quantity provided

class Exec1:
    def __init__(self):
        self.NAME = "E1_Y6P1024M128"
        # model
        self.MAXCYCLE=6
        self.MAXPATHFETCHED=1024
        self.MAXMVTPERTRANS=128


class Exec2:
    def __init__(self):
        self.NAME = "E2_Y6P2048M128"
        # model
        self.MAXCYCLE=6
        self.MAXPATHFETCHED=2048
        self.MAXMVTPERTRANS=128
        

class Exec3:
    def __init__(self):
        self.NAME = "E3_Y16P1024M128"
        # model
        self.MAXCYCLE=12
        self.MAXPATHFETCHED=1024
        self.MAXMVTPERTRANS=128


class Exec4:
    def __init__(self):
        self.NAME = "E4_Y6P1024M256"
        # model
        self.MAXCYCLE=6
        self.MAXPATHFETCHED=1024
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
        self.LIQ_PAS = 300
        self.LIQ_ITER = min(30,MAX_TORDER/self.LIQ_PAS)

                
class Basic100:
    def __init__(self):

        self.CONF_NAME='1e2uni'

        self.MAX_OWNER=min(100,MAX_TOWNER) # maximum number of owners
        self.MAX_QLT=100  # maximum number  of qualities

        """
        fonction de distribution des qualités
        """
        self.distribQlt = distrib.uniformQlt
        self.coupleQlt = distrib.couple

        # etendue des tests
        self.LIQ_PAS = 300
        self.LIQ_ITER = min(30,MAX_TORDER/self.LIQ_PAS)
        
class Basic1000:
    def __init__(self):

        self.CONF_NAME='1e3uni'

        self.MAX_OWNER=min(100,MAX_TOWNER) # maximum number of owners
        self.MAX_QLT=1000  # maximum number  of qualities

        """
        fonction de distribution des qualités
        """
        self.distribQlt = distrib.uniformQlt
        self.coupleQlt = distrib.couple

        # etendue des tests
        self.LIQ_PAS = 300
        self.LIQ_ITER = min(30,MAX_TORDER/self.LIQ_PAS)
       
                
class Basic100large:
    def __init__(self):

        self.CONF_NAME='UNI100'

        self.MAX_OWNER=min(100,MAX_TOWNER) # maximum number of owners
        self.MAX_QLT=100  # maximum number  of qualities

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
        self.LIQ_PAS = 30
        self.LIQ_ITER = min(30,MAX_TORDER/self.LIQ_PAS)


