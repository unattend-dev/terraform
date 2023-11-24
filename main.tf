locals {
  region = "eu-west-1"

  environment_name = "test"
  cluster_name     = "ecs-test-cluster"

  serviceList = [
    "backoffice-api",
    "backoffice-ui",
    "invoice-projectionhost",
    "invoice-scheduler"
  ]
  security_group_ids = ["sg-066896747728a6816"]
  subnet_ids         = ["subnet-05d6a0005ade34e30"]
  tags = {
    "Environment" = local.environment_name
    "Company"     = "Unattend"
  }
}

output "name" {
  value = toset(local.serviceList)
}

module "ecr" {
  source = "terraform-aws-modules/ecr/aws"

  for_each = { for serviceName in local.serviceList : serviceName => {
    repository_name = serviceName
    repository_type = "private"
    repository_lifecycle_policy = jsonencode({
      rules = [
        {
          rulePriority = 1,
          description  = "Keep last 30 images",
          selection = {
            tagStatus     = "tagged",
            tagPrefixList = ["v"],
            countType     = "imageCountMoreThan",
            countNumber   = 30
          },
          action = {
            type = "expire"
          }
        }
      ]
    })
    tags = local.tags
  } }

  repository_name             = each.value.repository_name
  repository_type             = each.value.repository_type
  repository_lifecycle_policy = each.value.repository_lifecycle_policy
  tags                        = each.value.tags
}

module "ecs" {
  source = "terraform-aws-modules/ecs/aws"

  for_each = { for serviceName in local.serviceList : serviceName => "496277223701.dkr.ecr.eu-west-1.amazonaws.com/${serviceName}:1.0.0" }

  cluster_name = local.cluster_name

  create_cloudwatch_log_group = false

  services = {
    (each.key) = {
      cpu                      = 1024
      memory                   = 2048
      desired_count            = 1
      autoscaling_max_capacity = 2
      autoscaling_min_capacity = 1
      tags                     = local.tags

      container_definitions = {
        (each.key) = {
          cpu       = 0
          essential = true
          image     = each.value
          port_mappings = [
            {
              name          = "http-forward"
              containerPort = 80
              hostPort      = 80
              protocol      = "tcp"
            }
          ]
          enable_cloudwatch_logging = false
          log_configuration = {
            logDriver = "awslogs"
            options = {
              awslogs-group         = "/ecs/${local.environment_name}/${each.key}/app",
              awslogs-region        = local.region,
              awslogs-stream-prefix = "ecs"
            }
          }
          tags = local.tags
        }
        aws-otel-collector = {
          cpu       = 0
          essential = false
          image     = "public.ecr.aws/aws-observability/aws-otel-collector:v0.35.0"
          command = [
            "--config=/etc/ecs/ecs-cloudwatch.yaml"
          ]
          enable_cloudwatch_logging = false
          log_configuration = {
            logDriver = "awslogs"
            options = {
              awslogs-group         = "/ecs/${local.environment_name}/${each.key}/otel-sidecar",
              awslogs-region        = "eu-west-1",
              awslogs-stream-prefix = "ecs"
            }
          }
          tags = local.tags
        }
      }
      security_group_ids = local.security_group_ids
      subnet_ids         = local.subnet_ids
    }
  }
}

# service_connect_configuration = {
#   namespace = aws_service_discovery_http_namespace.this.arn
#   service = {
#     client_alias = {
#       port     = 80
#       dns_name = local.container_name
#     }
#     port_name      = local.container_name
#     discovery_name = local.container_name
#   }
# }

# tasks_iam_role_name        = "rl-task-${local.environment_name}-${local.name}-tasks"
# tasks_iam_role_description = "Example tasks IAM role for ${local.name}"
# tasks_iam_role_policies = {
#   ReadOnlyAccess = "arn:aws:iam::aws:policy/ReadOnlyAccess"
# }
# tasks_iam_role_statements = [
#   {
#     actions   = ["s3:List*"]
#     resources = ["arn:aws:s3:::*"]
#   }
# ]



