variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "artifact_bucket_name" {
  type = string
}

variable "builder_role_instance_profile_name" {
  type = string
}

variable "builder_sg_id" {
  type = string
}

variable "builder_subnet_id" {
  type = string
}

variable "ami_sharing_account_ids" {
  type = list(string)
}


locals {
  name = "amazon-linux-2-git-docker-psql-stig"
}

resource "aws_imagebuilder_image_pipeline" "linux" {
  image_recipe_arn                 = aws_imagebuilder_image_recipe.linux.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.linux.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.linux.arn
  name                             = local.name

  schedule {
    schedule_expression = "cron(0 0 * * ? *)"
  }
}

resource "aws_imagebuilder_image_recipe" "linux" {
  name         = local.name
  parent_image = "arn:aws:imagebuilder:${var.region}:aws:image/amazon-linux-2-x86/x.x.x"
  version      = "1.0.0"

  working_directory = "/tmp"

  block_device_mapping {
    device_name = "/dev/xvda"

    ebs {
      delete_on_termination = true
      volume_size           = 12
      volume_type           = "gp2"
    }
  }

  component {
    component_arn = "arn:aws:imagebuilder:${var.region}:aws:component/amazon-cloudwatch-agent-linux/x.x.x"
  }

  component {
    component_arn = "arn:aws:imagebuilder:${var.region}:aws:component/docker-ce-linux/x.x.x"
  }

  component {
    component_arn = aws_imagebuilder_component.postgres_setup.arn
  }

  component {
    component_arn = aws_imagebuilder_component.git_setup.arn
  }

  component {
    component_arn = aws_imagebuilder_component.docker-compose_setup.arn
  }

  component {
    component_arn = aws_imagebuilder_component.logging_setup.arn
  }

  component {
    component_arn = "arn:aws:imagebuilder:${var.region}:aws:component/stig-build-linux-high/x.x.x"
  }

  component {
    component_arn = "arn:aws:imagebuilder:${var.region}:aws:component/reboot-linux/x.x.x"
  }
}

resource "aws_imagebuilder_component" "postgres_setup" {
  name        = "postgres_setup"
  description = "Install and configure Postgres"
  platform    = "Linux"
  version     = "1.0.0"

  data = yamlencode({
    schemaVersion = 1.0
    phases = [
      {
        name = "build"
        steps = [
          {
            name   = "add_repo"
            action = "ExecuteBash"
            inputs = {
              commands = [<<-EOT
                echo "Adding Postgres YUM Repo"
                sudo tee /etc/yum.repos.d/pgdg.repo<<EOF
                [pgdg12]
                name=PostgreSQL 12 for RHEL/CentOS 7 - x86_64
                baseurl=https://download.postgresql.org/pub/repos/yum/12/redhat/rhel-7-x86_64
                enabled=1
                gpgcheck=0
                EOF
                EOT
              ]
            }
          },
          {
            name   = "install_postgres"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "echo \"Installing Postgres\"",
                "yum install -y postgresql12"
              ]
            }
          }
        ]
      }
    ]
  })
}

resource "aws_imagebuilder_component" "git_setup" {
  name        = "git_setup"
  description = "Install and configure git"
  platform    = "Linux"
  version     = "1.0.0"

  data = yamlencode({
    schemaVersion = 1.0
    phases = [
      {
        name = "build"
        steps = [
          {
            name   = "install_git"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "echo \"Installing Git\"",
                "yum install -y git"
              ]
            }
          }
        ]
      }
    ]
  })
}

resource "aws_imagebuilder_component" "docker-compose_setup" {
  name        = "docker-compose_setup"
  description = "Install and configure docker-compose"
  platform    = "Linux"
  version     = "1.0.0"

  data = yamlencode({
    schemaVersion = 1.0
    phases = [
      {
        name = "build"
        steps = [
          {
            name   = "grab_docker-compose"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "echo \"Configuring docker-compose\"",
                "curl -L https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose",
                "chmod +x /usr/local/bin/docker-compose",
                "ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose"
              ]
            }
          }
        ]
      }
    ]
  })
}

