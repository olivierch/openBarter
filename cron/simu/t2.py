#!/usr/bin/python
#-*- coding: utf8 -*-
from utils import db
import psycopg2
import psycopg2.extras


with db.Connection() as conn:
	cur = conn.cursor()
	cur.execute("INSERT INTO test (num, data) VALUES(%s, %s)",(100, "abc'def"))
	cur.execute("select * from test")
	res = cur.fetchone()
	print res['num'],res['data']
	cur.execute("select * from test")
	res = cur.fetchmany(10)
	for r in res:
		print r['num'],r['data']
"""
con = psycopg2.connect(db.strconnect)
cur = con.cursor(cursor_factory=psycopg2.extras.DictCursor)
cur.execute("INSERT INTO test (num, data) VALUES(%s, %s)",(100, "abc'def"))
cur.execute("select * from test")
res = cur.fetchone()
print res['num'],res['data']
cur.execute("select * from test")
res = cur.fetchmany(10)
for r in res:
	print r['num'],r['data']
cur.close()
con.close()
"""
