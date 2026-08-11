# harikube-helm-charts

This repository contains a collection of Kubernetes-native packages (Helm charts) designed to streamline the deployment, management, and scaling of Harikube applications. Features include pre-configured values for high availability, security best practices, and seamless integration with existing CI/CD pipelines.


Inhalt
1.	Title and Introduction	1
1.1	What is HariKube?	1
2.	Prerequisites	2
3.	Installation	2
3.1	Install Harikube via helm chart	2
3.2	Create database topology config file	3
3.3	Routing Configuration Explained	4
4.	Configuration (Values)	5
4.1	Middleware Configuration	5
4.2	Database Configuration	5
5.	List of the most important parameters from the values.yaml .	6
6.	Applicate	8
6.1	Create Your First Custom Resource Definition.	8
6.2	Ensure Label with Mutation Admission Webhook	8
6.3	Create Your First Custom Resources	9
6.4	Custom Resource Versioning & Storage Migration	10
7.	Support	11
8.	Uninstall:	11


1. Title and Introduction 
HariKube is an advanced Kubernetes-native platform that enhances how microservices and custom resources are managed by distributing data across multiple databases. It addresses ETCD’s limitations by introducing a powerful multi-layer and vendor database topology. Bringing a cloud-native development experience and turning Kubernetes into a true PaaS.
1.1 What is HariKube?
HariKube is a system that simplifies data location management in Kubernetes by offloading microservice data from ETCD into databases like MySQL and PostgreSQL, which are optimized for handling large-scale, high-throughput data workloads. It uses a middleware to handle routing and storage logic, improving scalability, performance, and reliability.
For more details visit harikube.info.

2. Prerequisites
Kubernetes V1.3.5 
Helm V4.0 or later
Resources: SQL-Database (MySQL, MariaDB, TiDB, PostgreSQL, CockRoachDB, YugabyteDB SQLite (No large dataset support))

3. Installation
For more details or advanced options visit https://harikube.info/docs/installation/
3.1 Install Harikube via helm chart
You can install Harikube via helm chart as following:
_____________________________________________________________________________________
NAMESPACE=harikube
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
_____________________________________________________________________________________

Command to display
Using helm show readme [CHART], you can view the contents of a chart directly in the terminal. 

3.2 Create database topology config file
HariKube determines data locality using the object key structure and applies routing based on configurable policies, such as matching by resource type, namespace, key prefix, or custom resource definition.
Routing configurations are evaluated in order from top to bottom, and the first matching rule determines the data’s target database. Once a match is found, subsequent rules are ignored for that resource.
Routing policies must be carefully designed, as adding or changing a policy for resource types that already have stored data can result in the existing records becoming inaccessible. HariKube does not migrate previously stored resources to the new target automatically, so any change in routing may lead to apparent data loss unless migration handled manually.
During runtime the middleware monitors configuration changes and applies new configuration, but only adding new configuration to the bottom is supported.
Names and endpoints must be unique in the configuration. If you have to change endpoint, first ensure all data exists on the new endpoint, and then restart the middleware. If you have to change name, restart the middleware and all services - including Kubernetes - which depends on historical data.
Update your endpoints, because the example uses Docker bridge IP!
_____________________________________________________________________________________
topology.yaml
copy
backends:
- name: rbac
  endpoint: http://172.17.0.1:2579
  regexp:
    prefix: (clusterrolebindings|clusterroles|rolebindings|roles|serviceaccounts)
    key: (clusterrolebindings|clusterroles|rolebindings|roles|serviceaccounts)
- name: kube-system
  endpoint: mysql://root:passwd@tcp(172.17.0.1:3306)/kube_system
  namespace:
    namespace: kube-system
- name: pods
  endpoint: postgres://postgres:passwd@172.17.0.1:5432/pods
  prefix:
    prefix: pods
- name: shirts
  endpoint: sqlite://./db/shirts.db?_journal=WAL&cache=shared
  customresource:
    group: stable.example.com
    kind: shirts
_____________________________________________________________________________________

3.3 Routing Configuration Explained
ETCD with regular expression routing: Routes Kubernetes RBAC resources to an ETCD store.
MySQL endpoint with namespace matching: All objects in the kube-system namespace are routed to a MySQL backend.
If you want only a selected list of resources, you can configure them via kinds field. For custom resources you have to create a separate policy, because both given types and custom resources are not supported in the same time.
_____________________________________________________________________________________
topology.yaml
copy
- name: kube-system
  endpoint: mysql://root:passwd@tcp(172.17.0.1:3306)/kube_system
  namespace:
    namespace: kube-system
    kinds:
    - pods
    - deployments
_____________________________________________________________________________________

PostgreSQL endpoint with prefix matching: All pods resources - except pods in kube-system namespace - are routed to a PostgreSQL backend.
SQLite endpoint for specific custom resources: Routes all resources of type shirts in the group stable.example.com to a lightweight embedded SQLite database.
     kind is optional, leave it empty if you want to route the entire group to the database.
Rest of the objects are stored in the default database. (helm install ?).

