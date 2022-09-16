docker run --rm --name lilruby -v /vagrant:/vagrant \
  $(grep FROM /vagrant/Dockerfile |cut -d ' ' -f2) \
  /bin/bash -c "apt-get update && $(grep 'apt-get install' /vagrant/Dockerfile |sed -e 's/.*\(apt-get.*\)/\1/' |rev |cut -d ' ' -f2- |rev) && cd /vagrant && gem install bundler && bundle install --jobs=3 && bundle update && bundle update --bundler"
