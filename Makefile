REBAR=rebar
REBAR_COMPILE=$(REBAR) get-deps compile
PLT=dialyzer\sqlite3.plt

all: compile

compile:
	$(REBAR_COMPILE)

debug:
	$(REBAR_COMPILE) -C rebar.debug.config

tests: compile
	rebar skip-deps=true eunit

clean:
	if exist deps del /Q deps
	if exist ebin del /Q ebin
	if exist priv del /Q priv
	if exist doc\* del /Q doc\*
	if exist .eunit del /Q .eunit
	if exist c_src\*.o del /Q c_src\*.o
	if exist dialyzer del /Q dialyzer
	if exist sqlite3.* del /Q sqlite3.*

docs: compile
	rebar doc

static: compile
	@if not exist $(PLT) \
		(mkdir dialyzer & dialyzer --build_plt --apps kernel stdlib erts --output_plt $(PLT)); \
	else \
		(dialyzer --plt $(PLT) -r ebin)

cross_compile: clean
	$(REBAR_COMPILE) -C rebar.cross_compile.config
