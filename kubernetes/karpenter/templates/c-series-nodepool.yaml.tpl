---
# EC2NodeClass for C-series compute-optimized instances
# Optimized for compute-intensive workloads
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: c-series-compute
  labels:
    architecture: amd64
    purpose: compute-optimized
    instance-category: c-series
spec:
  # AMI selection - using Amazon Linux 2023 (AL2023)
  amiSelectorTerms:
    - alias: al2023@latest

  # IAM role created by Karpenter Terraform module
  # Injected from Terraform output: karpenter_node_iam_role_name
  role: "${node_role_name}"

  # Subnet discovery using tags
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${cluster_name}"

  # Security group discovery using tags
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${cluster_name}"

  # User data for node configuration
  userData: |
    #!/bin/bash
    echo "C-series compute-optimized node initialized for cluster ${cluster_name}"

  # Tags to apply to EC2 instances
  tags:
    Name: karpenter-c-series-node
    Architecture: amd64
    InstanceCategory: compute-optimized
    ManagedBy: Karpenter
    NodePool: c-series-compute
    Cluster: "${cluster_name}"

  # Block device mappings - larger for compute workloads
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 100Gi
        volumeType: gp3
        iops: 3000
        throughput: 125
        encrypted: true
        deleteOnTermination: true

  # Metadata options for IMDS
  metadataOptions:
    httpEndpoint: enabled
    httpProtocolIPv6: disabled
    httpPutResponseHopLimit: 2
    httpTokens: required

---
# NodePool for C-series compute-optimized workloads
# Best for: CPU-intensive tasks, batch processing, high-performance computing
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: c-series-compute
  labels:
    architecture: amd64
    instance-category: c-series
spec:
  # Reference to EC2NodeClass
  template:
    metadata:
      labels:
        karpenter.sh/nodepool: c-series-compute
        architecture: amd64
        node-type: compute-optimized
        instance-category: c-series
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: c-series-compute

      # Requirements for node selection
      requirements:
        # x86 architecture only
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]

        # Operating system
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]

        # Only C-series instances (compute-optimized)
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c"]

        # Modern generations only (6th gen and newer)
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["5"]

        # C-series instance families
        - key: karpenter.k8s.aws/instance-family
          operator: In
          values: ["c7i", "c7a", "c6i", "c6a", "c6in"]

        # CPU range for compute workloads
        - key: karpenter.k8s.aws/instance-cpu
          operator: In
          values: ["4", "8", "16", "32", "64"]

        # Capacity type: balanced mix
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]

        # Availability zones
        - key: topology.kubernetes.io/zone
          operator: In
          values: ["${region}a", "${region}b", "${region}c"]

      # Taints for workload isolation
      taints:
        - key: "workload-type"
          value: "compute-intensive"
          effect: "NoSchedule"

  # Limits for this NodePool
  limits:
    cpu: "500"
    memory: 1000Gi

  # Disruption budget for node lifecycle
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 60s
    budgets:
      - nodes: "10%"
        schedule: "@daily"
        duration: 30m

  # Weight for scheduling priority
  weight: 15
