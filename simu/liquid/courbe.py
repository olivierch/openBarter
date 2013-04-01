#!/usr/bin/python
# -*- coding: utf8 -*-
"""
from 
https://google-developers.appspot.com/chart/interactive/docs/gallery/linechart
"""
import os
import csv

from optparse import OptionParser


visplot_tmp ="""
<html>
  <head>
    <script type="text/javascript" src="https://www.google.com/jsapi"></script>
    <script type="text/javascript">
      google.load("visualization", "1", {packages:["corechart"]});
      google.setOnLoadCallback(drawChart);
      function drawChart() {
        var data = google.visualization.arrayToDataTable(%s);

        var options = {
          title: '%s',
          hAxis: {title: '%s'},
          legend: {position: 'out'},
          vAxes:[{title:'%s'}]
        };

        var chart = new google.visualization.LineChart(document.getElementById('chart_delay'));
        chart.draw(data, options);
      }
    </script>
  </head>
  <body>
<div id="chart_delay" style="width: 900px; height: 500px;"></div>
  </body>
</html>
"""

"""	
def gen(options):
    if(len(options.file)!=0):
        resu = []
        with open(options.file,'rb') as f:
            reader = csv.reader(f, delimiter=';', quotechar='|')
            for lin in reader:
                resu.append([lin[0]]+[float(e) for e in lin[1:]]) 
    else:
        resu = [['delay', 'graph1', 'graph2'], ['30', 0.012323, 0.015663], ['60', 0.012643, 0.01476], ['90', 0.013741, 0.014622], ['120', 0.014367, 0.014718], ['150', 0.01589, 0.014975], ['180', 0.015798, 0.016838], ['210', 0.016057, 0.015998], ['240', 0.016949, 0.015438], ['270', 0.01824, 0.015726], ['300', 0.0184, 0.016685], ['330', 0.019379, 0.017351], ['360', 0.01985, 0.016593], ['390', 0.019374, 0.017763], ['420', 0.020553, 0.018017], ['450', 0.020466, 0.017311], ['480', 0.021077, 0.016781], ['510', 0.021349, 0.017795], ['540', 0.021163, 0.01657], ['570', 0.021364, 0.016717], ['600', 0.021432, 0.016917], ['630', 0.021905, 0.017018], ['660', 0.022211, 0.016012], ['690', 0.023954, 0.016007], ['720', 0.024335, 0.016097], ['750', 0.022068, 0.016192], ['780', 0.022586, 0.016219], ['810', 0.021724, 0.015028], ['840', 0.021108, 0.015701], ['870', 0.02123, 0.015255], ['900', 0.02191, 0.015123]]
    
    print visplot_tmp % (resu,options.title,resu[0][0],options.unit)
    return
"""
def gen(options):
    cols = 4
    rows = 20
    mat = []
    row = ["gain = pow(prod(omega),1/i)"]
    for ind in range(cols):
        row.append("omega=%f" % getom(ind))
    mat.append(row)
    
    for x in range(rows):
        i = x+2
        row = [str(i)]
        for ind in range(cols):
            row.append(getres(i,ind))        
        mat.append(row)
        
    print visplot_tmp % (mat,"titre",mat[0][0],"gain")

def getom(ind):
    r = 1.0 + (1e-2 * ind)
    return r
    
def getres(x,ind):
    Omega = 1.
    for k in range(x):
        Omega = Omega *getom(ind)
    return pow(Omega, 1.0/x)
       
def main():
	usage = """usage: %prog [options]
	            to change config, modify the import in gen.py"""
	parser = OptionParser(usage)
	"""
	parser.add_option("-f","--file",type="string",action="store",dest="file",help="the cvs input file",default="")
	parser.add_option("-t","--title",type="string",action="store",dest="title",help="the title of the graph",default="")
	parser.add_option("-u","--unit",type="string",action="store",dest="unit",help="the nit of the graph",default="")
	"""
	(options, args) = parser.parse_args()
	
	gen(options)

if __name__ == "__main__":
	main()       
    
            
        
        
        

    
