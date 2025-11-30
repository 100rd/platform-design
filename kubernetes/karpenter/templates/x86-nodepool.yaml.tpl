---
# EC2NodeClass for x86 architecture
# Defines AWS-specific configuration for nodes
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: x86-general-purpose
  labels:
    architecture: amd64
    purpose: general-workloads
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
    echo "x86 node initialized for cluster ${cluster_name}"

  # Tags to apply to EC2 instances
  tags:
    Name: karpenter-x86-node
    Architecture: amd64
    ManagedBy: Karpenter
    NodePool: x86-general-purpose
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
# NodePool for x86/amd64 workloads
# Defines scheduling and scaling behavior
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: x86-general-purpose
  labels:
    architecture: amd64
spec:
  # Reference to EC2NodeClass
  template:
    metadata:
      labels:
        karpenter.sh/nodepool: x86-general-purpose
        architecture: amd64
        node-type: general-purpose
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: x86-general-purpose

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

        # Instance categories
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r"]

        # Instance generations (only modern ones)
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["5"]

        # Instance families - Intel and AMD
        - key: karpenter.k8s.aws/instance-family
          operator: In
          values: ["m6i", "m6a", "m7i", "m7a", "c6i", "c6a", "c7i", "c7a", "r6i", "r6a", "r7i", "r7a"]

        # CPU options
        - key: karpenter.k8s.aws/instance-cpu
          operator: In
          values: ["2", "4", "8", "16", "32"]

        # Capacity type: 80% spot, 20% on-demand
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]

        # Availability zones
        - key: topology.kubernetes.io/zone
          operator: In
          values: ["${region}a", "${region}b", "${region}c"]

      # Taints for workload isolation (optional)
      taints: []

  # Limits for this NodePool
  limits:
    cpu: "1000"
    memory: 1000Gi

  # Disruption budget for node lifecycle
  disruption:
    # Consolidation settings
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30s

    # Budget for disruptions (PDB-like)
    budgets:
      - nodes: "10%"
        schedule: "@daily"
        duration: 30m

  # Weight for scheduling priority
  weight: 10

---
# Example usage in a deployment:
# apiVersion: apps/v1
# kind: Deployment
# metadata:
#   name: x86-app
# spec:
#   template:
#     spec:
#       nodeSelector:
#         kubernetes.io/arch: amd64
#         karpenter.sh/nodepool: x86-general-purpose
