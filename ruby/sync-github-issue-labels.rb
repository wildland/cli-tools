#!/usr/bin/env ruby

require 'github_api'
require 'uri'
require 'highline/import'
require 'ruby-progressbar'

username = ask('Username act as: ')
password = ask('Password to use (This only exists in memory and is not stored): ') { |q| q.echo = '*' }
github_user = nil
org = nil
choose do |menu|
  menu.prompt = "Act on an organization or user?"
  menu.choice(:user) { github_user = ask('Username: ') { |q| q.default = username } }
  menu.choices(:organization) { org = ask('Organization: ') { |q| q.default = 'wildland' } }
end
org_or_github_user = github_user.nil? ? org : github_user

source_repo = ask('Model repo with correct labels: ') { |q| q.default = 'guides' }
verbose = false
verbose = agree("Verbose progress for all repos?")
auto_create = agree("Automatically create labels?")
auto_remove = agree("Automatically remove labels?")

github = Github.new(auto_pagination: true) do |config|
  config.basic_auth         = "#{username}:#{password}"
  if agree("Do you use Two-Factor authentication?")
    config.connection_options = { headers: {"X-GitHub-OTP" => ask('Two-Factor Code')} }
  end
end

total_progressbar = ProgressBar.create(
  format: 'Total %E |%bᗧ%i| %p%% %t | Processed: %c repos out of %C',
  progress_mark: ' ',
  remainder_mark: '･',
  total: nil
)

known_labels = github.issues.labels.list(user: org_or_github_user, repo: source_repo).map{|label| [label.name, label.color]}.to_h
known_label_names = known_labels.keys.sort

if github_user.nil?
  repo_names = github.repos.list(org: org).map(&:name)
else
  repo_names = github.repos.list(user: github_user).map(&:name)
end

repos_with_errors = Hash.new

total_progressbar.total = repo_names.count

repo_names.each do |repo_name|
  next if repo_name == source_repo
  current_label_names = github.issues.labels.list(user: org_or_github_user, repo: repo_name).map(&:name).sort

  if verbose
    repo_bar = ProgressBar.create(
      format: "#{repo_name} %E |%bᗧ%i| %p%% %t",
      progress_mark: ' ',
      remainder_mark: '･',
      total: nil
    )
  else
    total_progressbar.increment
  end

  labels_to_add = known_label_names - current_label_names
  labels_to_remove = current_label_names - known_label_names

  if verbose
    repo_bar.total = labels_to_add.count + labels_to_remove.count
  end

  labels_to_add.each do |new_label_name|
    repo_bar.increment if verbose
    begin
      if auto_create || agree("Add #{new_label_name} to #{repo_name}?")
        github.issues.labels.create(
          user: org_or_github_user,
          repo: repo_name,
          name: new_label_name,
          color: known_labels[new_label_name]
        )
      end
    rescue Exception => e
      puts e.to_s if verbose
      repos_with_errors[repo_name] = [] unless repos_with_errors.has_key?(repo_name)
      repos_with_errors[repo_name] << e.to_s
    end
  end

  labels_to_remove.each do |old_label_name|
    repo_bar.increment if verbose
    begin
      if auto_remove || agree("Remove #{old_label_name} from #{repo_name}?")
        github.issues.labels.delete(
          user: org_or_github_user,
          repo: repo_name,
          label_name: URI.escape(old_label_name)
        )
      end
    rescue Exception => e
      puts e.to_s if verbose
      repos_with_errors[repo_name] = [] unless repos_with_errors.has_key?(repo_name)
      repos_with_errors[repo_name] << e.to_s
    end
  end
end
total_progressbar.increment unless verbose

puts 'Ran into the following errors: ' if repos_with_errors.count > 0
repos_with_errors.each do |repo_name, errors_array|
  puts "#{repo_name} had the following errors: "
  errors_array.map{|e| puts "  #{e}"}
end
