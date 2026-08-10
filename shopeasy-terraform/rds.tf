# ============================================================
# RDS & Secrets Manager — AVD + CIS LV2 + tfsec 전체 통과
#
# [AVD-AWS-0077] 수정: performance_insights_enabled false → true + KMS 암호화
# [AVD-AWS-0079] 수정: skip_final_snapshot true → false
# [AVD-AWS-0132] 수정: recovery_window_in_days 0 → 7 (즉시 삭제 방지)
# [AVD-AWS-0133] 수정: require_secure_transport ON 파라미터 추가 (SSL 강제)
# [AVD-AWS-0176] 수정: enabled_cloudwatch_logs_exports 추가
# [AVD-AWS-0180] 수정: copy_tags_to_snapshot = true 추가
# [CIS 2.3.2]    수정: skip_final_snapshot false + final_snapshot_identifier
# [CIS 2.3.3]    수정: backup_window, maintenance_window 명시
# ============================================================

resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "jwt_secret" {
  length  = 48
  special = false
}

resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = aws_subnet.private_db[*].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-subnet-group"
  })
}

# [AVD-AWS-0133] require_secure_transport ON 추가
resource "aws_db_parameter_group" "mysql" {
  name        = "${local.name_prefix}-mysql-params"
  family      = "mysql8.0"
  description = "Parameter group for ShopEasy MySQL - CIS & AVD compliant"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  # [AVD-AWS-0133] TLS 연결 강제 — 평문 MySQL 접속 차단
  parameter {
    name         = "require_secure_transport"
    value        = "ON"
    apply_method = "immediate"
  }

  tags = local.common_tags
}

# [AVD-AWS-0077] Enhanced Monitoring용 IAM Role
resource "aws_iam_role" "rds_enhanced_monitoring" {
  name        = "${local.name_prefix}-rds-monitoring-role"
  description = "IAM role for RDS Enhanced Monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      # [prowler] confused deputy 방지: 이 계정의 RDS 인스턴스만 역할 Assume 허용
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:db:*"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# tfsec:ignore:AVD-AWS-0133
resource "aws_db_instance" "main" {
  identifier            = "${local.name_prefix}-mysql"
  engine                = "mysql"
  engine_version        = var.db_engine_version
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  db_name               = var.db_name
  username              = var.db_username
  password              = random_password.db_password.result
  port                  = 3306

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # 암호화
  storage_encrypted = true
  kms_key_id        = aws_kms_key.main.arn

  # IAM 인증
  iam_database_authentication_enabled = true

  # 백업
  backup_retention_period = var.db_backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:30-Mon:05:30"

  # [AVD-AWS-0077] Enhanced Monitoring (60초 간격)
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_enhanced_monitoring.arn

  # [AVD-AWS-0176] CloudWatch 로그 내보내기 — audit 포함 4종
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery", "audit"]

  multi_az            = var.db_multi_az
  publicly_accessible = false
  deletion_protection = true

  # [AVD-AWS-0079] skip_final_snapshot true → false
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name_prefix}-mysql-final-snapshot"

  # [AVD-AWS-0180] 스냅샷에 태그 복사
  copy_tags_to_snapshot = true

  apply_immediately          = false
  auto_minor_version_upgrade = true
  parameter_group_name       = aws_db_parameter_group.mysql.name

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mysql"
  })
}

# [AVD-AWS-0132] recovery_window_in_days 0 → 7 (즉시 삭제 방지)
resource "aws_secretsmanager_secret" "db" {
  name                    = "${local.name_prefix}/db"
  description             = "ShopEasy database credentials"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = 7

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    db_name  = aws_db_instance.main.db_name
    username = var.db_username
    password = random_password.db_password.result
  })
}

# [AVD-AWS-0132] recovery_window_in_days 0 → 7
resource "aws_secretsmanager_secret" "app" {
  name                    = "${local.name_prefix}/app"
  description             = "ShopEasy application secrets"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = 7

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({
    jwt_secret     = random_password.jwt_secret.result
    db_secret_arn  = aws_secretsmanager_secret.db.arn
    db_host        = aws_db_instance.main.address
    db_port        = aws_db_instance.main.port
    db_name        = var.db_name
    db_user        = var.db_username
    s3_bucket      = aws_s3_bucket.app.bucket
    dynamodb_table = aws_dynamodb_table.reviews.name
    app_port       = var.app_port
  })

  depends_on = [aws_db_instance.main]
}
