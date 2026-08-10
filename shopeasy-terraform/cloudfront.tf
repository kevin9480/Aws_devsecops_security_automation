# ============================================================
# CloudFront Origin Verification Secret
# ALB WAF의 RequireCloudFrontHeader 룰과 공유
# ============================================================
resource "random_password" "cf_origin_secret" {
  length  = 32
  special = false
}

# ============================================================
# CloudFront Distribution
# - Origin: ALB (deploy.yml에서 실제 ALB DNS로 갱신)
# - WAF: CloudFront 스코프 (us-east-1)
# - HTTPS 리다이렉트
# - 캐싱 비활성화 (동적 앱)
# ============================================================
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${local.name_prefix}-distribution"
  default_root_object = "index.html"

  # CloudFront 레벨 WAF 연결
  web_acl_id = aws_wafv2_web_acl.cloudfront.arn

  origin {
    # ALB DNS는 Terraform apply 시점에 알 수 없음
    # deploy.yml에서 ALB 프로비저닝 후 AWS CLI로 갱신
    domain_name = "placeholder.example.com"
    origin_id   = "${local.name_prefix}-alb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # ALB WAF가 이 헤더를 검증 → CloudFront 경유 트래픽만 ALB 통과
    custom_header {
      name  = "X-Origin-Verify"
      value = random_password.cf_origin_secret.result
    }
  }

  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "${local.name_prefix}-alb-origin"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    # 동적 앱: 캐싱 비활성화, 모든 헤더/쿼리/쿠키 전달
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0

    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies {
        forward = "all"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # 커스텀 도메인 없이 *.cloudfront.net 기본 인증서 사용 (HTTPS 자동 제공)
  # tfsec:ignore:AVD-AWS-0013 - cloudfront_default_certificate 사용 시 minimum_protocol_version 설정 불가 (ACM 인증서 필요)
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # origin은 deploy.yml에서 관리 → Terraform이 덮어쓰지 않도록
  lifecycle {
    ignore_changes = [origin]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-distribution"
  })
}
