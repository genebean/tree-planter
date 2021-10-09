#!/bin/bash
set -e

pre_branch='{"ref":"refs/heads/'
post_branch='", "repository":{"name":"tree-planter", "url":'\"https://github.com/${REPOSITORY}.git\"' }'
repo_path=', "repo_path":"custom_path"'
closing='}'


echo 'Running tests against the locally running container...'


################################################################################
#   Testing /
################################################################################
root_check=`curl -s 127.0.0.1:80 | grep 'To use this tool you need to send a post to one of the following' -c`

if [ $root_check -eq 1 ]; then
  echo 'GET / rendered correctly'
else
  echo 'GET / did not render correctly'
  exit 1
fi
echo


################################################################################
#   Testing /metrics
################################################################################
metrics_check=`curl -s 127.0.0.1:80/metrics | grep '^http_server_requests_total' -c`

if [ $metrics_check -gt 0 ]; then
  echo 'GET /metrics rendered correctly'
else
  echo 'GET /metrics did not render correctly'
  exit 1
fi
echo


################################################################################
#   Testing /deploy
################################################################################
deploy_payload='{ "tree_name": "tree-planter", "repo_url": '\"https://github.com/${REPOSITORY}.git\"' }'
echo 'Posting this payload to test /deploy:'
echo ${deploy_payload}|jq -C .
echo

curl -s -H "Content-Type: application/json" -X POST -d "${deploy_payload}" http://127.0.0.1:80/deploy

deploy_check=`ls -d ${WORKSPACE}/trees/tree-planter/ |wc -l`

if [ $deploy_check -eq 1 ]; then
  echo 'Successfully called the /deploy endpoint'
else
  echo 'Failed to deploy via the /deploy endpoint'
  exit 1
fi
echo


################################################################################
#   Testing /gitlab with master branch and default location
################################################################################
payload="${pre_branch}master${post_branch}${closing}"
echo 'Posting this payload to /gitlab:'
echo ${payload}|jq -C .
echo

curl -s -H "Content-Type: application/json" -X POST -d "${payload}" http://127.0.0.1:80/gitlab

master_check=`ls -d ${WORKSPACE}/trees/tree-planter___master/ |wc -l`

if [ $master_check -eq 1 ]; then
  echo 'Successfully pulled master'
else
  echo 'Failed to pull master'
  exit 1
fi
echo


################################################################################
#   Testing /gitlab with master branch and alternate location
################################################################################
echo "Testing pulling into alternate path"
payload_with_path="${pre_branch}master${post_branch}${repo_path}${closing}"
echo 'Posting this payload to /gitlab:'
echo ${payload_with_path}|jq -C .
echo

curl -s -H "Content-Type: application/json" -X POST -d "${payload_with_path}" http://127.0.0.1:80/gitlab

custom_path_check=`ls -d ${WORKSPACE}/trees/custom_path/ |wc -l`

if [ $custom_path_check -eq 1 ]; then
  echo 'Successfully pulled master to alternate path'
else
  echo 'Failed to pull master to alternate path'
  exit 1
fi
echo


################################################################################
#   Testing that pulled files have the proper ownership
################################################################################
echo "Testing that pulled files are owned by me (${USER})"
ls -ld ${WORKSPACE}/trees/
ls -ld ${WORKSPACE}/trees/tree-planter/
ls -ld ${WORKSPACE}/trees/tree-planter___master/
ls -ld ${WORKSPACE}/trees/custom_path/

# testing trees/tree-planter/
if [ "`stat -c '%U' ${WORKSPACE}/trees`" != "`stat -c '%U' ${WORKSPACE}/trees/tree-planter/`" ]; then
  echo 'Ownership is not the same on ./trees and ./trees/tree-planter'
  exit 1
fi

# testing trees/tree-planter___master/
if [ "`stat -c '%U' ${WORKSPACE}/trees`" != "`stat -c '%U' ${WORKSPACE}/trees/tree-planter___master/`" ]; then
  echo 'Ownership is not the same on ./trees and ./trees/tree-planter___master'
  exit 1
fi

# testing trees/custom_path/
if [ "`stat -c '%U' ${WORKSPACE}/trees`" != "`stat -c '%U' ${WORKSPACE}/trees/custom_path/`" ]; then
  echo 'Ownership is not the same on ./trees and ./trees/custom_path'
  exit 1
fi
echo


################################################################################
#   Testing /gitlab with the branch defined by ${CURRENT_BRANCH}
################################################################################
current_branch=$(echo ${GIT_REF} | cut -d / -f3-)
if [ "${current_branch}" != "master" ] && [ "${current_branch}" != "develop" ]; then
  payload="${pre_branch}${current_branch}${post_branch}${closing}"
  echo "Posting this payload to /gitlab to test branch ${current_branch}:"
  echo ${payload}|jq -C .
  echo

  curl -s -H "Content-Type: application/json" -X POST -d "${payload}" http://127.0.0.1:80/gitlab
  branch_dir=`echo "tree-planter___${current_branch}" | sed 's/\//___/g'`
  branch_check=`ls -d ${WORKSPACE}/trees/${branch_dir}/ |wc -l`

  if [ $branch_check -eq 1 ];then
    echo "Successfully pulled the ${current_branch} branch"
  else
    echo "Failed to pull the ${current_branch} branch"
    exit 1
  fi
fi
