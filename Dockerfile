FROM ruby:2.3-alpine

COPY . /src

WORKDIR /src
RUN rm highlander-*.gem ; \
    gem build highlander.gemspec && \
    gem install highlander-*.gem && \
    rm -rf /src

RUN adduser -u 1000 -D highlander && \
    apk add --update python py-pip git && \
    pip install awscli

WORKDIR /work

USER highlander

CMD 'highlander'
