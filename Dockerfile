# Dockerfile for icinga2 with icingaweb2
# https://github.com/jjethwa/icinga2

FROM debian:stretch

MAINTAINER Jordan Jethwa

ENV APACHE2_HTTP=REDIRECT \
    ICINGA2_FEATURE_GRAPHITE=false \
    ICINGA2_FEATURE_GRAPHITE_HOST=graphite \
    ICINGA2_FEATURE_GRAPHITE_PORT=2003 \
    ICINGA2_FEATURE_GRAPHITE_URL=http://graphite \
    ICINGA2_USER_FULLNAME="Icinga2" \
    ICINGA2_FEATURE_DIRECTOR="true" \
    ICINGA2_FEATURE_DIRECTOR_KICKSTART="true" \
    ICINGA2_FEATURE_DIRECTOR_USER="icinga2-director"

RUN export DEBIAN_FRONTEND=noninteractive \
 && apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y --no-install-recommends \
      apache2 \
      ca-certificates \
      curl \
      dnsutils \
      gnupg \
      locales \
      lsb-release \
      mailutils \
      mariadb-client \
      mariadb-server \
      php-curl \
      php-ldap \
      php-mysql \
      procps \
      pwgen \
      snmp \
      ssmtp \
      sudo \
      supervisor \
      unzip \
      wget \
      libdbd-mysql-perl \
      postgresql-client \
      netcat \
      jq \
      libwww-perl \
      libjson-perl \
      libdatetime-perl \
      default-jre \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

RUN export DEBIAN_FRONTEND=noninteractive \
 && curl -s https://packages.icinga.com/icinga.key \
 | apt-key add - \
 && echo "deb http://packages.icinga.org/debian icinga-$(lsb_release -cs) main" > /etc/apt/sources.list.d/icinga2.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      icinga2 \
      icinga2-ido-mysql \
      icingacli \
      icingaweb2 \
      icingaweb2-module-doc \
      icingaweb2-module-monitoring \
      monitoring-plugins \
      nagios-nrpe-plugin \
      nagios-plugins-contrib \
      nagios-snmp-plugins \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*



ARG GITREF_DIRECTOR=master
ARG GITREF_MODGRAPHITE=master
ARG GITREF_MODAWS=master

RUN mkdir -p /usr/local/share/icingaweb2/modules/ \
# Icinga Director
 && mkdir -p /usr/local/share/icingaweb2/modules/director/ \
 && wget -q --no-cookies -O - "https://github.com/Icinga/icingaweb2-module-director/archive/${GITREF_DIRECTOR}.tar.gz" \
 | tar xz --strip-components=1 --directory=/usr/local/share/icingaweb2/modules/director --exclude=.gitignore -f - \
# Icingaweb2 Graphite
 && mkdir -p /usr/local/share/icingaweb2/modules/graphite \
 && wget -q --no-cookies -O - "https://github.com/Icinga/icingaweb2-module-graphite/archive/${GITREF_MODGRAPHITE}.tar.gz" \
 | tar xz --strip-components=1 --directory=/usr/local/share/icingaweb2/modules/graphite -f - icingaweb2-module-graphite-${GITREF_MODGRAPHITE}/ \
# Icingaweb2 AWS
 && mkdir -p /usr/local/share/icingaweb2/modules/aws \
 && wget -q --no-cookies -O - "https://github.com/Icinga/icingaweb2-module-aws/archive/${GITREF_MODAWS}.tar.gz" \
 | tar xz --strip-components=1 --directory=/usr/local/share/icingaweb2/modules/aws -f - icingaweb2-module-aws-${GITREF_MODAWS}/ \
 && wget -q --no-cookies "https://github.com/aws/aws-sdk-php/releases/download/2.8.30/aws.zip" \
 && unzip -d /usr/local/share/icingaweb2/modules/aws/library/vendor/aws aws.zip \
 && rm aws.zip \
 && true

ENV PATH $PATH:/usr/lib/nagios/plugins/nagios-plugins

# Download Cassandra but don't install it. Needed to use nodetool to check cassandra connections
ARG CASSANDRA_VERSION=3.11.0
ARG TAR="apache-cassandra-$CASSANDRA_VERSION-bin.tar.gz"

RUN mkdir -p /opt/cassandra/ \
  && wget -q --no-cookies -O - "http://archive.apache.org/dist/cassandra/${CASSANDRA_VERSION}/${TAR}" \
  | tar xz --strip-components=1 --directory=/opt/cassandra/ --exclude=.gitignore -f - \
  && rm -fv "${TAR}" \
  && true



#Install custom nagios plugins from git repository
RUN bash -c ' \
    export DEBIAN_FRONTEND=noninteractive && \
    set -euxo pipefail && \
    apt-get update && \
    apt-get install -y --no-install-recommends git make && \
    cd /usr/lib/nagios/plugins/ && \
    git clone https://github.com/dmilcevski/nagios-plugins.git && \
    cd nagios-plugins/ && \
    git submodule update --init --recursive --remote && \
    git submodule foreach git checkout master && \
    make build zookeeper \
    #make apt-packages-remove && \
    #apt-get autoremove -y && \
    #apt-get clean \
    # run tests after autoremove to check that no important packages we need get removed
    #make test deep-clean && \
    # leave git it's needed for Git-Python and check_git_branch_checkout.pl/py
    #apt-get remove -y make && \
    #apt-get autoremove -y && \
    #apt-get clean \
    #bash-tools/check_docker_clean.sh \
    # basic test for missing dependencies again
    #tests/help.sh \
    '

ADD content/ /

# Final fixes
RUN true \
 && sed -i 's/vars\.os.*/vars.os = "Docker"/' /etc/icinga2/conf.d/hosts.conf \
 && mv /etc/icingaweb2/ /etc/icingaweb2.dist \
 && mkdir /etc/icingaweb2 \
 && mv /etc/icinga2/ /etc/icinga2.dist \
 && mkdir /etc/icinga2 \
 && usermod -aG icingaweb2 www-data \
 && usermod -aG nagios www-data \
 && rm -rf \
     /var/lib/mysql/* \
 && chmod u+s,g+s \
     /bin/ping \
     /bin/ping6 \
     /usr/lib/nagios/plugins/check_icmp

EXPOSE 80 443 5665

# Initialize and run Supervisor
ENTRYPOINT ["/opt/run"]
