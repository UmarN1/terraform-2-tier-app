variable "region" {}
variable "project_name" {}
variable "vpc_cidr" {}
variable "pub_sub_1a_cidr" {}
variable "pub_sub_2b_cidr" {}
variable "pri_sub_3a_cidr" {}
variable "pri_sub_4b_cidr" {}
variable "pri_sub_5a_cidr" {}
variable "pri_sub_6b_cidr" {}
variable "db_username" {}
variable "db_password" {}
variable "certificate_domain_name" {}
variable "additional_domain_name" {}

variable "enable_route53" {
  description = "Whether to enable Route 53 DNS record creation"
  type        = bool
  default     = false
}