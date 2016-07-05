# Makefile for besoked installation

#NOTE: override these at execution time
REGISTRY_DOMAIN ?= "mavenlink.jfrog.io"
IMAGE_NAME ?= "mavenlink/bespoked"
IMAGE_TAG ?= "latest"

all: build install

build:
	docker build -f Dockerfile.bespoked
	docker push $(REGISTRY_DOMAIN) $(IMAGE_NAME):$(IMAGE_TAG)

install:
	ruby manifest.rb $(REGISTRY_DOMAIN) $(IMAGE_NAME) $(IMAGE_TAG) | kubectl apply -f -
