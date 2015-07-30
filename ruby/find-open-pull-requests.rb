require 'github_api'
require 'uri'
require 'highline/import'
require 'ruby-progressbar'
require 'launchy'

username = ask('Username act as: ')
password = ask('Password to use (This only exists in memory and is not stored): ') { |q| q.echo = '*' }
org = ask('Organization/User to work on: ') { |q| q.default = 'wildland' }

total_progressbar = ProgressBar.create(
  format: 'Total %E |%bᗧ%i| %p%% %t | Processed: %c repos out of %C',
  progress_mark: ' ',
  remainder_mark: '･',
  total: nil
)

github = Github.new(login: username, password: password)

repo_names = github.repos.list(org: org).map(&:name)
repos_with_pull_requests = Hash.new

total_progressbar.total = repo_names.count

open_pull_request_count = 0
open_pull_request_repo_count = 0

repo_names.each do |repo_name|
  current_pull_requests = github.pull_requests.list(user: org, repo: repo_name)

  total_progressbar.increment

  repos_with_pull_requests[repo_name] = [] unless current_pull_requests.has_key?(repo_name)

  open_pull_request_count += current_pull_requests.count
  open_pull_request_repo_count += 1 unless current_pull_requests.empty?

  current_pull_requests.each do |pull_request|
    repos_with_pull_requests[repo_name] << {
      github_author: pull_request.user,
      title: pull_request.title,
      body: pull_request.body,
      html_url: pull_request.html_url
    }
  end
end

say("Summary: #{open_pull_request_count} open pull request(s) across #{open_pull_request_repo_count} repositories")

if agree('View pull request details?')
  repos_with_pull_requests.each do |repo_name, pull_requests|
    next if pull_requests.empty?
    say("#{repo_name} has #{pull_requests.count} open pull requests:")
    pull_requests.each do |request|
      say("Pull Request: \"#{request[:title]}\" by #{request[:github_author].login}")
    end
    if agree("Open them in all in your browser?")
      pull_requests.each do |pull_request|
        uri = pull_request[:html_url]
        Launchy.open( uri ) do |exception|
          say("Attempted to open #{uri} and failed because #{exception}")
        end
      end
    end
  end
end
