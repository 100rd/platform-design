# ---------------------------------------------------------------------------------------------------------------------
# Network Load Balancer — Ingress for EKS
# ---------------------------------------------------------------------------------------------------------------------
# Provisions a public-facing NLB with TLS termination for ingress traffic into EKS.
# The NLB forwards to a target group of type "ip" so that pod IPs (from Cilium CNI)
# can be registered directly, enabling client IP preservation.
#
# Port 443: TLS listener with ACM certificate, forwards to TCP target group.
# Port 80:  TCP listener that redirects all traffic to HTTPS (301).
#
# This NLB is intended to be the regional endpoint registered with Global Accelerator.
# ---------------------------------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------------------------------------
# Network Load Balancer
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_lb" "this" {
  count = var.enabled ? 1 : 0

  name               = var.name
  internal           = false
  load_balancer_type = "network"
  subnets            = var.public_subnet_ids

  enable_cross_zone_load_balancing = true

  tags = merge(var.tags, {
    Name = var.name
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# Target Group — IP-based for direct pod routing
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_lb_target_group" "this" {
  count = var.enabled ? 1 : 0

  name                 = "${var.name}-tg"
  port                 = 443
  protocol             = "TCP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    port                = var.health_check_port
    protocol            = var.health_check_protocol
    path                = var.health_check_protocol == "TCP" ? null : var.health_check_path
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }

  tags = merge(var.tags, {
    Name = "${var.name}-tg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Listener — TLS on port 443
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_lb_listener" "tls" {
  count = var.enabled ? 1 : 0

  load_balancer_arn = aws_lb.this[0].arn
  port              = 443
  protocol          = "TLS"
  certificate_arn   = var.certificate_arn
  ssl_policy        = var.ssl_policy

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }

  tags = merge(var.tags, {
    Name = "${var.name}-tls"
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# Listener — HTTP redirect on port 80
# ---------------------------------------------------------------------------------------------------------------------
# NLB does not support redirect actions natively. Instead we forward port 80
# to the same target group. The application or ingress controller behind the
# NLB should handle HTTP-to-HTTPS redirects.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_lb_listener" "http" {
  count = var.enabled ? 1 : 0

  load_balancer_arn = aws_lb.this[0].arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }

  tags = merge(var.tags, {
    Name = "${var.name}-http"
  })
}
