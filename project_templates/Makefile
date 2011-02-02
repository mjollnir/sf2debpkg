all: test build

clean:

build:
	packaging/maketime.pl
debug:

test:
ifneq ($(wildcard app/*/config/dynamic.yml),)
	echo "Sorry, you should not run this in your working directory" && false
endif


.PHONY: test build

.SILENT: test