4. Configuration (Values)
For more details or advanced options visit harikube.info
4.1 Middleware Configuration
A valid license is required to proceed - at least free Starter Edition. We invite you to explore our various licensing tiers on our Editions page.
The middleware is designed to operate seamlessly in both containerized and traditional environments. It can be executed within a Kubernetes cluster (e.g., as a Pod or Deployment) or deployed external to the cluster. All operational configuration files and parameters are standardized and require no modification based on the deployment location.

4.2 Database Configuration
The HariKube removes the “Single Connection” constraint, introducing native multi-database sharding. This allows you to orchestrate an unlimited fleet of independent databases through a single entry point. By using industry-standard layering, you can scale each individual database in your matrix to handle massive workloads.
Database Partitioning (Inside the Shard): Before adding more servers, optimize the one you have. HariKube is designed to work perfectly with native SQL partitioning. Create your schema and partitions manually. When HariKube pushes a query down to the DB, the SQL engine only scans the relevant partition. You get the speed of a sharded system within the simplicity of a single database connection.
Upgrading to a Distributed Database (The “Drop-In” Scale): The most powerful way to scale the database is to replace a standalone MySQL/Postgres instance with a Distributed SQL Engine like TiDB or CockroachDB. To HariKube, TiDB looks like a single MySQL database. You provide one connection string. Behind that single connection, TiDB distributes your data across dozens of nodes.
Introducing a Smart Load Balancer (Read/Write Splitting): To maximize throughput, you can place a State-Aware Proxy (like ProxySQL, MaxScale, Pgpool-II, or Pgcat) between HariKube and your database cluster. The Load Balancer identifies “Write” operations and routes them to the Database Leader/Primary. The Load Balancer identifies “Read” operations (GET, LIST) and distributes them across multiple Read Replicas. This offloads heavy “Watch” and “List” traffic from your primary database, ensuring that write operations remain lightning-fast and uncontended.

5. List of the most important parameters from the values.yaml 
 
For the middleware:
env:
  - name: TOPOLOGY_CONFIG
    value: secret://harikube/topology-config
  # - name: TOPOLOGY_CONFIG_TLS_DIR
  #   value: ./db/tls
  - name: LICENSE_KEY_FILE
    value: /etc/harikube/license
  # - name: LIST_MAX_ITEMS
  #   value: "10000"
  # - name: CUSTOM_RESOURCE_DEFINITION_METADATA_FILE
  #   value: ./db/crds.json
  # - name: GARBAGE_COLLECTION_DIR
  #   value: ./db/garbage-collector
  # - name: GARBAGE_COLLECTION_EXIT_ON_ERROR
  #   value: "false"
  # - name: REVISION_MAPPER
  #   value: "bbolt"
  # - name: REVISION_MAPPER_BBOLT_O2G_PATHS
  #   value: ./db
  # - name: REVISION_MAPPER_BBOLT_G2O_PATHS
  #   value: ./db
  # - name: REVISION_MAPPER_BBOLT_LEASE_PATH
  #   value: ./db
  # - name: REVISION_MAPPER_BBOLT_SYNC_PERIOD
  #   value: 0s
  # - name: REVISION_MAPPER_BBOLT_BATCH_SIZE
  #   value: "1"
  # - name: REVISION_MAPPER_BBOLT_WRITE_QUEUE
  #   value: "1"
  # - name: REVISION_MAPPER_SQLITE_O2G_PATHS
  #   value: ./db
  # - name: REVISION_MAPPER_SQLITE_G2O_PATHS
  #   value: ./db
  # - name: REVISION_MAPPER_SQLITE_LEASE_PATH
  #   value: ./db
  # - name: REVISION_MAPPER_SQLITE_SYNCHRONOUS
  #   value: OFF
  # - name: REVISION_MAPPER_SQLITE_WRITE_QUEUE
  #   value: ./db
  # - name: REVISION_MAPPER_SQLITE_MAX_CONNECTIONS
  #   value: "1"
  - name: ENABLE_TELEMETRY_PUSH
    value: "false"
  args:
  # - --debug=true
  - --log-format=json
  # - --emulated-etcd-version=3.5.13
  - --listen-address=0.0.0.0:2379
  - --metrics-bind-address=:8080
  - --server-cert-file=/etc/harikube-middleware-crt/tls.crt
  - --server-key-file=/etc/harikube-middleware-crt/tls.key
  # - --metrics-enable-profiling=true
  # - --metrics-ignore-tls-config=true
  - --slow-sql-threshold=2s
  # - --slow-sql-warning-threshold=5s
  - --datastore-max-idle-connections=50
  - --datastore-max-open-connections=90
  - --datastore-connection-max-lifetime=5m
  - --datastore-connection-max-idle-lifetime=5m
  - --endpoint=multi://sqlite:///db/main.db?_journal=WAL&cache=shared
  # - --ca-file=/etc/db/tls/database.ca
  # - --cert-file=/etc/db/tls/database.crt
  # - --key-file=/etc/db/tls/database.key
  # - --skip-verify=true
  # - --watch-progress-notify-interval=5s
  # - --compact-interval=5m
  # - --compact-interval-jitter=0
  # - --compact-timeout=5s
  # - --compact-min-retain=1000
  # - --compact-batch-size=1000
  # - --poll-batch-size=500

