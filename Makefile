.PHONY: build docker test fmt lint vet


BUILD := ./build

TAG = $(shell git describe --match 'v[0-9]*' --dirty --always)
VERSION_MAJOR = $(shell awk '/VersionMajor = / { print $$3; exit }' ./pkg/version/version.go)
VERSION_MINOR = $(shell awk '/VersionMinor = / { print $$3; exit }' ./pkg/version/version.go)
VERSION_PATCH = $(shell awk '/VersionPatch = / { print $$3; exit }' ./pkg/version/version.go)
VERSION = $(VERSION_MAJOR).$(VERSION_MINOR).$(VERSION_PATCH)-$(TAG)

PACKAGES = $(shell go list ./... | grep -v -e vendor -e tmp)
ALL_SRC := $(shell find . -name "*.go" | grep -v -e tmp -e vendor \
	-e ".*/\..*" \
	-e ".*/_.*" \
	-e ".*/mocks.*")
TEST_DIRS := $(sort $(dir $(filter %_test.go,$(ALL_SRC))))

GO_LDFLAGS=-ldflags "-X github.com/zhangpeihao/zim/pkg/version.VersionDev=$(TAG)"

all: build

# build the release files
build_all: build build_cross build_tar

build: zim

zim:
	go build ${GO_LDFLAGS} github.com/zhangpeihao/zim

build_cross: build_cross_linux build_cross_linux_386 build_cross_windows build_cross_windows_386 build_cross_darwin

build_cross_linux:
	GOOS=linux   GOARCH=amd64 CGO_ENABLED=0 go build -o release/linux/amd64/zim       ${GO_LDFLAGS} github.com/zhangpeihao/zim

build_cross_linux_386:
	GOOS=linux   GOARCH=386   CGO_ENABLED=0 go build -o release/linux/386/zim         ${GO_LDFLAGS} github.com/zhangpeihao/zim

build_cross_windows:
	GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -o release/windows/amd64/zim.exe ${GO_LDFLAGS} github.com/zhangpeihao/zim

build_cross_windows_386:
	GOOS=windows GOARCH=386   CGO_ENABLED=0 go build -o release/windows/386/zim.exe   ${GO_LDFLAGS} github.com/zhangpeihao/zim

build_cross_darwin:
	GOOS=darwin  GOARCH=amd64 CGO_ENABLED=0 go build -o release/darwin/amd64/zim      ${GO_LDFLAGS} github.com/zhangpeihao/zim

build_tar: build_cross
	tar -cvzf release/linux/amd64/zim.tar.gz   -C release/linux/amd64   zim
	tar -cvzf release/linux/386/zim.tar.gz     -C release/linux/386     zim
	tar -cvzf release/windows/amd64/zim.tar.gz -C release/windows/amd64 zim.exe
	tar -cvzf release/windows/386/zim.tar.gz   -C release/windows/386   zim.exe
	tar -cvzf release/darwin/amd64/zim.tar.gz  -C release/darwin/amd64  zim

rebuild: clean build

clean:
	rm -f ./zim

# build docker image
docker: docker_build docker_save

docker_build: build_cross_linux
	docker build -t zim:latest .
	docker tag zim:latest zim:$(VERSION)

docker_save: release/docker
	docker save -o release/docker/zim-$(VERSION).docker zim:$(VERSION)

release/docker:
	mkdir -p release/docker

# build test

test/service-stub/service-stub:
	cd test/service-stub && go build

buid_test_stub: test/service-stub/service-stub

# run

run_stub:
	cd test/service-stub && go run main.go

run:
	go run main.go gateway --config=./testconfig.yaml

run_stress_client:
	cd test/stress-test/stress-client && go run main.go

# fmt
fmt:
	gofmt -w -s cmd pkg test

# lint
lint:
	@for pkg in $(PACKAGES); do golint $$pkg; done

# vet
vet:
	@for pkg in $(PACKAGES); do go vet $$pkg; done

# test
test:
	@echo Testing packages:
	@mkdir -p $(BUILD)
	@echo "mode: atomic" > $(BUILD)/cover.out
	@for dir in $(TEST_DIRS); do \
		mkdir -p $(BUILD)/"$$dir"; \
		go test "$$dir" -race -v -timeout 5m -coverprofile=$(BUILD)/"$$dir"/coverage.out || exit 1; \
		cat $(BUILD)/"$$dir"/coverage.out | grep -v "mode: atomic" >> $(BUILD)/cover.out; \
	done

# cover
cover: test
	go tool cover -html=$(BUILD)/cover.out

cover_ci: build test
	goveralls -coverprofile=$(BUILD)/cover.out -service=travis-ci || echo -e "\x1b[31mCoveralls failed\x1b[m"

# code check
check: fmt lint vet test
