
The model is based on a graph where order is a node and arc represent possible relation between nodes.
The insertion mechanism is done so that the minimum number of arcs of cycles is obCMAXCYCLE+1. 
Cycles having less than obCMAXCYCLE should never occur, but it is not impossible. In case of occurence, 
algorithms are built in such a way that they do not loop indefinitely, but computing workload increase substantially.
For stability reasons, a cycle detection and removal process is implemented in the model.

finsertorder_int(pivot)
	insert order pivot
	_lpivots = [pivot]
	for _pivot in _lpivots:
		ftraversal(_pivot,pivotsFound)
		_lpivots := _lpivots union pivotFound
		
ftraversal(pivot,pivotsFound)
	backward_traversal on obCMAXCYCLE
	forward_traversal on obCMAXCYCLE+1
		if for an order, path length reaches obCMAXCYCLE+1, this order is contained in a cycle.
		it is added to the set pivotsFound 
	while pivot not empty:
		bellman_ford
		execute_flow(best_flow)
		forward_traversal on obCMAXCYCLE
		
bellman_ford
	If a cycle is found (attempt to add an order to a path that include it), the path is unchanged.
		this allows path formation even if one of it's orders creates a cycle

execute_flow
	creates movements and reduce orders when the flow is not refused
	otherwise adds a refused relation. In this case orders are not redused TODO

a relation exists between two orders X and Y if:
X.np = Y.nr AND NOT (Y.id=ANY(X.refused))	
	
Model
*****
The model is built by executing init.sql,order.sql,mvt.sql,admin.sql,user.sql
init.sql
	creates a schema,
	includes table definitions,
	
order.sql
	flow definition, 
	all necessary function for order insertion,
	fspendquota and fconnect are dummy functions,
	
mvt.sql
	functions related to mvt management,
	
admin.sql
	includes all necessary functions for administration of the market,
	
user.sql 
	includes all necessary functions for user and role management,
	replaces fspendquota and fconnect,
	all grants are performed.

stat.sql
	functions related to model statistics.
	
Tests:
actuellement:
model2.sql
	init.sql
	order.sql
	stat.sql
flow_0.sql
t.sql	

TODO:
	pb sur flow_orderaccepted(__tmp,int)
	test:
		\i sql/model2.sql
		simu/simu300.py 166


		
	
	
