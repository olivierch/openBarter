#!/usr/bin/env python
import sys,os,time
import consts
import signal

def daemonize(stdin='/dev/null',stdout='/dev/null',stderr='/dev/null'):
	try:
		pid = os.fork()
		if pid > 0:
			sys.stdout.write("fork with:\nstdin=%s\nstdout=%s\nstderr=%s\n" % (stdin,stdout,stderr))
			sys.exit(0) #exit the first parent.
	except OSError, e:
		sys.stderr.write("fork #1 failed: (%d) %s\n" % (e.errno,e.stderror))
		sys.exit(1)
	#decouple fromparent environment
	os.chdir("/")
	os.umask(0)
	os.setsid()
	#perform second fork.
	try:
		pid = os.fork()
		if pid > 0:
			sys.exit(0) # exit second parent.
	except OSError, e:
		sys.stderr.write("fork #2 failed: (%d) %s\n" % (e.errno,e.strerror))
	#The process is daemonized, rederiect std file descriptor.
	for f in sys.stdout,sys.stderr: f.flush()
	si = file(stdin,'r')
	so = file(stdout,'a+')
	se = file(stderr,'a+',0)
	os.dup2(si.fileno(), sys.stdin.fileno())
	os.dup2(so.fileno(), sys.stdout.fileno())
	os.dup2(se.fileno(), sys.stderr.fileno())
	

def sendMail(subject,body):
	import smtplib
	"Sends an e-mail to the specified recipient."
	 
	body = "" + body + ""
	
	headers = ["From: " + consts.SMTP_SENDER,
		       "Subject: " + subject,
		       "To: " + consts.SMTP_RECIPIENTS[0],
		       "MIME-Version: 1.0",
		       "Content-Type: text/html"]
	headers = "\r\n".join(headers)
	 
	session = smtplib.SMTP(consts.SMTP_SERVER, consts.SMTP_PORT)
	 
	session.ehlo()
	session.starttls()
	session.ehlo
	session.login(consts.SMTP_SENDER, consts.SMTP_PASSWORD)
	 
	session.sendmail(consts.SMTP_SENDER, consts.SMTP_RECIPIENTS, headers + "\r\n\r\n" + body)
	session.quit()
	
	
def send_error(title,msg,dosendmail):
	""" returns False when sendmail caused problem
	"""
	_msg = '[%s] %s\n'% (time.ctime(),msg)
	sys.stderr.write(_msg)
	if(dosendmail):
		try:
			sendMail(consts.APP_NAME + ' - '+title,_msg)
			return True
		except Exception,e:
			return False
	else:
		return True
	
	
def _example_main():
	''' Example '''
	import time
	sys.stdout.write('Daemon started with pid %d\n' % os.getpid())
	sys.stdout.write('Daemon stdout output\n')
	sys.stderr.write('Daemon stderr output\n')
	c = 0
	while True:
		sys.stdout.write('%d: %s\n' % (c,time.ctime()))
		sys.stdout.flush()
		c = c+1
		time.sleep(1)
		
if __name__ == "__main__":
	daemonize('dev/null','tmp/daemon.log','tmp/daemon.log')
	_example_main()

		
