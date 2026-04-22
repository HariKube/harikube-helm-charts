KIND_CLUSTER ?= harikube-helm-chart-test

.PHONY: lint
lint:
	@helm lint ./harikube

.PHONY: render
render:
	@helm template harikube ./harikube

.PHONY: validate
validate:
	@helm template harikube ./harikube | kubeconform -summary -verbose -ignore-missing-schemas -exit-on-error

.PHONY: setup-test
setup-test: cleanup-test
	@kind create cluster --name $(KIND_CLUSTER)
	kubectl wait --for=condition=Ready node/$(KIND_CLUSTER)-control-plane --timeout=120s

	kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.3/cert-manager.yaml
	kubectl apply -f https://github.com/prometheus-operator/prometheus-operator/releases/download/v0.77.1/stripped-down-crds.yaml
	kubectl wait -n cert-manager --for=jsonpath='{.status.readyReplicas}'=1 deployment/cert-manager-webhook --timeout=2m

.PHONY: test-integration
test-integration: setup-test _test-integration

_test-integration:
	@helm install --dry-run --debug -n harikube harikube ./harikube

.PHONY: test-e2e
test-e2e: setup-test _test-e2e

_test-e2e:
	@helm install --debug --create-namespace -n harikube harikube ./harikube

.PHONY: cleanup-test
cleanup-test:
	@kind delete cluster --name $(KIND_CLUSTER)