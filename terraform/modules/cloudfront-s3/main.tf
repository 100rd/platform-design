# ---------------------------------------------------------------------------------------------------------------------
# CloudFront Distribution with S3 Origin
# ---------------------------------------------------------------------------------------------------------------------
# Provisions a CloudFront distribution using Origin Access Control (OAC) for private
# S3 bucket access. Includes geo-restriction, HTTPS enforcement, and an S3 bucket policy
# granting CloudFront read access to the origin bucket.
# ---------------------------------------------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------------------------------------------------
# Origin Access Control (modern replacement for OAI)
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "this" {
  name                              = var.name
  description                       = "OAC for ${var.name} S3 origin"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ---------------------------------------------------------------------------------------------------------------------
# CloudFront Distribution
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "this" {
  comment             = var.name
  enabled             = true
  default_root_object = ""
  price_class         = var.price_class
  aliases             = var.aliases
  web_acl_id          = var.web_acl_id

  # S3 Origin with OAC
  origin {
    domain_name              = var.s3_bucket_regional_domain_name
    origin_id                = "s3-${var.s3_bucket_id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  # Default cache behavior
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-${var.s3_bucket_id}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    # Use AWS managed CachingOptimized policy
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"

    default_ttl = var.default_ttl
    max_ttl     = var.max_ttl
  }

  # Geo restriction
  restrictions {
    geo_restriction {
      restriction_type = length(var.allowed_countries) > 0 ? "whitelist" : "none"
      locations        = var.allowed_countries
    }
  }

  # TLS certificate
  viewer_certificate {
    cloudfront_default_certificate = var.acm_certificate_arn == null
    acm_certificate_arn            = var.acm_certificate_arn
    ssl_support_method             = var.acm_certificate_arn != null ? "sni-only" : null
    minimum_protocol_version       = var.acm_certificate_arn != null ? "TLSv1.2_2021" : null
  }

  # Custom error response: map 403 (S3 access denied) to 404
  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = ""
    error_caching_min_ttl = 300
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------------------------------------------------
# S3 Bucket Policy — Allow CloudFront OAC to read from the origin bucket
# ---------------------------------------------------------------------------------------------------------------------

data "aws_iam_policy_document" "s3_cloudfront" {
  statement {
    sid    = "AllowCloudFrontServicePrincipalReadOnly"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${var.s3_bucket_arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudfront" {
  bucket = var.s3_bucket_id
  policy = data.aws_iam_policy_document.s3_cloudfront.json
}
