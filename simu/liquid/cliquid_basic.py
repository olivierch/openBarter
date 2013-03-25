#!/usr/bin/python
# -*- coding: utf8 -*-
import cliquid
import distrib
CONF_NAME='basic'

MAX_OWNER=min(100,cliquid.MAX_TOWNER) # maximum number of owners
MAX_QLT=100  # maximum number  of qualities

# model
MAXCYCLE=6
MAXPATHFETCHED=1024
MAXMVTPERTRANS=128

"""
fonction de distribution des qualités
"""
distribQlt = distrib.uniformQlt
coupleQlt = distrib.couple

# etendue des tests
LIQ_PAS = 1000
LIQ_ITER = min(10,cliquid.MAX_TORDER/LIQ_PAS)



