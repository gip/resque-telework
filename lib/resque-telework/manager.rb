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
          loop do
            i_am_alive
            check_processes
            while cmd= cmds_pop( @HOST ) do
              do_command(cmd)
            end
            sleep @SLEEP
          end
        end
        
        # cmd is a flat hash with the following: command, revision, rails_env, worker_id, worker_count, worker_queue
        def do_command( cmd )
          puts "New command: #{cmd}"
          puts cmd['command']
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
            puts "Unknown command"
          end
        end
                
        def start_worker( cmd, path, rev )
          puts cmd
          puts path
          id= cmd['worker_id']
          # TODO: count... env= { "COUNT"=> cmd['worker_count'], "QUEUE"=> cmd['worker_queue'] }
          env= { "QUEUE"=> cmd['worker_queue'] }
          env["RAILS_ENV"]= cmd['rails_env'] if "(default)" != cmd['rails_env']
          opt= { :in => "/dev/null", :out => "telework_#{id}_stdout.log", :err => "telework_#{id}_stderr.log", :chdir => path }
          pid= spawn( env, "bundle exec rake resque:work --trace", opt)
          info= { 'pid' => pid, 'status' => 'running', 'environment' => env, 'options' => opt, 'revision' => rev }
          @WORKERS[id]= info
          workers_add( @HOST, id, info )
          pid
          puts "Started #{id} with #{env}"
        end

        def stop_worker ( cmd, kill=false )
          id= cmd['worker_id']
          info= @WORKERS[id]
          puts "Worker #{id} wasn't found on this machine #{@WORKERS}" unless info
          return unless info
          sig= kill ? "KILL" : "QUIT"
          puts "Sending #{sig} to #{info['pid']}"
          Process.kill( sig, info['pid'] )
          info['status']= kill ? 'killed' : 'exiting'
          workers_add( @HOST, id, info )
          @WORKERS[id]= info
        end
                
        def check_processes
          workers_delall( @HOST )
          @WORKERS.keys.each do |id|
            res= nil
            begin
              res= Process.waitpid(@WORKERS[id]['pid'], Process::WNOHANG)
            rescue
              res= 0
            end
            if res # It's a zombie...
              puts "Zombie #{id}"
              #workers_rem( @HOST, id )
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
