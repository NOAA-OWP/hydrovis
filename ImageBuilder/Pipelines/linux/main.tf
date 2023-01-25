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


resource "aws_imagebuilder_image_pipeline" "linux" {
  image_recipe_arn                 = aws_imagebuilder_image_recipe.linux.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.linux.arn
  name                             = "amazon-linux-2-git-docker-psql-stig"

  # schedule {
  #   schedule_expression = "cron(0 0 * * ? *)"
  # }
}

resource "aws_imagebuilder_image_recipe" "linux" {
  name         = "amazon-linux-2-git-docker-psql-stig"
  parent_image = "arn:aws:imagebuilder:${var.region}:aws:image/amazon-linux-2-x86/x.x.x"
  version      = "1.0.0"

  block_device_mapping {
    device_name = "/dev/xvda"

    ebs {
      delete_on_termination = true
      volume_size           = 12
      volume_type           = "gp2"
    }
  }

  component {
    component_arn = "arn:aws:imagebuilder:${var.region}:aws:component/docker-ce-linux/1.0.0/1"
  }

  component {
    component_arn = aws_imagebuilder_component.docker_git_psql_rsyslog_setup.arn
  }

  component {
    component_arn = "arn:aws:imagebuilder:${var.region}:aws:component/stig-build-linux-high/2022.3.2/1"
  }

  component {
    component_arn = "arn:aws:imagebuilder:${var.region}:aws:component/reboot-linux/1.0.1/1"
  }
}

resource "aws_imagebuilder_component" "docker_git_psql_rsyslog_setup" {
  name        = "docker_git_psql_rsyslog_setup"
  description = "Install and configure psql, git, docker-compose and rsyslog"
  platform    = "Linux"
  version     = "1.0.0"
  
  data = yamlencode({
    schemaVersion = 1.0
    constants = [{
      "Name" = {
        type = "string"
        value = "{{.Name}}"
      }
    }]
    phases = [
      {
        name = "build"
        steps = [
          {
            name = "add_repo"
            action = "ExecuteBash"
            inputs = {
              commands = [<<-EOT
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
            name = "update_rsyslog"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "sudo wget http://rpms.adiscon.com/v8-stable-nightly/rsyslog-nightly-rhel7.repo -P /etc/yum.repos.d",
                "yum upgrade rsyslog --disablerepo=amzn2-core -y"
              ]
            }
          },
          {
            name = "add_docker_log_driver"
            action = "ExecuteBash"
            inputs = {
              commands = [<<-EOT
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
            name = "add_rsyslog_json_template"
            action = "ExecuteBash"
            inputs = {
              commands = [<<-EOT
                sudo tee /etc/rsyslog.d/01-json-template.conf<<EOF
                template(name="json-template" type="list") {
                  constant(value="{")
                    constant(value="\"@timestamp\":\"")     property(name="timereported" dateFormat="rfc3339")
                    constant(value="\",\"message\":\"")     property(name="msg" format="json")
                    constant(value="\",\"sysloghost\":\"")  property(name="hostname")
                    constant(value="\",\"programname\":\"") property(name="programname")
                    constant(value="\",\"hydrovis_application\":\"") constant(value=\`echo \$HYDROVIS_APPLICATION\`)
                  constant(value="\"}\n")
                }
                EOF
                EOT
              ]
            }
          },
          {
            name = "add_rsyslog_log_destination"
            action = "ExecuteBash"
            inputs = {
              commands = [<<-EOT
                sudo tee /etc/rsyslog.d/60-output.conf<<EOF
                action(type="omfwd" template="json-template" target=\`echo \$LOGSTASH_IP\` port="5001" protocol="udp")
                EOF
                EOT
              ]
            }
          }
        ]
      },
      {
        name = "validate"
        steps = [
          {
            name = "grab_docker-compose"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "curl -L https://github.com/docker/compose/releases/download/1.28.5/docker-compose-Linux-x86_64 -o /usr/local/bin/docker-compose",
                "chmod +x /usr/local/bin/docker-compose"
              ]
            }
          }
        ]
      },
      {
        name = "test"
        steps = [
          {
            name = "install_git_and_pgsql"
            action = "ExecuteBash"
            inputs = {
              commands = ["yum install -y git postgresql12"]
            }
          },
          {
            name = "restart_docker_and_rsyslog"
            action = "ExecuteBash"
            inputs = {
              commands = ["sudo service docker restart;sudo service rsyslog restart"]
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

resource "aws_imagebuilder_infrastructure_configuration" "linux" {
  name                          = "amazon-linux-2-git-docker-psql-stig"
  description                   = "amazon-linux-2-git-docker-psql-stig"
  instance_profile_name         = var.builder_role_instance_profile_name
  instance_types                = ["t2.xlarge", "m5.large", "m5.xlarge"]
  key_pair                      = data.aws_key_pair.ec2.key_name
  security_group_ids            = [var.builder_sg_id]
  subnet_id                     = var.builder_subnet_id
  terminate_instance_on_failure = true

  logging {
    s3_logs {
      s3_bucket_name = var.artifact_bucket_name
      s3_key_prefix  = "logs"
    }
  }
}

resource "aws_imagebuilder_distribution_configuration" "linux" {
  name = "linux"

  distribution {
    ami_distribution_configuration {
      name = "${aws_imagebuilder_image_pipeline.linux.name}-{{ imagebuilder:buildDate }}"
      target_account_ids = var.ami_sharing_account_ids
    }

    region = var.region
  }
}