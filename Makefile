# Makefile for besoked installation

#NOTE: override these at execution time
REGISTRY_DOMAIN ?= mavenlink-maven-docker.jfrog.io
IMAGE_NAME ?= mavenlink/bespoked
IMAGE_TAG ?= latest
IMAGE = $(REGISTRY_DOMAIN)/$(IMAGE_NAME):$(IMAGE_TAG)

BUILD=build

$(shell mkdir -p $(BUILD))
MANIFEST_TMP=$(BUILD)/manifest.yml

#.INTERMEDIATE: $(MANIFEST_TMP)

all: image install

image:
	docker build -f Dockerfile.bespoked -t $(IMAGE) .
	docker push $(IMAGE)

install: $(MANIFEST_TMP)
	cat $(MANIFEST_TMP)
	kubectl apply -f $(MANIFEST_TMP)

$(MANIFEST_TMP): manifest.rb kubernetes/rc.yml
	ruby manifest.rb $(REGISTRY_DOMAIN) $(IMAGE_NAME) $(IMAGE_TAG) > $(MANIFEST_TMP)

uninstall:
	kubectl delete -f $(MANIFEST_TMP)

clean: uninstall
	rm -Rf $(BUILD)
