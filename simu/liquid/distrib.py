#!/usr/bin/python
# -*- coding: utf8 -*-
import random
import cliquid

def init():
    random.seed()
    
def couple(f):
    """
    usage: x,y = distrib.couple(distrib.uniform)
    """
    a = f()
    b = a
    while(a == b):
        b = f()
    return a,b
    
def couple_money(f):
    a = 1
    b = a    
    while(a == b):
        b = f()
    if(random.randint(0,1)):
        return a,b
    else:
        return b,a
        
def uniformQlt():
    return random.randint(1,cliquid.MAX_QLT)
    

    

    



