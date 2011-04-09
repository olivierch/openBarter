#!/usr/bin/python
# -*- coding: utf8 -*-
import daemon
import logger
from write_load_path import write_path
import settings
import db
import random	# random.randint(a,b) gives N such as a<=N<=b
from contextlib import closing
import os,sys
import errOb

#########################################################

NBQUALITY = 100
NBOWNER = 1000

#########################################################
# tools
def getDictsFromCursor(cursor):
	""" usage:
	for d in getDictsFromCursor(cursor):
		print d
	"""
	while True:
		nextRow = cursor.fetchone()
		if not nextRow: break
		d = {}
		for (i,coldesc) in enumerate(cursor.description):
			d[coldesc[0]] = nextRow[i]
		yield d


def getQualitySufName(i):
	return 'qual'+str(i+1)

def getQualityName(i):
	return settings.DATABASE_USER+'>'+getQualitySufName(i)
	
	
def getOwnerName(i):
	return 'owner'+str(i+1)
	
def exitError(log,msg,ret_code=-1):
	log.error("Exit after on:")
	log.error("\t%s with the following stack:" % msg,exc_info=True)
	#type, value, traceback = sys.exc_info()
	#log.error(traceback.format_exec())
	log.error("# END ################################################")
	os._exit(ret_code)
	
############################################################	

def clear_base(conn,log):
	file_name = os.path.join(settings.PGSQLOBDIR,'getdrafttest1.sql')
	with open(file_name, 'r') as f:
		sql_init = f.read()
		f.close()
	# with closing(conn.cursor()) as cursor:
	with db.Cursor(conn,log) as cursor:
		cursor.executemany(sql_init,((),))
	log.debug('most tables truncated')

def add_qualities(conn,log):
	# with closing(conn.cursor()) as cursor:
	with db.Cursor(conn,log) as cursor:
		for i in range(NBQUALITY):
			cursor.callproc("ob_fcreate_quality",(getQualitySufName(i),))
	log.debug("%i qualities added" % NBQUALITY)

def add_owners(conn,log):
	""" We allocate to each owner a quantity 1000 of a random quality"""
	with db.Cursor(conn,log) as cursor:
		for i in range(NBOWNER):
			qlt = getQualityName(random.randint(0,NBQUALITY-1))
			qtt = 1000
			owner = getOwnerName(i)
			cursor.callproc("ob_fadd_account",(owner,qlt,qtt))
			res = cursor.fetchone()
			if(res[0] <0):
				log.info(str((owner,qlt,qtt)))
				log.warning(errOb.psql.get(res[0],"psql error "+str(res[0])))
	log.debug("%i owners added" % NBOWNER)

def statMarket(conn,log):
	sql = 'SELECT * from ob_fstats()'
	with closing(conn.cursor()) as cursor:
		cursor.execute(sql)
		for d in getDictsFromCursor(cursor):
			for k,v in d.iteritems():
				if k in ('unbalanced_qualities','corrupted_draft','corrupted_stock_s','corrupted_stock_a'):
					if v!=0:
						exitError(log,'ob_fstats().%s = %i',k,v)
	# log.info('statMarket Ok')
	
def lirePrix(conn,log,natr,natf):
	# natr,natf are quality id
	# omegaLu,fluxLu = lirePrix(conn,log,natr,natf)
	prices = []
	with db.Cursor(conn,log) as cursor:
		args = [0,1.0,natr,natf]
		# log.info('ob_getdraft_get(%s)' % str(args))
		cursor.callproc('ob_getdraft_get',args)
		res = cursor.fetchall()
		for did,cix,nbsource,nbnoeud,cflags,bid,sid,wid,fluxarrondi,flags,ret_algo,versionsg in res:
			if(ret_algo < 0):
				raise Exception('%i = ob_getdraft_get(%s)' % (ret_algo,str(args)))
			#log.debug(str([did,cix,nbsource,nbnoeud,cflags,bid,sid,wid,fluxarrondi,flags,ret_algo,versionsg]))
			if(cix == 0): pr = fluxarrondi
			elif(cix == nbnoeud -1): 
				omega = float(fluxarrondi)/float(pr)
				log.debug('dans lirePrix '+str([omega,fluxarrondi]))
				prices.append([omega,fluxarrondi])
	#log.debug(str(prices))
	if(len(prices) != 0): 
		omegaLu,fluxLu = prices[0]
	else:
		omegaLu,fluxLu = 1.,0
	#log.debug(str((omegaLu,fluxLu)))
	return omegaLu,fluxLu
	
