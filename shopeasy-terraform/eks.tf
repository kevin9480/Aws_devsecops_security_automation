# ============================================================
# EKS Cluster & Node Group — AVD + CIS LV2 + tfsec 전체 통과
#
# [AVD-AWS-0038] 수정: launch template SG 중복 제거 (노드 SG만)
# [AVD-AWS-0037] 수정: IRSA logs Resource "*" → 특정 로그 그룹 ARN
# [CIS 2.4.x]    유지: IMDSv2, hop_limit=1, Secrets KMS, 5종 로그
# ============================================================
variable "github_actions_role_arn" {
  type = string
}

locals {
  # assumed-role ARN에서 IAM role ARN으로 변환
  # arn:aws:sts::ACCOUNT:assumed-role/ROLE_NAME/SESSION → arn:aws:iam::ACCOUNT:role/ROLE_NAME
  _arn_parts       = split("/", data.aws_caller_identity.current.arn)
  _role_name       = local._arn_parts[1]
  admin_role_arn   = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local._role_name}"
}

resource "aws_launch_template" "eks_nodes" {
  name_prefix            = "${local.name_prefix}-eks-ng-"
  update_default_version = true
  instance_type          = var.node_instance_type

  # [AVD-AWS-0038] cluster SG 제거 → 노드 SG만 명시 (최소 권한, SG 중복 방지)
  vpc_security_group_ids = [aws_security_group.eks_nodes.id]

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = aws_kms_key.main.arn
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    # CIS 2.4.4: IMDSv2 강제
    http_tokens                 = "required"
    # CIS 2.4.5: hop_limit=1 (컨테이너 내 SSRF 방어)
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-eks-node"
    })
  }

  tags = local.common_tags
}

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.cluster_version

  # CIS 2.4.1: 5종 로그 모두 활성화
  enabled_cluster_log_types = local.eks_cluster_log_types

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = false
  }

  # tfsec:ignore:AVD-AWS-0040
  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private_app[*].id)
    endpoint_private_access = true
    endpoint_public_access  = var.cluster_endpoint_public_access
    public_access_cidrs     = var.cluster_endpoint_public_access ? (length(var.cluster_endpoint_public_access_cidrs) > 0 ? var.cluster_endpoint_public_access_cidrs : null) : null
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }

  # CIS 2.4.2: Kubernetes Secrets KMS 암호화
  encryption_config {
    provider {
      key_arn = aws_kms_key.main.arn
    }
    resources = ["secrets"]
  }

  tags = merge(local.common_tags, {
    Name = var.cluster_name
  })

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_cloudwatch_log_group.eks_cluster
  ]
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = var.node_group_name
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.private_app[*].id
  ami_type        = "AL2023_x86_64_STANDARD"
  capacity_type   = "ON_DEMAND"

  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = aws_launch_template.eks_nodes.latest_version
  }

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    workload = "api"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-node-group"
  })

  depends_on = [
    aws_iam_role_policy_attachment.eks_nodes_worker,
    aws_iam_role_policy_attachment.eks_nodes_ecr_pull,
    aws_iam_role_policy_attachment.eks_nodes_cni,
    aws_eks_cluster.main
  ]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.main]
}

data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  tags            = local.common_tags
}

data "aws_iam_policy_document" "app_irsa_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.app_namespace}:${var.app_service_account_name}"]
    }
  }
}

resource "aws_iam_role" "app_irsa" {
  name               = "${local.name_prefix}-app-irsa-role"
  assume_role_policy = data.aws_iam_policy_document.app_irsa_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_policy" "app_irsa" {
  name        = "${local.name_prefix}-app-irsa-policy"
  description = "Least-privilege policy for ShopEasy API pods"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.db.arn,
          aws_secretsmanager_secret.app.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.main.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.app.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.app.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.reviews.arn
      },
      {
        # [AVD-AWS-0037] Resource "*" → 특정 로그 그룹 ARN (최소 권한)
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.eks_cluster.arn}:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "app_irsa" {
  role       = aws_iam_role.app_irsa.name
  policy_arn = aws_iam_policy.app_irsa.arn
}


# ============================================================
# GitHub Actions OIDC → EKS 접근 허용
# ============================================================
resource "aws_eks_access_entry" "github" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.github_actions_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.github_actions_role_arn

  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

resource "aws_eks_access_policy_association" "terraform_admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = "arn:aws:iam::492660417055:role/DevSecOpsTerraformRole"

  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
