NAMESPACE=harikube
KIND_CLUSTER ?= harikube-helm-chart-test

.PHONY: lint
lint:
	helm lint ./harikube
	yamllint --strict --format github <(make render)
	helm template harikube ./harikube | kubeconform -summary -verbose -ignore-missing-schemas

.PHONY: render
render:
	@helm template harikube ./harikube

.PHONY: setup-test
setup-test: cleanup-test
	kind create cluster --name $(KIND_CLUSTER)
	kubectl wait --for=condition=Ready node/$(KIND_CLUSTER)-control-plane --timeout=120s

	kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.3/cert-manager.yaml
	kubectl apply -f https://github.com/prometheus-operator/prometheus-operator/releases/download/v0.77.1/stripped-down-crds.yaml
	kubectl wait -n cert-manager --for=jsonpath='{.status.readyReplicas}'=1 deployment/cert-manager-webhook --timeout=2m

.PHONY: test-integration
test-integration: setup-test _test-integration cleanup-test

_test-integration:
	helm install harikube ./harikube \
		--dry-run \
		--debug \
		--namespace $(NAMESPACE)

.PHONY: test-e2e
test-e2e: setup-test _test-e2e cleanup-test

_test-e2e:
	kubectl create namespace $(NAMESPACE)
	kubectl label namespace $(NAMESPACE) harikube.info/middleware=enabled --overwrite
	kubectl create secret generic -n $(NAMESPACE) harikube-license --from-file=.vscode/license
	kubectl create secret docker-registry harikube-registry-secret \
		--docker-server=registry.harikube.info \
		--docker-username=harikube \
		--docker-password="$$(head -1 .vscode/credential)" \
		--namespace=$(NAMESPACE)

	helm install harikube ./harikube \
		--debug \
		--namespace $(NAMESPACE)
	kubectl wait -n $(NAMESPACE) --for=jsonpath='{.status.readyReplicas}'=1 deployment/harikube-operator-deploy --timeout=2m
	kubectl wait -n $(NAMESPACE) --for=jsonpath='{.status.readyReplicas}'=1 deployment/harikube-middleware-deploy --timeout=2m
	

	helm repo add loft-sh https://charts.loft.sh
	helm repo update
	helm install harikube-vcluster loft-sh/vcluster \
		--debug \
		--version 0.32.1 \
		--namespace $(NAMESPACE) \
		--values harikube/vcluster/workload-config.yaml \
		--set controlPlane.distro.k8s.image.tag=v1.35.3
	kubectl wait -n $(NAMESPACE) --for=jsonpath='{.status.readyReplicas}'=1 statefulset/harikube-vcluster --timeout=5m

	chainsaw test --test-dir test/integration

.PHONY: cleanup-test
cleanup-test:
	@kind delete cluster --name $(KIND_CLUSTER)