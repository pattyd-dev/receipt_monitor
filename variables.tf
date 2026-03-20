variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_user" {
  type = string
}

variable "aws_credential_path" {
  type = string
}

variable "route_53_zone_id" {
  type = string
}

variable "domain_name" {
  type    = string
  default = "example.com"
}

variable "aws_account" {
  type = string
}

variable "project_tag" {
  type    = string
  default = "Receipt Corrector"
}

variable "ssh_user" {
  type    = string
  default = "ec2-user"
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "ssh_identity_path" {
  type = string
}

variable "ssh_config_path" {
  type = string
}

variable "source_dynamo_arn" {
  type = string
}

variable "user_data_path" {
  type = string
}

variable "image_bucket" {
  type = string
}

variable "code_bucket" {
  type = string
}