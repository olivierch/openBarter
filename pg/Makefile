#-------------------------------------------------------------------------
#
# oenbarter Makefile
#
# $PostgreSQL$
# 
#-------------------------------------------------------------------------

MODULE_big = openbarter
OBJS	= iternoeud.o utils.o dbe.o chemin.o flux.o getdraft.o point.o  appel.o balance.o
SHLIB_LINK +=  $(filter -l%, $(LIBS)) -ldb -lpq -lpthread #  -lpthread  -print-search-dirs
# CPPFLAGS += -I/home/olivier/project/include
# DATA_built = openbarter.sql 
# DATA = uninstall_openbarter.sql 
# DOCS = README.openbarter

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = contrib/openBarter/pg
top_builddir = ../../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif
