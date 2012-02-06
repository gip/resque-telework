namespace :telework do

  desc 'Register a new revision into Telework'
  task :register_revision => :environment do 
    cfg= find_configuration
    host= cfg[:hostname]
    cfg.delete(:hostname)
    TeleworkRedis.new.register_revision(host, cfg)
  end
  
  desc 'Start a Telework daemon on this machine and returns'
  task :start_daemon => :environment do
    host= find_configuration[:hostname]
    klass= Resque::Plugins::Telework::Manager.new(host)
    if klass.is_alive(host)
      msg= "There is already a daemon running on #{host}"
      klass.send_status( 'Error', msg)
      klass.send_status( 'Error', "This daemon (PID #{Process.pid}) cannot be started and will terminare now")
      return nil
    end
    logf= 'telework_daemon.log'
    lpid= 'telework_daemon.pid'
    pid = fork do
      File.open(logf, 'w') do |lf|
        $stdout.reopen(lf)
        $stderr.reopen(lf)
      end
      Process.setsid
      klass.start
      File.delete(lpid)
    end
    open(lpid, 'w') { |f| f.write("#{pid}\n") } if pid
  end
  
  desc 'Run the Telework daemon'
  task :daemon => :environment do
    Resque::Plugins::Telework::Manager.new(find_configuration[:hostname]).start
  end

  def find_configuration
    # Configuration is done through a TeleworkConfig class - please read the doc!
    begin
      cfg= TeleworkConfig.new.config
    rescue NameError => e
      puts e.message
      raise "It is likely that the TeleworkConfig class couldn't be found (it should have been added to your app)"
    end
    cfg
  end
  
end
