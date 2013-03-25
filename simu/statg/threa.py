#!/usr/bin/python
# -*- coding: utf8 -*-

import threading
import logging

####################################################################################
logging.basicConfig(level=logging.DEBUG,
                    format='(%(threadName)-10s) %(message)s',
                    )

class ThreadWithArgs(threading.Thread):

    def __init__(self,func,args=(),name=None):
        threading.Thread.__init__(self, group=None, target=None, name=name,verbose=None)
        self.func = func
        self.args = args
        return

    def run(self):
        # logging.debug('Start')
        self.func(self.args)
        # logging.debug('stop')
        return