def insertBid(conn,log,owner,natf,qttf,qttr,natr):
	# offre sur la base du prix avec omega, natr,natf,qttf
	# usage: insertBid(conn,log,natf,qttf,qttr,natr)
	with db.Cursor(conn,log) as cursor:
		# nb_draft int8 = ob_finsert_bid(_owner text,_qualityprovided text,qttprovided int8,_qttrequired int8,_qualityrequired text)
		# omega = qttf/qttr => qttr = qttf/omega
		sql,pars = 'ob_finsert_bid',[owner,natf,qttf,qttr,natr]
		log.info( sql+str(pars))
		cursor.callproc(sql,pars)
		res = cursor.fetchone()
		res = res[0]
		if res < 0:
			exitError(log,(sql+"(%s,%s,%i,%i,%s) returned %i") % tuple(pars+[res]))
		elif res > 0:
			log.info('%i draft created',res)
	return 
	
def insertSbib(conn,log,owner,bidId,qttf,qttr,natr):
	""" inserts a bid with ob_finsert_bid
	"""
	with db.Cursor(conn,log) as cursor:
		# nb_draft int8 = ob_finsert_sbid(bid_id int8,_qttrequired int8,_qualityrequired text)
		# omega = qttf/qttr => qttr = qttf/omega
		sql,pars = 'ob_finsert_sbid',[bidId,qttf,qttr,natr]
		cursor.callproc(sql,pars)
		res = cursor.fetchone()
		res = res[0]
		if res < 0:
			exitError(log,(sql+"(%i,%i,%i) returned %i") % tuple(pars+[res]))
		elif res > 0:
			log.info('%i draft created',res)
	return 

def getRanBidId(conn,log,owner):
	""" returns id,natfId,natf for a random noeud of owner
	"""
	l = 0
	
	with closing(conn.cursor()) as cursor:
		cursor.execute("""SELECT n.id,q.id,q.name,q.qtt from ob_tnoeud n
						inner join ob_towner o on (o.id=n.own) 
						inner join ob_tquality q on (q.id=n.nf)
						where o.name=%s """,[owner])
		res = [e for e in cursor]
		l = len(res)
		
	if(l == 0): return (None,None,None,None)
	return res[random.randint(0,l-1)] 
		
def keepReserve(conn,log,owner):
	""" the oldest bid is removed
	"""
	with closing(conn.cursor()) as cursor:
		cursor.execute("""SELECT n.id from ob_tnoeud n
			inner join ob_towner o on (o.id=n.own)
			where o.name=%s  order by n.created asc
			limit 1 """,[owner])	
		res = cursor.fetchall()
		if(len(res) == 0):
			return	
		cursor.callproc("ob_fdelete_bid",res[0])
	return
	

