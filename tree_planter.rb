# frozen_string_literal: false

require 'json'
require 'logger'
require 'open3'
require 'prometheus/client'
require 'sinatra/base'
require 'pony'

# This is my Sinatra app for planting trees
class TreePlanter < Sinatra::Base
  set :logging, true

  config_obj = JSON.parse(File.read("#{Dir.pwd}/config.json"))
  prometheus = Prometheus::Client.registry
  tree_deploy_counter = Prometheus::Client::Counter.new(
    :tree_deploys,
    docstring: 'A count of how many times each variation of each tree has been deployed',
    labels: %i[
      tree_name
      branch_name
      repo_path
      endpoint
    ]
  )
  prometheus.register(tree_deploy_counter)

  get '/' do
    "<h1>Tree Planter</h1>
     <h2>To use this tool you need to send a post to one of the following:</h2>
     <ul>
       <li>#{request.url}deploy</li>
       <li>#{request.url}gitlab</li>
       <li>#{request.url}hook-test</li>
     </ul>
     <h2>Metrics</h2>
     <p>Prometheus metrics are available via
       <a href='#{request.url}metrics'>#{request.url}metrics</a>
     <p>"
  end

  # Deploys a repository using the default branch
  post '/deploy' do
    payload = JSON.parse(request.body.read)
    logger.info("json payload: #{payload.inspect}")

    endpoint = 'deploy'

    if payload.key?('tree_name')
      tree_name   = payload['tree_name']
      branch_name = ''
      repo_url    = payload['repo_url']
      if payload.key?('repo_path')
        repo_path = payload['repo_path']
      else
        repo_path = tree_name
      end

      logger.info("endpoint  = #{endpoint}")
      logger.info("tree name = #{tree_name}")
      logger.info("repo url  = #{repo_url}")
      logger.info("repo path = #{repo_path}")
    else
      # rubocop:disable Layout/SpaceAroundOperators
      tree_name    = (payload['repository']['url'].split('/')[-1]).split('.')[0]
      branch_name  = payload['ref'].split('/').drop(2).join('___')
      repo_url     = payload['repository']['url']
      if payload.key?('repo_path')
        repo_path  = payload['repo_path']
      else
        repo_path  = tree_name
      end
      # rubocop:enable Layout/SpaceAroundOperators

      logger.info("endpoint     = #{endpoint}")
      logger.info("tree name    = #{tree_name}")
      logger.info("repo url     = #{repo_url}")
      logger.info("repo path    = #{repo_path}")
      logger.info("branch name  = #{branch_name}")
    end

    logger.info('')
    deploy_tree(endpoint, tree_name, branch_name, repo_url, repo_path, config_obj, tree_deploy_counter)
  end

  # Parses the payload from GitLab and deploys a specific branch of a repository
  post '/gitlab' do
    payload = JSON.parse(request.body.read)
    logger.info("json payload: #{payload.inspect}")

    # Determine event type
    case payload['ref'].split('/')[1]
    when 'heads'
      # rubocop:disable Layout/SpaceAroundOperators
      endpoint     = 'gitlab'
      tree_name    = (payload['repository']['url'].split('/')[-1]).split('.')[0]
      branch_name  = payload['ref'].split('/').drop(2).join('/')
      repo_name    = payload['repository']['name']
      if payload.key?('repo_path')
        repo_path  = payload['repo_path']
      else
        repo_path  = "#{tree_name}___#{payload['ref'].split('/').drop(2).join('___')}"

      end
      repo_url     = payload['repository']['url']
      checkout_sha = payload['checkout_sha']
      after        = payload['after']
      # rubocop:enable Layout/SpaceAroundOperators

      logger.info("repo name    = #{repo_name}")
      logger.info("repo url     = #{repo_url}")
      logger.info("repo path    = #{repo_path}")
      logger.info("branch name  = #{branch_name}")
      logger.info("checkout sha = #{checkout_sha}")
      logger.info("after sha    = #{after}")
      logger.info('')
      if checkout_sha.eql?('0000000000000000000000000000000000000000') # old GitLab JSON Payload
        delete_branch(endpoint, repo_path, config_obj)
      elsif after.eql?('0000000000000000000000000000000000000000') && checkout_sha.nil? # newer GitLab JSON Payload
        delete_branch(endpoint, repo_path, config_obj)
      else
        deploy_tree(endpoint, tree_name, branch_name, repo_url, repo_path, config_obj, tree_deploy_counter)
      end

    when 'tags'
      tag_name = payload['ref'].split('/')[2]
      logger.info("tag = #{tag_name}")
    end
  end

  # Simply prints the
  post '/hook-test' do
    payload = JSON.parse(request.body.read)

    logger.info('JSON Payload:')
    logger.info("json payload: #{payload.inspect}")
    logger.info('')
    logger.info('request.env:')
    logger.info(JSON.pretty_generate(request.env))
  end

  # rubocop:disable Metrics/AbcSize
  def delete_branch(endpoint, repo_path, config_obj)
    base = config_obj['base_dir']
    repo = "#{base}/#{repo_path}"
    body_content = ''
    body_content << "endpoint:    #{endpoint}\n"
    body_content << "repo_path:   #{repo_path}\n"
    body_content << "base:        #{base}\n"
    body_content << "repo:        #{repo_path}\n"
    body_content << "base exists: #{Dir.exist?(base)}\n"
    body_content << "repo exists: #{Dir.exist?(repo)}\n"
    body_content << "\n"

    if Dir.exist?(base) && Dir.exist?("#{base}/#{repo_path}")
      body_content << "Attempting to remove '#{repo_path}' from inside '#{base}'\n"
      logger.info("Attempting to remove '#{repo_path}' from inside '#{base}'")

      begin
        Dir.chdir(base)
        # rubocop:disable Lint/UselessAssignment
        FileUtils.remove_entry_secure(repo_path, force = false)
        # rubocop:enable Lint/UselessAssignment
      rescue => e
        logger.info('This exception was thrown:')
        logger.error(e)
        body_content << "This exception was thrown:\n"
        body_content << e.message
        body_content << "\n"
        status 500
      end

      if Dir.exist?("#{base}/#{repo_path}")
        msg = "Something didn't go right... #{base}/#{repo_path} still exists."
        logger.error(msg)
        body_content << "#{msg}\n"
        status 500
      else
        msg = "#{base}/#{repo_path} was successfully deleted."
        logger.info(msg)
        body_content << "#{msg}\n"
      end
    else
      # rubocop:disable Layout/LineLength
      msg = 'Unable to delete branch. Either the delete failed or it does not exist locally. Additional info, if avilable, is below:'
      # rubocop:enable Layout/LineLength
      logger.error(msg)
      body_content << msg
      body_content << "\n"

      logger.error("Base: #{base}")
      logger.error("Repo: #{repo_path}")
      logger.error("Base Exists: #{Dir.exist?(base)}")
      logger.error("Repo Exists: #{Dir.exist?(repo)}")

      status 500
    end

    body body_content
  end
  # rubocop:enable Metrics/AbcSize

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/ParameterLists, Metrics/PerceivedComplexity
  def deploy_tree(endpoint, tree_name, branch_name, repo_url, repo_path, config_obj, tree_deploy_counter)
    # rubocop:enable Metrics/ParameterLists
    base = config_obj['base_dir']
    email_body = ''

    stream do |body_content|
      body_content << "endpoint:  #{endpoint}\n"
      body_content << "tree:      #{tree_name}\n"
      body_content << "branch:    #{branch_name}\n"
      body_content << "repo_url:  #{repo_url}\n"
      body_content << "repo_path: #{repo_path}\n"
      body_content << "base:      #{base}\n"
      body_content << "\n"

      logger.info("endpoint:    #{endpoint}")
      logger.info("tree:        #{tree_name}")
      logger.info("branch:      #{branch_name}")
      logger.info("repo_url:    #{repo_url}")
      logger.info("repo_path:   #{repo_path}")
      logger.info("base:        #{base}")

      if Dir.exist?(base)
        Dir.chdir(base)

        if !repo_path.nil?
          repo_exists = Dir.exist?("./#{repo_path}")
        else
          repo_exists = nil
          abort('No repo path was set.')
        end

        if repo_exists
          Dir.chdir(repo_path)
          deploy_command = 'git pull'
        elsif branch_name.eql? ''
          deploy_command = "git clone #{repo_url} #{repo_path}"
        else
          deploy_command = "git clone -b #{branch_name} --single-branch #{repo_url} #{repo_path}"

        end

        body_content << "Running #{deploy_command}\n"
        logger.info("Running #{deploy_command}")

        Open3.popen2e(deploy_command) do |_stdin, stdout_err, wait_thr|
          # rubocop:disable Lint/AssignmentInCondition
          email_body << "endpoint:  #{endpoint}\n"
          email_body << "tree:      #{tree_name}\n"
          email_body << "branch:    #{branch_name}\n"
          email_body << "repo_url:  #{repo_url}\n"
          email_body << "repo_path: #{repo_path}\n"
          email_body << "base:      #{base}\n\n"
          email_body << "Deploy command: #{deploy_command}\n\n"
          while line = stdout_err.gets
            body_content << line
            email_body << line
            logger.info(line)
          end
          # rubocop:enable Lint/AssignmentInCondition

          exit_status = wait_thr.value
          if exit_status.success?
            status 200
            # body body_content
          else
            status 500
            # body body_content
            pony_email_options = config_obj['pony_email_options']
            pony_email_defaults = { body: email_body.to_s, subject: 'Tree Planter Deployment Problem' }
            email_reseults(pony_email_options, pony_email_defaults) if config_obj['send_email_on_failure']
          end
        end # end Open3

        tree_deploy_counter.increment(labels: {
                                        tree_name: tree_name,
                                        branch_name: branch_name,
                                        repo_path: repo_path,
                                        endpoint: endpoint
                                      })
      else
        status 500
        msg = "#{base} cannot be found"
        body_content << "#{msg}\n"
        logger.info(msg)
      end
    end
  end
  # rubocop:enable Metrics/AbcSize
  # rubocop:enable Metrics/CyclomaticComplexity
  # rubocop:enable Metrics/PerceivedComplexity

  private

  def email_reseults(pony_email_options, pony_email_defaults)
    pony_email_options_merged = pony_email_defaults.merge(symbolize(pony_email_options))
    Pony.mail(pony_email_options_merged)
  end

  def symbolize(obj)
    if obj.is_a? Hash
      return obj.reduce({}) do |item, (key, value)|
        item.tap do |i|
          i[key.to_sym] = symbolize(value)
        end
      end
    end

    if obj.is_a? Array
      return obj.each_with_object([]) do |item, value|
        item << symbolize(value)
        item
      end
    end

    obj
  end
end
