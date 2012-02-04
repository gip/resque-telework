namespace :telework do

  desc 'Register the current app into telework'
  task :register => :environment do
    TeleworkRedis.new.register_my_revision
  end
  
  desc 'Start the Telework manager'
  task :run_manager => :environment do
    Resque::Plugins::Telework::Manager.new.start
  end

end