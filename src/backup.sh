#!/bin/bash

# Cronjobs don't inherit their env, so load from file
source env.sh

function info {
  bold="\033[1m"
  reset="\033[0m"
  echo -e "\n$bold[INFO] $1$reset\n"
}

info "Backup starting"
TIME_START="$(date +%s.%N)"
DOCKER_SOCK="/var/run/docker.sock"
if [ -S "$DOCKER_SOCK" ]; then
  TEMPFILE="$(mktemp)"
  docker ps --format "{{.ID}}" --filter "label=docker-volume-backup.stop-during-backup=true" > "$TEMPFILE"
  CONTAINERS_TO_STOP="$(cat $TEMPFILE | tr '\n' ' ')"
  CONTAINERS_TO_STOP_TOTAL="$(cat $TEMPFILE | wc -l)"
  CONTAINERS_TOTAL="$(docker ps --format "{{.ID}}" | wc -l)"
  rm "$TEMPFILE"
  echo "$CONTAINERS_TOTAL containers running on host in total"
  echo "$CONTAINERS_TO_STOP_TOTAL containers marked to be stopped during backup"
else
  CONTAINERS_TO_STOP_TOTAL="0"
  CONTAINERS_TOTAL="0"
  echo "Cannot access \"$DOCKER_SOCK\", won't look for containers to stop"
fi

if [ "$CONTAINERS_TO_STOP_TOTAL" != "0" ]; then
  info "Stopping containers"
  docker stop $CONTAINERS_TO_STOP
fi

if [ -S "$DOCKER_SOCK" ]; then
  TEMPFILE="$(mktemp)"
  docker ps \
    --filter "label=docker-volume-backup.exec-pre-backup" \
    --format '{{.ID}} {{.Label "docker-volume-backup.exec-pre-backup"}}' \
    > "$TEMPFILE"
  while read line; do
    info "Pre-exec command: $line"
    docker exec $line
  done < "$TEMPFILE"
  rm "$TEMPFILE"
fi

info "Creating backup"
TIME_BACK_UP="$(date +%s.%N)"
BACKUP_FILENAME_WITH_DATE="backup-$(date +%Y-%m-%dT%H-%M-%S).tar"
tar -czvf "$BACKUP_FILENAME_WITH_DATE" $BACKUP_SOURCES # allow the var to expand, in case we have multiple sources
if [ $? -ne 0 ] && [ "$SEND_MAIL_IN_CASE_OF_BACKUP_ERROR" == "true" ]
then
  echo "Backup failed, sending mail"
  DATA=$(echo "{'personalizations': [{'to': [{'email': '$EMAIL_TO'}]}],'from': {'email': '$EMAIL_FROM'},'subject': 'Sikertelen biztonsági mentés / Failed to backup','content': [{'type': 'text/plain', 'value': 'A következő fájl elkészítése sikertelen volt / Failed to create the following file: $BACKUP_FILENAME_WITH_DATE'}]}" | sed "s/'/\"/g")
  curl --request POST \
  --url https://api.sendgrid.com/v3/mail/send \
  --header "Authorization: Bearer $SENDGRID_API_KEY" \
  --header 'Content-Type: application/json' \
  --data "$DATA"
fi

BACKUP_SIZE="$(du --bytes $BACKUP_FILENAME_WITH_DATE | sed 's/\s.*$//')"
TIME_BACKED_UP="$(date +%s.%N)"

if [ -S "$DOCKER_SOCK" ]; then
  TEMPFILE="$(mktemp)"
  docker ps \
    --filter "label=docker-volume-backup.exec-post-backup" \
    --format '{{.ID}} {{.Label "docker-volume-backup.exec-post-backup"}}' \
    > "$TEMPFILE"
  while read line; do
    info "Post-exec command: $line"
    docker exec $line
  done < "$TEMPFILE"
  rm "$TEMPFILE"
fi

if [ "$CONTAINERS_TO_STOP_TOTAL" != "0" ]; then
  info "Starting containers back up"
  docker start $CONTAINERS_TO_STOP
fi

info "Waiting before processing"
echo "Sleeping $BACKUP_WAIT_SECONDS seconds..."
sleep "$BACKUP_WAIT_SECONDS"

TIME_UPLOAD="0"
TIME_UPLOADED="0"
if [ ! -z "$AWS_S3_BUCKET_NAME" ]; then
  info "Uploading backup to S3"
  echo "Will upload to bucket \"$AWS_S3_BUCKET_NAME\""
  TIME_UPLOAD="$(date +%s.%N)"
  aws s3 cp --only-show-errors "$BACKUP_FILENAME_WITH_DATE" "s3://$AWS_S3_BUCKET_NAME/"
  echo "Upload finished"
  TIME_UPLOADED="$(date +%s.%N)"
fi

if [ -d "$BACKUP_ARCHIVE" ]; then
  info "Archiving backup"
  mv -v "$BACKUP_FILENAME_WITH_DATE" "$BACKUP_ARCHIVE/$BACKUP_FILENAME_WITH_DATE"
fi

if [ -f "$BACKUP_FILENAME_WITH_DATE" ]; then
  info "Cleaning up"
  rm -vf "$BACKUP_FILENAME_WITH_DATE"
fi

info "Collecting metrics"
TIME_FINISH="$(date +%s.%N)"
INFLUX_LINE="$INFLUXDB_MEASUREMENT\
,host=$BACKUP_HOSTNAME\
\
 size_compressed_bytes=$BACKUP_SIZE\
,containers_total=$CONTAINERS_TOTAL\
,containers_stopped=$CONTAINERS_TO_STOP_TOTAL\
,time_wall=$(perl -E "say $TIME_FINISH - $TIME_START")\
,time_total=$(perl -E "say $TIME_FINISH - $TIME_START - $BACKUP_WAIT_SECONDS")\
,time_compress=$(perl -E "say $TIME_BACKED_UP - $TIME_BACK_UP")\
,time_upload=$(perl -E "say $TIME_UPLOADED - $TIME_UPLOAD")\
"
echo "$INFLUX_LINE" | sed 's/ /,/g' | tr , '\n'

if [ ! -z "$INFLUXDB_URL" ]; then
  info "Shipping metrics"
  curl \
    --silent \
    --include \
    --request POST \
    --user "$INFLUXDB_CREDENTIALS" \
    "$INFLUXDB_URL/write?db=$INFLUXDB_DB" \
    --data-binary "$INFLUX_LINE"
fi

if [ "$COPY_BACKUP_TO_EXTERNAL_SERVER" == "true" ]; then
info "Copying backup to external server"
tar -C / -cf - /archive/"$BACKUP_FILENAME_WITH_DATE" | ssh "$EXTERNAL_BACKUP_SERVER_CREDENTIAL" tar -C / -xvf -
info "Copying finished"
fi

info "Backup finished"

if [ "$BACKUP_CLEANING_ENABLED" == "true" ]; then
info "Cleaning old backups"
groovy /root/dump-cleaner.groovy /archive/ "$DAYS_TO_LEFT" "$DAY_OF_WEEK_TO_LEFT" "$DELETE_FILES_BEFORE_DAYS"
info "Cleaning finished"
fi


echo "Will wait for next scheduled backup"
