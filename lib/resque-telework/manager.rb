module Resque
  module Plugins
    module Telework      
      class Manager
        
        include Resque::Plugins::Telework::Redis
        
        def initialize(host)
          @HOST= host
          @SLEEP= 2
          @WORKERS= {}
          @STOPPED= []
        end
        
        def start
          send_status( 'Info', "Manager starting..." )
          unless check_redis
           err= "Telework: Error: Redis interface version mismatch - exciting"
           puts err
           raise err
          end          
          loop do
            i_am_alive
            check_processes
            while cmd= cmds_pop( @HOST ) do
              do_command(cmd)
            end
            sleep @SLEEP
          end
        rescue Interrupt
          send_status( 'Info', "Manager interrupted, exiting gracefully") if @WORKERS.empty?
          send_status( 'Error', "Manager interrupted, exiting, running workers may now unexpectedly terminate") unless @WORKERS.empty?
        rescue Exception => e
          send_status( 'Error', "Exception #{e.message}")
          send_status( 'Error', "Exception should not be thrown here, please submit a bug report")
        end
        
        def send_status( severity, message )
          puts "Telework: #{severity}: #{message}"
          info= { 'host'=> @HOST, 'severity' => severity, 'message'=> message,
                  'date'=> Time.now }
          status_push(info)
        end
        
        # cmd is a flat hash with the following: command, revision, rails_env, worker_id, worker_count, worker_queue
        def do_command( cmd )
          case cmd['command']
          when 'start_worker'
            start_worker( cmd, find_revision(cmd['revision']) )
          when 'stop_worker'
            stop_worker( cmd )
          when 'kill_worker'
            stop_worker( cmd, true )
          else
            send_status( 'Error', "Unknown command '#{cmd['command']}'" )
          end
        end
                
        def start_worker( cmd, rev_info )
          path= rev_info['revision_path']
          log_path= rev_info['revision_log_path']
          log_path||= "."
          rev= rev_info['revision']
          id= cmd['worker_id']
          # TODO: count... env= { "COUNT"=> cmd['worker_count'], "QUEUE"=> cmd['worker_queue'] }
          env= { "QUEUE"=> cmd['worker_queue'] }
          env["RAILS_ENV"]= cmd['rails_env'] if "(default)" != cmd['rails_env']
          opt= { :in => "/dev/null", 
                 :out => "#{log_path}/telework_#{id}_stdout.log", 
                 :err => "#{log_path}/telework_#{id}_stderr.log", 
                 :chdir => path }
          pid= spawn( env, "bundle exec rake resque:work --trace", opt)
          info= { 'pid' => pid, 'status' => 'running', 'environment' => env, 'options' => opt, 'revision_info' => rev_info }
          @WORKERS[id]= info
          workers_add( @HOST, id, info )
          send_status( 'Info', "Starting worker #{id} (PID #{pid})" )
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
              workers_add( @HOST, id, @WORKERS[id] )
            end
                        
          end
        end
      
      end
    end
  end
end
