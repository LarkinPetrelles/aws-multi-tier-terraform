terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.region
}

###########################################################
# VARIABLES (minimal, the rest come from terraform.tfvars)
###########################################################

variable "region" {}
variable "ssh_key_path" {}

###########################################################
# VPC & SUBNETS
###########################################################

resource "aws_vpc" "mt" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Environment = "dev"
    Name        = "multitier-vpc"
  }
}

data "aws_availability_zones" "azs" {}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.mt.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = data.aws_availability_zones.azs.names[0]
  map_public_ip_on_launch = true

  tags = {
    Environment = "dev"
    Name        = "multitier-public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.mt.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.azs.names[1]
  map_public_ip_on_launch = true

  tags = {
    Environment = "dev"
    Name        = "multitier-public-b"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.mt.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.azs.names[0]

  tags = {
    Environment = "dev"
    Name        = "multitier-private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.mt.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = data.aws_availability_zones.azs.names[1]

  tags = {
    Environment = "dev"
    Name        = "multitier-private-b"
  }
}

###########################################################
# INTERNET GATEWAY & PUBLIC ROUTES
###########################################################

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.mt.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.mt.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "rt_pub_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "rt_pub_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

###########################################################
# NAT INSTANCE (Free Tier workaround) + PRIVATE ROUTE
###########################################################

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-ebs"]
  }
}

resource "aws_instance" "nat" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_a.id
  associate_public_ip_address = true
  source_dest_check           = false

  user_data = <<EOF
#!/bin/bash
yum update -y
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
EOF

  tags = {
    Name = "mt-nat"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.mt.id

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.nat.primary_network_interface_id
  }
}

resource "aws_route_table_association" "rt_priv_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "rt_priv_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

###########################################################
# SECURITY GROUPS
###########################################################

# ALB SG: HTTP in from anywhere, all egress
resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  vpc_id = aws_vpc.mt.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# APP SG: HTTP in only from ALB SG
resource "aws_security_group" "app_sg" {
  name   = "app-sg"
  vpc_id = aws_vpc.mt.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# RDS SG: MySQL in only from APP SG
resource "aws_security_group" "rds_sg" {
  name   = "rds-sg"
  vpc_id = aws_vpc.mt.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

###########################################################
# ALB + TARGET GROUP
###########################################################

resource "aws_lb" "alb" {
  name               = "multitier-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  security_groups    = [aws_security_group.alb_sg.id]
}

resource "aws_lb_target_group" "tg" {
  name     = "mt-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.mt.id

  health_check {
    protocol = "HTTP"
    path     = "/"
    matcher  = "200-399"
    interval = 30
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

###########################################################
# IAM ROLE + INSTANCE PROFILE (for SSM etc.)
###########################################################

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_role" {
  name_prefix        = "mt-ec2-role-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name_prefix = "mt-ec2-profile-"
  role        = aws_iam_role.ec2_role.name
}

###########################################################
# EC2 LAUNCH TEMPLATE & ASG
###########################################################

resource "aws_key_pair" "kp" {
  key_name   = "mt-key"
  public_key = file(var.ssh_key_path)
}

resource "aws_launch_template" "web" {
  name_prefix            = "mt-web-"
  image_id               = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  key_name               = aws_key_pair.kp.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  # IMPORTANT: this points to app/start.sh defined above
  user_data = base64encode(file("../app/start.sh"))
}

resource "aws_autoscaling_group" "asg" {
  desired_capacity    = 1
  max_size            = 1
  min_size            = 1
  vpc_zone_identifier = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.tg.arn]

  tag {
    key                 = "Name"
    value               = "mt-web"
    propagate_at_launch = true
  }
}

###########################################################
# RDS
###########################################################

resource "aws_db_subnet_group" "dbsub" {
  name        = "multitier-dbsub-vpc2"
  subnet_ids  = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  description = "DB subnet group for multi-tier demo VPC"
}

resource "aws_db_instance" "appdb" {
  allocated_storage      = 20
  engine                 = "mysql"
  instance_class         = "db.t3.micro"
  db_name                = "appdb"
  username               = "mtadmin"
  password               = "ChangeMe123!"
  skip_final_snapshot    = true
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.dbsub.name
}

###########################################################
# OUTPUTS
###########################################################

output "alb_dns_name" {
  value = aws_lb.alb.dns_name
}

output "db_endpoint" {
  value = aws_db_instance.appdb.address
}

output "db_name" {
  value = aws_db_instance.appdb.db_name
}
