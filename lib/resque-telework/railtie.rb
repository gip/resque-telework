require 'resque-telework'
require 'rails'

class Railtie < Rails::Railtie
  railtie_name :telework
  
  rake_tasks do
    load "tasks/telework.rake"
  end
end
  
