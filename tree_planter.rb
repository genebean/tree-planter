require 'json'
require 'logger'
require 'open3'
require 'sinatra/base'

# This is my Sinatra app for planting trees
class TreePlanter < Sinatra::Base
  set :logging, true

  config_obj = JSON.parse(File.read(Dir.pwd + '/config.json'))

  get '/' do
    "<h1>Tree Planter</h1>
     <h2>To use this tool you need to send a post to one of the following:</h2>
     <ul>
       <li>#{request.url}deploy</li>
       <li>#{request.url}gitlab</li>
       <li>#{request.url}hook-test</li>
     </ul>"
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
      tree_name    = (payload['repository']['url'].split('/')[-1]).split('.')[0]
      branch_name  = payload['ref'].split('/').drop(2).join('___')
      repo_url     = payload['repository']['url']
      if payload.key?('repo_path')
        repo_path  = payload['repo_path']
      else
        repo_path  = tree_name
      end

      logger.info("endpoint     = #{endpoint}")
      logger.info("tree name    = #{tree_name}")
      logger.info("repo url     = #{repo_url}")
      logger.info("repo path    = #{repo_path}")
      logger.info("branch name  = #{branch_name}")
    end

    logger.info('')

    # rubocop:disable Metrics/LineLength
    deploy_tree(endpoint, tree_name, branch_name, repo_url, repo_path, config_obj)
    # rubocop:enable Metrics/LineLength
  end

  # Parses the payload from GitLab and deploys a specific branch of a repository
  post '/gitlab' do
    payload = JSON.parse(request.body.read)
    logger.info("json payload: #{payload.inspect}")

    # Determine event type
    if payload['ref'].split('/')[1].eql? 'heads'
      endpoint     = 'gitlab'
      tree_name    = (payload['repository']['url'].split('/')[-1]).split('.')[0]
      branch_name  = payload['ref'].split('/').drop(2).join('/')
      repo_name    = payload['repository']['name']
      if payload.key?('repo_path')
        repo_path  = payload['repo_path']
      else
        # rubocop:disable Metrics/LineLength
        repo_path  = "#{tree_name}___#{payload['ref'].split('/').drop(2).join('___')}"
        # rubocop:enable Metrics/LineLength
      end
      repo_url     = payload['repository']['url']
      checkout_sha = payload['checkout_sha']
      after        = payload['after']

      logger.info("repo name    = #{repo_name}")
      logger.info("repo url     = #{repo_url}")
      logger.info("repo path    = #{repo_path}")
      logger.info("branch name  = #{branch_name}")
      logger.info("checkout sha = #{checkout_sha}")
      logger.info("after sha    = #{after}")
      logger.info('')

      # rubocop:disable Metrics/LineLength
      if checkout_sha.eql?('0000000000000000000000000000000000000000') # old GitLab JSON Payload
        delete_branch(endpoint, repo_path, config_obj)
      elsif after.eql?('0000000000000000000000000000000000000000') && checkout_sha.nil? # newer GitLab JSON Payload
        delete_branch(endpoint, repo_path, config_obj)
      else
        deploy_tree(endpoint, tree_name, branch_name, repo_url, repo_path, config_obj)
      end
      # rubocop:enable Metrics/LineLength

    elsif payload['ref'].split('/')[1].eql? 'tags'
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
      # rubocop:disable Metrics/LineLength
      body_content << "Attempting to remove '#{repo_path}' from inside '#{base}'\n"
      logger.info("Attempting to remove '#{repo_path}' from inside '#{base}'")
      # rubocop:enable Metrics/LineLength

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
      # rubocop:disable Metrics/LineLength
      msg = 'Unable to delete branch. Either the delete failed or it does not exist locally. Additional info, if avilable, is below:'
      # rubocop:enable Metrics/LineLength
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

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/LineLength, Metrics/ParameterLists, Metrics/PerceivedComplexity
  def deploy_tree(endpoint, tree_name, branch_name, repo_url, repo_path, config_obj)
    # rubocop:enable Metrics/LineLength, Metrics/ParameterLists
    base = config_obj['base_dir']

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
          # rubocop:disable Metrics/LineLength
          deploy_command = "git clone -b #{branch_name} --single-branch #{repo_url} #{repo_path}"
          # rubocop:enable Metrics/LineLength
        end

        body_content << "Running #{deploy_command}\n"
        logger.info("Running #{deploy_command}")

        Open3.popen2e(deploy_command) do |_stdin, stdout_err, wait_thr|
          # rubocop:disable Lint/AssignmentInCondition
          while line = stdout_err.gets
            body_content << line
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
          end
        end # end Open3
      else
        status 500
        msg = "#{base} cannot be found"
        body_content << "#{msg}\n"
        logger.info(msg)
      end
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity
  # rubocop:enable Metrics/ParameterLists, Metrics/PerceivedComplexity
end
