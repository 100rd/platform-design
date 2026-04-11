mock_provider "aws" {}

variables {
  name                           = "test-cdn"
  s3_bucket_id                   = "test-bucket"
  s3_bucket_arn                  = "arn:aws:s3:::test-bucket"
  s3_bucket_regional_domain_name = "test-bucket.s3.us-east-1.amazonaws.com"
  tags = {
    Environment = "test"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

run "creates_distribution" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.this.comment == "test-cdn"
    error_message = "Distribution comment should match name"
  }
}

run "default_price_class" {
  command = plan

  assert {
    condition     = var.price_class == "PriceClass_100"
    error_message = "Default price class should be PriceClass_100 (EU/NA)"
  }
}

run "oac_created" {
  command = plan

  assert {
    condition     = aws_cloudfront_origin_access_control.this.name == "test-cdn"
    error_message = "OAC should be created with matching name"
  }
}
