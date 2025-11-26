# AWS Multi-Tier Terraform Project

This repo holds the Terraform code I used to build a small multi-tier app in AWS.

The goal was simple: use Terraform (not the console) to stand up a VPC, public web tier, private DB tier, and expose a basic web page through an Application Load Balancer.

---

## What gets created

### Networking
- VPC `10.0.0.0/16`
- Public + private subnets in two AZs
- Internet gateway + routes for public subnets

### Web tier
- Launch template for a web EC2 instance
- Auto Scaling Group (1 instance for this lab)
- User data that installs a web server and serves the **“Multi-tier demo”** page on port 80
- Security groups:
  - ALB → web on HTTP 80
  - Web → outbound only as needed

### Load balancer
- Internet-facing Application Load Balancer
- HTTP listener (port 80) → target group
- Health checks on `/` (expects HTTP 200–399)
- ALB DNS name is the main entry point for the app

### Database tier
- Private MySQL RDS instance (no public access)
- Security group only allows traffic from the web tier

### IAM
- EC2 IAM role with SSM managed policy  
  (manage instances with Session Manager instead of SSH keys)

---

## How to deploy

From the `terraform` folder:

```bash
terraform init
terraform plan
terraform apply