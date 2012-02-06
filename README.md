Resque Telework
===============

[github.com/gip/resque-telework](https://github.com/gip/resque-telework)

Telework depends on Resque 1.19 and Redis 2.2

Description
-----------

Telework is a [Resque](https://github.com/defunkt/resque) plugin aimed at controlling Resque workers from the web UI. It makes it easy to manage workers on a complex systems that includes several hosts, different queue(s) and an evolving source code that is deployed several times a day. Beyond starting and stopping workers on remote hosts, the plugin makes it easy to switch between code revisions, gives a partial view of each worker's log (stdout and stderr) and maintains a status of each workers.

Telework comes with three main components

* A web interface that smoothly integrates in Resque and adds its own tab
* A daemon process to be started on each host (`rake telework:start_daemon` starts a new daemon and returns while `rake telework:daemon` runs the daemon interactively)
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

Telework requires a configuration class to be added to your app. An example class (show below and in the `config/example/telework.rb`) is included for convenience. This file should be modified to reflect your own environment. It is necessary to make sure the file is loaded at startup by Rails as Telework will instantiate the class upon startup. The simplest way to achieve this is to copy the modified `telework_config.rb` file into your app `config/initializers` directory.

The `TeleworkConfig` class allows for Telework to retrieve information regarding versioning of your source code, hostname and related data. As the example class has been developed for git and github, users of these revision control systems will potentially have to update a single line in the example file. Subversion users will have to do more work as the `TeleworkConfig` class needs to be able to retrieve revision and host information.

The `TeleworkConfig` class must implement the methods `config` and `host_config` as show below.

```ruby
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

Known Issues
------------

For version 0.0.1:

* The daemon crashes if any of the log directories do not exist


Bugs
----

Please report bugs on [github](https://github.com/gip/resque-telework/issues) or directly to [gilles.github@gmail.com](gilles.github@gmail.com)

Todo
----

The following features are are being developed and should be available shortly:

* Improved window layout
* Seamless update of workers to newer revision
* Worker history (there is currently no history for terminated workers)

The following features are planned for future releases:

* Light-weight daemon
* Starting multiple workers at once
* Worker statistics

Thanks
------

I would like to thank [RG Labs](http://www.rglabsinc.com/) for the awesome environment and support to open-source development 
