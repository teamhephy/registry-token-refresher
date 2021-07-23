include includes.mk

SHORT_NAME ?= registry-token-refresher
DEIS_REGISTRY ?= ${DEV_REGISTRY}
IMAGE_PREFIX ?= hephy

include versioning.mk

# dockerized development environment variables
REPO_PATH := github.com/teamhephy/${SHORT_NAME}
DEV_ENV_IMAGE := hephy/go-dev:v1.33.3
DEV_ENV_WORK_DIR := /go/src/${REPO_PATH}
DEV_ENV_PREFIX := docker run --rm -v ${CURDIR}:${DEV_ENV_WORK_DIR} -w ${DEV_ENV_WORK_DIR}
DEV_ENV_CMD := ${DEV_ENV_PREFIX} ${DEV_ENV_IMAGE}

# SemVer with build information is defined in the SemVer 2 spec, but Docker
# doesn't allow +, so we use -.
BINDIR := rootfs/usr/bin
# Common flags passed into Go's linker.
LDFLAGS := "-s -w -X main.version=${VERSION}"
# Docker Root FS
BINDIR := ./rootfs

# The following variables describe the source we build from
GO_FILES := $(wildcard *.go)
GO_DIRS := pkg/
GO_PACKAGES := ${REPO_PATH} $(addprefix ${REPO_PATH}/,${GO_DIRS})

# The binary compression command used
UPX := upx -9 --mono --no-progress

all:
	@echo "Use a Makefile to control top-level building of the project."

# Allow developers to step into the containerized development environment
dev: check-docker
	${DEV_ENV_CMD_INT} bash

fmt: ## Run go fmt against code.
	${DEV_ENV_CMD} go fmt ./...

vet: ## Run go vet against code.
	${DEV_ENV_CMD} go vet ./...

# Containerized dependency resolution
vendor: check-docker
	${DEV_ENV_CMD} go mod vendor

tidy:
	${DEV_ENV_CMD} go mod tidy -v

# This illustrates a two-stage Docker build. docker-compile runs inside of
# the Docker environment. Other alternatives are cross-compiling, doing
# the build as a `docker build`.

# Builds the binary-- this should only be executed within the
# containerized development environment.
binary-build:
	GOOS=linux GOARCH=amd64 go build -o ${BINDIR}/boot -ldflags ${LDFLAGS} boot.go
	$(call check-static-binary,$(BINDIR)/${SHORT_NAME})
	${UPX} ${BINDIR}/boot

# Containerized build of the binary
build: check-docker
	mkdir -p ${BINDIR}
	${DEV_ENV_CMD} make binary-build

docker-build: build check-docker
	DOCKER_BUILDKIT=1 docker build ${DOCKER_BUILD_FLAGS} -t ${IMAGE} rootfs
	docker tag ${IMAGE} ${MUTABLE_IMAGE}

test: lint test-unit test-functional

test-cover: check-docker vendor
	${DEV_ENV_CMD} test-cover.sh

test-functional:
	@echo no functional tests

lint: check-docker vendor
	${DEV_ENV_CMD} lint

test-unit: check-docker  vendor
	${DEV_ENV_CMD} go test --cover -v ${GO_PACKAGES}

update-changelog:
	${DEV_ENV_PREFIX} -e RELEASE=${WORKFLOW_RELEASE} ${DEV_ENV_IMAGE} gen-changelog.sh \
	  | cat - CHANGELOG.md > tmp && mv tmp CHANGELOG.md

.PHONY: all docker-build test
