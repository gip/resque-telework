module Resque
  module Plugins
    module Telework      
      class Manager
        
        include Resque::Plugins::Telework::Redis
        
        def initialize
          # TODO: move that to local conf file
          @SLEEP= 2
          @HOST= configatron.sources.hostname
          @WORKERS= {}
        end
        
        def start
          send_status( 'Info', "Manager starting..." )
          loop do
            i_am_alive
            check_processes
            while cmd= cmds_pop( @HOST ) do
              do_command(cmd)
            end
            sleep @SLEEP
          end
        end
        
        def send_status( severity, message )
          info= { 'host'=> @HOST, 'severity' => severity, 'message'=> message,
                  'date'=> Time.now }
          puts info
          status_push(info)
        end
        
        # cmd is a flat hash with the following: command, revision, rails_env, worker_id, worker_count, worker_queue
        def do_command( cmd )
          case cmd['command']
          when 'start_worker'
            rev= cmd['revision']
            path= find_revision(rev)['path']
            start_worker( cmd, path, rev )
          when 'stop_worker'
            stop_worker( cmd )
          when 'kill_worker'
            stop_worker( cmd, true )
          else
            send_status( 'Error', "Unknown command '#{cmd['command']}'" )
          end
        end
                
        def start_worker( cmd, path, rev )
          id= cmd['worker_id']
          # TODO: count... env= { "COUNT"=> cmd['worker_count'], "QUEUE"=> cmd['worker_queue'] }
          env= { "QUEUE"=> cmd['worker_queue'] }
          env["RAILS_ENV"]= cmd['rails_env'] if "(default)" != cmd['rails_env']
          opt= { :in => "/dev/null", :out => "telework_#{id}_stdout.log", :err => "telework_#{id}_stderr.log", :chdir => path }
          pid= spawn( env, "bundle exec rake resque:work --trace", opt)
          info= { 'pid' => pid, 'status' => 'running', 'environment' => env, 'options' => opt, 'revision' => rev }
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
          info['status']= kill ? 'killed' : 'exiting'
          workers_add( @HOST, id, info )
          @WORKERS[id]= info
        end
                
        def check_processes
          workers_delall( @HOST )
          @WORKERS.keys.each do |id|
            remove= false
            unexpected_death= false
            begin 
              # Zombie hunt..
              res= Process.waitpid(@WORKERS[id]['pid'], Process::WNOHANG)
              remove= true if res 
            rescue
              # Not a child.. so the process is already dead (we don't know why, maybe someone did a kill -9)
              unexpected_death= true
              remove= true
            end
            
            if remove
              send_status( 'Error', "Worker #{id} (PID #{@WORKERS[id]['pid']}) has unexpectedly ended" ) if unexpected_death
              send_status( 'Info', "Worker #{id} (PID #{@WORKERS[id]['pid']}) has exited" ) unless unexpected_death
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
