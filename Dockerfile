# sshd and the tools to look at and fix files over ssh. Only the tools: the configuration (sshd_config,
# the login shell, passwd and group, the host key and the authorized keys) is given by whoever runs the image.
FROM ubuntu:24.04

LABEL org.opencontainers.image.source=https://github.com/yuanying/natsumi-sshd

# --no-install-recommends keeps out what sshd and the tools only suggest (xauth, ssh-import-id, ...);
# what is wanted is listed by name. C.UTF-8 is part of glibc, so no locales package is needed.
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        openssh-server \
        openssh-client \
        ca-certificates \
        curl \
        vim \
        git \
        less \
        jq \
        ripgrep \
        rsync \
        procps \
        bash && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    # The package makes host keys at install time; a public image must not carry them.
    rm -f /etc/ssh/ssh_host_*

EXPOSE 22

# Nothing runs before sshd. Without a host key given in a configuration, this default does not start.
CMD ["/usr/sbin/sshd", "-D", "-e"]
