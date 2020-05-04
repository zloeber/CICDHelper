SHELL := /bin/bash
.DEFAULT_GOAL := help
ROOT_PATH := $(abspath $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST))))))
BIN_PATH := $(ROOT_PATH)/.local/bin
INSTALL_PATH := $(BIN_PATH)
APP_PATH := $(ROOT_PATH)/.local/apps
SCRIPT_PATH ?= $(ROOT_PATH)/scripts
DEPLOY_PATH ?= $(ROOT_PATH)/deploy
ENVIRONMENT ?= default

# Import target deployment env vars
ENVIRONMENT_VARS ?= ${ROOT_PATH}/config/$(ENVIRONMENT).env
ifneq (,$(wildcard $(ENVIRONMENT_VARS)))
include ${ENVIRONMENT_VARS}
export $(shell sed 's/=.*//' ${ENVIRONMENT_VARS})
endif

## List of sane defaults for local makefile building/testing
# Note: all values in here should be ?= in case they are already set upstream
CLOUD ?= local
KUBE_PROVIDER ?= kind
KUBE_CLUSTER ?= cicd
KUBE_VERSION ?= 1.18.0
DOCKER_PROVIDER ?= dockerhub
TASKSETS ?= cluster.$(KUBE_PROVIDER) common kube helm

DEPTASKS := $(foreach taskset, $(TASKSETS), $(addprefix .deps/, $(taskset)))
INCLUDES := $(foreach taskset, $(TASKSETS), $(addprefix $(ROOT_PATH)/inc/makefile., $(taskset)))

-include $(INCLUDES)

.PHONY: .githubapps
.githubapps: ## Install githubapp (ghr-installer)
ifeq (,$(wildcard $(APP_PATH)/githubapp))
	@rm -rf $(APP_PATH)
	@mkdir -p $(APP_PATH)
	@git clone https://github.com/zloeber/ghr-installer $(APP_PATH)/githubapp
endif

.PHONY: deps
deps: .githubapps $(DEPTASKS) ## Install general dependencies
ifeq (,$(wildcard $(INSTALL_PATH)/yq))
	@$(MAKE) --no-print-directory -C $(APP_PATH)/githubapp auto mikefarah/yq INSTALL_PATH=$(INSTALL_PATH)
endif

.PHONY: clean
clean: ## Remove downloaded dependencies
	rm -rf $(APP_PATH)/githubapp
	rm $(INSTALL_PATH)/*

.PHONY: dnsforward/start
dnsforward/start: ## Forwards all dns requests to a local dns-proxy-server
	tmpdir=$$(mktemp -d) && echo "$${tmpdir}" && \
	export STACK_INGRESS_INTERNALIP=`kubectl -n kube-system get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'` && \
	$(gomplate) --file $(DEPLOY_PATH)/dnsproxy/config.json --out "$${tmpdir}/config.json" && \
	$(docker) run --rm -d \
		--hostname $(DNS_DOMAIN) \
		--name dns-proxy-server \
		-p 5380:5380 \
		-v $${tmpdir}:/app/conf \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v /etc/resolv.conf:/etc/resolv.conf \
		defreitas/dns-proxy-server