resource "aws_iam_role" "receipt_monitor" {
  name = "receipt_corrector_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "dynamodb_read_policy" {
  name        = "DynamoDBReadPolicy"
  description = "Allows read-only access to DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:DescribeTable"
        ]
        Effect   = "Allow"
        Resource = var.source_dynamo_arn
      },
    ]
  })
}
# =============================================================================
# IAM — Prometheus / Grafana Monitoring Instance
# Replace all <PLACEHOLDER> values before applying.
# =============================================================================

locals {
  aws_account_id   = var.aws_account       # e.g. "123456789012"
  aws_region       = var.aws_region           # e.g. "us-east-1"

  # Resource identifiers — must match your actual resource names/IDs
  #ecs_cluster_name     = data.terraform_remote_state.ecs_fargate.outputs.ecs_cluster_name 
  ecs_cluster_name = "receipt-corrector-cluster"
 # rds_instance_id      = "<YOUR_RDS_INSTANCE_ID>"
  lambda_function_name = data.terraform_remote_state.uploader.outputs.lambda_task_name

  tags = {
    ManagedBy   = "terraform"
    Purpose     = "prometheus-grafana-monitoring"
  }
}

# =============================================================================
# IAM ROLE — assumed by the EC2 instance
# =============================================================================

resource "aws_iam_role" "monitoring" {
  name        = "prometheus-grafana-monitoring-role"
  description = "Allows the Prometheus/Grafana EC2 instance to read CloudWatch metrics"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEC2AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

# =============================================================================
# IAM POLICY — least-privilege CloudWatch read for ECS, RDS, Lambda + tagging
# =============================================================================

resource "aws_iam_policy" "monitoring_cloudwatch" {
  name        = "prometheus-grafana-cloudwatch-read"
  description = "Least-privilege CloudWatch read access scoped to monitored resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [

      # ── 1. GetMetricStatistics / GetMetricData — scoped per namespace ────────
      {
        Sid    = "CloudWatchGetMetricsECS"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData"
        ]
        Resource = "*"
        # CloudWatch metric actions do not support resource-level ARNs natively;
        # the Condition block below provides the effective scoping.
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = [
              "AWS/ECS",
              "ECS/ContainerInsights"
            ]
          }
        }
      },

#      {
#        Sid    = "CloudWatchGetMetricsRDS"
#        Effect = "Allow"
#        Action = [
#          "cloudwatch:GetMetricStatistics",
#          "cloudwatch:GetMetricData"
#        ]
#        Resource = "*"
#        Condition = {
#          StringEquals = {
#            "cloudwatch:namespace" = ["AWS/RDS"]
#          }
#        }
#      },

      {
        Sid    = "CloudWatchGetMetricsLambda"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = ["AWS/Lambda"]
          }
        }
      },

      # ── 2. ListMetrics — scoped to relevant namespaces ───────────────────────
      {
        Sid    = "CloudWatchListMetrics"
        Effect = "Allow"
        Action = ["cloudwatch:ListMetrics"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = [
              "AWS/ECS",
              "ECS/ContainerInsights",
              "AWS/RDS",
              "AWS/Lambda"
            ]
          }
        }
      },

      # ── 3. DescribeAlarms — read-only, needed by some Grafana panels ─────────
      {
        Sid      = "CloudWatchDescribeAlarms"
        Effect   = "Allow"
        Action   = ["cloudwatch:DescribeAlarms"]
        Resource = "arn:aws:cloudwatch:${local.aws_region}:${local.aws_account_id}:alarm:*"
      },

      # ── 4. Tag-based auto-discovery (tag:GetResources) ───────────────────────
      # Scoped to the four resource types the exporters care about.
      {
        Sid    = "TagGetResourcesForDiscovery"
        Effect = "Allow"
        Action = ["tag:GetResources"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceType" = [
              "ecs:cluster",
              "ecs:service",
              "rds:db",
              "lambda:function"
            ]
          }
        }
      },

      # ── 5. Describe permissions — needed to resolve dimension metadata ────────
      {
        Sid    = "ECSDescribeForDiscovery"
        Effect = "Allow"
        Action = [
          "ecs:DescribeClusters",
          "ecs:ListClusters",
          "ecs:ListServices",
          "ecs:DescribeServices"
        ]
        Resource = [
          "arn:aws:ecs:${local.aws_region}:${local.aws_account_id}:cluster/${local.ecs_cluster_name}",
          "arn:aws:ecs:${local.aws_region}:${local.aws_account_id}:service/${local.ecs_cluster_name}/*"
        ]
      },

#      {
#        Sid    = "RDSDescribeForDiscovery"
#        Effect = "Allow"
#        Action = [
#          "rds:DescribeDBInstances",
#          "rds:ListTagsForResource"
#        ]
#        Resource = "arn:aws:rds:${local.aws_region}:${local.aws_account_id}:db:${local.rds_instance_id}"
#      },

      {
        Sid    = "LambdaDescribeForDiscovery"
        Effect = "Allow"
        Action = [
          "lambda:GetFunction",
          "lambda:ListFunctions",
          "lambda:ListTags"
        ]
        Resource = "arn:aws:lambda:${local.aws_region}:${local.aws_account_id}:function:${local.lambda_function_name}"
      }
    ]
  })

  tags = local.tags
}

# =============================================================================
# POLICY ATTACHMENT — bind the policy to the role
# =============================================================================

resource "aws_iam_role_policy_attachment" "monitoring_cloudwatch" {
  role       = aws_iam_role.monitoring.name
  policy_arn = aws_iam_policy.monitoring_cloudwatch.arn
}

# =============================================================================
# INSTANCE PROFILE — wraps the role so EC2 can use it
# =============================================================================

resource "aws_iam_instance_profile" "monitoring" {
  name = "prometheus-grafana-monitoring-profile"
  role = aws_iam_role.monitoring.name
  tags = local.tags
}

# =============================================================================
# OUTPUTS — reference these when creating the EC2 instance
# =============================================================================

output "monitoring_role_arn" {
  description = "ARN of the monitoring IAM role"
  value       = aws_iam_role.monitoring.arn
}

output "monitoring_instance_profile_name" {
  description = "Instance profile name — pass to aws_instance.iam_instance_profile"
  value       = aws_iam_instance_profile.monitoring.name
}

output "monitoring_instance_profile_arn" {
  description = "Instance profile ARN"
  value       = aws_iam_instance_profile.monitoring.arn
}



resource "aws_instance" "monitor_server" {
  instance_type          = var.instance_type
  ami                    = data.aws_ami.amazon_linux_server_ami.id
  key_name               = data.terraform_remote_state.networking.outputs.receipt_corrector_key_pair
  vpc_security_group_ids = [data.terraform_remote_state.networking.outputs.public_sg]
  subnet_id              = data.terraform_remote_state.networking.outputs.public_subnet_a
  iam_instance_profile = aws_iam_instance_profile.monitoring.name
  user_data     = file(var.user_data_path)

  root_block_device {
    volume_size = 8
  }

  tags = {
    Project = var.project_tag
  }

  provisioner "local-exec" {
    command = templatefile(var.ssh_config_path, {
      hostname     = self.public_ip,
      user         = var.ssh_user,
      identityfile = var.ssh_identity_path
    })

    interpreter = ["bash", "-c"]
  }
}

resource "aws_route53_record" "receipt_corrector" {
  zone_id = var.route_53_zone_id
  name    = "monitor.${var.domain_name}"
  type    = "A"
  ttl     = 300

  records = [aws_instance.monitor_server.public_ip]
}

