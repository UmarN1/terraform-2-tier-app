# Architecture Decisions

Notes on why I built things the way I did. Mostly so I remember,
but also useful if someone else looks at this.

---

## Why six subnets instead of four

Most tutorials use four subnets — two public, two private. I went with
six because I wanted to properly separate the application tier from the
database tier at the network level.

Subnets 3 and 4 are for EC2 (app tier). Subnets 5 and 6 are for RDS
(db tier). Both sets are private, but having them in separate subnet
groups means I can write more specific security group rules later — like
allowing a bastion host to reach EC2 but never touching the DB subnets.

It also matches how you would actually design this in a real company.
One flat "private" layer that holds both EC2 and RDS is technically fine
but harder to lock down as requirements change.

---

## Why the security groups are chained

The DB security group only allows inbound from the EC2 security group —
not from a CIDR range. This is an important distinction.

If I had used a CIDR like `10.0.3.0/24` to restrict DB access, any
instance that happens to be in that subnet could reach the database —
including things I might deploy later that should not have DB access.

By referencing the security group ID instead, only resources that are
explicitly assigned `client_sg` can reach the database. If I add a new
EC2 instance later and do not attach `client_sg`, it cannot connect to
RDS even if it is in the same subnet.

---

## Why NAT gateway instead of a NAT instance

NAT instances are cheaper but you have to manage them — patching,
rebooting, handling failover. NAT Gateway is managed by AWS, scales
automatically, and does not need maintenance.

For a portfolio project the cost difference is a few dollars a month.
For anything running in production that cost is worth not waking up at
2am because a NAT instance went down.

---

## Why CloudWatch alarms at 70% and 5%

The scale-up threshold is 70% CPU. I looked at a few articles on ASG
tuning and the common advice is to scale up before you are at capacity,
not after. 70% gives the new instance time to warm up before the
existing ones are maxed out.

The scale-down threshold is 5% CPU. This is intentionally low. Scaling
down too aggressively can cause a loop where the ASG scales down,
traffic spikes, it scales back up, traffic drops, it scales down again.
5% means the instances are basically idle before we terminate one.

The cooldown period is 300 seconds (5 minutes) for both. This prevents
the ASG from making decisions too quickly when traffic is spiky.

---

## Why enable_route53 is a boolean flag

Not everyone running this has a domain set up in Route 53. If I just
hardcoded the Route 53 module call, the deploy would fail for anyone
without the hosted zone already created.

The `enable_route53 = false` default means you can deploy the full
infrastructure — VPC, ALB, EC2, RDS, CloudFront — and test it using
the CloudFront domain name, then flip the flag to true once DNS is
ready.

This also means the CI/CD pipeline can run `terraform plan` without
needing Route 53 access.

---

## What I would change if this were going to production

**RDS encryption** — `storage_encrypted` is set to `false` right now.
That was fine for building and testing but should be `true` for
anything real. I would also set `backup_retention_period` to at least 7
days instead of 0.

**ALB HTTPS** — the ALB listener is on port 80 with a forward action.
CloudFront forces HTTPS at the edge but traffic between CloudFront and
the ALB is currently HTTP. I would add a port 443 listener to the ALB
and attach the ACM certificate there too, then set the CloudFront origin
protocol to HTTPS-only.

**Remote state access** — the S3 bucket for Terraform state is not
currently locked down with a bucket policy. Anyone with AWS access
could read or modify the state file. In a real team setup I would add
a bucket policy restricting access to the CI/CD IAM role only.

**Outputs** — the root module has no `outputs.tf` file right now. After
`terraform apply` you have to go into the AWS console to find the ALB
DNS name and RDS endpoint. Adding outputs would print those directly
in the terminal.
