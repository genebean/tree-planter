# frozen_string_literal: true

# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure(2) do |config|
  config.vm.box = 'genebean/centos-7-puppet-latest'

  config.vm.hostname = 'dockerhost.localdomain'
  config.vm.network 'forwarded_port', guest: 80, host: 8080

  config.vm.provision 'shell',
                      name: 'Pull insecure vagrant_priv_key',
                      inline: <<-EOF
    set -e
    curl -o /home/vagrant/.ssh/vagrant_priv_key https://raw.githubusercontent.com/mitchellh/vagrant/master/keys/vagrant
    chown vagrant.vagrant /home/vagrant/.ssh/vagrant_priv_key
    chmod 600 /home/vagrant/.ssh/vagrant_priv_key
  EOF
  config.vm.provision 'shell',
                      name: 'Install Puppet Modules',
                      inline: 'puppet module install puppetlabs-docker --version 3.5.0'
  config.vm.provision 'shell',
                      name: 'Install Docker',
                      inline: "puppet apply -e \"class { 'docker': log_driver => 'journald' }\""
  config.vm.provision 'shell',
                      name: 'Update Gemfile.lock',
                      inline: '/vagrant/update-gemfile-dot-lock.sh'
  config.vm.provision 'shell',
                      name: 'System setup',
                      inline: 'puppet apply /vagrant/docker.pp'
  config.vm.provision 'shell',
                      name: 'List running containers',
                      inline: 'docker ps'
  config.vm.provision 'shell',
                      name: 'Test container',
                      inline: "docker exec johnny_appleseed /bin/sh -c 'bundle exec rake test'"
  config.vm.provision 'shell',
                      name: 'API test',
                      inline: <<-EOF
    set -e
    rm -rf /home/vagrant/trees/tree-planter*
    curl -H "Content-Type: application/json" -X POST -d \
      '{"ref":"refs/heads/main", "repository":{"name":"tree-planter", "url":"https://github.com/genebean/tree-planter.git" }}' \
      http://localhost:80/deploy
    curl -H "Content-Type: application/json" -X POST -d \
      '{"ref":"refs/heads/main", "repository":{"name":"tree-planter", "url":"https://github.com/genebean/tree-planter.git" }}' \
      http://localhost:80/gitlab
    ls -ld /home/vagrant/trees/
    ls -l /home/vagrant/trees/
  EOF
end
