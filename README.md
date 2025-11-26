# AWS Multi-Tier Terraform Project

This repo holds the Terraform code I used to build a small multi-tier app in AWS.

The goal was simple: use Terraform (not the console) to stand up a VPC, public web tier, private DB tier, and expose a basic web page through an Application Load Balancer.

---

## What this deploys

- **Networking**
  - 1 VPC (`10.0.0.0/16`)
  - Public + private subnets across 2 AZs
  - Internet gateway and route tables for public access

- **Web tier**
  - Auto Scaling group (min/max 1 for this demo)
  - Launch template for the web EC2 instance
  - User data boots the instance and serves a simple “Multi-tier demo” web page on port 80
  - Security groups:
    - ALB → web on HTTP 80  
    - Web → outbound only as needed

- **Application Load Balancer**
  - Internet-facing ALB
  - HTTP listener forwarding to a target group
  - Health checks on `/` (HTTP 200–399)

- **Database tier**
  - Private MySQL RDS instance (no public endpoint)
  - Security group only allows traffic from the web tier

- **IAM**
  - EC2 role with SSM managed policy so instances can be managed with Session Manager (no SSH keys)

---

## How to run it

1. Set your AWS credentials (I used `us-east-1`).
2. From the `terraform` folder:

   ```bash
   terraform init
   terraform plan
   terraform apply
