#!/usr/bin/python
# -*- coding: utf8 -*-
import random

def init():
    random.seed()
    
def couple(f,maxi):
    """
    usage: x,y = distrib.couple(distrib.uniform)
    """
    a = f(maxi)
    b = a
    while(a == b):
        b = f(maxi)
    return a,b
    
def couple_money(f,maxi):
    a = 1
    b = a    
    while(a == b):
        b = f(maxi)
    if(random.randint(0,1)):
        return a,b
    else:
        return b,a
        
def uniformQlt(maxi):
    return random.randint(1,maxi)
    
def betaQlt(maxi):
    r = random.betavariate(2.0,5.0)
    # r in [0,1] proba max pour 0.2
    s = int(r*maxi)+1
    if(s<0):
        return 0
    if(s>maxi):
        return maxi
    return s
    

    



