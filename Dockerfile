# syntax=docker/dockerfile:1
#:======================================================================================================================
#: first build - building the postgres and pgaudit code
#:

FROM ubuntu:24.04 AS build01

ARG author="Wagner Bianchi"
ARG email="me@wagnerbianchi.com"
ARG VERSION=${VERSION}
ARG RELEASE=${RELEASE}

LABEL "maintainer"=$email

USER root

#: seeting ENV
ENV SCPATH=/etc/supervisor/conf.d
ENV PG_HOME=/usr/local/pgsql/bin
ENV PGDATA=/data/pgsql/data
ENV PGPORT=5432
ENV PGDATABASE=postgres
ENV PGUSER=postgres
ENV PG_WORKDIR=/data/pgsql
ENV SSH_PORT=22

#: download and build the postgresql database application
RUN --mount=type=cache,target=/root/.cache.1 DEBIAN_FRONTEND=noninteractive apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    gcc \
    bison \
    flex \
    build-essential \
    zlib1g-dev \
    libreadline6-dev \
    libicu-dev \
    pkg-config \
    wget \
    sudo \
    git \
    libzstd-dev

#: Downloading the PostgreSQL source code and building it up
#: It will place the extension files at `/usr/local/pgsql/share/extension`
#: To make the installation succeed together with all the native extensions
#: we need to use the `make world-bin`, and `make install-world-bin`, 
#: which exclude only the documentation (HTML/PDF files).
#: https://www.postgresql.org/docs/15/install-procedure.html
#: https://github.com/postgres/postgres/tree/master/contrib
RUN --mount=type=cache,target=/root/.cache.2 wget -q https://ftp.postgresql.org/pub/source/v${VERSION}.${RELEASE}/postgresql-${VERSION}.${RELEASE}.tar.bz2 \
 && tar -xf postgresql-${VERSION}.${RELEASE}.tar.bz2 -C /root \
 && cd /root/postgresql-${VERSION}.${RELEASE} \
 && ./configure --with-zstd \
 && make world-bin \
 && make install \
 && make install-world-bin

#: pgaudit, cloning the pgAudit extension
RUN git clone https://github.com/pgaudit/pgaudit.git /root/pgaudit \
&& cd /root/pgaudit \
&& git checkout REL_${VERSION}_STABLE \
&& make install USE_PGXS=1 PG_CONFIG=${PG_HOME}/pg_config

#: creating the postgres user - the below password should be on a vault instance
RUN groupadd -g 10001 postgres \
 && useradd postgres -u 10001 -g postgres -p '123456' -s '/bin/bash' -c 'PostgreSQL Database Application Superuser' \
 && usermod -aG sudo postgres \
 && mkdir -p /data/pgsql/data \
 && mkdir -p /var/run/sshd \
 && chown -R postgres: /data/pgsql/data \
 && chown -R postgres:postgres /usr/local/pgsql/bin \
 && chown -R postgres:postgres /data/pgsql/data \
 && mkdir -p /data/pgsql/local \
 && chown -R postgres:postgres /data/pgsql/local \ 
 && mkdir -p /data/pgsql/tmp \
 && chown -R postgres:postgres /data/pgsql/tmp

#:======================================================================================================================
#: using the build1 image to copy binaries to a
#: smaller container image
FROM ubuntu:24.04 AS build02

#: seeting ENV
ENV SCPATH=/etc/supervisor/conf.d
ENV PG_HOME=/usr/local/pgsql/bin
ENV PGDATA=/data/pgsql/data
ENV PGPORT=5432
ENV PGDATABASE=postgres
ENV PGUSER=postgres
ENV PG_WORKDIR=/data/pgsql
ENV SSH_PORT=22

#: download and build the postgresql database application
RUN --mount=type=cache,target=/root/.cache DEBIAN_FRONTEND=noninteractive apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    vim \
    sudo \
    supervisor \
    zlib1g-dev \
    libpq-dev \
    libreadline6-dev \
    libicu-dev \
    libdictzip-java \
    pkg-config \
    openssh-server

VOLUME [ "/data" ]

#: copying the PG_HOME
COPY --from=build01 /usr/local/pgsql /usr/local/pgsql

#: creating the postgres user - the below password should be on a vault instance
RUN groupadd -g 10001 postgres \
 && useradd postgres -m -d /home/postgres -u 10001 -g sudo -G sudo -p '123456' -s '/bin/bash' -c 'PostgreSQL Database Application Superuser' \
 && mkdir -p /data/pgsql/data \
 && mkdir -p /var/log/supervisor \
 && mkdir -p /var/run/sshd \
 && chown -R postgres:postgres /data/pgsql/data \
 && chown -R postgres:postgres /usr/local/pgsql

#: attributing a password auth-method=scram-sha-256
#: to the postgres user - the beklow file has a hash
COPY ./secretpassword /tmp/.secretpassword
RUN chown -R postgres:postgres /tmp/.secretpassword

#: initialising the database - it needs an anonimous volume
RUN su - postgres -c "/usr/local/pgsql/bin/initdb --locale=C.UTF-8 --encoding=UTF8 -D ${PGDATA} -U ${PGUSER} -A scram-sha-256 -d --data-checksums --pwfile=/tmp/.secretpassword"

#: setting directories permissions
RUN mkdir -p /data/pgsql/data/walbackup \
&& mkdir -p /data/pgsql/data/databackup \
&& mkdir -p /data/pgsql/local \
&& mkdir -p /data/pgsql/tmp \
&& chown -R postgres /data/pgsql/data/walbackup \
&& chown -R postgres /data/pgsql/data/databackup \
&& chown -R postgres /data/pgsql/local \ 
&& chown -R postgres /data/pgsql/tmp \
&& rm -rf /tmp/.secretpassword

# Supervisor Configuration
COPY ./supervisord/conf.d/* ${SCPATH}/

#: exposing ports
EXPOSE ${PGPORT}/tcp ${SSH_PORT}/tcp

#: adding the pgsudo to sudoers.d
COPY ./pgsudo /etc/sudoers.d/pgsudo

 #: COPYing the customized postgresql.conf
RUN rm -rf ${PGDATA}/postgresql.conf \
 && rm -rf ${PGDATA}/pg_hba.conf

COPY postgresql.conf ${PGDATA}/postgresql.conf
COPY pg_hba.conf ${PGDATA}/pg_hba.conf
COPY bashrc /home/postgres/.bashrc
RUN chown postgres:postgres ${PGDATA}/postgresql.conf \
 && chown postgres:postgres ${PGDATA}/pg_hba.conf \
 && chown postgres:postgres /home/postgres/.bashrc

#: setting up the working directory
WORKDIR ${PG_WORKDIR}

#: lauching up the container starting up services
#: up ordering postgres (p1) and the sshd (p2)
CMD [ "supervisord", "-n" ]
