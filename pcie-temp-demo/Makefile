CC ?= cc
CFLAGS ?= -O2 -g -Wall -Wextra -Werror

.PHONY: all clean

all: catapult-bar

catapult-bar: catapult_bar.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	$(RM) catapult-bar
