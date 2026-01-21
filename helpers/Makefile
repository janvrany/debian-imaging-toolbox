O ?= .
OUTDIR ?= $(O)
CFLAGS ?= -O2 -Wextra -Wall -Wno-unused-parameter
CROSS ?=
CC = gcc

SOURCES = $(wildcard *.c)
BINARIES =$(patsubst %.c,$(OUTDIR)/%,$(SOURCES))

default: all

all: $(BINARIES)


$(OUTDIR) :
	mkdir -p $@

$(OUTDIR)/%: %.c | $(OUTDIR)
	$(CROSS)$(CC) $(CFLAGS) -static -o $@ $<

clean:
	rm -rf $(BINARIES)