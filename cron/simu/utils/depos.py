#!/usr/bin/python
import db
	
def getName(prefix,i):
	return prefix+str(i+1)
	
def getQualityName(deposName,i):
	return deposName+'>'+getName('qual',i)
	
def getDeposName(i):
	return getName("depos",i)
	
class Depos(db.Connection):
	connect ={"dbname":"test_charge","host":"176.31.243.132"}
	def __init__(self,nom,autocommit = True):
		self.nom = nom
		super(Depos,self).__init__(strcon = self.strconnect(),autocommit = autocommit)
		
	def strconnect(self):
		con = self.connect
		con["user"] = self.nom
		return " ".join([ k+"="+v for k,v in con.iteritems()])
		
	def getQualityName(self,i):
		return getQualityName(self.nom,i)
		
	def getName(self):
		return self.nom
		


