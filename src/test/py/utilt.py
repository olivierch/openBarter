# -*- coding: utf-8 -*-
import string

class PrTest(object):

	def __init__(self,parlen,sep):
		self.parlen = parlen+ parlen%2
		self.sep = sep

	def title(self,title):
		_l = len(title)
		_p = max(_l%2 +_l,40)
		_x = self.parlen -_p
		if (_x > 2):
			print (_x/2)*self.sep + string.center(title,_p) + (_x/2)*self.sep
		else:
			print string.center(text,self.parlen)

	def line(self):
		print self.parlen*self.sep

	def center(self,text):
		print string.center(text,self.parlen)