resource "aws_s3_bucket" "falco_alerts" {
  bucket = "shopeasy-falco-alerts-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name    = "shopeasy-falco-alerts"
    Project = "shopeasy"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "falco_alerts" {
  bucket = aws_s3_bucket.falco_alerts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "falco_alerts" {
  bucket = aws_s3_bucket.falco_alerts.id

  rule {
    id     = "expire-7days"
    status = "Enabled"

    expiration {
      days = 7
    }
  }
}

resource "aws_s3_bucket_public_access_block" "falco_alerts" {
  bucket = aws_s3_bucket.falco_alerts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role_policy" "falco_s3" {
  name = "shopeasy-falco-s3"
  role = aws_iam_role.app_irsa.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.falco_alerts.arn,
          "${aws_s3_bucket.falco_alerts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = [aws_kms_key.main.arn]
      }
    ]
  })
}

output "falco_s3_bucket" {
  value = aws_s3_bucket.falco_alerts.bucket
}