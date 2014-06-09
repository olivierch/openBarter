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

'''
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
'''
