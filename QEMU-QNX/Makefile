# Makefile — QNX x86_64 cross-compile for wolfBoot QEMU demo apps
#
# Usage:
#   source ~/qnx800/qnxsdp-env.sh
#   make                      # build in current directory
#   make OUTDIR=build/        # build into build/

QNX_HOST ?= $(HOME)/qnx800/host/linux/x86_64
CC = $(QNX_HOST)/usr/bin/qcc -Vgcc_ntox86_64

CFLAGS  = -Wall -g
OUTDIR ?= .

APPS = $(OUTDIR)/app_v1 $(OUTDIR)/app_v2

all: $(OUTDIR) $(APPS)

$(OUTDIR):
	mkdir -p $(OUTDIR)

$(OUTDIR)/app_v1: app_v1.c update_helper.c update_helper.h
	$(CC) $(CFLAGS) -o $@ app_v1.c update_helper.c

$(OUTDIR)/app_v2: app_v2.c update_helper.h
	$(CC) $(CFLAGS) -o $@ app_v2.c

clean:
	rm -f $(OUTDIR)/app_v1 $(OUTDIR)/app_v2

.PHONY: all clean
