namespace :telework do

  desc 'Register a new revision into Telework'
  task :register_revision => :environment do 
    check_configuration    
    cfg= TeleworkConfig.new.config
    host= cfg[:hostname]
    cfg.delete(:hostname)
    TeleworkRedis.new.register_revision(host, cfg)
  end
  
  desc 'Start a Telework daemon on this machine and returns'
  task :start_daemon => :environment do
    check_configuration
    cfg= TeleworkConfig.new.host_config
    host= cfg[:hostname]
    daemon= Resque::Plugins::Telework::Manager.new(cfg)
    if daemon.is_alive(host)
      msg= "There is already a daemon running on #{host}"
      daemon.send_status( 'Error', msg)
      daemon.send_status( 'Error', "This daemon (PID #{Process.pid}) cannot be started and will terminare now")
      return nil
    end
    logp= cfg[:daemon_log_path]
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
      daemon.start        # Start the daemon
      File.delete(lpid)   # Delete the pid file
    end
    
    open(lpid, 'w') { |f| f.write("#{pid}\n") } if pid  # Create the pid file
    
  end
  
  desc 'Run the Telework daemon'
  task :daemon => :environment do
    check_configuration
    Resque::Plugins::Telework::Manager.new(find_configuration).start
  end

  def check_configuration
    klass = Module.const_get('TeleworkConfig')
    unless klass.is_a?(Class)
      msg= "Telework: Error: It is likely that the TeleworkConfig class couldn't be found (it should have been added to your app)"
      puts msg
      raise msg
    end
  end
  
end
