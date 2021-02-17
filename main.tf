terraform {
  required_version = ">= 0.14"
  required_providers {
    tls = {
      source  = "hashicorp/tls"
      version = "3.0.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "3.25.0"
    }
  }
}

provider "aws" {
  region = var.region
}
provider "tls" {}

// This backend bucket belongs to my AWS Account. Please change the name if you want to run it on your own one
terraform {
  backend "s3" {
    bucket = "cazorla19-test-tfstates"
    key    = "tfstates/api.tf"
    region = "eu-west-1"
  }
}

data "aws_vpc" "main" {
  default = true
}

data "aws_subnet_ids" "main" {
  vpc_id = data.aws_vpc.main.id
}

// Fetching the data about api.com DNS zone as we want to run our app on techtaskchallenge.api.com
data "aws_route53_zone" "api" {
  name = "api.com."
}

// Creates a DNS alias for the domain
resource "aws_route53_record" "challenge" {
  zone_id = data.aws_route53_zone.api.zone_id
  name    = "techtaskchallenge"
  type    = "A"

  alias {
    name                   = module.fargate_alb.dns_name
    zone_id                = module.fargate_alb.zone_id
    evaluate_target_health = true
  }
}

// Deploys LB with HTTPS support
module "fargate_alb" {
  source  = "telia-oss/loadbalancer/aws"
  version = "3.0.0"

  name_prefix = var.name_prefix
  type        = "application"
  internal    = false
  vpc_id      = data.aws_vpc.main.id
  subnet_ids  = data.aws_subnet_ids.main.ids

  tags = {
    environment = "dev"
    terraform   = "True"
  }
}

resource "aws_lb_listener" "alb" {
  load_balancer_arn = module.fargate_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

// Creates TLS self-signed certificate & private key for techtaskchallenge.api.com
resource "tls_private_key" "example" {
  algorithm = "RSA"
}

resource "tls_self_signed_cert" "example" {
  key_algorithm   = "RSA"
  private_key_pem = tls_private_key.example.private_key_pem

  subject {
    common_name  = "techtaskchallenge.api.com"
    organization = "ACME Examples, Inc"
  }

  validity_period_hours = 1

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "cert" {
  private_key      = tls_private_key.example.private_key_pem
  certificate_body = tls_self_signed_cert.example.cert_pem
}

resource "aws_lb_listener" "alb_https" {
  load_balancer_arn = module.fargate_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.cert.arn

  default_action {
    target_group_arn = module.fargate.target_group_arn
    type             = "forward"
  }
}

// Enable access to ports
resource "aws_security_group_rule" "task_ingress_8000" {
  security_group_id        = module.fargate.service_sg_id
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 8000
  to_port                  = 8000
  source_security_group_id = module.fargate_alb.security_group_id
}

// Open 800 and 443 ports to public
resource "aws_security_group_rule" "alb_ingress_80" {
  security_group_id = module.fargate_alb.security_group_id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

resource "aws_security_group_rule" "alb_ingress_443" {
  security_group_id = module.fargate_alb.security_group_id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

resource "aws_ecs_cluster" "cluster" {
  name = "${var.name_prefix}-cluster"
}

resource "aws_ecr_repository" "challenge" {
  name                 = "api_challenge"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

// Build the Docker image straight from Terraform and push one to ECR
module "ecr_docker_build" {
  source = "github.com/onnimonni/terraform-ecr-docker-build-module"

  # Absolute path into the service which needs to be build
  dockerfile_folder  = "${path.module}/app"
  aws_region         = var.region
  ecr_repository_url = aws_ecr_repository.challenge.repository_url
}

// Application spec
module "fargate" {
  source  = "telia-oss/ecs-fargate/aws"
  version = "3.5.1"

  name_prefix          = var.name_prefix
  vpc_id               = data.aws_vpc.main.id
  private_subnet_ids   = data.aws_subnet_ids.main.ids
  lb_arn               = module.fargate_alb.arn
  cluster_id           = aws_ecs_cluster.cluster.id
  task_container_image = aws_ecr_repository.challenge.repository_url

  // public ip is needed for default vpc, default is false
  task_container_assign_public_ip = true

  // port, default protocol is HTTP
  task_container_port = 8000

  task_container_environment = {
    TEST_VARIABLE = "TEST_VALUE"
  }

  health_check = {
    port = "traffic-port"
    path = "/"
  }

  tags = {
    environment = "dev"
    terraform   = "True"
  }
}

