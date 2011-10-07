#!/usr/bin/python

# from multiprocessing import Process,Lock,Value
from utils import procPool,db,depos
import settings

class ExcSimu(Exception):
	pass

def simuOld(log,lock,k):
	with db.Connection(autocommit = False) as conn:
		# with transaction, using a dictionary as factory
		with db.Cursor(conn) as cur:
			cur.execute("select * from test")
			res = cur.fetchone()
			log.info(str(res))	

def createRoles(): #one shot
	# creates roles for depositary
	with depos.Depos("desktop") as conn:
		with db.Cursor(conn) as cur:
			for i in range(settings.NBDEPOS):
				cur.execute("create role %s"%(depos.getDeposName(i),))

def createDb(): #one shot
	with db.Connection(autocommit = True,strcon = db.strconnect) as conn:
		with db.Cursor(conn) as cur:
			cur.execute("drop database if exists tests_charge")
			cur.execute("create database tests_charge")
	# marche pas
	"""
	with db.Connection(autocommit = False,strcon = strconnect) as conn:
		db.exec_file(conn,"../../pg/openbarter.sql")
	"""

def simu(log,lock,iDepos):

	deposit = depos.getDeposName(iDepos)
	with depos.Depos(deposit) as conn:
		for iOwn in range settings.NBOWNER:
			owner = depos.getName("own",iOwn)
			decideDraft(log,lock,depos,owner)
			idStock,quaf,qttf = deposeValue(log,lock,depos,owner)
			
def decideDraft(log,lock,depos,owner):
	""" the owner accept drafts.
	"""
	with Cursor(depos) as cur:
		cur.execute("select * from ob_vdraft where owner=%s",[owner])
		resu = cur.fetchall()
		
		for res in resu:
			did,status,owner,cntcommit,flags,created = res
				
			#accepted 9 times on 10, else refused
			#accept = not( random.randint(0,9)==0)
			accept = True
			
			res = -1
			pars = [did,owner]
			if(accept):
				sql = """ob_faccept_draft""" # (%i,%s) did,owner, 
				# retourne 0: draft, 1: execute, <0 erreur
			else: #refus
				sql = """ob_frefuse_draft""" # (%i,%s) did,owner, 
				# retourne 1: cancelled, <0 erreur		
			cur.callproc(sql,pars)
			log.info("%s(%s)" % (sql,str(pars)))
			res = cursor2.fetchone()
			res = res[0]
				
			if (res ==1): 
				log.info("A draft %i was %s" % (did,"executed" if accept else "refused"))
			elif (res <0): 
				raise ExcSimu(sql+" returned %i") % tuple(pars+[res]) )	

def deposeValue(log,lock,depos,owner):
	quaf = depos.getQualityName(deposit,random.randint(0,settings.NBQUALITY-1))
	qttf = random.randint(100,10000)
	with Cursor(depos) as cur:
		cur.callproc("ob_fadd_account",(owner,quat,qttf))
		res = cur.fetchone()
		if(res[0] <0):
			log.info(str((owner,qlt,qtt)))
			log.warning(errOb.psql.get(res[0],"psql error "+str(res[0])))
	return idStock,quaf,qttf
			
		
			
		    	
if __name__ == '__main__':
	procPool.run(simu)
	#procPool.runProcess(simu)
	# ok

	# createRoles()
			
	
	


