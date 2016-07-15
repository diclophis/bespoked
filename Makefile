# Makefile for besoked installation

#NOTE: override these at execution time
REGISTRY_DOMAIN ?= mavenlink-maven-docker.jfrog.io
IMAGE_NAME ?= mavenlink/bespoked
IMAGE_TAG ?= $(strip $(shell find Gemfile Gemfile.lock lib config nginx kubernetes main.rb -type f | xargs shasum | sort | shasum | cut -f1 -d" "))
IMAGE = $(REGISTRY_DOMAIN)/$(IMAGE_NAME):$(IMAGE_TAG)

BUILD=build

$(shell mkdir -p $(BUILD))
MANIFEST_TMP=$(BUILD)/manifest.yml

#.INTERMEDIATE: $(MANIFEST_TMP)
.PHONY: image uninstall clean

all: $(BUILD)/$(IMAGE_TAG) install

image:
	docker build --rm=false -f Dockerfile.bespoked -t $(IMAGE) .
	docker push $(IMAGE)

$(BUILD)/$(IMAGE_TAG): image
	touch $(BUILD)/$(IMAGE_TAG)

install: $(MANIFEST_TMP)
	cat $(MANIFEST_TMP)
	kubectl apply -f $(MANIFEST_TMP)

$(MANIFEST_TMP): manifest.rb kubernetes/rc.yml $(BUILD)/$(IMAGE_TAG)
	ruby manifest.rb $(REGISTRY_DOMAIN) $(IMAGE_NAME) $(IMAGE_TAG) > $(MANIFEST_TMP)

uninstall:
	kubectl delete -f $(MANIFEST_TMP)

clean: uninstall
	rm -Rf $(BUILD)
