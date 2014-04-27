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
        %s
      }
    </script>
  </head>
  <body>
<table>
<tr>
<td><div id="chart_delay" style="width: 450px; height: 250px;"></div></td>
<td><div id="chart_fluidity" style="width: 450px; height: 250px;"></div></td>
</tr>
<tr>
<td><div id="chart_nbcycle" style="width: 450px; height: 250px;"></div></td>
<td><div id="chart_gain" style="width: 450px; height: 250px;"></div></td>
</tr>
</table>
  </body>
</html>
"""
visplot_graph ="""
        var data = google.visualization.arrayToDataTable(%s);

        var options = {
          title: '%s',
          hAxis: {title: 'Volume of the order book'},
          legend: {position: 'out'},
          vAxes:[{title:'%s'}]
        };

        var chart = new google.visualization.LineChart(document.getElementById('chart_%s'));
        chart.draw(data, options);
"""

PATH_DATA = cliquid.PATH_DATA
def makeHtml(content):
    fn = os.path.join(PATH_DATA,'result.html')
    with open(fn,'w') as f:
        f.write(visplot_tmp % (content,))

def makeGraph(title,arr,unite):
    return (visplot_graph % (arr,title,unite,title))
       
def makeVis(prefix):

    fils = []
    for root,dirs,files in os.walk(PATH_DATA):
        for fil in files:
            if(not fil.endswith('.txt')):
                continue
            if(fil.startswith(prefix)):
                fils.append(os.path.join(root,fil))
                
    content = []
    for clef,valeurs in {'delay':(1,'seconds'),'fluidity':(2,'%'),'nbcycle':(3,'nbcycle'),'gain':(4,'%')}.iteritems():
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
        content.append(makeGraph(clef,titles+mat,unite))
    makeHtml('\n'.join(content))
            

if __name__ == "__main__":
	makeVis('result_')        
    
    
        
    
            
        
        
        

    
