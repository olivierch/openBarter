
MODULE_big = flowf
OBJS = flowm.o yflow.o yflowparse.o yorder.o flowc.o earthrad.o worker_ob.o

EXTENSION = flowf
DATA = flowf--0.1.sql flowf--unpackaged--0.1.sql

REGRESS = testflow_1 testflow_2 testflow_2a testflow_earth 

EXTRA_CLEAN = yflowparse.c yflowscan.c test/results/*.res test/py/*.pyc ../doc/*.pdf ../META.json

PGXS := $(shell pg_config --pgxs)
include $(PGXS)

yflowparse.o: yflowscan.c

yflowparse.c: yflowparse.y

ifdef BISON
	$(BISON) $(BISONFLAGS) -o $@ $<
else
	@$(missing) bison $< $@
endif

yflowscan.c: yflowscan.l
ifdef FLEX
	$(FLEX) $(FLEXFLAGS) -o'$@' $<
else
	@$(missing) flex $< $@
endif

test: installcheck test/py/run.py test/*.sql
	cd test; python py/run.py; cd ..

doc: 
	soffice --invisible --norestore --convert-to pdf --outdir ../doc ../doc/*.odt


