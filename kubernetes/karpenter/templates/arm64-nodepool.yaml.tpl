---
# EC2NodeClass for ARM64/Graviton architecture
# Defines AWS-specific configuration for Graviton nodes
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: arm64-graviton
  labels:
    architecture: arm64
    purpose: cost-optimized-workloads
spec:
  # AMI selection - using Amazon Linux 2023 (AL2023) for ARM64
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
    echo "ARM64 Graviton node initialized for cluster ${cluster_name}"

  # Tags to apply to EC2 instances
  tags:
    Name: karpenter-arm64-node
    Architecture: arm64
    Processor: Graviton
    ManagedBy: Karpenter
    NodePool: arm64-graviton
    Cluster: "${cluster_name}"

  # Block device mappings
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 50Gi
        volumeType: gp3
        encrypted: true
        deleteOnTermination: true

  # Metadata options for IMDS
  metadataOptions:
    httpEndpoint: enabled
    httpProtocolIPv6: disabled
    httpPutResponseHopLimit: 2
    httpTokens: required

---
# NodePool for ARM64/Graviton workloads
# Optimized for cost-efficiency with 20-40% savings over x86
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: arm64-graviton
  labels:
    architecture: arm64
    processor: graviton
spec:
  # Reference to EC2NodeClass
  template:
    metadata:
      labels:
        karpenter.sh/nodepool: arm64-graviton
        architecture: arm64
        processor: graviton
        node-type: cost-optimized
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: arm64-graviton

      # Requirements for node selection
      requirements:
        # ARM64 architecture only
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64"]

        # Operating system
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]

        # Instance categories (Graviton processors)
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r", "t"]

        # Instance generations (Graviton 2, 3, 4)
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["5"]

        # Graviton instance families
        # m7g/c7g/r7g = Graviton3
        # m6g/c6g/r6g = Graviton2
        # t4g = Graviton2 burstable
        - key: karpenter.k8s.aws/instance-family
          operator: In
          values: ["m7g", "m7gd", "c7g", "c7gd", "c7gn", "r7g", "r7gd", "m6g", "m6gd", "c6g", "c6gd", "c6gn", "r6g", "r6gd", "t4g"]

        # CPU options
        - key: karpenter.k8s.aws/instance-cpu
          operator: In
          values: ["2", "4", "8", "16", "32", "64"]

        # Capacity type: Prefer spot for maximum cost savings
        # 90% spot, 10% on-demand for better cost optimization
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]

        # Availability zones
        - key: topology.kubernetes.io/zone
          operator: In
          values: ["${region}a", "${region}b", "${region}c"]

      # Taints for workload isolation (optional)
      # Uncomment to require explicit ARM64 toleration
      # taints:
      #   - key: "arm64"
      #     value: "true"
      #     effect: "NoSchedule"
      taints: []

  # Limits for this NodePool
  limits:
    cpu: "1000"
    memory: 1000Gi

  # Disruption budget for node lifecycle
  disruption:
    # Consolidation settings - more aggressive for cost savings
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30s

    # Budget for disruptions (PDB-like)
    budgets:
      - nodes: "15%"
        schedule: "@daily"
        duration: 30m

  # Weight for scheduling priority (higher = preferred)
  # Higher weight prefers Graviton for cost savings
  weight: 20

---
# Example usage in a deployment:
# apiVersion: apps/v1
# kind: Deployment
# metadata:
#   name: arm64-app
# spec:
#   template:
#     spec:
#       nodeSelector:
#         kubernetes.io/arch: arm64
#         karpenter.sh/nodepool: arm64-graviton
#
# Benefits of Graviton:
# - 20-40% better price/performance vs x86
# - Lower power consumption
# - Modern ARM architecture
# - Best for: web apps, microservices, data processing
