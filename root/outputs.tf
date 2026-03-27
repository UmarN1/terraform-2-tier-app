# Useful values printed after terraform apply
# Add these to root/outputs.tf in your repo

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer — use this to test before DNS is set up"
  value       = module.alb.alb_dns_name
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = module.cloudfront.cloudfront_domain_name
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "rds_endpoint" {
  description = "RDS instance endpoint — use this in your app config"
  value       = module.rds.db_endpoint
  sensitive   = true
}
