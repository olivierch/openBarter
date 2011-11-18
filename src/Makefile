# contrib/flow/Makefile

MODULE_big = flow
OBJS= flow.o flowparse.o flowc.o

EXTENSION = flow
DATA = flow--1.0.sql flow--unpackaged--1.0.sql

REGRESS = flow_1 flow_2 flow_3 flow_4

EXTRA_CLEAN = y.tab.c y.tab.h

SHLIB_LINK += $(filter -lm, $(LIBS))

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
PG91 = $shell $(PG_CONFIG) --version | grep -qE " 8\.| 9\.0" && echo no || echo yes 
include $(PGXS)
else
subdir = contrib/openbarter/src
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif


# flowscan is compiled as part of flowparse
flowparse.o: flowscan.c

flowparse.c: flowparse.y
ifdef BISON
	$(BISON) $(BISONFLAGS) -o $@ $<
else
	@$(missing) bison $< $@
endif

flowscan.c: flowscan.l
ifdef FLEX
	$(FLEX) $(FLEXFLAGS) -o'$@' $<
else
	@$(missing) flex $< $@
endif

distprep: flowparse.c flowscan.c

maintainer-clean:
	rm -f flowparse.c flowscan.c

	
