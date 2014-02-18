module Resque
  module Plugins
    module Telework
      module JobStats
        
        include Resque::Plugins::Telework::Redis

        def before_perform_stats(*args)
          unless @host
            @host= ENV['TELEWORK_HOSTNAME']
            unless @host
              require 'socket'
              @host= Socket::gethostname()
            end
          end
          puts "before_perform_stats()"
          puts "host is #{@host}"
          stats_inc( @host, @queue, 'started' )
        end

        def after_perform_stats(*args)
          puts "after_perform_stats()"
          puts "host is #{@host}"        	
          stats_inc( @host, @queue, 'ended' )	
        end

        def on_failure_stats(e, *args)
          puts "on_failure_stats()"
          puts "Exception #{e}"
          puts "host is #{@host}"        	
          stats_inc( @host, @queue, 'failed' )
        end

      end
    end
  end
end
