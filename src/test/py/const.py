# -*- coding: utf-8 -*-

class _const(object):

	class ConstError(TypeError):
		pass

	def __setattr__(self,name,value):
			if name in self.__dict__:
				raise self.ConstError, "Cannot rebind const(%s)" % name
			self.__dict__[name] = value

	def __delattr__(self,name):
			if name in self.__dict__:
				raise self.ConstError, "Cannot unind const(%s)" % name

import sys
sys.modules[__name__] = _const()