# Load required file

require 'resque'
require 'resque/server'

require 'resque-telework/redis'
require 'resque-telework/server'
require 'resque-telework/global'
require 'resque-telework/manager'
require 'resque-telework/railtie' if defined?(Rails)
