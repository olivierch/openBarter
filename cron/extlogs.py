#!/usr/bin/python
"""
"""
import settings
import logger
import json
from os import path
from write_load_path import write_path

def extract(name="to_be_named"):
		
	def _extractLine(line):
		l = line [logger.LOG_OFFSETS:]
		h,m,s = line[0:logger.LOG_OFFSET[0]].split(':')
		time = "%02s:%02s" % (h,m)
		try:
			res = json.loads(l)
		except ValueError:
			res = { "comment": l }
		return time,res
	
	def _cumulDict(elt,st):
		t = type(elt)
		_t = type(st)

		if(t == _t):	
			if(t == type({})):
				# elt and st are both dict	
				for k,v in elt.iteritems():
					if st.has_key(k):
						st[k] = _cumulDict(v,st[k])
					else:
						st[k] = v
				return st
				
			if((t == type(1)) or (t == type(1.))):
				return elt+st	

		else:
			if(st == None):
				return elt
			if((_t == type(1)) or (_t == type(1.))):
				return 1+st
		
		return st
	
	stats = {}

	logfiles = glob.glob(path.join(settings.LOGGINGDIR,'%s*' % name))
	for filename in logfiles:
		with open(filename) as f:
			line = f.readline()
			time,res = _extractLine(line)
			stat = stats.get(time)
			if(stat != None):
				stat = _cumulDict(res,stat)
			else:
				stat = res
			stats[time] = stat

	write_path(path.join(settings.JSONDIR,"stats.json"),json.dumps(stats, sort_keys=True))