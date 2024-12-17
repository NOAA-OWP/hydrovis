# This script was added so that the dump_to_s3.sh script will work
# It was failing since only postgresql12 was installed on the bastion
# and the "viz" db runs postgresql15 (since pg_dump cannot dump
# a higher version)

# Postgres YUM Repo
sudo tee /etc/yum.repos.d/pgdg.repo<<EOF
[pgdg15]
name=PostgreSQL 15 for RHEL/CentOS 7 - x86_64
baseurl=https://download.postgresql.org/pub/repos/yum/15/redhat/rhel-7.10-x86_64
enabled=1
gpgcheck=0
EOF

# Install PostgreSQL:
sudo yum install -y postgresql15