SHELL=bash
MAKEFILE_PATH = $(dir $(realpath -s $(firstword $(MAKEFILE_LIST))))
BUILD_DIR_PATH = ${MAKEFILE_PATH}/build
GOOS ?= linux
GOARCH ?= amd64
KO_DOCKER_REPO = ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
WITH_GOFLAGS = KO_DOCKER_REPO=${KO_DOCKER_REPO} GOOS=${GOOS} GOARCH=${GOARCH}
K8S_NODE_LATENCY_IAM_ROLE_ARN ?= arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CLUSTER_NAME}-k8s-node-latency

build: ## Build the controller image
	$(eval CONTROLLER_TAG=$(shell $(WITH_GOFLAGS) ko build -B github.com/bwagner5/k8s-node-latency/cmd/knl  | sed 's/.*knl@//'))
	echo Built ${CONTROLLER_TAG}

build-bin: ## Build the binary
	$(WITH_GOFLAGS) go build -a -ldflags="-s -w" -o ${BUILD_DIR_PATH}/knl ${MAKEFILE_PATH}/cmd/knl/main.go

install:  ## Deploy the latest released version into your ~/.kube/config cluster
	@echo Upgrading to $(shell grep version charts/k8s-node-latency/Chart.yaml)
	helm upgrade --install k8s-node-latency charts/k8s-node-latency --create-namespace --namespace k8s-node-latency \
	$(HELM_OPTS)

apply: build ## Deploy the controller from the current state of your git repository into your ~/.kube/config cluster
	helm upgrade --install k8s-node-latency charts/k8s-node-latency --namespace k8s-node-latency --create-namespace \
	$(HELM_OPTS) \
	--set serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=${K8S_NODE_LATENCY_IAM_ROLE_ARN} \
	--set image.repository=$(KO_DOCKER_REPO)/knl \
	--set image.digest="$(CONTROLLER_TAG)" 

test: build-bin ## local test with docker
	docker build -t knl-test -f test/Dockerfile .
	docker run -it -v $(shell pwd)/test/not-ready/var/log:/var/log -v ${BUILD_DIR_PATH}/knl:/bin/knl knl-test /bin/knl --timeout=11 --output=json --no-imds
	docker run -it -v $(shell pwd)/test/normal/var/log:/var/log -v ${BUILD_DIR_PATH}/knl:/bin/knl knl-test /bin/knl
	docker run -it -v $(shell pwd)/test/no-cni/var/log:/var/log -v ${BUILD_DIR_PATH}/knl:/bin/knl knl-test /bin/knl --timeout=11 --output=json

verify: helm-lint ## Run Verifications like helm-lint

fmt: ## go fmt the code
	find . -iname "*.go" -exec go fmt {} \;

helm-lint: ## Lint the helm chart
	helm lint --strict charts/k8s-node-latency

help: ## Display help
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.PHONY: verify helm-lint apply build fmt
