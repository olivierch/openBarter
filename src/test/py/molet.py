# -*- coding: utf-8 -*-
class MoletException(Exception):
    pass
 
'''---------------------------------------------------------------------------
envoi des mails
---------------------------------------------------------------------------'''
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText 

def sendMail(subject,body,recipients,smtpServer,
    smtpSender,smtpPort,smtpPassword,smtpLogin):
    
    ''' Sends an e-mail to the specified recipients 
    returns False when failed'''

    if(len(recipients)==0): 
        raise MoletException("No recipients was found for the message")
        return False

    msg = MIMEMultipart("alternative")
    msg.set_charset("utf-8")

    msg["Subject"] = subject
    msg["From"] = smtpSender
    msg["To"] = ','.join(recipients)

    try:
        _uniBody = unicode(body,'utf-8','replace') if isinstance(body,str) else body
        _encBody = _uniBody.encode('utf-8')

        part1 = MIMEText(_encBody,'html',_charset='utf-8')
        # possible UnicodeDecodeError before this

        msg.attach(part1)
         
        session = smtplib.SMTP(smtpServer, smtpPort)
         
        session.ehlo()
        session.starttls()
        session.ehlo
        session.login(smtpLogin, smtpPassword)
        # print msg.as_string()
        session.sendmail(smtpSender, recipients, msg.as_string())
        session.quit()
        return True

    except Exception,e:
        raise MoletException('The message "%s" could not be sent.' % subject )
        return False	


###########################################################################
# gestion de fichiers et de répertoires

import os,shutil
def removeFile(f,ignoreWarning = False):
    """ removes a file """
    try:
        os.remove(f) 
        return True   
    except OSError,e:
        if e.errno!=2:
            raise e
        if not ignoreWarning:
            raise MoletException("path %s could not be removed" % f) 
        return False
        
def removeTree(path,ignoreWarning = False):        
    try:
        shutil.rmtree(path)
        return True
    except OSError,e:
        if e.errno!=2:
            raise e
        if not ignoreWarning:
            raise MoletException("directory %s could not be removed" % path)
        return False
        
def mkdir(path,mode = 0755,ignoreWarning = False):
    try:
        os.mkdir(path,mode)
        return True
    except OSError,e:
        if e.errno!=17: # exists
            raise e
        if not ignoreWarning:
            raise MoletException("directory %s exists" % path)
        return False
        
def readIntFile(f):
    try:
        if(os.path.exists(f)):
            with open(f,'r') as f:
                r = f.readline()
                i = int(r)
                return i
        else:
            return None
    except ValueError,e:
        return None 
        
def writeIntFile(lfile,i):
    with open(lfile,'w') as f:
        f.write('%d\n' % i)  
         
###########################################################################
# driver postgres

import psycopg2
import psycopg2.extras
import psycopg2.extensions
  
class DbCursor(object):
    '''
    with statement used to wrap a transaction. The transaction and cursor type 
    is defined by DbData object. The transaction is commited by the wrapper.
    Several cursors can be opened with the connection. 
    usage:
    dbData = DbData(dbBO,dic=True,autocommit=True)
    
    with DbCursor(dbData) as cur:
        ... (always close con and cur)
        
    '''
    def __init__(self,dbData, dic = False,exit = False):
        self.dbData = dbData
        self.cur = None
        self.dic = dic
        self.exit = exit

    def __enter__(self):
        self.cur = self.dbData.getCursor(dic = self.dic)
        return self.cur
        
    def __exit__(self, type, value, traceback):
        exit = self.exit

        if self.cur:
            self.cur.close()

        if type is None:
            self.dbData.commit()
            exit = True
        else:
            self.dbData.rollback()
            self.dbData.exception(value,msg='An exception occured while using the cursor')
            #return False  # on propage l'exception
        return exit

class DbData(object):
    ''' DbData(db com.srvob_conf.DbInti(),dic = False,autocommit = True)
    db defines DSN. 
    '''
    def __init__(self,db,autocommit = True,login=None):
        self.db = db
        self.aut = autocommit
        self.login = login
        
        self.con=psycopg2.connect(self.getDSN())
        
        if self.aut:
            self.con.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)

    def getDSN(self):
        if self.login:
            _login = self.login
        else:
            _login = self.db.login
        return "dbname='%s' user='%s' password='%s' host='%s' port='%s'" % (self.db.name,_login,self.db.password,self.db.host,self.db.port)
        
    def getCursor(self,dic=False):
        if dic:
            cur = self.con.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        else:
            cur = self.con.cursor()
        return cur
    
    def commit(self):
        if self.aut:
            # raise MoletException("Commit called while autocommit") 
            return
        self.con.commit()

    def rollback(self):
        if self.aut:
            # raise MoletException("Rollback called while autocommit")
            return
        try:
            self.con.rollback()    
        except psycopg2.InterfaceError,e:
            self.exception(e,msg="Attempt to rollback while the connection were closed")

    def exception(self,e,msg = None):
        if msg:
            print e
            raise MoletException(msg)
        else:
            raise e

    def close(self):
        self.con.close()
        

'''---------------------------------------------------------------------------
divers
---------------------------------------------------------------------------'''
import datetime
def utcNow():
    return datetime.datetime.utcnow()

import os
import pwd
import grp

def get_username():
    return pwd.getpwuid( os.getuid() )[ 0 ]

def get_usergroup(_file):
    stat_info = os.stat(_file)
    uid = stat_info.st_uid
    gid = stat_info.st_gid
    user = pwd.getpwuid(uid)[0]
    group = grp.getgrgid(gid)[0]
    return (user, group)