def traiteOwner(conn,log,owner):
	
	def getRandQuality(natfId):
		# natr,natrId = getRandQuality(natfId)
		while True:
			natrId = random.randint(1,NBQUALITY) 
			natr = getQualityName(natrId - 1)	
			if natrId != natfId: return natr,natrId
	
	def getFromPrix(omegaLu,qttf):
		k,teta = 2.,2.	# esperance k*teta
		omega = random.gammavariate(k,teta)*omegaLu/k*teta
		qttr = int(qttf/omega)
		return max(1,qttr)
	
	
	def ob_draft_of_own(cursor,owner):
		cursor.execute("select * from ob_vdraft where owner=%s",[owner])
		return cursor.fetchall()

	
	# For drafts where he is a partner
	with db.Cursor(conn,log) as cursor:
		resu = ob_draft_of_own(cursor,owner)
		for res in resu:
			did,status,owner,cntcommit,flags,created = res
				
			#accepted 9 times on 10, else refused
			accept = not( random.randint(0,9)==0)
			
			res = -1
			with closing(conn.cursor()) as cursor2:
				pars = [did,owner]
				if(accept):
					sql2 = """ob_faccept_draft""" # (%i,%s) did,owner, 
					# retourne 0: draft, 1: execute, <0 erreur
				else: #refus
					sql2 = """ob_frefuse_draft""" # (%i,%s) did,owner, 
					# retourne 1: cancelled, <0 erreur		
				cursor2.callproc(sql2,pars)
				res = cursor2.fetchone()
				res = res[0]
				
			if (res ==1): 
				log.info("A draft %i was %s" % (did,"accepted" if accept else "refused"))
			elif (res <0): 
				exitError(log,(sql2+" returned %i") % tuple(pars+[res]) )
	
	# remove oldest bid
	keepReserve(conn,log,owner)

	# what he owns 
	sql = """SELECT q.id as qualityid,q.name as quality,sum(s.qtt) as qtt 
		from ob_tstock s 
		inner join ob_tquality q on (q.id=s.nf)
		inner join ob_towner o on (s.own=o.id)
		where o.name = %s and s.type='A' group by q.id,q.name """
	with closing(conn.cursor()) as cursor:
		# log.info(cursor.mogrify(sql,[owner]))
		cursor.execute(sql,[owner])
		res = cursor.fetchall()
		dOwned ={}
		sOwned = []
		for qualityid,quality,qtt in res:
			dOwned[quality] = qtt
			sOwned.append({'qualityid':qualityid,'quality':quality,'qtt':qtt})
		nbOwned =len(sOwned)
		
	if(nbOwned <1):		
		log.warning('traiteOwner terminated, %s does nt own anything!' % owner)
		return

	
	# makes a bid
	makeSbid = (random.randint(0,5)==0) # 1 fois sur 5
	
	bidId,natfId,natf,qttf = getRanBidId(conn,log,owner)
	
	if(bidId and makeSbid):
		natr,natrId = getRandQuality(natfId)
		omegaLu,fluxLu = lirePrix(conn,log,natrId,natfId)
		qttr = getFromPrix(omegaLu,qttf)
		insertSbib(conn,log,owner,bidId,qttf,qttr,natr)
	else:
		# chooses a quality owned
		valf = sOwned[random.randint(0,nbOwned-1) if nbOwned >1 else 0 ] # valf={'quality':..,'qtt': .. }
		# takes a part of it
		natfId = valf['qualityid']
		natf = valf['quality']
		if(valf['qtt'] >1):
			qttf = random.randint(1,valf['qtt'])
		
			# choisit une qualité au hasard != natfId
			natr,natrId = getRandQuality(natfId)
		
			omegaLu,fluxLu = lirePrix(conn,log,natrId,natfId) # http://fr.wikipedia.org/wiki/Distribution_Gamma
			qttr = getFromPrix(omegaLu,qttf)

			insertBid(conn,log,owner,natf,qttf,qttr,natr)

	# log.info('traiteOwner terminated')
	return
	
def loopSimu(conn,log):
	"""  chooses a random owner """
	while True:
		owner = getOwnerName(random.randint(1,NBOWNER)-1)
		traiteOwner(conn,log,owner)
		statMarket(conn,log)

def simu():
	logger.start("simu")
	log = logger.getLogger(name="simu")
	random.seed(0) #for reproductibility of playings
	try:
		with db.Connection(log) as conn:
			clear_base(conn,log)
			add_qualities(conn,log)
			add_owners(conn,log)
			loopSimu(conn,log)
		log.info("Db connection closed")
		
	except Exception,e:
		exitError(log,"Abnormal termination")

if __name__ == "__main__":
	simu()
