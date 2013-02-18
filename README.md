Resque Telework
===============

[github.com/gip/resque-telework](https://github.com/gip/resque-telework)

Telework depends on Resque 1.20+ and Redis 2.2+

Telework 0.3 has a new auto feature that is in beta and currently under testing - please report bugs to [gip.github@gmail.com](gip.github@gmail.com)

Description
-----------

Telework is a [Resque](https://github.com/defunkt/resque) plugin aimed at controlling Resque workers from the web UI. It makes it easy to manage workers on a complex systems that includes several hosts, different queue(s) and an evolving source code that is deployed several times a day. Beyond starting and stopping workers on remote hosts, the plugin makes it easy to switch between code revisions, gives a partial view of each worker's log (stdout and stderr) and maintains a status of each workers. Version 0.3 adds an auto mode that is able to start workers depending on how full a given queue (or several queues) are. The workers are stopped once all the jobs are processed, allowing a better memory usage.

Telework comes with three main components

* A web interface that smoothly integrates in Resque and adds its own tab
* A daemon process to be started on each host (`rake telework:start_daemon` starts a new daemon and returns while `rake telework:daemon` runs the daemon interactively)
* A registration command (`rake telework:register_revision`) to be called by the deployment script when a new revision is added on the host

Note that currently (Telework 0.3), the daemon process is included in the main app, which is not really elegant as the full Rails environment needs to be loaded to run the daemon. A light-weight daemon is currently being developed and should be ready in the coming weeks.

Telework has been successfully used in production at Entelo for more that a year with up to 10 servers.

Overview of the WebUI
---------------------

![Main Telework Window](https://github.com/gip/resque-telework/raw/master/doc/screenshots/view_overview.png)

The screenshot above shows the initial version of the Telework main window. The top table shows the active hosts, the different revision and the running workers. The bottom table shows the different status messages received from the hosts. Not that the layout is being improved and will look better soon :)

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

Some external configuration is necessary when working with Telework as the gem needs a way to retrieve information about the code revision being deployed (git hash or SVN revision number), its path, the location for log files and so on.. When Telework rake tasks start (`telework:register_revision`, `telework:start_daemon` or `telework:daemon`), it will try to open the file in the environment variable `TELEWORK_CONFIG_FILE`. If this variable doesn't exist it will try to open the `telework.conf` file in the local directory.

The configuration file should contains information about the revision being deployed in the JSON format. A simple way of achieving this is to add a task in the deployment script. For instance, if you are using [Capistrano](https://github.com/capistrano/capistrano), the new task could look like this:

```ruby
# ...

namespace :deploy do

    # ... other deployment tasks here

    # Telework registration task (example for github)
    task :telework_register do
      repo= 'john/reputedly'                                                         # <<< Change your Github repo name here 
      github_repo= "https://github.com/#{repo}"
      log_path= "#{deploy_to}/shared/worker_log"                                     # <<< Change paths to the log files here
      run "mkdir -p #{log_path}" # Making sure the log directory exists
      begin 
        require 'octokit'  # Gem to access the Github API
        client = Octokit::Client.new(:login => ACCOUNT, :password => PASSWORD )      # <<< Put your Github credentials here
        commit= client.commit(repo, latest_revision)
        rev_date= commit['commit']['committer']['date']
        rev_name= commit['commit']['committer']['name']
        rev_info= commit['commit']['message']
      rescue                                                                         # No big deal if there is a problem accessing Github, 
                                                                                     #   the info fields will just remain empty
      end
      cfg= { :revision => latest_revision,                                           # latest_revison, current_release, branch,...
             :revision_small => latest_revision[0..6],                               #   are defined by Capistrano
             :revision_path => "#{current_release}",
             :revision_link => "#{github_repo}/commit/#{latest_revision}",
             :revision_branch => branch,
             :revision_date => rev_date,
             :revision_committer => rev_name,
             :revision_deployement_date => Time.now,
             :revision_info => rev_info,
             :revision_log_path => log_path,
             :daemon_pooling_interval => 2,
             :daemon_log_path => deploy_to }
      
      # Create the config file
      require 'json' 
      put cfg.to_json, "#{deploy_to}/current/telework.conf"
      
      # Start the registration rake task
      run "cd #{deploy_to}/current && bundle exec rake telework:register_revision --trace"
    end
    after "deploy:more_symlinks", "deploy:telework_register"                          # <<< Schedule the task at the end of deployment

end
```

Workflow
--------

After Telework is installed and the `TeleworkConfig` class modified to match your environment, the code may be deployed to all the relevant hosts. If you're using [Capistrano](https://github.com/capistrano/capistrano) it may look like:

```
gilles@myapphost $ cap deploy -S servers=myapphost,myworkhost0,myworkhost1,myworkhost2
```

The code above deploys the code to the main app box (`myapphost`) and all the other 'worker' hosts. On each of these hosts, it is now necessary to register the new revision with Telework and start the Telework daemon. For instance on host0, this is done using the following commands:

```
gilles@myworkhost0 $ rake telework:register_revision
gilles@myworkhost0 $ rake telework:start_daemon
```

The main Telework tab should now show the new box as alive. It is now possible to seamlessly start new workers on these boxes using the new web-based UI.

Going forward, when a new version of the app is deployed on host, it is necessary to register the new revision using the following command:

```
gilles@myworkhost0 $ rake telework:register_revision
```
Note that it is not necessary to stop and restart the daemon. Restarting the daemon is only required when the Telework gem is updated.

Auto Mode
---------

The auto mode is still under testing as of version 0.3. Starting/stopping workers in auto mode is done by the daemon using a simple heuristic. Parameters may be modified as the task page. The main parameters controlling the auto mode are
* `Auto_delay`: this is the minimum amount of time, in second, that the daemon has to wait before to make a new change to the workers (e.g. start or stop workers). A large number prevents the overhead of stopping/starting workers too often
* `Worker_count`, `Auto_job_per_worker` and `Auto_min_worker`: these parameters control the number of workers needed to process jobs from a given queue. Given a queue with `Q` pending jobs, the number of workers started by the daemon at a given time will be:

  min( `Worker_count`, max( `Auto_min_worker`, ceil( `Q` / `Auto_job_per_worker` ) ) )

Known Issues
------------

For version 0.3:

* The daemon crashes if any of the log directories do not exist

Bugs
----

Please report bugs on [github](https://github.com/gip/resque-telework/issues) or directly to [gip.github@gmail.com](gip.github@gmail.com)

Todo
----

The following features are planned for future releases:

* Light-weight daemon in Haskell
* Worker statistics

Thanks
------

I would like to thank [Entelo](http://www.entelo.com/) for the awesome environment and support to open-source development 
