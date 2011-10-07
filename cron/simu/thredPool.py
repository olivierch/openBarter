#!/usr/bin/python
import threading,Queue,time,sys

class PoolT():
	def __init__(self):
		self.qin = Queue.Queue()
		self.qout = Queue.Queue()
		self.qerr = Queue.Queue()
		self.pool = []
		
	def report_error(self):
		self.qerr.put(sys.execinfo()[:2])
		
	def get_all_from_queue(self,q):
		try:
			while True:
				yield q.get_nowait()
		except Queue.Empty:
			raise StopIteration
			
	def do_work_from_queue(self):
		while True:
			command,item = self.qin.get()
			if command == 'stop':
				break
			try:
				if command == 'process':
					result = 'new'+item
				else:
					raise ValueError, 'Unknown command %r' % command
			except:
				self.report_error()
			else:
				self.qout.put(result)
	
	def start_thread_pool(self,number_of_thread=5,daemon=True):
		for i in range(number_of_thread):
			newt = threading.Thread(target = self.do_work_from_queue())
			newt.setDaemon(daemon)
			self.pool.append(newt)
			newt.start()
			
	def request_work(self,data,command='process'):
		self.qin.put((command,data))
		
	def get_result(self):
		return self.qout.get()
	
	def show_all_results(self):
		for result in self.get_all_result_from_queue(self.qout):
			print 'result:',result
	
	def show_all_errors(self):
		for etyp,err in self.get_all_result_from_queue(self.qerr):
			print 'error:',etyp,err	
	
	def stop_thread_pool(self):
		for i in range(len(self.pool)):
			self.request_work(None,'stop')
		for existing in self.pool:
			existing.join()
		del self.pool[:]
		
if(__name__ == "__main__"):
	pool = PoolT()
	for s in ["_aa","_bb","_cc","_dd","_ee"]:
		pool.request_work(s)
	pool.start_thread_pool()
	pool.stop_thread_pool()
	pool.show_all_result()
	pool.show_all_errors()		
	
