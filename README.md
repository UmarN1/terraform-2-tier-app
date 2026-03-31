# AWS Two-Tier Infrastructure — Terraform + GitHub Actions

[![Validate & Format](https://github.com/UmarN1/terraform-2-tier-app/actions/workflows/terraform.yml/badge.svg)](https://github.com/UmarN1/terraform-2-tier-app/actions/workflows/terraform.yml)
[![Terraform](https://img.shields.io/badge/Terraform-1.7-623CE4?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-us--east--1-FF9900?logo=amazonaws&logoColor=white)](https://aws.amazon.com/)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

Production-ready two-tier AWS infrastructure written entirely in Terraform, organized into reusable modules, and deployed automatically through a GitHub Actions CI/CD pipeline. Every pull request gets a full `terraform plan` posted as a comment. Every merge to `main` requires a manual approval before `terraform apply` runs.

\---

## Architecture

```
                         Internet
                             │
                    ┌────────▼────────┐
                    │   CloudFront    │  HTTPS only, ACM cert, geo-restricted
                    │   + ACM + DNS   │  redirects HTTP → HTTPS
                    └────────┬────────┘
                             │
              ┌──────────────▼──────────────┐
              │         us-east-1 VPC        │  10.0.0.0/16
              │                              │
              │   ┌──────────┬──────────┐   │
              │   │ pub-1a   │ pub-1b   │   │  Public Subnets
              │   │          │          │   │
              │   │    Application      │   │
              │   │    Load Balancer    │   │  HTTP → EC2 (port 80)
              │   └────────────────┬───┘   │
              │                    │        │
              │   ┌──────────┬─────▼────┐  │
              │   │ pri-3a   │ pri-4b   │  │  Private Subnets (App tier)
              │   │          │          │  │
              │   │  EC2 Auto Scaling   │  │  min 1 / max 3, CPU-based scaling
              │   │  Group (t2.micro)   │  │  CloudWatch alarms at 70% / 5%
              │   └──────────┴──────────┘  │
              │         NAT Gateway         │  outbound traffic only
              │   ┌──────────┬──────────┐  │
              │   │ pri-5a   │ pri-6b   │  │  Private Subnets (DB tier)
              │   │          │          │  │
              │   │    RDS MySQL 5.7    │  │  Multi-AZ, encrypted subnet group
              │   │    (db.t3.micro)    │  │  only reachable from EC2 sg
              │   └──────────┴──────────┘  │
              └──────────────────────────────┘

Remote State: S3 bucket (umar-tfstate-dev-1) + DynamoDB table (dynamo-demo)
```

\---

## Security Model

Traffic flows in one direction through security groups — nothing talks to anything it does not need to:

|Security Group|Allows inbound from|Port|
|-|-|-|
|`alb\\\_sg`|Internet (0.0.0.0/0)|80, 443|
|`client\\\_sg` (EC2)|`alb\\\_sg` only|80|
|`db\\\_sg` (RDS)|`client\\\_sg` only|3306|

EC2 instances have no public IPs. RDS is not publicly accessible. The database is only reachable from the application tier — not the load balancer, not the internet.

\---

## Module Structure

```
terraform-2-tier-app/
├── .github/
│   └── workflows/
│       └── terraform.yml       # CI/CD — validate, plan, apply
├── root/
│   ├── main.tf                 # Calls all modules, wires outputs to inputs
│   ├── variables.tf            # All input variables declared here
│   ├── backend.tf              # S3 remote state + DynamoDB locking
│   └── provider.tf             # AWS provider, pinned to \\\~> 5.0
└── modules/
    ├── vpc/                    # VPC, 6 subnets, IGW, route tables
    ├── nat/                    # NAT gateway + private route tables
    ├── security-group/         # ALB, EC2, and RDS security groups
    ├── alb/                    # Application Load Balancer + target group
    ├── asg/                    # Launch template + ASG + CloudWatch scaling
    ├── rds/                    # RDS MySQL, subnet group, Multi-AZ
    ├── cloudfront/             # CloudFront distribution + ACM certificate
    └── route53/                # Optional Route 53 DNS record (flag-gated)
```

Each module is self-contained with its own `main.tf`, `variables.tf`, `output.tf`, and `provider.tf`. The root module wires everything together — no module talks to another directly, everything goes through root outputs and inputs.

\---

## CI/CD Pipeline

```
Pull Request opened
        │
        ├── Validate job ──► terraform fmt -check
        │                    terraform validate
        │
        └── Plan job ──────► terraform plan
                             └── Posts full diff as PR comment

Merge to main
        │
        └── Manual approval required (GitHub Environments)
                │
                └── Apply job ──► terraform apply -auto-approve
```

Every pull request gets a full infrastructure diff posted as a comment before anyone reviews the code. Sensitive variables (`db\\\_username`, `db\\\_password`) are passed via GitHub Secrets as `TF\\\_VAR\\\_\\\*` environment variables — they never appear in the plan output or the codebase.

\---

## Prerequisites

* AWS account with IAM permissions for EC2, VPC, RDS, S3, CloudFront, ACM, DynamoDB, Route53
* Terraform >= 1.7 installed locally
* AWS CLI configured (`aws configure`)
* An ACM certificate already issued in `us-east-1` (CloudFront requires this region)
* S3 bucket and DynamoDB table for remote state (see setup below)

\---

## Remote State Setup

Run these once before the first `terraform init`:

```bash
# Create the S3 bucket for state storage
aws s3api create-bucket \\\\
  --bucket umar-tfstate-dev-1 \\\\
  --region us-east-1

# Enable versioning so you can recover from bad applies
aws s3api put-bucket-versioning \\\\
  --bucket umar-tfstate-dev-1 \\\\
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \\\\
  --bucket umar-tfstate-dev-1 \\\\
  --server-side-encryption-configuration \\\\
  '{"Rules":\\\[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Create the DynamoDB table for state locking
aws dynamodb create-table \\\\
  --table-name dynamo-demo \\\\
  --attribute-definitions AttributeName=LockID,AttributeType=S \\\\
  --key-schema AttributeName=LockID,KeyType=HASH \\\\
  --billing-mode PAY\\\_PER\\\_REQUEST \\\\
  --region us-east-1
```

\---

## Local Deployment

```bash
# 1. Clone the repo
git clone https://github.com/UmarN1/terraform-2-tier-app.git
cd terraform-2-tier-app/root

# 2. Create your variable values file (never commit this)
cat > terraform.tfvars <<EOF
region                  = "us-east-1"
project\\\_name            = "myapp"
vpc\\\_cidr                = "10.0.0.0/16"
pub\\\_sub\\\_1a\\\_cidr         = "10.0.1.0/24"
pub\\\_sub\\\_2b\\\_cidr         = "10.0.2.0/24"
pri\\\_sub\\\_3a\\\_cidr         = "10.0.3.0/24"
pri\\\_sub\\\_4b\\\_cidr         = "10.0.4.0/24"
pri\\\_sub\\\_5a\\\_cidr         = "10.0.5.0/24"
pri\\\_sub\\\_6b\\\_cidr         = "10.0.6.0/24"
db\\\_username             = "admin"
db\\\_password             = "changeme123"
certificate\\\_domain\\\_name = "yourdomain.com"
additional\\\_domain\\\_name  = "app.yourdomain.com"
enable\\\_route53          = false
EOF

# 3. Initialise — pulls providers and configures S3 backend
terraform init

# 4. Preview what will be created
terraform plan

# 5. Deploy
terraform apply

# 6. Tear down when done (saves AWS costs)
terraform destroy
```

\---

## GitHub Actions Setup

**Secrets** — go to your repo → Settings → Secrets and variables → Actions:

|Secret name|What it is|
|-|-|
|`AWS\\\_ACCESS\\\_KEY\\\_ID`|IAM user access key|
|`AWS\\\_SECRET\\\_ACCESS\\\_KEY`|IAM user secret key|
|`TF\\\_VAR\\\_DB\\\_USERNAME`|RDS master username|
|`TF\\\_VAR\\\_DB\\\_PASSWORD`|RDS master password|

**Production environment** — go to Settings → Environments → New environment:

* Name: `production`
* Required reviewers: add yourself
* This gates every `terraform apply` behind a manual approval click

\---

## What Each Module Does

**vpc** — creates the VPC with DNS hostnames enabled, an internet gateway, 2 public subnets across 2 AZs, 4 private subnets across 2 AZs, and a public route table. Uses `data "aws\\\_availability\\\_zones"` so it always picks real AZs for the region — no hardcoding.

**nat** — places a NAT gateway in the public subnet and creates private route tables pointing outbound traffic through it. EC2 instances in private subnets can reach the internet for package installs but are not reachable from it.

**security-group** — three security groups chained together. ALB accepts public traffic. EC2 only accepts traffic from the ALB security group. RDS only accepts traffic from the EC2 security group. No direct internet access to instances or database.

**alb** — an internet-facing Application Load Balancer across both public subnets with a target group and health check. Listener on port 80 forwards to the target group. EC2 instances register themselves via the ASG.

**asg** — a launch template and Auto Scaling Group in the private subnets. Includes CloudWatch metric alarms: scales up when average CPU exceeds 70% for two periods, scales down when CPU drops below 5%. Bootstraps instances with a `config.sh` user data script on first boot.

**rds** — a MySQL 5.7 RDS instance in a dedicated subnet group using the two DB-tier private subnets. Multi-AZ enabled for failover. Not publicly accessible. Credentials come in via variables and are never hardcoded.

**cloudfront** — a CloudFront distribution in front of the ALB. Looks up an existing ACM certificate in us-east-1 by domain name. Forces HTTPS for all viewers. Geo-restricted to US, CA, IN. Forwards all cookies and query strings to the origin.

**route53** — creates a DNS alias record pointing to the CloudFront distribution. Controlled by the `enable\\\_route53` boolean variable so you can deploy the infrastructure without touching DNS.

\---

## Things I Would Add Next

* Enable RDS encryption at rest (`storage\\\_encrypted = true`) — currently off, should be on in production
* Replace the HTTP-only ALB listener with an HTTPS listener once the certificate is attached directly to the ALB
* Add an outputs file to the root module so ALB DNS name and RDS endpoint are printed after `terraform apply`

\---

## License

MIT

