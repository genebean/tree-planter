FROM ruby:2.4-slim

LABEL maintainer "gene@technicalissues.us"

ENV GOSU_VERSION 1.10

RUN apt-get update -qq \
  && apt-get install -y --no-install-recommends gcc git make openssh-client ruby-dev wget \
  && dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')" \
  && wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch" \
  && wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc" \
  && export GNUPGHOME="$(mktemp -d)" \
  && gpg --keyserver ha.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
  && gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
  && rm -r "$GNUPGHOME" /usr/local/bin/gosu.asc \
  && chmod +x /usr/local/bin/gosu \
  && gosu nobody true \
  && apt-get clean autoclean \
  && apt-get autoremove -y \
  && rm -rf /var/lib/apt /var/lib/dpkg /var/lib/cache /var/lib/log

ENV APP_ROOT /var/www/tree-planter
RUN mkdir -p $APP_ROOT
WORKDIR $APP_ROOT
ADD Gemfile* $APP_ROOT/

RUN bundle install --jobs=3 --without development

ADD . $APP_ROOT
COPY config-example.json $APP_ROOT/config.json
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# SSH Setup
RUN mkdir -p /home/user/.ssh \
  && printf "Host *\n\tStrictHostKeyChecking no\n" >> /home/user/.ssh/config \
  && chmod 700 /home/user/.ssh \
  && chmod 644 /home/user/.ssh/config

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

EXPOSE 8080
CMD ["bundle", "exec", "passenger", "start", "--port", "8080"]
