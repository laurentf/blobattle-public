TOOLS := docker compose --profile tools run --rm --no-deps blobattle-tools
CONFORMANCE := docker compose -p blobattle-conformance

.PHONY: tools test lint fmt perf sweep trig bench vectors conformance up down harness web journey serve site https tunnel tunnel-down

tools:
	docker compose --profile tools build blobattle-tools

test:
	$(TOOLS) sh tools/run-specs.sh default

perf:
	$(TOOLS) sh tools/run-specs.sh perf

sweep:
	$(TOOLS) sh tools/run-specs.sh sweep luajit

lint:
	$(TOOLS) sh -c 'luacheck . && stylua --check . && stylua --check --glob "**/*.script" --glob "**/*.gui_script" client'

fmt:
	$(TOOLS) sh -c 'stylua . && stylua --glob "**/*.script" --glob "**/*.gui_script" client'

trig:
	$(TOOLS) luajit tools/gen_trig.lua shared/sim/trig.lua

N ?= 200

bench:
	$(TOOLS) luajit tools/bench/run.lua $(N)

vectors:
	$(TOOLS) sh -c 'luajit tools/conformance/record.lua duel 1240 2 2 2400 && luajit tools/conformance/record.lua brawl 4242 8 6 2400 && luajit tools/conformance/record.lua grenades 777 3 3 2400 && luajit tools/conformance/record.lua quake 10 2 2 4600 easy && luajit tools/conformance/record.lua dynamite 42 2 2 1500 hard 2 && luajit tools/conformance/record.lua crates 105 3 3 6000 medium "" crates && stylua spec/vectors'

conformance:
	$(CONFORMANCE) --profile conformance up -d --wait blobattle-check-nakama && $(CONFORMANCE) --profile tools run --rm --no-deps blobattle-tools sh tools/conformance/check.sh; status=$$?; $(CONFORMANCE) --profile conformance down -v; exit $$status

up:
	docker compose up -d --wait blobattle-nakama && $(TOOLS) sh tools/server/check-up.sh

down:
	docker compose --profile site --profile https --profile tunnel down

harness:
	docker compose up -d --wait blobattle-postgres && docker compose up -d --wait --force-recreate --no-deps blobattle-nakama && $(TOOLS) sh tools/harness/run.sh $(S)

web:
	$(TOOLS) sh tools/web/build.sh

journey: web
	[ "$(J)" = offline ] || { docker compose up -d --wait blobattle-postgres && docker compose up -d --wait --force-recreate --no-deps blobattle-nakama; }
	$(TOOLS) sh tools/journey/run.sh $(J)

serve:
	docker compose --profile tools run --rm --no-deps -p 5373:5373 blobattle-tools node tools/web/serve.mjs out/web/Blobattle 5373 0.0.0.0

site:
	docker compose --profile site up -d --wait blobattle-nakama blobattle-web

https:
	docker compose --profile https up -d --wait blobattle-nakama blobattle-web blobattle-caddy

tunnel:
	docker compose --profile tunnel up -d --wait blobattle-nakama blobattle-web && docker compose --profile tunnel up -d blobattle-cloudflared

tunnel-down:
	docker compose --profile tunnel stop blobattle-cloudflared blobattle-web

