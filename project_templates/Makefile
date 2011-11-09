all: test build

clean:

prepare:
	# remove cache ... not doing this may lead to a failure in some cases where dependencies have changed.
	rm -rf app/*/cache/*
	# if you are using git submodules, you'll want to uncomment the following line:
	#git submodule update --init --recursive
	# if you are using a bin/vendors script to manage third party components, you'll want something like the following line:
	#bin/vendors install --reinstall --deployment

build:
	packaging/maketime.pl
debug:

test:
ifneq ($(wildcard app/*/config/dynamic.yml),)
	echo "Sorry, you should not run this in your working directory" && false
endif


.PHONY: test build

.SILENT: test
