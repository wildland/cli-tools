require 'github_api'
require 'uri'
require 'highline/import'
require 'ruby-progressbar'

username = ask('Username act as: ')
password = ask('Password to use (This only exists in memory and is not stored): ') { |q| q.echo = '*' }
org = ask('Organization to work on: ') { |q| q.default = 'wildland' }
source_repo = ask('Model repo with correct labels: ') { |q| q.default = 'guides' }
verbose = false
verbose = agree("Verbose progress for all repos?")
auto_create = agree("Automatically create labels?")
auto_remove = agree("Automatically remove labels?")

total_progressbar = ProgressBar.create(
  format: 'Total %E |%bᗧ%i| %p%% %t | Processed: %c repos out of %C',
  progress_mark: ' ',
  remainder_mark: '･',
  total: nil
)

github = Github.new(login: username, password: password)
known_labels = github.issues.labels.list(user: org, repo: source_repo).map{|label| [label.name, label.color]}.to_h
known_label_names = known_labels.keys.sort

repo_names = github.repos.list(org: org).map(&:name)
repos_with_errors = Hash.new

total_progressbar.total = repo_names.count

repo_names.each do |repo_name|
  next if repo_name == source_repo
  current_label_names = github.issues.labels.list(user: org, repo: repo_name).map(&:name).sort

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
          user: org,
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
          user: org,
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
