.PHONY: test edoc dialyzer

ERL=erl
BASE_DIR = $(shell pwd)
BEAMDIR  = $(BASE_DIR)/deps/*/ebin $(BASE_DIR)/ebin
REBAR    = $(BASE_DIR)/rebar
DIALYZER = dialyzer

#update-deps 
all: get-deps compile xref

get-deps:
	@$(REBAR) get-deps

update-deps:
	@$(REBAR) update-deps

compile:
	@$(REBAR) compile

xref:
	@$(REBAR) xref skip_deps=true

clean:
	@$(REBAR) clean

test:
	@$(REBAR) skip_deps=true eunit

edoc:
	@$(REBAR) doc

PLT = $(BASE_DIR)/.ecql_dialyzer.plt

build_plt: compile
	dialyzer --build_plt --output_plt $(PLT) --apps erts kernel stdlib ssl ./deps/*/ebin ./ebin

dialyzer: compile
	dialyzer -Wno_return --plt $(PLT) ./ebin

