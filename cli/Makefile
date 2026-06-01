REGISTRY := us-central1-docker.pkg.dev/t-labs-shared/t-labs
APPS := hello-world api-service

.PHONY: build install push-all $(APPS)

build:
	go build -o tld .

install: build
	cp tld /usr/local/bin/tld

$(APPS):
	docker build -t $(REGISTRY)/$@:latest ../apps/$@
	docker push $(REGISTRY)/$@:latest

push-all: $(APPS)
