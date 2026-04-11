package terraform.no_unrestricted_sg_ingress

import rego.v1

# ---------------------------------------------------------------------------
# Policy: No security groups with unrestricted ingress (0.0.0.0/0 or ::/0)
#
# Applies to:
#   - aws_security_group (inline ingress blocks)
#   - aws_security_group_rule (type = "ingress")
#   - aws_vpc_security_group_ingress_rule
#
# Port 443 (HTTPS) is allowed from any CIDR because it is a common legitimate
# pattern for load-balancer listeners. All other unrestricted ingress is denied.
# ---------------------------------------------------------------------------

_open_cidrs := {"0.0.0.0/0", "::/0"}

_is_unrestricted_cidr(cidr_blocks) if {
  some c in cidr_blocks
  c in _open_cidrs
}

# Skip HTTPS (443) — legitimate for public-facing load balancers
_is_sensitive_port(from_port, to_port) if {
  not (from_port <= 443; 443 <= to_port; from_port == to_port)
  true
}

# aws_security_group — inline ingress blocks
deny contains msg if {
  some addr, rc in input.resource_changes
  rc.type == "aws_security_group"
  actions := rc.change.actions
  not (actions == ["no-op"])
  not (actions == ["read"])
  some rule in rc.change.after.ingress
  _is_unrestricted_cidr(object.get(rule, "cidr_blocks", []))
  from_port := object.get(rule, "from_port", 0)
  to_port := object.get(rule, "to_port", 65535)
  not (from_port == 443; to_port == 443)
  msg := sprintf(
    "POLICY VIOLATION [sg-unrestricted-ingress]: resource %q has unrestricted ingress on ports %d-%d from 0.0.0.0/0 or ::/0",
    [addr, from_port, to_port],
  )
}

# aws_security_group — inline ingress blocks (IPv6)
deny contains msg if {
  some addr, rc in input.resource_changes
  rc.type == "aws_security_group"
  actions := rc.change.actions
  not (actions == ["no-op"])
  not (actions == ["read"])
  some rule in rc.change.after.ingress
  _is_unrestricted_cidr(object.get(rule, "ipv6_cidr_blocks", []))
  from_port := object.get(rule, "from_port", 0)
  to_port := object.get(rule, "to_port", 65535)
  not (from_port == 443; to_port == 443)
  msg := sprintf(
    "POLICY VIOLATION [sg-unrestricted-ingress-ipv6]: resource %q has unrestricted IPv6 ingress on ports %d-%d",
    [addr, from_port, to_port],
  )
}

# aws_security_group_rule (standalone ingress rule)
deny contains msg if {
  some addr, rc in input.resource_changes
  rc.type == "aws_security_group_rule"
  actions := rc.change.actions
  not (actions == ["no-op"])
  not (actions == ["read"])
  rc.change.after.type == "ingress"
  _is_unrestricted_cidr(object.get(rc.change.after, "cidr_blocks", []))
  from_port := object.get(rc.change.after, "from_port", 0)
  to_port := object.get(rc.change.after, "to_port", 65535)
  not (from_port == 443; to_port == 443)
  msg := sprintf(
    "POLICY VIOLATION [sg-rule-unrestricted-ingress]: resource %q allows unrestricted ingress on ports %d-%d",
    [addr, from_port, to_port],
  )
}

# aws_vpc_security_group_ingress_rule
deny contains msg if {
  some addr, rc in input.resource_changes
  rc.type == "aws_vpc_security_group_ingress_rule"
  actions := rc.change.actions
  not (actions == ["no-op"])
  not (actions == ["read"])
  cidr := object.get(rc.change.after, "cidr_ipv4", "")
  cidr in _open_cidrs
  from_port := object.get(rc.change.after, "from_port", 0)
  to_port := object.get(rc.change.after, "to_port", 65535)
  not (from_port == 443; to_port == 443)
  msg := sprintf(
    "POLICY VIOLATION [vpc-sg-unrestricted-ingress]: resource %q allows unrestricted ingress on ports %d-%d",
    [addr, from_port, to_port],
  )
}
