namespace :telework do

  desc 'Register a new revision into Telework'
  task :register_revision => :environment do     
    cfg= get_config
    host= cfg['hostname']
    cfg.delete('hostname')
    TeleworkRedis.new.register_revision(host, cfg)
  end
  
  desc 'Start a Telework daemon on this machine and returns'
  task :start_daemon => :environment do
    cfg= get_config
    host= cfg['hostname']
    daemon= Resque::Plugins::Telework::Manager.new(cfg)
    if daemon.is_alive(host)
      msg= "There is already a daemon running on #{host}"
      daemon.send_status( 'Error', msg)
      daemon.send_status( 'Error', "This daemon (PID #{Process.pid}) cannot be started and will terminare now")
      return nil
    end
    logp= cfg['daemon_log_path']
    logp||= "."
    logf= "#{logp}/telework_daemon.log"
    lpid= "#{logp}/telework_daemon.pid"
    
    # Forking
    pid = fork do
      File.open(logf, 'w') do |lf|
        $stdout.reopen(lf)
        $stderr.reopen(lf)
      end
      Process.setsid      # I'm grown up now
      
      # New Redis connection after fork
      ns = Resque.redis.namespace
      redis_host = Resque.redis.client.host
      redis_port = Resque.redis.client.port
      Resque.redis = Redis.new(:host => redis_host, :port => redis_port)
      Resque.redis.namespace = ns

      daemon.start        # Start the daemon
      File.delete(lpid)   # Delete the pid file
    end
    open(lpid, 'w') { |f| f.write("#{pid}\n") } if pid  # Create the pid file
    
  end
  
  desc 'Run the Telework daemon'
  task :daemon => :environment do
    Resque::Plugins::Telework::Manager.new(get_config).start
  end
  
  desc 'Register the local git installation'
  task :local_config_from_git => :environment do
    begin
      rev_date= Time.parse(`git show --format=format:"%aD"`)
    rescue
      rev_date= nil
    end
    github_repo= "https://github.com/john/reputedly"
    latest_revision= `git rev-parse HEAD`.chomp
    cfg= { :hostname => find_hostname,
           :revision => latest_revision,
           :revision_small => latest_revision[0..6],
           :revision_type => 'Rails:Resque',
           :revision_path => pwd,
           :revision_link => "#{github_repo}/commit/#{latest_revision}",
           :revision_branch => ( $1 if /\* (\S+)\s/.match(`git branch`) ),
           :revision_date => rev_date,
           :revision_deployement_date => Time.now,
           :revision_info => `git log -1`,
           :revision_log_path => "#{pwd}/log",
           :daemon_pooling_interval => 2,
           :daemon_log_path => pwd }  
    # Create the config file
    require 'json'
    open("telework.conf", 'w') { |f| f.write(cfg.to_json) } 
  end
  
  # Helper functions
  def get_config
    ch= { 'hostname' => find_hostname }
    # TELEWORK_CONFIG_FILE
    fn= ENV['TELEWORK_CONFIG_FILE']
    # Local config file
    fn||= "telework.conf" if File.exist?("telework.conf")
    fn||= "telework_config.log" if File.exist?("telework_config.log")  # Legacy, this will be removed
    raise "Could not find Telework configuration file.. exiting" unless fn
    ActiveSupport::JSON.decode(open(fn, "r").read).merge(ch)
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
