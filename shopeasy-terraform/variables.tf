variable "project_name" {
  description = "Project name used for tagging and naming."
  type        = string
  default     = "shopeasy"
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-northeast-2"
}

variable "availability_zones" {
  description = "Availability zones to use."
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "Private application subnet CIDRs."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "private_db_subnet_cidrs" {
  description = "Private database subnet CIDRs."
  type        = list(string)
  default     = ["10.0.100.0/24", "10.0.101.0/24"]
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "ShopEasy-EKS"
}

variable "cluster_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.31"
}

variable "cluster_endpoint_public_access" {
  description = "Whether the EKS API endpoint should be reachable from the public internet."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint when enabled."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.cluster_endpoint_public_access_cidrs : cidr != "0.0.0.0/0"])
    error_message = "Do not allow 0.0.0.0/0 for the public EKS API endpoint. Use approved admin CIDRs only."
  }
}

variable "node_group_name" {
  description = "EKS managed node group name."
  type        = string
  default     = "workers"
}

variable "node_instance_type" {
  description = "EC2 instance type for worker nodes."
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 3
}

variable "db_name" {
  description = "Initial MySQL database name."
  type        = string
  default     = "shopeasy"
}

variable "db_username" {
  description = "RDS master username."
  type        = string
  default     = "admin"
}

variable "db_engine_version" {
  description = "MySQL major version for RDS."
  type        = string
  default     = "8.0"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GiB."
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "RDS max autoscaling storage in GiB."
  type        = number
  default     = 100
}

variable "db_backup_retention_period" {
  description = "RDS backup retention days."
  type        = number
  default     = 7
}

variable "db_multi_az" {
  description = "Enable RDS Multi-AZ deployment."
  type        = bool
  default     = false
}

variable "app_namespace" {
  description = "Kubernetes namespace for the ShopEasy API."
  type        = string
  default     = "shopeasy"
}

variable "app_service_account_name" {
  description = "Kubernetes service account name that will assume the app IRSA role."
  type        = string
  default     = "shopeasy-api"
}

variable "app_port" {
  description = "Application container port."
  type        = number
  default     = 5000
}

variable "tags" {
  description = "Additional tags to apply to resources."
  type        = map(string)
  default     = {}
}
