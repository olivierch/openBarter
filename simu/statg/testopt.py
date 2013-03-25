#!/usr/bin/python
# -*- coding: utf8 -*-



from optparse import OptionParser

def main():
	usage = "usage: %prog [options] arg"
	parser = OptionParser(usage)
	parser.add_option("-f", "--file", dest="filename",
		      help="read data from FILENAME")
	parser.add_option("-v", "--verbose",
		      action="store_true", dest="verbose")
	parser.add_option("-q", "--quiet",
		      action="store_false", dest="verbose")
	parser.add_option("-r", "--reset",action="store_true", dest="reset",help="database is reset",default=False)
	parser.add_option("--MAXTRY",type="int",dest="MAXTRY",help="reset MAXTRY")

	(options, args) = parser.parse_args()
	if len(args) != 1:
		parser.error("incorrect number of arguments")
	if options.verbose:
		print "reading %s..." % options.filename
	print options.reset
	print options.MAXTRY
	print "args %s" % args

if __name__ == "__main__":
	main()


