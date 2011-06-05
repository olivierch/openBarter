#!/usr/bin/python
# -*- coding: utf8 -*-

import random	# random.randint(a,b) gives N such as a<=N<=b

def rd():
	random.seed(0) #for reproductibility of playings
	res = []
	for i in range(10):
		res.append(str(random.randint(1,10)))
	print ','.join(res)


if __name__ == "__main__":
	rd()
