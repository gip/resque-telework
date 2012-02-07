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
      daemon.start        # Start the daemon
      File.delete(lpid)   # Delete the pid file
    end
    
    open(lpid, 'w') { |f| f.write("#{pid}\n") } if pid  # Create the pid file
    
  end
  
  desc 'Run the Telework daemon'
  task :daemon => :environment do
    Resque::Plugins::Telework::Manager.new(get_config).start
  end
  
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
