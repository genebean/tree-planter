ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'minitest/reporters'
require 'rack/test'
require_relative '../tree_planter'

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

class TreePlanterTest < MiniTest::Test
  include Rack::Test::Methods

  def app
    TreePlanter
  end

  def test_get_home
    get '/'
    assert last_response.ok?
    assert last_response.body.include?('To use this tool you need to send a post to one of the following')
  end

  def test_post_deploy
    payload = '{"ref":"refs/heads/master", "checkout_sha":"some_commit_sha", "repository":{"name":"tree-planter", "url":"https://github.com/genebean/tree-planter.git" }}'
    header 'Content-Type', 'application/json'
    post '/deploy', payload, 'CONTENT_TYPE' => 'application/json'
    assert last_response.ok?
    assert last_response.body.include?('repo_path: tree-planter')
  end

  def test_post_gitlab_master
    payload = '{"ref":"refs/heads/master", "checkout_sha":"some_commit_sha", "repository":{"name":"tree-planter", "url":"https://github.com/genebean/tree-planter.git" }}'
    header 'Content-Type', 'application/json'
    post '/gitlab', payload, 'CONTENT_TYPE' => 'application/json'
    assert last_response.ok?
    assert last_response.body.include?('repo_path: tree-planter___master')
  end

  def test_post_gitlab_delete
    payload = '{"ref":"refs/heads/master", "checkout_sha":"0000000000000000000000000000000000000000", "repository":{"name":"tree-planter", "url":"https://github.com/genebean/tree-planter.git" }}'
    header 'Content-Type', 'application/json'
    post '/gitlab', payload, 'CONTENT_TYPE' => 'application/json'
    assert last_response.body.include?('base exists: true')
    assert last_response.body.include?('repo exists: ')
  end

  def test_post_hook_test
    payload = '{"ref":"refs/heads/master", "checkout_sha":"some_commit_sha", "repository":{"name":"tree-planter", "url":"https://github.com/genebean/tree-planter.git" }}'
    header 'Content-Type', 'application/json'
    post '/hook-test', payload
    assert last_response.ok?
  end
end
