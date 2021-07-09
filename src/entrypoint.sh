#!/bin/bash

# Exit immediately on error
set -e

# Write cronjob env to file, fill in sensible defaults, and read them back in
cat <<EOF > env.sh
SEND_MAIL_IN_CASE_OF_BACKUP_ERROR="${SEND_MAIL_IN_CASE_OF_BACKUP_ERROR:-false}"
EMAIL_FROM="${EMAIL_FROM:-}"
EMAIL_TO="${EMAIL_TO:-}"
SENDGRID_API_KEY="${SENDGRID_API_KEY:-}"
COPY_BACKUP_TO_EXTERNAL_SERVER="${COPY_BACKUP_TO_EXTERNAL_SERVER:-false}"
EXTERNAL_BACKUP_SERVER_CREDENTIAL="${EXTERNAL_BACKUP_SERVER_CREDENTIAL:-}"
DAYS_TO_LEFT="${DAYS_TO_LEFT:-7}"
DAY_OF_WEEK_TO_LEFT="${DAY_OF_WEEK_TO_LEFT:-6}"
DELETE_FILES_BEFORE_DAYS="${DELETE_FILES_BEFORE_DAYS:-30}"
BACKUP_CLEANING_ENABLED="${BACKUP_CLEANING_ENABLED:-false}"
BACKUP_SOURCES="${BACKUP_SOURCES:-/backup}"
BACKUP_CRON_EXPRESSION="${BACKUP_CRON_EXPRESSION:-@daily}"
AWS_S3_BUCKET_NAME="${AWS_S3_BUCKET_NAME:-}"
BACKUP_FILENAME="$(date +"${BACKUP_FILENAME:-backup-%Y-%m-%dT%H-%M-%S.tar.gz}")"
BACKUP_ARCHIVE="${BACKUP_ARCHIVE:-/archive}"
BACKUP_WAIT_SECONDS="${BACKUP_WAIT_SECONDS:-0}"
BACKUP_HOSTNAME="${BACKUP_HOSTNAME:-$(hostname)}"
INFLUXDB_URL="${INFLUXDB_URL:-}"
INFLUXDB_DB="${INFLUXDB_DB:-}"
INFLUXDB_CREDENTIALS="${INFLUXDB_CREDENTIALS:-}"
INFLUXDB_MEASUREMENT="${INFLUXDB_MEASUREMENT:-docker_volume_backup}"
EOF
chmod a+x env.sh
source env.sh

# Configure AWS CLI
mkdir -p .aws
cat <<EOF > .aws/credentials
[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
EOF
if [ ! -z "$AWS_DEFAULT_REGION" ]; then
cat <<EOF > .aws/config
[default]
region = ${AWS_DEFAULT_REGION}
EOF
fi

# Add our cron entry, and direct stdout & stderr to Docker commands stdout
echo "Installing cron.d entry: docker-volume-backup"
echo "$BACKUP_CRON_EXPRESSION root /root/backup.sh > /proc/1/fd/1 2>&1" > /etc/cron.d/docker-volume-backup

# Let cron take the wheel
echo "Starting cron in foreground with expression: $BACKUP_CRON_EXPRESSION"
cron -f
