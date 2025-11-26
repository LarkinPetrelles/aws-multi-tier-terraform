# AWS Multi-Tier Terraform Project

This project uses Terraform to deploy a simple three-tier style architecture in AWS:

- **VPC (`10.0.0.0/16`)** with public and private subnets across 2 AZs  
- **Application Load Balancer** (`multitier-alb`) in public subnets  
- **Web tier EC2 instance** (`mt-web`) in a private subnet, in an Auto Scaling Group  
- **MySQL RDS instance** (`appdb`) in private subnets  
- **IAM role + SSM** for Session Manager access to the EC2 instance  

The ALB DNS endpoint serves the demo page:

`Multi-tier demo – This page is served from the web-tier EC2 instance.`

---

## Architecture

High-level layout:

![VPC topology](01-vpc-multitier-topology.png)

ALB listener and target group:

![ALB listener](02-alb-multitier-listener.png)  
![Target group](03-target-group-mt-tg-healthy.png)

Web tier + security:

![ASG](04-asg-terraform-web-tier.png)  
![Web instance security](05-ec2-mt-web-instance-security.png)

Database + IAM:

![RDS MySQL](06-rds-mysql-appdb.png)  
![EC2 IAM role / SSM](07-iam-mt-ec2-role-ssm.png)

Demo page:

![Multi-tier demo](08-multi-tier-demo.png)

---

## Tech Stack

- **AWS**: VPC, Subnets, Route Tables, Internet Gateway, NAT (if added), ALB, EC2, RDS, IAM, SSM
- **Terraform**: HCL, remote modules not used (all defined locally)
- **OS**: Windows 11 + PowerShell

---

## Files

- `main.tf` – core AWS resources (VPC, subnets, ALB, ASG, EC2, RDS, IAM, SSM)
- `variables.tf` – input variables (region, instance types, CIDRs, etc.)
- `outputs.tf` – outputs such as `alb_dns_name` and `db_endpoint`
- `user_data.sh` – bootstrap script for the web tier EC2 instance
- `01-...png` – `08-...png` – architecture and console screenshots
- `.gitignore` – ignores `.terraform/`, `terraform.tfstate*`, and plan files

---

## Prerequisites

- AWS account with permissions to create EC2, RDS, ALB, IAM, VPC resources
- Terraform v1.5+ installed locally
- AWS credentials configured (e.g., `~/.aws/credentials` or environment variables)

---

## Usage

```bash
# Initialize providers
terraform init

# Preview changes
terraform plan

# Deploy the stack
terraform apply

# After apply, Terraform outputs:
# - alb_dns_name
# - db_endpoint