For the operator:
args:
  - --metrics-bind-address=:8443
  - --leader-elect
  # - --enable-http2=true
  - --health-probe-bind-address=:8081
  - --metrics-secure
  # - --metrics-cert-path=/etc/harikube-operator-metrics-crt
  # - --metrics-cert-name=tls.crt
  # - --metrics-cert-key=tls.key
  - --webhook-cert-path=/etc/harikube-operator-crt
  # - --webhook-cert-name=tls.crt
  # - --webhook-cert-key=tls.key
6. Applicate 
For more details or advanced options visit harikube.info
6.1 Create Your First Custom Resource Definition.
_____________________________________________________________________________________
kubectl apply -f https://raw.githubusercontent.com/kubernetes/website/main/content/en/examples/customresourcedefinition/shirt-resource-definition.yaml
_____________________________________________________________________________________
By default, the Kubernetes Controller Manager caches every resource to support background operations, which might you don’t need for custom resources. To reduce memory usage and improve performance in high-volume environments, you can label specific resources with skip-controller-manager-metadata-caching to exclude them from being cached.
6.2 Ensure Label with Mutation Admission Webhook
MutatingAdmissionPolicies allow you to modify (or “mutate”) incoming requests to the Kubernetes API.
However, if you only need a declarative policy to ensure a label on each resources, the MutatingAdmissionPolicy is a simpler and more effective choice. We’ve provided a simple example below, but for complete and detailed information, please refer to the following the link: Mutating Admission Policy.
To use the feature, enable the MutatingAdmissionPolicy feature gate (which is off by default) and set 
_____________________________________________________________________________________
--runtime-config=admissionregistration.k8s.io/v1beta1=true on the kube-apiserver.
_____________________________________________________________________________________

6.3 Create Your First Custom Resources
_____________________________________________________________________________________
cat | kubectl apply -f - <<EOF
---
apiVersion: stable.example.com/v1
kind: Shirt
metadata:
  name: example1
spec:
  color: blue
  size: S
---
apiVersion: stable.example.com/v1
kind: Shirt
metadata:
  name: example2
spec:
  color: blue
  size: M
---
apiVersion: stable.example.com/v1
kind: Shirt
metadata:
  name: example3
spec:
  color: green
  size: M
EOF
_____________________________________________________________________________________


Verify the resources are exists.
_____________________________________________________________________________________

copy
kubectl get shirts
NAME       COLOR   SIZE
example1   blue    S
example2   blue    M
example3   green   M
_____________________________________________________________________________________

6.4 Custom Resource Versioning & Storage Migration
HariKube supports storage-side filtering by persisting resource field selectors directly in the database. To maintain accuracy, HariKube tracks the storage version of each resource, ensuring that saved selectors always match the current storage schema.

When you update a Custom Resource definition, the required action depends on whether the storage version or the selector logic has changed:

Scenario						Impact				Action Required 
New CR version (Storage version unchanged)		Metadata change only		Nothing
New Storage version (Selectors unchanged)		Schema version bump only		Nothing
New Storage version + New Selectors		Selectors are now out of sync	Migration Needed

Migration Strategies
If a migration is required, you can choose a strategy based on your dataset size and uptime requirements.
Why it’s easy: Because HariKube persists fields in JSON format, you can use standard SQL JSON functions to update thousands of records with a single command.

_____________________________________________________________________________________
SELECT * FROM kine_fields;
_____________________________________________________________________________________
...
424|/registry/stable.example.com/shirts/default/example1|shirts.stable.example.com/v1|{"metadata_name":"example1","metadata_namespace":"default","spec_color":"blue","spec_size":"S"}
...
_____________________________________________________________________________________

On the fly migrations
These strategies allow your service to stay online, though they may impact performance during the transition. Temporarily disable storage-side filtering. Toggle the disableStorageLevelFiltering flag to true in your backend configuration. Disabling storage filtering forces the database to return the entire dataset to the API server, which significantly increases memory and latency for large datasets.

Best for small datasets or services where brief slowness is acceptable.
Native Kubernetes Re-apply: Perform a standard paginated GET and UPDATE cycle via the Kubernetes API. Safest approach; utilizes native Kubernetes logic without any custom development.
SQL Migration: Execute a custom SQL script directly against the underlying database to update selectors in bulk while the system is running.

Offline migrations
Temporarily disable services that depend on the resource to prevent errors caused by mismatched selectors. Deploy new version of Custom Resource Definition, then start migration of the data.

Best for large datasets where you can afford a brief maintenance window to ensure data integrity.
Native Kubernetes Re-apply: Perform a standard paginated GET and UPDATE cycle via the Kubernetes API. Safest approach; utilizes native Kubernetes logic without any custom development.
SQL Migration: Execute a custom SQL script directly against the underlying database to update selectors in bulk.

7. Support
inspirNation BT
Mail to: support@inspirnation.eu

8. Uninstall: 
How to Uninstall
