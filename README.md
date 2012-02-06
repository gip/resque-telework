Resque Telework
===============

[github.com/gip/resque-telework](https://github.com/gip/resque-telework)

Telework depends on Resque 1.19 and Redis 2.2

Description
-----------

Telework is a [Resque](https://github.com/defunkt/resque) plugin allowing to control workers by selecting the host, the queue(s) and the code revision to be used to run the worker. It it possible to start and stop workers remotely as well as taking a look to the last lines of the logs.

Telework comes with three main components

* A web interface that smoothly integrates in Resque by adding it's own 'Telework' tab
* A daemon process to be started on each host (`rake telework:start_daemon` starts a new daemon and returns while `rake telework:daemon` starts the new daemon interactively)
* A registration command (`rake telework:register_revision`) to be called by the deployment script when a new revision is added on the host

Note that currently (Telework 0.0.1), the daemon process is included in the main app, which is not really elegant as the full Rails environment needs to be loaded to run the daemon. A light-weight daemon is currently being developed and should be ready in the coming weeks.

Installation
------------

Install as a gem:

```
gilles@myapphost $ gem install resque-telework
```

You may also add the following line in the Gemfile

```
gem 'resque-telework'
```

Configuration
-------------

Telework requires a configuration class to be added to your app. An example class (show below and in the `config/example/telework.rb`) is included for convenience. This file should be modified to reflect your own environment. It is necessary to make sure the file is loaded at startup by Rails as Telework will instantiate the class upon startup. The simplest way to achieve this is to copy the modified `telework.rb` file into your app `config/initializers` directory.

The `TeleworkConfig` class allows for Telework to retrieve information regarding versioning of your source code, hostname and related data. As the example class has been developed for git and github, users of these revision control systems will potentially have to update a single line in the example file. Subversion users will have to do more work as TeleworkConfig needs to be able to retrieve revision information.

```ruby
# Initializer for the resque-telework config plugin
#
# This is an example file created for git. 
# You may copy this file to your Rails config/initializers directory
#   and make changes to the TeleworkConfig class to reflect your environment
# For git users, only the git_repo variable may need to be changed
# Note that this implementation is using git commands under the hood, that is
#  not really elegant but environment variables may also be used


# Base class - feel free to extend
class TeleworkConfigBase

  def config_env
    revision= ENV['TELEWORK_REVISION']
    path= ENV['TELEWORK_REVISION_PATH']
    return nil unless revision && path
    cfg= { :hostname => find_hostname,
           :revision => revision,
           :revision_path => path,
           :revision_log_path => log_path }
    cfg[:revision_link]= ENV['TELEWORK_REVISION_LINK'] if ENV['TELEWORK_REVISION_LINK']
    cfg[:revision_small]= ENV['TELEWORK_REVISION_SMALL'] if ENV['TELEWORK_REVISION_SMALL']
    cfg[:revision_branch]= ENV['TELEWORK_REVISION_BRANCH'] if ENV['TELEWORK_REVISION_BRANCH']
    cfg[:revision_date]= ENV['TELEWORK_REVISION_DATE'] if ENV['TELEWORK_REVISION_DATE']
    cfg[:revision_deployement_date]= ENV['TELEWORK_REVISION_DATE']
    cfg[:revision_deployement_date]||= Time.now
    cfg
  end

  def config_git
    repo= git_repo
    
    revision= `git rev-parse HEAD`.chomp    
    { :hostname => find_hostname,
      :revision_log_path => log_path,
      :revision => revision,
      :revision_small => revision[0..6],
      :revision_path => Rails.root.to_s,
      :revision_link => "#{repo}/commit/#{revision}",
      :revision_branch => ( $1 if /\* (\S+)\s/.match(`git branch`) ),
      :revision_date => Time.parse(`git show --format=format:"%aD" | head -n1`),
      :revision_deployement_date => Time.now,
      :revision_info => `git log -1` }
  end
  
  def find_hostname
    # To find the hostname, we successively looks into
    #  1) the environement variable TELEWORK_HOSTNAME
    #  2) the environement variable HOSTNAME or
    #  3) we get it through a Socket call
    host= ENV['TELEWORK_HOSTNAME']
    host||= ENV['HOSTNAME']
    unless host
      require 'socket'
      host= Socket::gethostname()
    end
    raise "Could not find hostname.. exiting" unless host
    host
  end
    
end

# Example class used at RG Labs, you should change point to your git repo
class TeleworkConfig < TeleworkConfigBase

  def config
    cfg= config_env
    cfg||= config_git
    cfg
  end

  def git_repo
    "https://github.com/john/reputedly"  # <<< Change this line to point to your own git repo
  end
  
  def log_path
    "#{Rails.root.to_s}/log"
  end

end
```

Workflow
--------

After Telework is installed and the TeleworkConfig class implemented according to your environment, the code is deployed to all the relevant hosts. If you're using [Capistrano](https://github.com/capistrano/capistrano) it may look like:

```
gilles@myapphost $ cap deploy -S servers=myapphost,myworkhost0,myworkhost1,myworkhost2
```

The code is therefore deployed to the main app box (`myapphost`) and all the other 'worker' hosts. On each of these hosts, it is now necessary to register the new revision with Telework and start the Telework daemon. For instance on host0, this is done using the following commands:

```
gilles@myworkhost0 $ rake telework:register_revision
gilles@myworkhost0 $ rake telework:start_daemon
```

The main Telework tab should now show the new box as alive. It is now possible to start new workers on these boxes using the new web-based UI, saving a lot of ssh/screen commands.

Going forward, when a new version of the app is deployed on host, it is necessary to register the new revision using the following command:

```
gilles@myworkhost0 $ rake telework:register_revision
```
Note that it is not necessary to stop and restart the daemon. Restarting the daemon should only happens when the Telework gem is updated.

Bugs
----

Please report bugs on [github](https://github.com/gip/resque-telework/issues) or directly to [gilles.github@gmail.com](gilles.github@gmail.com)

Todo
----

The following features are planned in coming versions

* Starting multiple workers at once
* Worker history (there is currently no history for terminated workers)
* Statistics
* Light-weight daemon (in Ruby and Haskell)

Thanks
------

I would like to thanks [RG Labs](http://www.rglabsinc.com/) for the awesome environment and support to open-source development 
