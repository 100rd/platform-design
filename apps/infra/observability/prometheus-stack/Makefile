.PHONY: help deps lint install upgrade uninstall test port-forward clean

# Variables
NAMESPACE ?= monitoring
RELEASE_NAME ?= prometheus-stack
KUBECONFIG ?= ~/.kube/config
CLUSTER_NAME ?= eks-us-east-1
ENVIRONMENT ?= production

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
RED := \033[0;31m
YELLOW := \033[0;33m
NC := \033[0m # No Color

help: ## Show this help message
	@echo "$(BLUE)Prometheus Stack - Makefile Commands$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'

deps: ## Update Helm chart dependencies
	@echo "$(BLUE)Updating Helm dependencies...$(NC)"
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo add bitnami https://charts.bitnami.com/bitnami
	helm repo update
	helm dependency update

lint: ## Lint Helm chart
	@echo "$(BLUE)Linting Helm chart...$(NC)"
	helm lint . \
		--values values.yaml \
		--values values-thanos.yaml
	@echo "$(GREEN)✓ Lint passed$(NC)"

validate: ## Validate Kubernetes manifests
	@echo "$(BLUE)Validating Kubernetes manifests...$(NC)"
	helm template $(RELEASE_NAME) . \
		--namespace $(NAMESPACE) \
		--values values.yaml \
		--values values-thanos.yaml \
		| kubectl apply --dry-run=client -f -
	@echo "$(GREEN)✓ Validation passed$(NC)"

template: ## Generate Kubernetes manifests
	@echo "$(BLUE)Generating Kubernetes manifests...$(NC)"
	helm template $(RELEASE_NAME) . \
		--namespace $(NAMESPACE) \
		--values values.yaml \
		--values values-thanos.yaml \
		--output-dir ./output
	@echo "$(GREEN)✓ Manifests generated in ./output$(NC)"

dry-run: ## Dry-run Helm install
	@echo "$(BLUE)Running dry-run install...$(NC)"
	helm upgrade --install $(RELEASE_NAME) . \
		--namespace $(NAMESPACE) \
		--create-namespace \
		--values values.yaml \
		--values values-thanos.yaml \
		--values values-$(ENVIRONMENT).yaml \
		--dry-run \
		--debug

install: deps ## Install Prometheus Stack
	@echo "$(BLUE)Installing Prometheus Stack...$(NC)"
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install $(RELEASE_NAME) . \
		--namespace $(NAMESPACE) \
		--values values.yaml \
		--values values-thanos.yaml \
		--set kube-prometheus-stack.prometheus.prometheusSpec.externalLabels.cluster=$(CLUSTER_NAME) \
		--wait \
		--timeout 15m
	@echo "$(GREEN)✓ Prometheus Stack installed successfully$(NC)"
	@make status

install-prod: deps ## Install Prometheus Stack for production
	@echo "$(BLUE)Installing Prometheus Stack for production...$(NC)"
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install $(RELEASE_NAME) . \
		--namespace $(NAMESPACE) \
		--values values.yaml \
		--values values-thanos.yaml \
		--values values-production.yaml \
		--wait \
		--timeout 15m
	@echo "$(GREEN)✓ Prometheus Stack (production) installed successfully$(NC)"
	@make status

upgrade: deps ## Upgrade Prometheus Stack
	@echo "$(BLUE)Upgrading Prometheus Stack...$(NC)"
	helm upgrade $(RELEASE_NAME) . \
		--namespace $(NAMESPACE) \
		--values values.yaml \
		--values values-thanos.yaml \
		--set kube-prometheus-stack.prometheus.prometheusSpec.externalLabels.cluster=$(CLUSTER_NAME) \
		--wait \
		--timeout 15m
	@echo "$(GREEN)✓ Prometheus Stack upgraded successfully$(NC)"
	@make status

uninstall: ## Uninstall Prometheus Stack
	@echo "$(RED)Uninstalling Prometheus Stack...$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		helm uninstall $(RELEASE_NAME) --namespace $(NAMESPACE); \
		echo "$(GREEN)✓ Prometheus Stack uninstalled$(NC)"; \
	else \
		echo "$(YELLOW)Uninstall cancelled$(NC)"; \
	fi

status: ## Show Prometheus Stack status
	@echo "$(BLUE)Prometheus Stack Status:$(NC)"
	@echo ""
	@echo "$(YELLOW)Helm Release:$(NC)"
	@helm list -n $(NAMESPACE) | grep $(RELEASE_NAME) || echo "Not installed"
	@echo ""
	@echo "$(YELLOW)Pods:$(NC)"
	@kubectl get pods -n $(NAMESPACE) -l "app.kubernetes.io/part-of=kube-prometheus-stack" -o wide
	@echo ""
	@echo "$(YELLOW)Services:$(NC)"
	@kubectl get svc -n $(NAMESPACE) -l "app.kubernetes.io/part-of=kube-prometheus-stack"
	@echo ""
	@echo "$(YELLOW)PersistentVolumeClaims:$(NC)"
	@kubectl get pvc -n $(NAMESPACE)

test: ## Run basic health checks
	@echo "$(BLUE)Running health checks...$(NC)"
	@echo ""
	@echo "$(YELLOW)Testing Prometheus...$(NC)"
	@kubectl exec -n $(NAMESPACE) prometheus-$(RELEASE_NAME)-kube-prometheus-prometheus-0 -c prometheus -- \
		wget -qO- http://localhost:9090/-/healthy && echo "$(GREEN)✓ Prometheus healthy$(NC)" || echo "$(RED)✗ Prometheus unhealthy$(NC)"
	@echo ""
	@echo "$(YELLOW)Testing Alertmanager...$(NC)"
	@kubectl exec -n $(NAMESPACE) alertmanager-$(RELEASE_NAME)-kube-prometheus-alertmanager-0 -- \
		wget -qO- http://localhost:9093/-/healthy && echo "$(GREEN)✓ Alertmanager healthy$(NC)" || echo "$(RED)✗ Alertmanager unhealthy$(NC)"
	@echo ""
	@echo "$(YELLOW)Testing Grafana...$(NC)"
	@kubectl exec -n $(NAMESPACE) deployment/$(RELEASE_NAME)-grafana -- \
		wget -qO- http://localhost:3000/api/health && echo "$(GREEN)✓ Grafana healthy$(NC)" || echo "$(RED)✗ Grafana unhealthy$(NC)"

test-metrics: ## Test Prometheus metrics ingestion
	@echo "$(BLUE)Testing metrics ingestion...$(NC)"
	@kubectl exec -n $(NAMESPACE) prometheus-$(RELEASE_NAME)-kube-prometheus-prometheus-0 -c prometheus -- \
		promtool query instant http://localhost:9090 'up{job="prometheus"}' | grep -q "1" && \
		echo "$(GREEN)✓ Metrics ingestion working$(NC)" || echo "$(RED)✗ Metrics ingestion failing$(NC)"

test-thanos: ## Test Thanos components
	@echo "$(BLUE)Testing Thanos components...$(NC)"
	@echo ""
	@echo "$(YELLOW)Testing Thanos Sidecar...$(NC)"
	@kubectl exec -n $(NAMESPACE) prometheus-$(RELEASE_NAME)-kube-prometheus-prometheus-0 -c thanos-sidecar -- \
		wget -qO- http://localhost:10902/-/healthy && echo "$(GREEN)✓ Thanos Sidecar healthy$(NC)" || echo "$(RED)✗ Thanos Sidecar unhealthy$(NC)"
	@echo ""
	@echo "$(YELLOW)Testing Thanos Query...$(NC)"
	@kubectl exec -n $(NAMESPACE) deployment/thanos-query -- \
		wget -qO- http://localhost:9090/-/healthy && echo "$(GREEN)✓ Thanos Query healthy$(NC)" || echo "$(RED)✗ Thanos Query unhealthy$(NC)"

port-forward: ## Port-forward to services
	@echo "$(BLUE)Starting port-forwards...$(NC)"
	@echo "$(YELLOW)Prometheus:$(NC)    http://localhost:9090"
	@echo "$(YELLOW)Alertmanager:$(NC)  http://localhost:9093"
	@echo "$(YELLOW)Grafana:$(NC)       http://localhost:3000 (admin/changeme)"
	@echo "$(YELLOW)Thanos Query:$(NC)  http://localhost:19090"
	@echo ""
	@echo "$(RED)Press Ctrl+C to stop$(NC)"
	@echo ""
	@trap 'kill 0' EXIT; \
		kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-kube-prometheus-prometheus 9090:9090 & \
		kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-kube-prometheus-alertmanager 9093:9093 & \
		kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-grafana 3000:80 & \
		kubectl port-forward -n $(NAMESPACE) svc/thanos-query 19090:9090 & \
		wait

logs-prometheus: ## Tail Prometheus logs
	@kubectl logs -n $(NAMESPACE) -f prometheus-$(RELEASE_NAME)-kube-prometheus-prometheus-0 -c prometheus

logs-thanos: ## Tail Thanos sidecar logs
	@kubectl logs -n $(NAMESPACE) -f prometheus-$(RELEASE_NAME)-kube-prometheus-prometheus-0 -c thanos-sidecar

logs-grafana: ## Tail Grafana logs
	@kubectl logs -n $(NAMESPACE) -f deployment/$(RELEASE_NAME)-grafana

logs-alertmanager: ## Tail Alertmanager logs
	@kubectl logs -n $(NAMESPACE) -f alertmanager-$(RELEASE_NAME)-kube-prometheus-alertmanager-0

exec-prometheus: ## Exec into Prometheus pod
	@kubectl exec -n $(NAMESPACE) -it prometheus-$(RELEASE_NAME)-kube-prometheus-prometheus-0 -c prometheus -- /bin/sh

exec-grafana: ## Exec into Grafana pod
	@kubectl exec -n $(NAMESPACE) -it deployment/$(RELEASE_NAME)-grafana -- /bin/bash

backup: ## Backup Grafana dashboards and PrometheusRules
	@echo "$(BLUE)Backing up Grafana dashboards and PrometheusRules...$(NC)"
	@mkdir -p backups
	@kubectl get configmaps -n $(NAMESPACE) -l grafana_dashboard=1 -o yaml > backups/grafana-dashboards-$$(date +%Y%m%d-%H%M%S).yaml
	@kubectl get prometheusrules -n $(NAMESPACE) -o yaml > backups/prometheus-rules-$$(date +%Y%m%d-%H%M%S).yaml
	@echo "$(GREEN)✓ Backup completed in ./backups/$(NC)"

restore: ## Restore Grafana dashboards and PrometheusRules
	@echo "$(BLUE)Restoring Grafana dashboards and PrometheusRules...$(NC)"
	@if [ -z "$(FILE)" ]; then \
		echo "$(RED)Error: FILE variable required$(NC)"; \
		echo "Usage: make restore FILE=backups/grafana-dashboards-20240101-120000.yaml"; \
		exit 1; \
	fi
	@kubectl apply -f $(FILE)
	@echo "$(GREEN)✓ Restore completed$(NC)"

clean: ## Clean generated files
	@echo "$(BLUE)Cleaning generated files...$(NC)"
	@rm -rf output/
	@rm -rf charts/
	@rm -f Chart.lock
	@echo "$(GREEN)✓ Clean completed$(NC)"

docs: ## Generate documentation
	@echo "$(BLUE)Generating documentation...$(NC)"
	@helm-docs
	@echo "$(GREEN)✓ Documentation generated$(NC)"

check-scale: ## Check if scaling is needed
	@echo "$(BLUE)Checking scale metrics...$(NC)"
	@echo ""
	@echo "$(YELLOW)Active Series:$(NC)"
	@kubectl exec -n $(NAMESPACE) prometheus-$(RELEASE_NAME)-kube-prometheus-prometheus-0 -c prometheus -- \
		promtool query instant http://localhost:9090 'prometheus_tsdb_head_series' | grep value || true
	@echo ""
	@echo "$(YELLOW)Ingestion Rate (samples/s):$(NC)"
	@kubectl exec -n $(NAMESPACE) prometheus-$(RELEASE_NAME)-kube-prometheus-prometheus-0 -c prometheus -- \
		promtool query instant http://localhost:9090 'rate(prometheus_tsdb_head_samples_appended_total[5m])' | grep value || true
	@echo ""
	@echo "$(YELLOW)Query Latency P99:$(NC)"
	@kubectl exec -n $(NAMESPACE) prometheus-$(RELEASE_NAME)-kube-prometheus-prometheus-0 -c prometheus -- \
		promtool query instant http://localhost:9090 'histogram_quantile(0.99, rate(prometheus_http_request_duration_seconds_bucket[5m]))' | grep value || true

argocd-apply: ## Apply ArgoCD Application
	@echo "$(BLUE)Applying ArgoCD Application...$(NC)"
	@kubectl apply -f argocd-application.yaml
	@echo "$(GREEN)✓ ArgoCD Application created$(NC)"
	@kubectl get application -n argocd prometheus-stack

argocd-sync: ## Sync ArgoCD Application
	@echo "$(BLUE)Syncing ArgoCD Application...$(NC)"
	@argocd app sync prometheus-stack
	@argocd app wait prometheus-stack

argocd-status: ## Show ArgoCD Application status
	@argocd app get prometheus-stack

# Default target
.DEFAULT_GOAL := help
