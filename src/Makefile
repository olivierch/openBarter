
MODULE_big = flowf
#OBJS = tsquery.o ywolf.o earth.o wolfc.o follow.o
OBJS = flowm.o yflow.o yflowparse.o yorder.o flowc.o

EXTENSION = flowf
DATA = flowf--0.7.sql flowf--unpackaged--0.7.sql

REGRESS = testflow_1 testflow_2 testflow_2a testflow_3 testflow_3a testflow_3b testflow_4

EXTRA_CLEAN = yflowparse.c yflowscan.c

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

