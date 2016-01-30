PROJECT = ecql
DEPS = gen_logger
dep_gen_logger = git git://github.com/emqtt/gen_logger.git
include erlang.mk

DIALYZER = dialyzer
BASE_DIR = $(shell pwd)
PLT = $(BASE_DIR)/.ecql_dialyzer.plt

.PHONY: buid_plt dialyzer

build_plt: compile
	dialyzer --build_plt --output_plt $(PLT) --apps erts kernel stdlib ssl ./deps/*/ebin ./ebin

dialyzer: compile
	dialyzer -Wno_return --plt $(PLT) ./ebin

