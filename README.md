![Docker Image Version (latest semver)](https://img.shields.io/docker/v/genebean/tree-planter?label=Docker%20Image&style=plastic)
![GitHub Release (latest by date)](https://img.shields.io/github/v/release/genebean/tree-planter?label=GitHub%20Release&style=plastic)
[![Docker Image CI](https://github.com/genebean/tree-planter/actions/workflows/docker-image.yml/badge.svg)](https://github.com/genebean/tree-planter/actions/workflows/docker-image.yml)
[![Build-and-Push](https://github.com/genebean/tree-planter/actions/workflows/build-and-push.yml/badge.svg)](https://github.com/genebean/tree-planter/actions/workflows/build-and-push.yml)

# tree-planter

tree-planter is a webhook receiver that is designed to deploy code trees via either a simple JSON payload or the payload from a GitLab webhook. Cloned branches can also be deleted via a the GitLab webhook.

New builds are automatically published to [Docker Hub](https://hub.docker.com/r/genebean/tree-planter) and [GitHub Container Registry](https://github.com/genebean/tree-planter/pkgs/container/tree-planter) whenever a pull request is merged. Each time the image tag `latest` is updated and a new containing the date and the short version of the git sha is created.

Technology-wise, tree-planter is a Ruby application built on [Sinatra][sinatra]. The application is served up by the [Passenger][passenger] gem. All this has been neatly wrapped up in a Docker container that's based on the official [ruby:slim-buster][ruby] one which, in turn, is based on the official [debian:buster][debian] one. A utility called [gosu][gosu] is used for the entry point so that the application can run with a specified UID.

- [File ownership / permissions](#file-ownership--permissions)
- [Running the container](#running-the-container)
  - [And here it is all together](#and-here-it-is-all-together)
  - [Send email on deployment failure](#send-email-on-deployment-failure)
- [End Points](#end-points)
- [Examples](#examples)
  - [Metrics](#metrics)
  - [Triggering the `/deploy` endpoint via cURL](#triggering-the-deploy-endpoint-via-curl)
  - [Triggering the `/gitlab` endpoint via cURL with a GitLab-like payload](#triggering-the-gitlab-endpoint-via-curl-with-a-gitlab-like-payload)
  - [Clone a branch into an alternate destination path](#clone-a-branch-into-an-alternate-destination-path)
  - [Delete cloned copy of feature/parsable_names branch with a GitLab-like payload](#delete-cloned-copy-of-featureparsable_names-branch-with-a-gitlab-like-payload)
- [Updating Gemfile.lock](#updating-gemfilelock)
- [Development & Testing](#development--testing)
  - [Vagrant](#vagrant)
  - [Manual testing](#manual-testing)
  - [Validation](#validation)
  - [Don't forget](#dont-forget)

## File ownership / permissions

If you are deploying a git repository somewhere, and you must be if you are looking to use to use tree-planter, then permissions on the downloaded files are likely important. This is where [gosu][gosu] comes in. We will pass in a UID when we start up our container and that is who tree-planter will run as.

## Running the container

All the example code below assumes you are using [Puppet][puppet] and the [puppetlabs/docker][puppetlabs/docker] module to manage your servers. If that is not the case you will still need to account for creating an application user and creating init scripts or systemd unit files for starting and stopping the container. There are also a couple of directories that need to be created and have their ownership set to that of the application user. Now, on with getting your instance of tree-planter up and running.

Lets step through things and then put it all together in one copy/past friendly block farther down the page.

First things first, let create the group that lets other users run Docker commands:

```puppet
group { 'docker':
  ensure => 'present',
}
```

Now lets create an application user. Since development of this project is done inside a VM by way of Vagrant our example user is going to be named `vagrant`.

```puppet
$appuser    = 'vagrant'
$appuseruid = '1000'

user { $appuser:
  ensure           => 'present',
  gid              => '1000',
  groups           => ['wheel', 'docker'],
  home             => "/home/${appuser}",
  password         => '$6$eVECWbuT$6PZ6cqTwG11jrwpgB0g1Q5GyV3Y.UvEiXfT/KR3XP8RfHhHvJsp1.zU1H0ljuhFnw39r.HoSQiXm/RxcqCBQ7/',
  password_max_age => '99999',
  password_min_age => '0',
  shell            => '/bin/zsh',
  uid              => $appuseruid,
  require          => Group['docker'],
}
```

A key thing to note in the code above is that the user is in the docker group. This lets them run Docker commands without sudo.

Next, lets make the directories needed for this application.

```puppet
# this is where your git repo(s) will live
file { "/home/${appuser}/trees":
  ensure   => 'directory',
  group    => $appuser,    # generally the same as your app user
  mode     => '755',       # adjust as needed
  owner    => $appuser,    # must be your app user
}

# this is so you can see the logs generated by Sinatra and Passenger
file { '/var/log/tree-planter':
  ensure   => 'directory',
  group    => $appuser,
  mode     => '755',
  owner    => $appuser,
}
```

Now that our user and directories are in place lets get the container going. Details of what the code below does can be found at on the Puppet Forge page for [puppetlabs/docker][puppetlabs/docker].

```puppet
class { 'docker':
  log_driver => 'journald',
}

docker::image { 'genebean/tree-planter':
  image_tag => 'latest',
}

docker::run { 'johnny_appleseed':
  image           => 'genebean/tree-planter',
  ports           => '80:8080',
  volumes         => [
    "/home/${appuser}/.ssh/id_rsa:/home/user/.ssh/id_rsa",
    "/home/${appuser}/trees:/opt/trees",
    '/var/log/tree-planter:/var/www/tree-planter/log',
  ],
  env             => "LOCAL_USER_ID=${appuseruid}",
  restart_service => true,
  privileged      => false,
  require         => [
    User[$appuser],
    File["/home/${appuser}/trees"],
    File['/var/log/tree-planter'],
  ],
}
```

There are a couple of things from above that I want to pull your attention to:

- `log_driver => 'journald',` - Explicitly use journald. If you are not using systemd then you will need to adjust this.
- `ports => '80:8080',` - 80 is the port that will be used on your host.
- `"/home/${appuser}/.ssh/id_rsa:/home/user/.ssh/id_rsa",` - this is the ssh key that will be used for pulling repositories.

### And here it is all together

```puppet
$appuser    = 'vagrant'
$appuseruid = '1000'

group { 'docker':
  ensure => 'present',
}

user { $appuser:
  ensure           => 'present',
  gid              => '1000',
  groups           => ['wheel', 'docker'],
  home             => "/home/${appuser}",
  password         => '$6$eVECWbuT$6PZ6cqTwG11jrwpgB0g1Q5GyV3Y.UvEiXfT/KR3XP8RfHhHvJsp1.zU1H0ljuhFnw39r.HoSQiXm/RxcqCBQ7/',
  password_max_age => '99999',
  password_min_age => '0',
  shell            => '/bin/bash',
  uid              => $appuseruid,
  require          => Group['docker'],
}

# this is where your git repo(s) will live
file { "/home/${appuser}/trees":
  ensure   => 'directory',
  group    => $appuser,    # generally the same as your app user
  mode     => '755',       # adjust as needed
  owner    => $appuser,    # must be your app user
}

# this is so you can see the logs generated by Sinatra and Passenger
file { '/var/log/tree-planter':
  ensure   => 'directory',
  group    => $appuser,
  mode     => '755',
  owner    => $appuser,
}

class { 'docker':
  log_driver => 'journald',
}

docker::image { 'genebean/tree-planter':
  image_tag => 'latest',
}

docker::run { 'johnny_appleseed':
  image           => 'genebean/tree-planter',
  ports           => '80:8080',
  volumes         => [
    "/home/${appuser}/.ssh/id_rsa:/home/user/.ssh/id_rsa",
    "/home/${appuser}/trees:/opt/trees",
    '/var/log/tree-planter:/var/www/tree-planter/log',
  ],
  env             => "LOCAL_USER_ID=${appuseruid}",
  restart_service => true,
  privileged      => false,
  require         => [
    User[$appuser],
    File["/home/${appuser}/trees"],
    File['/var/log/tree-planter'],
  ],
}
```

### Send email on deployment failure

tree-planter uses the [Pony](https://github.com/benprew/pony) gem to send emails. Please see the Pony documentation and pass any Pony specific option keys to the `pony_email_options` in `config.json`, and set `send_email_on_failure` equal to `true`.

For example, create `config-custom-example.json`:

```
{
  "base_dir": "/opt/trees",
  "send_email_on_failure": true,
  "pony_email_options": {
    "to": "you@example.com",
    "via": "smtp",
    "via_options": {
      "address"              : "smtp.gmail.com",
      "port"                 : "587",
      "enable_starttls_auto" : true,
      "user_name"            : "user",
      "password"             : "password",
      "authentication"       : "plain",
      "domain"               : "localhost.localdomain"
    }
  }
}
```

And modify the `docker::run` resource to use the custom `config.json`:

```
docker::run { 'johnny_appleseed':
  image           => 'genebean/tree-planter',
  ports           => '80:8080',
  volumes         => [
    "/home/${appuser}/.ssh/vagrant_priv_key:/home/user/.ssh/id_rsa",
    "/home/${appuser}/trees:/opt/trees",
    '/var/log/tree-planter:/var/www/tree-planter/log',
    '/vagrant/config-custom-example.json:/var/www/tree-planter/config.json',
  ],
  env             => "LOCAL_USER_ID=${appuseruid}",
  restart_service => true,
  privileged      => false,
  require         => [
    User[$appuser],
    File["/home/${appuser}/trees"],
    File['/var/log/tree-planter'],
  ],
}
```

## End Points

tree-planter has the following endpoints:

- `/` - when the base URL is opened in a browser it show you a list of the endpoints.
- `/deploy` - Deploys the default branch of a repository. It accepts a POST in the format of a GitLab webhook or in the custom format shown in the examples below.
- `/gitlab` - Deploys the branch of a repo referenced in the payload of a webhook POST from GitLab. Each branch is placed into a folder using the naming convention `repository_branch` such as `tree-planter_main`. All /'s are replaced with underscores.
- `/hook-test` - Used for testing and debugging. It displays diagnostic info about the payload that was POST'ed.
- `/metrics` - Displays Prometheus metrics

If using the Vagrant box or running behind Apache on your server these will all send a fair amount of info to Apache's error log. The error log is used as a byproduct of how Sinatra / Rack do their logging.

## Examples

### Metrics

Both stock metrics provided by integrating with Rack and custom metrics are available via the `/metrics` endpoint. Here is a sample of what you should see there:

```plain
# TYPE tree_deploys counter
# HELP tree_deploys A count of how many times each variation of each tree has been deployed
tree_deploys{tree_name="tree-planter",branch_name="main",repo_path="tree-planter",endpoint="deploy"} 3.0
tree_deploys{tree_name="tree-planter",branch_name="main",repo_path="tree-planter___main",endpoint="gitlab"} 2.0
# TYPE http_server_requests_total counter
# HELP http_server_requests_total The total number of HTTP requests handled by the Rack application.
http_server_requests_total{code="200",method="head",path="/"} 1.0
http_server_requests_total{code="200",method="get",path="/metrics"} 3.0
http_server_requests_total{code="200",method="post",path="/deploy"} 3.0
http_server_requests_total{code="200",method="post",path="/gitlab"} 2.0
```

### Triggering the `/deploy` endpoint via cURL

```bash
# first run using
[vagrant@localhost opt]$ curl -H "Content-Type: application/json" -X POST -d \
'{ "tree_name": "tree-planter", "repo_url": "https://github.com/genebean/tree-planter.git" }' \
http://localhost:4567/deploy
endpoint:  deploy
tree:      tree-planter
branch:
repo_url:  https://github.com/genebean/tree-planter.git
repo_path: tree-planter
base:      /opt/trees

Running git clone https://github.com/genebean/tree-planter.git tree-planter
Cloning into 'tree-planter'...
```

```bash
# second run using the /deploy endpoint
[vagrant@localhost ~]$ curl -H "Content-Type: application/json" -X POST -d \
'{ "tree_name": "tree-planter", "repo_url": "https://github.com/genebean/tree-planter.git" }' \
http://localhost:4567/deploy
endpoint:  deploy
tree:      tree-planter
branch:
repo_url:  https://github.com/genebean/tree-planter.git
repo_path: tree-planter
base:      /opt/trees

Running git pull
Already up-to-date.
```

### Triggering the `/gitlab` endpoint via cURL with a GitLab-like payload

```bash
# Pull main branch
curl -H "Content-Type: application/json" -X POST -d \
'{"ref":"refs/heads/main", "checkout_sha":"858f1411ecd9d0b7c8f049a98412d1b3dcb68eae", "repository":{"name":"tree-planter", "url":"https://github.com/genebean/tree-planter.git" }}' \
http://localhost/gitlab

# Pull develop branch
curl -H "Content-Type: application/json" -X POST -d \
'{"ref":"refs/heads/develop", "checkout_sha":"858f1411ecd9d0b7c8f049a98412d1b3dcb68eae", "repository":{"name":"tree-planter", "url":"https://github.com/genebean/tree-planter.git" }}' \
http://localhost/gitlab

# Pull feature/parsable_names branch
curl -H "Content-Type: application/json" -X POST -d \
'{"ref":"refs/heads/feature/parsable_names", "checkout_sha":"858f1411ecd9d0b7c8f049a98412d1b3dcb68eae", "repository":{"name":"tree-planter", "url":"https://github.com/genebean/tree-planter.git" }}' \
http://localhost/gitlab
```

### Clone a branch into an alternate destination path

```bash
# Pull the default branch into a directory named "custom_path"
# Note the presence of "repo_path" in this one
curl -H "Content-Type: application/json" -X POST -d \
'{ "tree_name": "tree-planter", "repo_url": "https://github.com/genebean/tree-planter.git", "repo_path": "custom_path" }' \
http://localhost:4567/deploy
endpoint:  deploy
tree:      tree-planter
branch:
repo_url:  https://github.com/genebean/tree-planter.git
repo_path: custom_path
base:      /opt/trees

Running git clone https://github.com/genebean/tree-planter.git custom_path
Cloning into 'custom_path'...
```

### Delete cloned copy of feature/parsable_names branch with a GitLab-like payload

```bash
# Current style GitLab
# Note the absence of "checkout_sha" in this one
curl -H "Content-Type: application/json" -X POST -d \
'{"ref":"refs/heads/feature/parsable_names", "after":"0000000000000000000000000000000000000000", "repository":{"name":"tree-planter", "url":"https://github.com/genebean/tree-planter.git" }}' \
http://localhost/gitlab

# Old style GitLab
curl -H "Content-Type: application/json" -X POST -d \
'{"ref":"refs/heads/feature/parsable_names", "checkout_sha":"0000000000000000000000000000000000000000", "repository":{"name":"tree-planter", "url":"https://github.com/genebean/tree-planter.git" }}' \
http://localhost/gitlab
```

## Updating Gemfile.lock

`update-gemfile-dot-lock.sh` will update `Gemfile.lock` using the Docker image defined in `Dockerfile`. It is designed to be run inside a vagrant environment and is run as part of `vagrant up`.

## Development & Testing

### Vagrant

The repository contains a Vagrantfile that will allow you to fire up a CentOS 7 box that contains the Puppet agent. It builds and deploys the Docker image using the tools documented above. After it is up you can talk to the container in four ways:

1. Run `curl` commands from inside the Vagrant box targeted at http://localhost
2. Run `curl` or a similar command from the command prompt / terminal of your local computer targeted at http://localhost:8080
3. Run `vagrant share` and then target an endpoint such as http://caring-orangutan-0713.vagrantshare.com/gitlab You can learn more about Vagrant Share [here][vs].
4. Run [ngrok][ngrok] on your local computer by executing `./ngrok http 8080` and then targeting an endpoint such as http://2bf16064.ngrok.io/gitlab (adapt the URL based on ngrok's output)

### Manual testing

You can then easily rebuild and test your code by stopping the puppet-created service and using docker directly like so:

```bash
sudo systemctl stop docker-johnny_appleseed
cd /vagrant
docker build -t genebean/tree-planter .
docker run --rm -p 80:8080 -v /home/vagrant/.ssh/vagrant_priv_key:/home/user/.ssh/id_rsa -v /home/vagrant/trees:/opt/trees -v /var/log/tree-planter:/var/www/tree-planter/log -e LOCAL_USER_ID=1000 genebean/tree-planter:latest
```

Depending on your changes, you may also need to clean up what currently exists:

```bash
# clean most things
docker system prune -f

# clean all the things
docker system prune -fa
```

### Validation

Once you think everything is good you should re-run puppet to update its setup and then re-run the tests done during `vagrant up`:

```bash
sudo -i puppet apply /vagrant/docker.pp

docker exec johnny_appleseed /bin/sh -c 'bundle exec rake test'

sudo rm -rf /home/vagrant/trees/tree-planter*

curl -H "Content-Type: application/json" -X POST -d \
  '{"ref":"refs/heads/main", "repository":{"name":"tree-planter", "url":"https://github.com/genebean/tree-planter.git" }}' \
  http://localhost:80/deploy

curl -H "Content-Type: application/json" -X POST -d \
  '{"ref":"refs/heads/main", "repository":{"name":"tree-planter", "url":"https://github.com/genebean/tree-planter.git" }}' \
  http://localhost:80/gitlab

ls -ld /home/vagrant/trees/

ls -l /home/vagrant/trees/
```

Alternatively, you could simply run `vagrant destroy -f; vagrant up` to recreate the Vagrant environment from scratch as that will take care of performing a build in a clean environment and then running some basic tests.

If all of that looks good you should also run `rubocop` against your local copy of the code. You can do that from inside Vagrant like so:

```bash
~ » docker run --rm -it --entrypoint='' -v /vagrant:/vagrant genebean/tree-planter \
/bin/bash -c 'cd /vagrant; bundle exec rake rubocop'
Running RuboCop...
Inspecting 6 files
......

6 files inspected, no offenses detected
Running RuboCop...
Inspecting 6 files
......

6 files inspected, no offenses detected
```

Many errors that are may be returned can be fixed by running a variation of the command above that has `rake rubocop` replaced with `rake rubocop:auto_correct`.

### Don't forget

Lastly, be sure to check the output of the [`/metrics` endpoint](http://localhost:8080/metrics) if you have made any changes to the Prometheus metrics' code.


[debian]: https://hub.docker.com/_/debian/
[dockerimage]: https://hub.docker.com/r/genebean/tree-planter/
[gosu]: https://github.com/tianon/gosu
[ngrok]: https://ngrok.com
[passenger]: https://www.phusionpassenger.com
[puppet]: https://puppet.com
[puppetlabs/docker]: https://forge.puppet.com/puppetlabs/docker
[ruby]: https://hub.docker.com/_/ruby/
[sinatra]: http://www.sinatrarb.com
[vs]: https://www.vagrantup.com/docs/share/http.html

