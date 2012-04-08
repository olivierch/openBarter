# contrib/flow/Makefile

MODULE_big = flow
OBJS= yflow.o yflowparse.o yorder.o flowc.o

EXTENSION = flow
DATA = flow--1.0.sql flow--unpackaged--1.0.sql

REGRESS = testflow_1 testflow_2 testflow_3 testflow_4 testflow_5 testflow_6

EXTRA_CLEAN = y.tab.c y.tab.h

# SHLIB_LINK += $(filter -lm, $(LIBS)) `uuid-config --libs`

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
PG91 = $shell $(PG_CONFIG) --version | grep -qE " 8\.| 9\.0" && echo no || echo yes 
include $(PGXS)
else
subdir = contrib/yord/src
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif


# flowscan is compiled as part of flowparse
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

distprep: yflowparse.c yflowscan.c

maintainer-clean:
	rm -f yflowparse.c yflowscan.c

	
