PROJECT = ecql
include erlang.mk

DIALYZER = dialyzer
BASE_DIR = $(shell pwd)
PLT = $(BASE_DIR)/.ecql_dialyzer.plt

ERLC_OPTS = +debug_info

.PHONY: buid_plt dialyzer

build_plt: compile
	dialyzer --build_plt --output_plt $(PLT) --apps erts kernel stdlib ssl ./deps/*/ebin ./ebin

dialyzer: compile
	dialyzer -Wno_return --plt $(PLT) ./ebin

