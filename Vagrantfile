# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure(2) do |config|
  config.vm.box = 'genebean/centos-7-puppet-agent'

  if Vagrant.has_plugin?('vagrant-cachier')
    # Configure cached packages to be shared between instances of the same base box.
    # More info on http://fgrehm.viewdocs.io/vagrant-cachier/usage
    config.cache.scope = :box
  end

  config.vm.hostname = 'dockerhost.localdomain'
  config.vm.network 'forwarded_port', guest: 80, host: 8080

  config.vm.provision 'shell', inline: <<-EOF
    curl -o /home/vagrant/.ssh/vagrant_priv_key https://raw.githubusercontent.com/mitchellh/vagrant/master/keys/vagrant
    chown vagrant.vagrant /home/vagrant/.ssh/vagrant_priv_key
    chmod 600 /home/vagrant/.ssh/vagrant_priv_key
  EOF

  config.vm.provision 'shell', inline: 'puppet module install garethr-docker --version 5.3.0'
  config.vm.provision 'shell', inline: 'puppet apply /vagrant/docker.pp'
  config.vm.provision 'shell', inline: 'docker ps'
  config.vm.provision 'shell', inline: "docker exec johnny-appleseed /bin/sh -c 'bundle exec rake test'"

  config.vm.provision 'shell', inline: <<-EOF
    rm -rf /home/vagrant/trees/tree-planter*
    curl -H "Content-Type: application/json" -X POST -d \
      '{"ref":"refs/heads/master", "repository":{"name":"tree-planter", "url":"https://github.com/genebean/tree-planter.git" }}' \
      http://localhost:80/deploy
    curl -H "Content-Type: application/json" -X POST -d \
      '{"ref":"refs/heads/master", "repository":{"name":"tree-planter", "url":"https://github.com/genebean/tree-planter.git" }}' \
      http://localhost:80/gitlab
    ls -ld /home/vagrant/trees/
    ls -l /home/vagrant/trees/
  EOF
end
