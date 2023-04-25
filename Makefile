# Copyright 2017 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

CMDS=iscsiplugin
all: build

include release-tools/build.make

GOPATH ?= $(shell go env GOPATH)
GOBIN ?= $(GOPATH)/bin
export GOPATH GOBIN

REGISTRY ?= test
IMAGENAME ?= iscsiplugin
IMAGE_VERSION ?= local
# Output type of docker buildx build
OUTPUT_TYPE ?= docker
ARCH ?= amd64
IMAGE_TAG = $(REGISTRY)/$(IMAGENAME):$(IMAGE_VERSION)

ALL_ARCH.linux = arm64 amd64

.PHONY: test-container
test-container:
	make
	docker buildx build --pull --output=type=$(OUTPUT_TYPE) --platform="linux/$(ARCH)" \
		-t $(IMAGE_TAG) --build-arg ARCH=$(ARCH) .

.PHONY: sanity-test
sanity-test:
	make
	./test/sanity/run-test.sh
.PHONY: mod-check
mod-check:
	go mod verify && [ "$(shell sha512sum go.mod)" = "`sha512sum go.mod`" ] || ( echo "ERROR: go.mod was modified by 'go mod verify'" && false )

.PHONY: clean
clean:
	go clean -mod=vendor -r -x
	rm -f bin/iscsiplugin

.PHONY: iscsi
iscsi:
	CGO_ENABLED=0 GOOS=linux GOARCH=$(ARCH) go build -a -ldflags "${LDFLAGS} ${EXT_LDFLAGS}" -mod vendor -o bin/${ARCH}/iscsiplugin ./cmd/iscsiplugin

.PHONY: container-build
container-build:
	docker buildx build --pull --output=type=$(OUTPUT_TYPE) --platform="linux/$(ARCH)" \
		--provenance=false --sbom=false \
		-t $(IMAGE_TAG)-linux-$(ARCH) --build-arg ARCH=$(ARCH) .

.PHONY: container
container:
	# enable qemu for arm64 build
	# https://github.com/docker/buildx/issues/464#issuecomment-741507760
	docker run --privileged --rm tonistiigi/binfmt --uninstall qemu-aarch64
	docker run --rm --privileged tonistiigi/binfmt --install all
	for arch in $(ALL_ARCH.linux); do \
		ARCH=$${arch} $(MAKE) iscsi; \
		ARCH=$${arch} $(MAKE) container-build; \
	done

.PHONY: push
push:
	for arch in $(ALL_ARCH.linux); do \
		docker push $(IMAGE_TAG)-linux-$$arch; \
	done 
	docker manifest create --amend $(IMAGE_TAG) $(foreach osarch, $(ALL_ARCH.linux), $(IMAGE_TAG)-linux-${osarch})
	docker manifest push $(IMAGE_TAG)
	docker manifest inspect $(IMAGE_TAG)