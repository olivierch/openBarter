#!/usr/bin/python
# -*- coding: utf8 -*-
"""
from 
https://google-developers.appspot.com/chart/interactive/docs/gallery/linechart
"""
import os
import csv
import cliquid
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

        var chart = new google.visualization.LineChart(document.getElementById('chart_div'));
        chart.draw(data, options);
      }
    </script>
  </head>
  <body>
    <div id="chart_div" style="width: 900px; height: 500px;"></div>
  </body>
</html>
"""
PATH_DATA = "/home/olivier/Bureau/ob92/simu/liquid/test"
#PATH_DATA = cliquid.PATH_DATA
def makeHtml(title,arr,unite):
    fn = os.path.join(PATH_DATA,'result_'+title+'.html')
    with open(fn,'w') as f:
        f.write(visplot_tmp % (arr,title,'Volume of the order book',unite))


        
def makeVis(prefix):

    fils = []
    for root,dirs,files in os.walk(PATH_DATA):
        for fil in files:
            if(not fil.endswith('.txt')):
                continue
            if(fil.startswith(prefix)):
                fils.append(os.path.join(root,fil))
    for clef,valeurs in {'delay':(1,'seconds'),'liquidity':(2,'%'),'nbcycle':(3,'nbcycle'),'gain':(4,'%')}.iteritems():
        indice,unite = valeurs
        resus = {}          
        for fil in fils:
            resu = []
            with open(fil,'rb') as f:
                reader = csv.reader(f, delimiter=';', quotechar='|')
                for lin in reader:
                    l= [lin[0],lin[indice]]
                    resu.append(l)
            nam = fil.split(prefix)
            nam = nam[1].split('.txt')
            nam = nam[0]
            resus[nam] = resu
           
        keys = resus.keys() 
        titles = [[clef]+keys,]

        mat = []
        cnt = len(resu)
        begin = True
        for k in keys:
            if(begin):
                begin = False;
                for i in range(cnt):
                    mat.append([resus[k][i][0]])
            for i in range(cnt):
                lin = mat[i]
                lin.append(float(resus[k][i][1]))
                mat[i] = lin   
        makeHtml(clef,titles+mat,unite)
            

if __name__ == "__main__":
	makeVis('result_')        
    
    
        
    
            
        
        
        

    
