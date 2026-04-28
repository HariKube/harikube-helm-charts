MIDDLEWARE_VERSION ?= $(cat harikube/Chart.yaml | grep '^appVersion' | cut -d' ' -f2)
NAMESPACE = harikube
SECRET_DIR ?= .vscode
KIND_CLUSTER ?= harikube-helm-chart-test

HELM ?= helm
YAMLLINT ?= yamllint
KIND ?= kind
KUBECTL ?= kubectl
CHAINSAW ?= chainsaw
VCLUSTER ?= vcluster

.PHONY: lint
lint:
	$(HELM) lint ./harikube
	$(YAMLLINT) --strict --format github <(make render)
	$(HELM) template harikube ./harikube | kubeconform -summary -verbose -ignore-missing-schemas

.PHONY: render
render:
	@$(HELM) template harikube ./harikube

.PHONY: setup-test
setup-test: cleanup-test
	$(KIND) create cluster --name $(KIND_CLUSTER)
	$(KUBECTL) wait --for=condition=Ready node/$(KIND_CLUSTER)-control-plane --timeout=120s

	$(KUBECTL) apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.3/cert-manager.yaml
	$(KUBECTL) apply -f https://github.com/prometheus-operator/prometheus-operator/releases/download/v0.77.1/stripped-down-crds.yaml
	$(KUBECTL) wait -n cert-manager --for=jsonpath='{.status.readyReplicas}'=1 deployment/cert-manager-webhook --timeout=2m

.PHONY: test-integration
test-integration: setup-test _test-integration
	$(MAKE) cleanup-test

_test-integration:
	$(HELM) install harikube ./harikube \
		--dry-run \
		--debug \
		--namespace $(NAMESPACE)

.PHONY: test-e2e
test-e2e: setup-test _setup-e2e _test-e2e
	$(MAKE) cleanup-test

_setup-e2e:
	$(KUBECTL) create namespace $(NAMESPACE)
	$(KUBECTL) label namespace $(NAMESPACE) harikube.info/middleware=enabled --overwrite
	$(KUBECTL) create secret generic -n $(NAMESPACE) harikube-license --from-file=$(SECRET_DIR)/license
	$(KUBECTL) create secret docker-registry harikube-registry-secret \
		--docker-server=registry.harikube.info \
		--docker-username=harikube \
		--docker-password="$$(head -1 $(SECRET_DIR)/credential)" \
		--namespace=$(NAMESPACE)

	$(HELM) install harikube ./harikube \
		--debug \
		--namespace $(NAMESPACE) \
		--set middleware.image.tag=$(MIDDLEWARE_VERSION)
	$(KUBECTL) wait -n $(NAMESPACE) --for=jsonpath='{.status.readyReplicas}'=1 deployment/harikube-operator-deploy --timeout=2m
	$(KUBECTL) wait -n $(NAMESPACE) --for=jsonpath='{.status.readyReplicas}'=1 deployment/harikube-middleware-deploy --timeout=2m

	$(HELM) install harikube-vcluster https://charts.loft.sh/charts/vcluster-0.32.1.tgz \
		--debug \
		--namespace $(NAMESPACE) \
		--values harikube/vcluster/workload-config.yaml
	$(KUBECTL) wait -n $(NAMESPACE) --for=jsonpath='{.status.readyReplicas}'=1 statefulset/harikube-vcluster --timeout=5m

_test-e2e:
	$(CHAINSAW) test --test-dir test/integration/00-topology-config

	$(VCLUSTER) connect harikube-vcluster
	$(CHAINSAW) test --test-dir test/integration/01-shirt
	$(VCLUSTER) disconnect

.PHONY: cleanup-test
cleanup-test:
	@$(KIND) delete cluster --name $(KIND_CLUSTER)
