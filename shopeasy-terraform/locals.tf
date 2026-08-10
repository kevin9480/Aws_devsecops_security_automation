locals {
  name_prefix = lower(replace(var.project_name, " ", "-"))

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )

  app_bucket_name  = "${local.name_prefix}-app-${data.aws_caller_identity.current.account_id}-${var.region}"
  logs_bucket_name = "${local.name_prefix}-logs-${data.aws_caller_identity.current.account_id}-${var.region}"

  eks_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}
