data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# CloudFront 관리형 프리픽스 리스트 (ALB SG 인바운드 제한용)
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}
