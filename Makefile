
MAKEFLAGS += --no-print-directory

NAMESPACE = harikube
SECRET_DIR ?= .vscode
KIND_CLUSTER ?= harikube-helm-chart-test
CERT_MANAGER ?= false
MODE ?= os

HELM ?= helm
YAMLLINT ?= yamllint
KIND ?= kind
KUBECTL ?= kubectl
CHAINSAW ?= chainsaw
VCLUSTER ?= vcluster

define SETS
--namespace $(NAMESPACE) \
--set middleware.monitoring.create=true \
--set middleware.networkPolicy.create=true \
--set apiServer.create=true \
--set apiServer.monitoring.create=true \
--set apiServer.networkPolicy.create=true \
--set controllerManager.create=true \
--set controllerManager.monitoring.create=true \
--set controllerManager.networkPolicy.create=true \
--set serverlessKubeWatchTrigger.create=true \
--set apiExtension.create=true \
--set certManagerIntegration.create=$(CERT_MANAGER) \
--set vcluster.exportKubeConfig.server=https://harikube.$(NAMESPACE):443
endef

ifeq ($(MODE),ee)
define EE_SETS
--set enterprise.key="$$(cat $(SECRET_DIR)/license)" \
--set enterprise.user=harikube \
--set enterprise.password="$$(head -1 $(SECRET_DIR)/credential)" \
--set middleware.endPoint.url="multi://sqlite:///db/main.db?_journal_mode=WAL&_busy_timeout=30000&_synchronous=NORMAL&_txlock=immediate&_stmt_cache_size=20&cache=shared" \
--set operator.create=true \
--set operator.monitoring.create=true
endef
SETS += $(EE_SETS)
endif
	
.PHONY: lint
lint:
	$(HELM) lint ./harikube
	$(YAMLLINT) --strict --format github <(make render)
	$(HELM) template harikube ./harikube | kubeconform -summary -verbose -ignore-missing-schemas

.PHONY: render
render:
	@$(HELM) template harikube ./harikube $(SETS) --debug

.PHONY: test
test:
	helm plugin install https://github.com/helm-unittest/helm-unittest ||:
	helm unittest --debug --with-subchart=false ./harikube

.PHONY: package
package:
	helm package ./harikube

.PHONY: setup-test
setup-test: cleanup-test
	$(KIND) create cluster --name $(KIND_CLUSTER)
	$(KUBECTL) wait --for=condition=Ready node/$(KIND_CLUSTER)-control-plane --timeout=120s

	$(KUBECTL) apply -f https://github.com/prometheus-operator/prometheus-operator/releases/download/v0.77.1/stripped-down-crds.yaml

ifeq ($(CERT_MANAGER),true)
	$(KUBECTL) apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.3/cert-manager.yaml
	$(KUBECTL) wait -n cert-manager --for=jsonpath='{.status.readyReplicas}'=1 deployment/cert-manager-webhook --timeout=2m
	sleep 5
endif

.PHONY: test-integration
test-integration: setup-test _test-integration
	$(MAKE) cleanup-test

_test-integration:
	$(HELM) install harikube ./harikube --dry-run $(SETS) --debug

.PHONY: test-e2e
test-e2e: setup-test _setup-e2e _test-e2e
	$(MAKE) cleanup-test

_setup-e2e:
	$(KUBECTL) create namespace $(NAMESPACE)
	$(KUBECTL) label namespace $(NAMESPACE) harikube.info/$(NAMESPACE)-middleware=enabled --overwrite
	$(KUBECTL) label namespace $(NAMESPACE) harikube.info/$(NAMESPACE)-apiserver=enabled --overwrite
	$(KUBECTL) label namespace $(NAMESPACE) harikube.info/$(NAMESPACE)-controllermanager=enabled --overwrite

	$(KUBECTL) apply -f operator-crd.yaml
	$(KUBECTL) apply -f serverless-kube-watch-trigger-crd.yaml
	$(KUBECTL) apply -f api-extension-crd.yaml

	$(HELM) install harikube ./harikube $(SETS) --debug
ifeq ($(MODE),ee)
	$(KUBECTL) wait -n $(NAMESPACE) --for=jsonpath='{.status.readyReplicas}'=1 deployment/harikube-operator-deploy --timeout=2m
endif
	$(KUBECTL) wait -n $(NAMESPACE) --for=jsonpath='{.status.readyReplicas}'=1 deployment/harikube-middleware-deploy --timeout=2m
	$(KUBECTL) wait -n $(NAMESPACE) --for=jsonpath='{.status.readyReplicas}'=1 deployment/serverless-kube-watch-trigger-controller-manager --timeout=2m
	$(KUBECTL) wait -n $(NAMESPACE) --for=jsonpath='{.status.readyReplicas}'=1 deployment/api-extension-controller-manager --timeout=2m
	$(KUBECTL) wait -n $(NAMESPACE) --for=jsonpath='{.status.readyReplicas}'=1 statefulset/harikube --timeout=5m
		$(KUBECTL) wait -n $(NAMESPACE) --for=jsonpath='{.status.readyReplicas}'=1 deployment/harikube-api-server-deploy --timeout=2m
	$(KUBECTL) wait -n $(NAMESPACE) --for=jsonpath='{.status.readyReplicas}'=1 deployment/harikube-controller-manager-deploy --timeout=5m

_test-e2e:
ifeq ($(MODE),ee)
	$(CHAINSAW) test --test-dir test/integration/00-topology-config
endif

	$(VCLUSTER) connect harikube
	$(CHAINSAW) test --test-dir test/integration/01-shirt
	$(VCLUSTER) disconnect

.PHONY: cleanup-test
cleanup-test:
	@$(KIND) delete cluster --name $(KIND_CLUSTER)
