# Makefile for besoked installation

#NOTE: override these at execution time
REPO ?= localhost/
IMAGE_NAME ?= bespoked
IMAGE_TAG ?= $(strip $(shell find Gemfile Gemfile.lock lib config nginx kubernetes main.rb -type f | xargs shasum | sort | shasum | cut -f1 -d" "))
IMAGE = $(REPO)$(IMAGE_NAME):$(IMAGE_TAG)

BUILD=build

$(shell mkdir -p $(BUILD))
MANIFEST_TMP=$(BUILD)/manifest.yml

#.INTERMEDIATE: $(MANIFEST_TMP)
.PHONY: image uninstall clean

all: $(BUILD)/$(IMAGE_TAG) install

image:
	docker build -f Dockerfile.bespoked -t $(IMAGE) .
	#docker push $(IMAGE)

$(BUILD)/$(IMAGE_TAG): image
	touch $(BUILD)/$(IMAGE_TAG)

install: $(MANIFEST_TMP)
	cat $(MANIFEST_TMP)
	kubectl apply -f $(MANIFEST_TMP)
	# kubectl rolling-update bespoked-replication-controller --image=$(IMAGE) --image-pull-policy=IfNotPresent --update-period=9s --poll-interval=3s

$(MANIFEST_TMP): manifest.rb kubernetes/rc.yml $(BUILD)/$(IMAGE_TAG)
	ruby manifest.rb "$(REPO)" $(IMAGE_NAME) $(IMAGE_TAG) > $(MANIFEST_TMP)

uninstall:
	kubectl delete -f $(MANIFEST_TMP)

clean: uninstall
	rm -Rf $(BUILD)
