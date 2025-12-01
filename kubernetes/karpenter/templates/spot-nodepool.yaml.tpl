---
# EC2NodeClass for Spot instances
# Highly flexible for maximum spot availability and cost savings
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: spot-flexible
  labels:
    capacity-type: spot
    purpose: cost-optimized
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
    echo "Spot instance node initialized for cluster ${cluster_name}"

  # Tags to apply to EC2 instances
  tags:
    Name: karpenter-spot-node
    CapacityType: spot
    CostOptimized: "true"
    ManagedBy: Karpenter
    NodePool: spot-flexible
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
# NodePool for pure Spot instances
# Maximum cost savings (up to 90%) with high instance diversity
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: spot-flexible
  labels:
    capacity-type: spot
spec:
  # Reference to EC2NodeClass
  template:
    metadata:
      labels:
        karpenter.sh/nodepool: spot-flexible
        capacity-type: spot
        node-type: cost-optimized
        interruption-tolerant: "true"
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: spot-flexible

      # Requirements for node selection
      requirements:
        # Support both x86 and ARM64 for maximum flexibility
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64", "arm64"]

        # Operating system
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]

        # Broad instance categories
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["m", "c", "r", "t"]

        # Modern generations only
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["5"]

        # Wide range of instance families
        - key: karpenter.k8s.aws/instance-family
          operator: In
          values:
            - "m7i"
            - "m7a"
            - "m6i"
            - "m6a"
            - "c7i"
            - "c7a"
            - "c6i"
            - "c6a"
            - "r7i"
            - "r7a"
            - "r6i"
            - "r6a"
            - "t3"
            - "m7g"
            - "m7gd"
            - "c7g"
            - "c7gd"
            - "r7g"
            - "r7gd"
            - "m6g"
            - "m6gd"
            - "c6g"
            - "c6gd"
            - "r6g"
            - "r6gd"
            - "t4g"

        # Flexible CPU range
        - key: karpenter.k8s.aws/instance-cpu
          operator: In
          values: ["2", "4", "8", "16", "32"]

        # SPOT ONLY - 100% spot
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]

        # All availability zones
        - key: topology.kubernetes.io/zone
          operator: In
          values: ["${region}a", "${region}b", "${region}c"]

      # Taints to indicate spot nature
      taints:
        - key: "karpenter.sh/spot"
          value: "true"
          effect: "NoSchedule"

  # Limits for this NodePool
  limits:
    cpu: "1000"
    memory: 2000Gi

  # Disruption budget
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 15s
    budgets:
      - nodes: "20%"
        schedule: "@daily"
        duration: 1h

  # Weight for scheduling priority
  weight: 50
