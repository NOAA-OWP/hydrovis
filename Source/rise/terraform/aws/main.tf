provider "aws" {
  region = var.region
}

resource "aws_iam_role" "rise_instance_role" {
  name = "${var.env}_rise_instance_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "rise_s3_access_policy" {
  name = "${var.env}_rise_s3_access_policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:ListBucket"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:s3:::${var.rise_s3_bucket}"
      },
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:s3:::${var.rise_s3_bucket}/fims-iac/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rise_attach_s3_policy" {
  role       = aws_iam_role.rise_instance_role.name
  policy_arn = aws_iam_policy.rise_s3_access_policy.arn
}

resource "aws_iam_role_policy_attachment" "attach_extra_policy" {
  count      = var.extra_policy_arn != "" ? 1 : 0
  role       = aws_iam_role.rise_instance_role.name
  policy_arn = var.extra_policy_arn
}

resource "aws_iam_instance_profile" "rise_instance_profile" {
  name = "${var.env}_rise_instance_profile"
  role = aws_iam_role.rise_instance_role.name
}

resource "aws_security_group" "rise_server_sg" {
  name_prefix = "rise_server_sg"
  vpc_id      = var.vpc_id
  
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
    
  ingress {
    from_port   = 8000
    to_port     = 8000
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

resource "aws_instance" "rise" {
  ami                  = var.rocky_linux_ami_id
  instance_type        = var.instance_type
  security_groups      = [aws_security_group.rise_server_sg.id]
  subnet_id            = var.subnet_id
  iam_instance_profile = aws_iam_instance_profile.rise_instance_profile.name

  root_block_device {
    volume_size = var.ebs_volume_size
    encrypted   = true
  }

  user_data = <<-EOF
              #!/bin/bash
              set -e

              # Install and start AWS SSM agent
              dnf install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
              systemctl enable amazon-ssm-agent
              systemctl start amazon-ssm-agent

              # Update system packages
              dnf upgrade -y
              dnf update -y
              dnf install -y git unzip nmap-ncat

              # Install AWS CLI v2
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              unzip awscliv2.zip
              ./aws/install --update

              # Verify AWS CLI installation
              aws --version

              # Install Docker
              dnf config-manager -y --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
              dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

              systemctl start docker
              systemctl enable docker
              #usermod -aG docker ssm-user

              # Verify installation
              docker compose version

              # Set up the application directory
              mkdir -p /app
              chmod -R 777 /app
              cd /app

              # Clone the specified Git repository and branch
              git clone -b ${var.git_branch} ${var.git_repo_url} rise

              # Sync rise data from S3 
              aws s3 sync s3://${var.rise_s3_bucket}/fims-iac/rise-pi-3/ /app/rise/data


              COMPOSE_FILE="/app/rise/compose.yaml"

              # Create and enable Docker Compose systemd service for future reboots
              cat <<-SERVICE_EOF > /etc/systemd/system/rise-app.service
              [Unit]
              Description=Docker Compose Application
              After=network.target

              [Service]
              Type=simple
              RemainAfterExit=true
              ExecStart=/usr/bin/docker compose -f $COMPOSE_FILE up -d
              ExecStop=/usr/bin/docker compose -f $COMPOSE_FILE down
              WorkingDirectory=/app/rise
              Restart=always

              [Install]
              WantedBy=multi-user.target
              SERVICE_EOF

              # Reload systemd and enable the service
              systemctl daemon-reload
              systemctl enable rise-app
              systemctl start rise-app

              while ! ncat -z localhost 8000; do   
                sleep 10 # Wait 10 seconds before checking again
                echo "RISE / SFINCS not ready yet. Retrying..."
              done

              echo "RISE / SFINCS is now listening on port 8000."
              sleep 5
              
              cd /app/rise
              /app/rise/run_sfincs.sh --serverless

              # Push the output to S3
              /usr/local/bin/aws s3 sync /app/rise/data/SFINCS/ngwpc_data/ s3://${var.rise_s3_bucket}/fims-iac/rise-pi-3-outputs/

              EOF

  tags = {
    Name = "${var.env}-RISE-Instance"
  }
}
