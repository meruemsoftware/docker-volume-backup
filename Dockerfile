FROM ubuntu:18.04

RUN apt-get update && apt-get install -y --no-install-recommends curl cron awscli groovy openssh-client
RUN rm -rf /var/lib/apt/lists/*

RUN mkdir -p /root/.ssh
RUN chown -R root: root /root/.ssh
RUN echo "Host *\n\tStrictHostKeyChecking no\n" >> /root/.ssh/config

# https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/#install-using-the-convenience-script
COPY ./src/install-docker.sh /root/
RUN chmod a+x /root/install-docker.sh
RUN /root/install-docker.sh

COPY ./src/entrypoint.sh /root/
COPY ./src/backup.sh /root/
COPY ./src/dump-cleaner.groovy /root/
RUN chmod a+x /root/entrypoint.sh
RUN chmod a+x /root/backup.sh
RUN chmod +x /root/dump-cleaner.groovy

WORKDIR /root
CMD [ "/root/entrypoint.sh" ]
