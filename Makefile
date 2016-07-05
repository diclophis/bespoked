# Makefile for besoked installation

#NOTE: override these at execution time
REGISTRY_DOMAIN ?= "mavenlink.jfrog.io"
IMAGE_NAME ?= "mavenlink/bespoked"
IMAGE_TAG ?= "latest"
IMAGE = $(REGISTRY_DOMAIN)/$(IMAGE_NAME):$(IMAGE_TAG)

all: build install

build:
	docker build -f Dockerfile.bespoked -t $(IMAGE) .
	docker push $(IMAGE)

install:
	ruby manifest.rb $(REGISTRY_DOMAIN) $(IMAGE_NAME) $(IMAGE_TAG) | kubectl apply -f -
