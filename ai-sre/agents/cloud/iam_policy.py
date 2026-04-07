"""IAM policy definition for the AWS Cloud Agent.

The cloud agent requires read-only access to EC2, EBS, VPC, GuardDuty,
SecurityHub, CloudTrail, Service Quotas, CloudWatch, Cost Explorer, and EKS.
"""

# Read-only IAM policy for the AWS Cloud Agent
# Attach to the agent's IRSA (IAM Roles for Service Accounts) role
IAM_POLICY_DOCUMENT: dict = {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "EC2ReadOnly",
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceStatus",
                "ec2:DescribeSpotInstanceRequests",
                "ec2:DescribeVolumes",
                "ec2:DescribeVolumeStatus",
                "ec2:DescribeTransitGatewayConnectPeers",
                "ec2:DescribeTransitGatewayAttachments",
                "ec2:DescribeFlowLogs",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeSubnets",
                "ec2:DescribeVpcs",
            ],
            "Resource": "*",
        },
        {
            "Sid": "ELBReadOnly",
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:DescribeLoadBalancers",
                "elasticloadbalancing:DescribeTargetGroups",
                "elasticloadbalancing:DescribeTargetHealth",
            ],
            "Resource": "*",
        },
        {
            "Sid": "CloudWatchReadOnly",
            "Effect": "Allow",
            "Action": [
                "cloudwatch:GetMetricData",
                "cloudwatch:DescribeAlarms",
                "cloudwatch:ListMetrics",
            ],
            "Resource": "*",
        },
        {
            "Sid": "CloudWatchLogsReadOnly",
            "Effect": "Allow",
            "Action": [
                "logs:GetLogEvents",
                "logs:FilterLogEvents",
                "logs:DescribeLogGroups",
            ],
            "Resource": "*",
        },
        {
            "Sid": "GuardDutyReadOnly",
            "Effect": "Allow",
            "Action": [
                "guardduty:GetFindings",
                "guardduty:ListFindings",
                "guardduty:GetDetector",
                "guardduty:ListDetectors",
            ],
            "Resource": "*",
        },
        {
            "Sid": "SecurityHubReadOnly",
            "Effect": "Allow",
            "Action": [
                "securityhub:GetFindings",
                "securityhub:DescribeHub",
            ],
            "Resource": "*",
        },
        {
            "Sid": "CloudTrailReadOnly",
            "Effect": "Allow",
            "Action": [
                "cloudtrail:LookupEvents",
            ],
            "Resource": "*",
        },
        {
            "Sid": "ServiceQuotasReadOnly",
            "Effect": "Allow",
            "Action": [
                "servicequotas:GetServiceQuota",
                "servicequotas:ListServiceQuotas",
                "servicequotas:GetAWSDefaultServiceQuota",
            ],
            "Resource": "*",
        },
        {
            "Sid": "CostExplorerReadOnly",
            "Effect": "Allow",
            "Action": [
                "ce:GetCostAndUsage",
                "ce:GetSavingsPlansUtilization",
                "ce:GetReservationUtilization",
            ],
            "Resource": "*",
        },
        {
            "Sid": "EKSReadOnly",
            "Effect": "Allow",
            "Action": [
                "eks:DescribeCluster",
                "eks:ListClusters",
                "eks:DescribeNodegroup",
                "eks:ListNodegroups",
            ],
            "Resource": "*",
        },
    ],
}

# IRSA annotation for the Kubernetes ServiceAccount
IRSA_ANNOTATION_KEY = "eks.amazonaws.com/role-arn"

# Recommended trust policy condition for IRSA
IRSA_TRUST_CONDITION = {
    "StringEquals": {
        "${OIDC_PROVIDER}:sub": "system:serviceaccount:ai-sre-system:aws-cloud-agent",
        "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
    }
}
