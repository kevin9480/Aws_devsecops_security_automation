# ============================================================
# 계정 수준 기본값 설정
# [prowler] ec2_ebs_default_encryption     - EBS 기본 암호화
# [prowler] ec2_instance_account_imdsv2    - IMDSv2 계정 기본값
# [prowler] s3_account_level_public_access - S3 계정 퍼블릭 차단
# [prowler] securityhub_enabled            - Security Hub 활성화
# ============================================================

# EBS 계정 수준 기본 암호화 활성화
resource "aws_ebs_encryption_by_default" "main" {
  enabled = true
}

# EBS 기본 암호화에 CMK 지정 (AWS 관리형 키 대신 프로젝트 KMS 키 사용)
resource "aws_ebs_default_kms_key" "main" {
  key_arn    = aws_kms_key.main.arn
  depends_on = [aws_ebs_encryption_by_default.main]
}

# EC2 IMDSv2 계정 기본값 (launch template 설정과 동일하게 계정 레벨 적용)
resource "aws_ec2_instance_metadata_defaults" "main" {
  http_endpoint               = "enabled"
  http_tokens                 = "required"
  http_put_response_hop_limit = 1
}

# S3 계정 수준 퍼블릭 액세스 차단 (개별 버킷 설정과 이중 방어)
resource "aws_s3_account_public_access_block" "main" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Security Hub 활성화
resource "aws_securityhub_account" "main" {}
