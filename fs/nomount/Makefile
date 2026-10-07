# Makefile for NoMount

# This source is vendored here, so git would count the parent kernel history.
# Pin the commit count from the recorded upstream revision instead.
NOMOUNT_COMMITS := 500
ifneq ($(NOMOUNT_COMMITS),)
ccflags-y += -DNOMOUNT_COMMIT_COUNT=\"$(NOMOUNT_COMMITS)\"
endif

obj-$(CONFIG_NOMOUNT) += nomount.o
ccflags-y += -std=gnu11 -Wno-declaration-after-statement
