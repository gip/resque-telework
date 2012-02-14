module Resque
  module Plugins
    module Telework      
      class Manager
        
        include Resque::Plugins::Telework::Redis
        
        def initialize(cfg)
          @RUN_DAEMON= true
          @HOST= cfg['hostname']
          @SLEEP= cfg['daemon_pooling_interval']
          @WORKERS= {}
          @STOPPED= []
        end
        
        # The manager (e.g. daemon) main loop
        def start
          send_status( 'Info', "Daemon (PID #{Process.pid}) starting on host #{@HOST}" )
          unless check_redis # Check the Redis interface version
           err= "Telework: Error: Redis interface version mismatch, exiting"
           puts err # We can't use send_status() as it relies on Redis so we just show a message
           raise err
          end
          if is_alive(@HOST)  # Only one deamon can be run on a given host at the moment (this may change)
            send_status( 'Error', "There is already a daemon running on #{@HOST}")
            send_status( 'Error', "This daemon (PID #{Process.pid}) cannot be started and will terminare now")
            exit
          end
          loop do                                # The main loop
            while @RUN_DAEMON do                 # If there is no request to stop
              i_am_alive(health_info)            # Notify the system that the daemon is alive
              check_processes                    # Check the status of the child processes (to catch zombies)
              while cmd= cmds_pop( @HOST ) do    # Pop a command in the command queue
                do_command(cmd)                  # Execute it
              end
              sleep @SLEEP                       # Sleep
            end
                                                 # A stop request has been received
            send_status( 'Info', "A stop request has been received and the #{@HOST} daemon will now terminate") if @WORKERS.empty?
            break if @WORKERS.empty?
            send_status( 'Error', "A stop request has been received by the #{@HOST} daemon but there are still running worker(s) so it will keep running") unless @WORKERS.empty?
            @RUN_DAEMON= true
          end
        rescue Interrupt         # Control-C
          send_status( 'Info', "Interruption for #{@HOST} daemon, exiting gracefully") if @WORKERS.empty?
          send_status( 'Error', "Interruption for #{@HOST} daemon, exiting, running workers may now unexpectedly terminate") unless @WORKERS.empty?
        rescue SystemExit        # Exit has been called
          send_status( 'Info', "Exit called in #{@HOST} daemon") if @WORKERS.empty?
          send_status( 'Error', "Exit called in #{@HOST} daemon but workers are still running") unless @WORKERS.empty?
        rescue Exception => e    # Other exceptions
          send_status( 'Error', "Exception #{e.message}")
          puts "Backtrace: #{e.backtrace}"
          send_status( 'Error', "Exception should not be raised in the #{@HOST} daemon, please submit a bug report")
        end
        
        # Health info
        def health_info
          require "sys/cpu"
          load= Sys::CPU.load_avg
          { :cpu_load_1mins => load[0],
            :cpu_load_5mins => load[1],
            :cpu_load_15mins => load[2] }
        rescue
          {}
        end
        
        # Add a status message on the status queue
        def send_status( severity, message )
          puts "Telework: #{severity}: #{message}"
          info= { 'host'=> @HOST, 'severity' => severity, 'message'=> message,
                  'date'=> Time.now }
          status_push(info)
        end
        
        # Execute a command synchronously
        def do_command( cmd )
          case cmd['command']
          when 'start_worker'
            start_worker( cmd, find_revision(cmd['revision']) )
          when 'stop_worker'
            stop_worker( cmd )
          when 'kill_worker'
            stop_worker( cmd, true )
          when 'stop_daemon'
            @RUN_DAEMON= false
          when 'kill_daemon'
            send_status( 'Error', "A kill request has been received, the daemon on #{@HOST} is now brutally terminating by calling exit()")
            exit # Bye
          else
            send_status( 'Error', "Unknown command '#{cmd['command']}'" )
          end
        end
        
        # Start a task
        def start_worker( cmd, rev_info )
          # Retrieving args
          path= rev_info['revision_path']
          log_path= rev_info['revision_log_path']
          log_path||= "."
          rev= rev_info['revision']
          id= cmd['worker_id']
          queuel= cmd['worker_queue'].gsub(/,/, '_').gsub(/\*/, '(star)')
          # Starting the job
          env= { "QUEUE"=> cmd['worker_queue'] }
          env["RAILS_ENV"]= cmd['rails_env'] if "(default)" != cmd['rails_env']
          opt= { :in => "/dev/null", 
                 :out => "#{log_path}/telework_#{id}_#{queuel}_stdout.log", 
                 :err => "#{log_path}/telework_#{id}_#{queuel}_stderr.log", 
                 :chdir => path }
          exec= cmd['exec']
          pid= spawn( env, exec, opt) # Start it!
          info= { 'pid' => pid, 'status' => 'running', 'environment' => env, 'options' => opt, 'revision_info' => rev_info }
          # Log snapshot
          info['log_snapshot_period']= cmd['log_snapshot_period'] if cmd['log_snapshot_period']
          info['log_snapshort_lines']= cmd['log_snapshot_lines'] if cmd['log_snapshot_lines']
          @WORKERS[id]= info
          workers_add( @HOST, id, info )
          send_status( 'Info', "Starting worker #{id} (PID #{pid})" )
          # Create an helper file
          intro = "# Telework: starting worker #{id} on host #{@HOST} at #{Time.now.strftime("%a %b %e %R %Y")}"
          env.keys.each { |v| intro+= "\n# Telework: environment variable '#{v}' set to '#{env[v]}'" }
          intro+= "\n# Telework: command line is: #{exec}"
          intro+= "\n# Telework: path is: #{path}"
          intro+= "\n# Telework: log file for stdout is: #{opt[:out]}"
          intro+= "\n# Telework: log file for stderr is: #{opt[:err]}"
          intro+= "\n# Telework: PID is: #{pid}"
          intro+= "\n"
          File.open("#{log_path}/telework_#{id}.log", 'w') { |f| f.write(intro) }
        end

        def stop_worker ( cmd, kill=false )
          id= cmd['worker_id']
          info= @WORKERS[id]
          send_status( 'Error', "Worker #{id} was not found on this host" ) unless info
          return unless info
          sig= kill ? "KILL" : "QUIT"
          send_status( 'Info', "Stopping worker #{id} (PID #{info['pid']}) using signal #{sig}" )
          Process.kill( sig, info['pid'] )
          @STOPPED << id
          info['status']= kill ? 'killed' : 'exiting'
          workers_add( @HOST, id, info )
          @WORKERS[id]= info
        end
                
        def check_processes
          workers_delall( @HOST )
          @WORKERS.keys.each do |id|
            remove= false
            unexpected_death= false
            begin # Zombie hunt..
              res= Process.waitpid(@WORKERS[id]['pid'], Process::WNOHANG)
              remove= true if res 
            rescue # Not a child.. so the process is already dead (we don't know why, maybe someone did a kill -9)
              unexpected_death= true
              remove= true
            end
            if remove
              if unexpected_death
                send_status( 'Error', "Worker #{id} (PID #{@WORKERS[id]['pid']}) has unexpectedly ended" )
              else
                send_status( 'Info', "Worker #{id} (PID #{@WORKERS[id]['pid']}) has exited" ) if @STOPPED.index(id)
                send_status( 'Error', "Worker #{id} (PID #{@WORKERS[id]['pid']}) has unexpectedly exited" ) unless @STOPPED.index(id)
                @STOPPED.delete(id)
              end
              @WORKERS.delete(id)
            else
              update_log_snapshot(id)
              workers_add( @HOST, id, @WORKERS[id] )
            end
                        
          end
        end
        
        def update_log_snapshot( id )
          ls= @WORKERS[id]['log_snapshot_period']
          return unless ls
          last= @WORKERS[id]['last_log_snapshot']
          last||= 0
          now= Time.now.to_i
          if now >= last+ls
            size= @WORKERS[id]['log_snapshot_lines']
            size||= 20
            # Getting the logs
            logerr= get_tail( @WORKERS[id]['options'][:err], size )
            logout= get_tail( @WORKERS[id]['options'][:out], size )
            # Write back
            info= { :date => Time.now, :log_stderr => logerr, :log_stdout => logout }
            logs_add( @HOST, id, info )
            @WORKERS[id]['last_log_snapshot']= now
          end 
        end
        
        def get_tail( f, size )
          `tail -n #{size} #{f}`
        end
      
      end
    end
  end
end
