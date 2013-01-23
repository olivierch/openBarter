
MODULE_big = flow
#OBJS = tsquery.o ywolf.o earth.o wolfc.o follow.o
OBJS = flowm.o yflow.o yflowparse.o yorder.o flowc.o

EXTENSION = flow
DATA = flow--1.0.sql flow--unpackaged--1.0.sql

#REGRESS = testwolf_1 testwolf_2

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

