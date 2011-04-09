#!/usr/bin/python
# -*- coding: UTF-8 -*-
"""
bilds a graph for each quality, with the following form:
q1->q2 [2,3]
q1->q2->q3 [4,3]
q1->q4 [5,6]
q1->q4->q3 [3,2]
..........
{
"q1":{
	"q2":{	"":[2,3]
		,"q3":[4,3]
	}
	,"q4":{	"": [5,6]
		,"q3":[3,2]
	}
}
"""
def getGraphFromQuality(qualityName):

	res = {}	
	sql = """select n.id,s.id,qr.id,qf.id,n.omega,s.qtt from ob_tnoeud n
		inner join ob_tstock s on (s.id = n.sid)
		inner join ob_tquality qr on (qr.id = n.nr)
		inner join ob_tquality qf on (qf.id = n.nf)
		where qr.name = %s """
	found = True
	qua = qualityName
	chemin = []
	while(found):
		cursor.execute(sql,qua)
		#for nid,sid,qrid,qfid,omega,qtt in cursor:
		for atuple in cursor:
			flux = getFlux(chemin
			

