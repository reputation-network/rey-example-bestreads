FROM reputationnetwork/gatekeeper as gatekeeper
FROM node:8.12.0-alpine

WORKDIR /gatekeeper
COPY --from=gatekeeper / .

WORKDIR /usr/src/app
RUN apk upgrade --update && apk add --no-cache libatomic readline readline-dev libxml2 libxml2-dev libxml2-utils \
        libxslt libxslt-dev zlib-dev zlib ruby yaml yaml-dev libffi-dev build-base git ruby-io-console ruby-irb \
        ruby-json ruby-rake imagemagick imagemagick-dev make gcc g++ libffi-dev ruby-dev ruby-rdoc ruby-bundler \
        openssl openssl-dev
RUN bundle config --global frozen 1
ADD Gemfile Gemfile.lock ./
RUN bundle install
ADD . .

WORKDIR /
RUN gem install foreman
RUN echo -e "gatekeeper: cd /gatekeeper/app && node src/server.js\nweb: cd /usr/src/app && bundle exec ruby app.rb -p 8081" > Procfile
ENV TARGET_APP_URL=http://localhost:8081

CMD ["foreman", "start"]
