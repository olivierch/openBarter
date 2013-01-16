
MODULE_big = wolf
OBJS = tsquery.o ywolf.o earth.o wolfc.o follow.o

EXTENSION = wolf
DATA = wolf--1.0.sql wolf--unpackaged--1.0.sql

REGRESS = testwolf_1 testwolf_2

PGXS := $(shell pg_config --pgxs)
include $(PGXS)

