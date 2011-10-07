#!/usr/bin/python

def getSufName(i):
	return 'qual'+str(i+1)

def getName(depos,i):
	return settings.DATABASE_USER+'>'+getSufName(i)
