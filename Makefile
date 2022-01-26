PERL = docker run --rm -w /app -v "$(realpath .):/app" perl:5-slim perl
BASH = docker run --rm bash:5 bash
E =
S = $E $E

update_version:
	$(PERL) -i -p -e 's/^(ENV FLYWAY_VERSION) .*$$/$$1 $(VERSION)/g;' Dockerfile alpine/Dockerfile flyway-azure/alpine/Dockerfile
	$(PERL) -i -p \
		-e 's/`\d+\.\d+\.\d+(?:-beta\d+)?(-alpine)?`/`$(VERSION)$$1`/g;' \
		-e 'my $$version = $$1 if ("$(VERSION)" =~ /(\d+\.\d+)\.\d+/); s/`\d+\.\d+(-alpine)?`/`$$version$$1`/g;' \
		-e 'my $$version = $$1 if ("$(VERSION)" =~ /(\d+)\.\d+\.\d+/); s/`\d+(-alpine)?`/`$$version$$1`/g;' \
		README.md

wait_for_artifacts: URL = https://repo1.maven.org/maven2/org/flywaydb/flyway-commandline/$(VERSION)/
wait_for_artifacts:
	$(info Waiting for artifacts...)
	$(BASH) -c 'until wget -q --spider --user-agent="Mozilla" $(URL) &> /dev/null; do sleep 2; done'

build:
	-docker buildx rm multi_arch_builder
	docker buildx create --name multi_arch_builder --driver-opt network=bridge --use
	docker buildx build $(DOCKER_BUILD_ARGS) --platform linux/arm/v7,linux/arm64/v8,linux/amd64 \
	-t flyway/flyway:latest \
	-t flyway/flyway:$(VERSION) \
	-t flyway/flyway:$(subst $S,.,$(wordlist 1,2,$(subst .,$S,$(VERSION)))) \
	-t flyway/flyway:$(subst $S,.,$(wordlist 1,1,$(subst .,$S,$(VERSION)))) .
	docker build $(DOCKER_BUILD_ARGS) \
	-t flyway/flyway:latest-alpine \
	-t flyway/flyway:$(VERSION)-alpine \
	-t flyway/flyway:$(subst $S,.,$(wordlist 1,2,$(subst .,$S,$(VERSION))))-alpine \
	-t flyway/flyway:$(subst $S,.,$(wordlist 1,1,$(subst .,$S,$(VERSION))))-alpine ./alpine
	docker build $(DOCKER_BUILD_ARGS) \
	-t flyway/flyway-azure:latest-alpine \
	-t flyway/flyway-azure:$(VERSION)-alpine \
	-t flyway/flyway-azure:$(subst $S,.,$(wordlist 1,2,$(subst .,$S,$(VERSION))))-alpine \
	-t flyway/flyway-azure:$(subst $S,.,$(wordlist 1,1,$(subst .,$S,$(VERSION))))-alpine ./flyway-azure/alpine

test:
	$(info Testing standard Docker image...)
	docker run --rm $(shell docker build -q .) -url=jdbc:h2:mem:test info
	$(info Testing alpine Docker image...)
	docker run --rm $(shell docker build -q ./alpine) -url=jdbc:h2:mem:test info
	$(info Testing azure Docker image...)
	docker run --rm $(shell docker build -q ./flyway-azure/alpine) flyway -url=jdbc:h2:mem:test info

release: DOCKER_BUILD_ARGS = --output=type=registry
release: build
	git commit --allow-empty -a -m 'Update to $(VERSION)'
	git tag v$(VERSION)
	git push origin --atomic $(shell git rev-parse --abbrev-ref HEAD) v$(VERSION)
