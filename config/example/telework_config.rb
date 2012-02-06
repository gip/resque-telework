# Configuration class for the resque-telework plugin

# This is an example file that works with git and github
# You may copy this file to your Rails config/initializers directory
#   and make changes to the TeleworkConfig class to reflect your environment

# Note that this implementation is using git commands under the hood
# Another way would be to have the deployement script generate a configuration
#   file (in JSON for instance) and have the TeleworkConfig class load it


# Example Teleconfig class, change it to reflect you environment
# This class should have two methods: config and host_config
#
class TeleworkConfig

  def git_repo
    "https://github.com/john/reputedly"       # <<< Change this line to point to your own github repo
  end
  
  def log_path
    "#{Rails.root.to_s}/log"                  # <<< Change this to set a different path to worker log files
  end
  
  def daemon_log_path
    "#{Rails.root.to_s}/daemon_log"           # <<< Change this to set a path to daemon log files
  end
  
  def daemon_pooling_interval
    2                                         # <<< Change this to set a new daemon pooling interval (in seconds)
  end  
  
  # Config method, works well for git
  def config
    revision= `git rev-parse HEAD`.chomp    
    { :revision => revision,
      :revision_small => revision[0..6],
      :revision_path => Rails.root.to_s,
      :revision_link => "#{git_repo}/commit/#{revision}",
      :revision_branch => ( $1 if /\* (\S+)\s/.match(`git branch`) ),
      :revision_date => Time.parse(`git show --format=format:"%aD" | head -n1`),
      :revision_deployement_date => Time.now,
      :revision_info => `git log -1` }.merge(host_config)
  end
  
  def host_config
    { :hostname => find_hostname,
      :daemon_pooling_interval => daemon_pooling_interval,
      :daemon_log_path => daemon_log_path }
  end
  
  def find_hostname
    # To find the hostname, we successively looks into
    #  1) the environement variable TELEWORK_HOSTNAME
    #  2) we get it through a Socket call
    host= ENV['TELEWORK_HOSTNAME']
    unless host
      require 'socket'
      host= Socket::gethostname()
    end
    raise "Could not find hostname.. exiting" unless host
    host
  end

end