resource "aws_imagebuilder_component" "logging_setup" {
  name        = "logging_setup"
  description = "Configure Docker and Rsyslog to send logs to Logstash"
  platform    = "Linux"
  version     = "1.0.0"

  data = yamlencode({
    schemaVersion = 1.0
    constants = [{
      "Name" = {
        type  = "string"
        value = "{{.Name}}"
      }
    }]
    phases = [
      {
        name = "build"
        steps = [
          {
            name   = "add_docker_log_driver"
            action = "ExecuteBash"
            inputs = {
              commands = [<<-EOT
                echo "Adding Docker Logger Driver to Docker Daemon Config"
                sudo tee /etc/docker/daemon.json<<EOF
                {
                  "log-driver": "syslog",
                  "log-opts": {
                    "syslog-address": "unixgram:///dev/log",
                    "tag" : "docker/{{Name}}"
                  }
                }
                EOF
                EOT
              ]
            }
          },
          {
            name   = "add_rsyslog_log_destination"
            action = "ExecuteBash"
            inputs = {
              commands = [<<-EOT
                echo "Adding Rsyslog Destination Config"
                sudo tee /etc/rsyslog.d/01-docker-logs.conf<<'EOF'

                template(name="dockerjson" type="list") {
                  constant(value="{")
                    constant(value="\"@timestamp\":\"")        property(name="timereported" dateFormat="rfc3339")
                    constant(value="\",\"host\":\"")           property(name="hostname")
                    constant(value="\",\"programname\":\"")    property(name="programname")
                    constant(value="\",\"application\":\"")    constant(value=`echo $HYDROVIS_APPLICATION`)
                    constant(value="\",\"container_name\":\"") property(name="syslogtag" regex.type="ERE" regex.submatch="1" regex.expression="docker\\/(.+)\\[[0-9]+]")
                    constant(value="\",\"message\":\"")        property(name="msg" format="json")
                  constant(value="\"}\n")
                }

                if $programname == 'docker' then {
                  action(type="omfile" file="/var/log/docker-containers.log")
                  action(type="omfile" file="/var/log/docker-containers-json.log" template="dockerjson")
                }

                if $syslogtag contains 'docker' then {
                  action(type="omfile" file="/var/log/important.log")
                  action(type="omfile" file="/var/log/important-json.log" template="dockerjson")
                }
                EOF
                EOT
              ]
            }
          },
          {
            name   = "add_cloudwatch_agent_config"
            action = "ExecuteBash"
            inputs = {
              commands = [<<-EOT
                echo "Adding CloudWatch Agent Configuration File"
                sudo tee /opt/aws/amazon-cloudwatch-agent/config.json<<EOF
                {
                  "agent": {
                    "metrics_collection_interval": 10,
                    "logfile": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
                  },
                  "logs": {
                    "logs_collected": {
                      "files": {
                        "collect_list": [
                          {
                            "file_path": "/var/log/docker-containers-json.log",
                            "log_group_name": "/aws/ec2/linux",
                            "log_stream_name": "{instance_id}/docker-json",
                            "timezone": "UTC"
                          },
                          {
                            "file_path": "/var/log/docker-containers.log",
                            "log_group_name": "/aws/ec2/linux",
                            "log_stream_name": "{instance_id}/docker",
                            "timezone": "UTC"
                          },      
                          {
                            "file_path": "/var/log/important-json.log",
                            "log_group_name": "/aws/ec2/linux",
                            "log_stream_name": "{instance_id}/important-json",
                            "timezone": "UTC"
                          },
                          {
                            "file_path": "/var/log/important.log",
                            "log_group_name": "/aws/ec2/linux",
                            "log_stream_name": "{instance_id}/important",
                            "timezone": "UTC"
                          },                                               
                          {
                            "file_path": "/var/log/cloud-init-output.log",
                            "log_group_name": "/aws/ec2/linux",
                            "log_stream_name": "{instance_id}/cloudinit",
                            "timezone": "UTC"
                          }
                        ]
                      }
                    },
                    "log_stream_name": "unspecified",
                    "force_flush_interval" : 15
                  }
                }
                EOF
                EOT
              ]
            }
          },
          {
            name   = "add_logrotate_config_for_docker_logs"
            action = "ExecuteBash"
            inputs = {
              commands = [<<-EOT
                echo "Adding Logrotate Configs for docker logs"
                sudo tee /etc/logrotate.d/ingest<<EOF
                /var/log/docker-containers-json.log
                /var/log/docker-containers.log
                /var/log/important-json.log
                /var/log/important.log
                {
                    daily
                    rotate 6
                    compress
                    missingok
                    notifempty
                    create 0600 root root
                    sharedscripts
                    postrotate
                        /usr/bin/systemctl kill -s HUP rsyslog.service >/dev/null 2>&1 || true
                    endscript
                }
                EOF
                EOT
              ]
            }
          },
          {
            name   = "restart_docker_and_rsyslog"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "echo \"Restarting Docker\"",
                "sudo service docker restart",
                "echo \"Restarting Rsyslog\"",
                "sudo service rsyslog restart"
              ]
            }
          },
          {
            name   = "start_cloudwatch_agent"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "echo \"Starting CloudWatch Agent\"",
                "sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/config.json",
              ]
            }
          }
        ]
      }
    ]
  })
}

data "aws_key_pair" "ec2" {
  key_name = "hv-${var.environment}-ec2-key-pair-${var.region}"
}

data "aws_default_tags" "default" {}

resource "aws_imagebuilder_infrastructure_configuration" "linux" {
  name                          = local.name
  description                   = local.name
  instance_profile_name         = var.builder_role_instance_profile_name
  instance_types                = ["t2.xlarge", "m5.large", "m5.xlarge"]
  key_pair                      = data.aws_key_pair.ec2.key_name
  security_group_ids            = [var.builder_sg_id]
  subnet_id                     = var.builder_subnet_id
  terminate_instance_on_failure = true

  logging {
    s3_logs {
      s3_bucket_name = var.artifact_bucket_name
      s3_key_prefix  = "logs/${local.name}"
    }
  }

  resource_tags = { for k, v in data.aws_default_tags.default.tags : k => v if k != "CreatedBy" }
}

resource "aws_imagebuilder_distribution_configuration" "linux" {
  name = local.name

  distribution {
    ami_distribution_configuration {
      name               = "${local.name}-{{ imagebuilder:buildDate }}"
      target_account_ids = var.ami_sharing_account_ids
      ami_tags           = merge(data.aws_default_tags.default.tags, { Name = local.name })
    }

    region = var.region
  }
}
