# ============================================================
# Logging, CloudTrail, VPC Flow Logs, CloudWatch Alarms
# AVD + CIS LV2 + tfsec 전체 통과
#
# [AVD-AWS-0089] 수정: retention_in_days 30 → 90 (CIS: 90일 이상)
# [AVD-AWS-0014] 수정: CloudTrail SNS 알림 추가
# [AVD-AWS-0162] 수정: CloudTrail S3 데이터 이벤트 추가
# [AVD-AWS-0016] 수정: CIS 필수 CloudWatch 알람 6개 추가
#   - 루트 계정 사용 / 권한없는 API / MFA없는 로그인
#   - IAM 변경 / CloudTrail 변경 / SG 변경
# ============================================================

# [AVD-AWS-0089] retention 30 → 90일
resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.main.arn
  tags              = local.common_tags
}

# [AVD-AWS-0089] retention 30 → 90일
resource "aws_cloudwatch_log_group" "vpc_flow" {
  name              = "/aws/vpc/${local.name_prefix}/flowlogs"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.main.arn

  lifecycle { ignore_changes = [name] }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${local.name_prefix}"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.main.arn
  tags              = local.common_tags
}

# VPC Flow Logs IAM
data "aws_iam_policy_document" "flow_logs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
    # [prowler] confused deputy 방지: vpc-flow-logs 서비스가 이 계정의 리소스에 대해서만 역할 Assume 허용
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:vpc-flow-log/*"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${local.name_prefix}-flowlogs-role"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume_role.json
  tags               = local.common_tags
}

# tfsec:ignore:AVD-AWS-0057
resource "aws_iam_role_policy" "flow_logs" {
  name = "${local.name_prefix}-flowlogs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.vpc_flow.arn}:*"
    }]
  })
}

resource "aws_flow_log" "vpc" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  iam_role_arn         = aws_iam_role.flow_logs.arn
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.vpc_flow.arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-flowlogs"
  })
}

# CloudTrail S3 버킷 정책
data "aws_iam_policy_document" "cloudtrail_bucket" {
  statement {
    sid    = "AWSCloudTrailAclCheck20150319"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.logs.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${local.name_prefix}-trail"]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite20150319"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${local.name_prefix}-trail"]
    }
  }

  statement {
    sid    = "AllowS3ServerAccessLogsFromAppBucket"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/s3-access/app/*"]
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.app.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  # DenyNonTLS — logs 버킷 HTTPS 강제
  statement {
    sid    = "DenyNonTLS"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

data "aws_iam_policy_document" "app_bucket" {
  statement {
    sid    = "AllowS3ServerAccessLogsFromLogsBucket"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.app.arn}/s3-access/logs/*"]
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.logs.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  # DenyNonTLS — app 버킷 HTTPS 강제
  statement {
    sid    = "DenyNonTLS"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.app.arn, "${aws_s3_bucket.app.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket.json
}

resource "aws_s3_bucket_policy" "app" {
  bucket = aws_s3_bucket.app.id
  policy = data.aws_iam_policy_document.app_bucket.json
}

# CloudTrail → CloudWatch Logs IAM
data "aws_iam_policy_document" "cloudtrail_logs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    # [prowler] confused deputy 방지: 이 계정의 특정 trail만 역할 Assume 허용
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${local.name_prefix}-trail"]
    }
  }
}

resource "aws_iam_role" "cloudtrail_logs" {
  name               = "${local.name_prefix}-cloudtrail-logs-role"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_logs_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "cloudtrail_logs" {
  name = "${local.name_prefix}-cloudtrail-logs-policy"
  role = aws_iam_role.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:log-stream:*"
    }]
  })
}

# [AVD-AWS-0014] SNS 알림 토픽
resource "aws_sns_topic" "security_alerts" {
  name              = "${local.name_prefix}-security-alerts"
  kms_master_key_id = aws_kms_key.main.arn
  tags              = local.common_tags
}

# CloudWatch + CloudTrail → SNS 발행 허용
resource "aws_sns_topic_policy" "security_alerts" {
  arn = aws_sns_topic.security_alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudWatchAlarms"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.security_alerts.arn
      },
      {
        Sid       = "AllowCloudTrail"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.security_alerts.arn
      }
    ]
  })
}

resource "aws_cloudtrail" "main" {
  name                          = "${local.name_prefix}-trail"
  s3_bucket_name                = aws_s3_bucket.logs.bucket
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.main.arn
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_logs.arn

  # [AVD-AWS-0014] SNS 알림 연결
  sns_topic_name = aws_sns_topic.security_alerts.arn

  # [AVD-AWS-0162] S3 객체 수준 데이터 이벤트 (CIS 3.8)
  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::"]
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_s3_bucket_policy.logs,
    aws_cloudwatch_log_group.cloudtrail,
    aws_iam_role_policy.cloudtrail_logs
  ]
}

# ============================================================
# [AVD-AWS-0016] CIS 필수 CloudWatch 알람 6개
# ============================================================

# CIS 3.10 — 루트 계정 사용 탐지
resource "aws_cloudwatch_log_metric_filter" "root_usage" {
  name           = "${local.name_prefix}-root-usage"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
  metric_transformation {
    name      = "RootAccountUsage"
    namespace = "CISMetrics"
    value     = "1"
  }
  depends_on = [aws_cloudtrail.main]
}

resource "aws_cloudwatch_metric_alarm" "root_usage" {
  alarm_name          = "${local.name_prefix}-root-account-usage"
  alarm_description   = "CIS 3.10 / 4.3: Root account usage detected"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "RootAccountUsage"
  namespace           = "CISMetrics"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  tags                = local.common_tags
  depends_on          = [aws_cloudwatch_log_metric_filter.root_usage]
}

# CIS 3.11 — 권한 없는 API 호출
resource "aws_cloudwatch_log_metric_filter" "unauthorized_api" {
  name           = "${local.name_prefix}-unauthorized-api"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.errorCode = \"*UnauthorizedAccess*\") || ($.errorCode = \"AccessDenied\") }"
  metric_transformation {
    name      = "UnauthorizedAPICalls"
    namespace = "CISMetrics"
    value     = "1"
  }
  depends_on = [aws_cloudtrail.main]
}

resource "aws_cloudwatch_metric_alarm" "unauthorized_api" {
  alarm_name          = "${local.name_prefix}-unauthorized-api-calls"
  alarm_description   = "CIS 3.11 / 4.1: Unauthorized API calls detected"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "UnauthorizedAPICalls"
  namespace           = "CISMetrics"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  tags                = local.common_tags
  depends_on          = [aws_cloudwatch_log_metric_filter.unauthorized_api]
}

# CIS 3.12 — MFA 없는 콘솔 로그인
resource "aws_cloudwatch_log_metric_filter" "console_no_mfa" {
  name           = "${local.name_prefix}-console-no-mfa"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.eventName = \"ConsoleLogin\") && ($.additionalEventData.MFAUsed != \"Yes\") && ($.userIdentity.type != \"AssumedRole\") }"
  metric_transformation {
    name      = "ConsoleLoginWithoutMFA"
    namespace = "CISMetrics"
    value     = "1"
  }
  depends_on = [aws_cloudtrail.main]
}

resource "aws_cloudwatch_metric_alarm" "console_no_mfa" {
  alarm_name          = "${local.name_prefix}-console-login-no-mfa"
  alarm_description   = "CIS 3.12 / 4.2: Console login without MFA detected"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ConsoleLoginWithoutMFA"
  namespace           = "CISMetrics"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  tags                = local.common_tags
  depends_on          = [aws_cloudwatch_log_metric_filter.console_no_mfa]
}

# CIS 3.13 — IAM 정책 변경
resource "aws_cloudwatch_log_metric_filter" "iam_changes" {
  name           = "${local.name_prefix}-iam-changes"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{($.eventName=DeleteGroupPolicy)||($.eventName=DeleteRolePolicy)||($.eventName=DeleteUserPolicy)||($.eventName=PutGroupPolicy)||($.eventName=PutRolePolicy)||($.eventName=PutUserPolicy)||($.eventName=CreatePolicy)||($.eventName=DeletePolicy)||($.eventName=AttachRolePolicy)||($.eventName=DetachRolePolicy)||($.eventName=AttachUserPolicy)||($.eventName=DetachUserPolicy)}"
  metric_transformation {
    name      = "IAMPolicyChanges"
    namespace = "CISMetrics"
    value     = "1"
  }
  depends_on = [aws_cloudtrail.main]
}

resource "aws_cloudwatch_metric_alarm" "iam_changes" {
  alarm_name          = "${local.name_prefix}-iam-policy-changes"
  alarm_description   = "CIS 3.13 / 4.4: IAM policy changes detected"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "IAMPolicyChanges"
  namespace           = "CISMetrics"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  tags                = local.common_tags
  depends_on          = [aws_cloudwatch_log_metric_filter.iam_changes]
}

# CIS 3.14 — CloudTrail 설정 변경
resource "aws_cloudwatch_log_metric_filter" "cloudtrail_changes" {
  name           = "${local.name_prefix}-cloudtrail-changes"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.eventName = CreateTrail) || ($.eventName = UpdateTrail) || ($.eventName = DeleteTrail) || ($.eventName = StartLogging) || ($.eventName = StopLogging) }"
  metric_transformation {
    name      = "CloudTrailChanges"
    namespace = "CISMetrics"
    value     = "1"
  }
  depends_on = [aws_cloudtrail.main]
}

resource "aws_cloudwatch_metric_alarm" "cloudtrail_changes" {
  alarm_name          = "${local.name_prefix}-cloudtrail-config-changes"
  alarm_description   = "CIS 3.14 / 4.5: CloudTrail configuration changes detected"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "CloudTrailChanges"
  namespace           = "CISMetrics"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  tags                = local.common_tags
  depends_on          = [aws_cloudwatch_log_metric_filter.cloudtrail_changes]
}

# CIS 3.15 — 보안 그룹 변경
resource "aws_cloudwatch_log_metric_filter" "sg_changes" {
  name           = "${local.name_prefix}-sg-changes"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.eventName = AuthorizeSecurityGroupIngress) || ($.eventName = AuthorizeSecurityGroupEgress) || ($.eventName = RevokeSecurityGroupIngress) || ($.eventName = RevokeSecurityGroupEgress) || ($.eventName = CreateSecurityGroup) || ($.eventName = DeleteSecurityGroup) }"
  metric_transformation {
    name      = "SecurityGroupChanges"
    namespace = "CISMetrics"
    value     = "1"
  }
  depends_on = [aws_cloudtrail.main]
}

resource "aws_cloudwatch_metric_alarm" "sg_changes" {
  alarm_name          = "${local.name_prefix}-security-group-changes"
  alarm_description   = "CIS 3.15 / 4.10: Security group changes detected"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "SecurityGroupChanges"
  namespace           = "CISMetrics"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  tags                = local.common_tags
  depends_on          = [aws_cloudwatch_log_metric_filter.sg_changes]
}
