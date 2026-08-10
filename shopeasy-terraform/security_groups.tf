# ============================================================
# Security Groups — AVD + CIS LV2 + tfsec 전체 통과
#
# [AVD-AWS-0104] 수정: eks_nodes egress protocol=-1 → 포트별 화이트리스트
# [AVD-AWS-0107] 수정: 0.0.0.0/0 egress → HTTPS(443)만 + tfsec:ignore 명시
# [AVD-AWS-0099] 수정: eks_cluster_self protocol=-1 → 443/tcp만
# [AVD-AWS-0099] 수정: eks_nodes_from_cluster 0-65535 → kubelet+nodeport 분리
# [AVD-AWS-0040] 수정: rds egress protocol=-1 제거 (Stateful 자동 허용)
# [AVD-AWS-0018] 수정: 모든 SG 규칙 description 추가
# [CIS 5.x]      추가: ALB 전용 SG (CIDR → SG 참조 방식)
# ============================================================

# --- 1. ALB Security Group ---
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Security group for Application Load Balancer - WAF protected"
  vpc_id      = aws_vpc.main.id

  # CloudFront 관리형 프리픽스 리스트만 허용 — ALB 직접 접근 차단
  # origin_protocol_policy = "http-only" 이므로 CloudFront → ALB 는 HTTP(80)만 사용
  # HTTPS(443) 규칙을 추가하면 프리픽스 리스트(max 55) × 2 = 110 → 한도(60) 초과
  ingress {
    description     = "HTTP from CloudFront edge nodes only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  egress {
    description     = "Forward to EKS nodes - API port"
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  egress {
    description     = "Forward to EKS nodes - Frontend port"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-sg"
  })
}

# --- 2. EKS Cluster (Control Plane) SG ---
resource "aws_security_group" "eks_cluster" {
  name        = "${local.name_prefix}-eks-cluster-sg"
  description = "Security group for EKS control plane - restricted egress to nodes only"
  vpc_id      = aws_vpc.main.id

  # [AVD-AWS-0104] 전체 허용 제거 → 노드 SG로만 출력 제한
  egress {
    description     = "Allow control plane to reach worker nodes on high ports"
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  egress {
    description     = "Allow control plane webhook traffic to nodes on 443"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-cluster-sg"
  })
}

# --- 3. EKS Worker Nodes SG ---
# 인라인 ingress/egress를 모두 제거하고 aws_security_group_rule 리소스로 분리
# (인라인 규칙과 별도 rule 리소스 혼용 시 Terraform이 "존재하지 않는 규칙 취소" 오류 발생)
resource "aws_security_group" "eks_nodes" {
  name        = "${local.name_prefix}-eks-nodes-sg"
  description = "Security group for EKS worker nodes - whitelisted egress only"
  vpc_id      = aws_vpc.main.id

  lifecycle {
    ignore_changes = [ingress, egress]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-nodes-sg"
  })
}

# --- 4. RDS MySQL SG ---
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "Security group for RDS MySQL - inbound from EKS nodes only, no egress"
  vpc_id      = aws_vpc.main.id

  # [AVD-AWS-0040] egress 전체 허용 블록 제거
  # Stateful SG: 인바운드 응답은 egress 규칙 없이 자동 허용됨

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-sg"
  })
}

# ============================================================
# Security Group Rules
# ============================================================

# --- EKS Nodes 규칙 (모두 별도 리소스로 관리) ---

# 노드간 전체 통신 (pod-to-pod, CoreDNS 포함)
resource "aws_security_group_rule" "eks_nodes_self_ingress" {
  type              = "ingress"
  description       = "Allow node-to-node all-protocol communication within node SG"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.eks_nodes.id
  self              = true
}

resource "aws_security_group_rule" "eks_nodes_self_egress" {
  type              = "egress"
  description       = "Allow node-to-node all-protocol communication within node SG"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.eks_nodes.id
  self              = true
}

# tfsec:ignore:AVD-AWS-0104
# tfsec:ignore:AVD-AWS-0107
resource "aws_security_group_rule" "eks_nodes_egress_https" {
  type              = "egress"
  description       = "Allow HTTPS to AWS services - ECR, SSM, CloudWatch, Secrets Manager"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.eks_nodes.id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "eks_nodes_egress_mysql" {
  type                     = "egress"
  description              = "Allow MySQL to RDS"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_nodes.id
  source_security_group_id = aws_security_group.rds.id
}

# --- 노드 → 제어 평면 (Kubernetes API 443) ---
resource "aws_security_group_rule" "eks_cluster_from_nodes" {
  type                     = "ingress"
  description              = "Allow Kubernetes API access from worker nodes"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_cluster.id
  source_security_group_id = aws_security_group.eks_nodes.id
}

# [AVD-AWS-0099] protocol=-1 전체 허용 → 443/tcp만
resource "aws_security_group_rule" "eks_cluster_self" {
  type              = "ingress"
  description       = "Allow HTTPS within cluster security group only"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.eks_cluster.id
  self              = true
}

# [AVD-AWS-0099] 0-65535 → Kubelet(10250)만
resource "aws_security_group_rule" "eks_nodes_from_cluster_kubelet" {
  type                     = "ingress"
  description              = "Allow control plane to reach Kubelet API on worker nodes"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_nodes.id
  source_security_group_id = aws_security_group.eks_cluster.id
}

# EKS 관리형 클러스터 SG → 노드 high ports 허용
# (kubectl exec/logs: 10250, admission webhook: 9443, 기타 컨트롤플레인→노드 통신)
resource "aws_security_group_rule" "eks_nodes_from_managed_cluster_sg" {
  type                     = "ingress"
  description              = "Allow EKS managed cluster SG to reach worker nodes on high ports"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_nodes.id
  source_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

# [AVD-AWS-0099] NodePort 범위만 별도 허용
resource "aws_security_group_rule" "eks_nodes_from_cluster_nodeport" {
  type                     = "ingress"
  description              = "Allow control plane to reach NodePort range on worker nodes"
  from_port                = 30000
  to_port                  = 32767
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_nodes.id
  source_security_group_id = aws_security_group.eks_cluster.id
}

# RDS 인바운드 — EKS 노드에서만 허용
resource "aws_security_group_rule" "rds_from_eks_nodes" {
  type                     = "ingress"
  description              = "Allow MySQL access from EKS worker nodes only"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = aws_security_group.eks_nodes.id
}

# [CIS] VPC CIDR 기반 → ALB SG 참조 방식
resource "aws_security_group_rule" "eks_nodes_from_alb_api" {
  type                     = "ingress"
  description              = "Allow traffic from ALB to API pods on port 5000"
  from_port                = 5000
  to_port                  = 5000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_nodes.id
  source_security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "eks_nodes_from_alb_frontend" {
  type                     = "ingress"
  description              = "Allow traffic from ALB to frontend pods on port 80"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_nodes.id
  source_security_group_id = aws_security_group.alb.id
}
