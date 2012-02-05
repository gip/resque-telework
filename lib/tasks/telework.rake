namespace :telework do

  desc 'Register a new revision into Telework'
  task :register_revision => :environment do 
    cfg= find_configuration
    host= cfg[:hostname]
    cfg.delete(:hostname)
    TeleworkRedis.new.register_revision(host, cfg)
  end
  
  desc 'Start the Telework manager'
  task :run_manager => :environment do
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
