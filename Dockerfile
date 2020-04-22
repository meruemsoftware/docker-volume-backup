FROM ubuntu:18.04

RUN apt-get update && apt-get install -y --no-install-recommends curl cron awscli groovy
RUN rm -rf /var/lib/apt/lists/*

# https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/#install-using-the-convenience-script
RUN curl -fsSL get.docker.com -o get-docker.sh
RUN sh get-docker.sh

COPY ./src/entrypoint.sh /root/
COPY ./src/backup.sh /root/
COPY ./src/dump-cleaner.groovy /root/
RUN chmod a+x /root/entrypoint.sh
RUN chmod a+x /root/backup.sh
RUN chmod +x /root/dump-cleaner.groovy

WORKDIR /root
CMD [ "/root/entrypoint.sh" ]
