#!/bin/bash

echo 'Creating config.json for testing'
printf "{ \"base_dir\": \"${TRAVIS_BUILD_DIR}/trees\" }" > ${TRAVIS_BUILD_DIR}/config.json

echo 'Testing app code outside of Docker...'
bundle exec rake test || exit 1
bundle exec rake rubocop || exit 1
