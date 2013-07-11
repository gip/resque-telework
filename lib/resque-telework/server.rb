module Resque
  module Plugins
    module Telework
      module Server

        require 'erb'

        VIEW_PATH = File.join(File.dirname(__FILE__), 'server', 'views')
        PUBLIC_PATH = File.join(File.dirname(__FILE__), 'server', 'public')
                        
        def self.registered( app )
          appn= 'Telework'
          
          # This helpers adds stuff to the app closure
          app.helpers do
            @@myredis= TeleworkRedis.new
            def redis
              @@myredis
            end
            def my_substabs
              ["Overview", "Start", "Misc"]
            end
            def my_show(page, layout = true)
              response["Cache-Control"] = "max-age=0, private, must-revalidate"
              begin
                erb(File.read(File.join(VIEW_PATH, "#{page}.erb")), {:layout => layout}, :resque => Resque)
              rescue Errno::ECONNREFUSED
                erb :error, {:layout => false}, :error => "Can't connect to Redis! (#{Resque.redis_id})"
              end
            end
            def generic_filter(id, name, list, more= "")
              html = "<select id=\"#{id}\" name=\"#{name}\" #{more}>"
              value= list[0]
              list.each do |k|
                selected = k == value ? 'selected="selected"' : ''
                html += "<option #{selected} value=\"#{k}\">#{k}</option>"
              end
              html += "</select>"
            end
            def generic_filter_with_dis(id, name, list, more= "")
              html = "<select id=\"#{id}\" name=\"#{name}\" #{more}>"
              value= list[0][0]
              list.each do |k,dis|
                selected = k == value ? 'selected="selected"' : ''
                html += "<option #{selected} value=\"#{k}\">#{dis}</option>"
              end
              html += "</select>"
            end
            def task_default
              { 'auto_max_waiting_job_per_worker' => 1,'auto_worker_min' => 0, 'auto_delay' => 15,
                'log_snapshot_period' => 30, 'log_snapshot_lines' => 40, 'exec' => "bundle exec rake resque:work --trace"
              }
            end
          end

          app.get "/#{appn.downcase}" do
            redirect "/resque/#{appn.downcase}/Overview"
          end
          
          app.get "/#{appn.downcase}/Overview" do
            @refresh= 10
            if params[:refresh]
              @refresh= params[:refresh].to_i
              @refresh= nil if @refresh==0
            end
            @status_messages= 100
            @scheduling= nil
            my_show appn.downcase
          end

          app.get "/#{appn.downcase}/Start" do
            @status_messages= 100
            @scheduling= true
            my_show appn.downcase
          end
          
          app.get "/#{appn.downcase}/Misc" do
            my_show 'misc'
          end          
          
          app.get "/#{appn.downcase}/revision/:revision" do
            @revision= params[:revision]
            my_show 'revision' 
          end

          app.get "/#{appn.downcase}/worker/:host/:worker" do
            @worker= params[:worker]
            @host= params[:host]
            my_show 'worker' 
          end

          app.get "/#{appn.downcase}/task/:host/:task_id" do
            @task_id= params[:task_id]
            @host= params[:host]
            my_show 'task' 
          end

          app.get "/#{appn.downcase}/host/:host" do
            @host= params[:host]
            my_show 'host' 
          end
          
          app.get "/#{appn.downcase}/config" do
            content_type :json
            redis.configuration
          end
          
          app.post "/#{appn.downcase}_stopit/:worker" do
            @worker= params[:worker]
            @host= nil
            @daemon= nil
            redis.hosts.each do |h|
              redis.workers(h).each do |id, info|
                @host= h if id==@worker # TODO: break nested loops
              end
            end
            redis.cmds_push( @host, { 'command' => 'stop_worker', 'worker_id'=> @worker } ) if @host
            my_show 'stopit'
          end

          app.post "/#{appn.downcase}_stopitd/:host" do
            # Todo - check that the host indeed exists
            @host= params[:host]
            @daemon= true
            redis.cmds_push( @host, { 'command' => 'stop_daemon' } )
            my_show 'stopit'
          end

          app.post "/#{appn.downcase}_killitd/:host" do
            # Todo - check that the host indeed exists
            @host= params[:host]
            @daemon= true
            @kill= true
            redis.cmds_push( @host, { 'command' => 'kill_daemon' } )
            my_show 'stopit'
          end

          app.post "/#{appn.downcase}_mod_host/:host" do
            host= params[:host]
            ahost= params[:alias]
            comment= params[:comment]
            if ahost.blank? || ahost==host
              redis.aliases_rem( host )
            else
              redis.aliases_add( host, ahost )
            end
            if comment.blank?
              redis.comments_rem( host )
            else
              redis.comments_add( host, comment )
            end
            redirect "/resque/#{appn.downcase}"            
          end

          app.post "/#{appn.downcase}_mod_task/:task" do
            @task_id= params[:task]
            @host= nil
            redis.hosts.each do |h|
              redis.tasks(h).each do |id, info|
                @host= h if id==@task_id # TODO: break nested loops
              end
            end
            @task= redis.tasks_by_id( @host, @task_id )
            all= ['log_snapshot_period', 'log_snapshot_lines', 'exec', 'worker_count',
                  'auto_delay', 'auto_max_waiting_job_per_worker', 'auto_worker_min' ]
            all.each do |a|
              @task[a]= params[a]
            end
            redis.tasks_add( @host , @task_id, @task )
            redirect "/resque/#{appn.downcase}"
          end

          app.post "/#{appn.downcase}_killit/:worker" do
            @worker= params[:worker]
            @host= nil
            @kill= true
            redis.hosts.each do |h|
              redis.workers(h).each do |id, info|
                @host= h if id==@worker # TODO: break nested loops
              end
            end
            redis.cmds_push( @host, { 'command' => 'kill_worker', 'worker_id'=> @worker } ) if @host
            my_show 'stopit'
          end
          
          app.post "/#{appn.downcase}/add_note" do
            @user= params[:note_user]
            @date= Time.now
            @note= params[:note_text]
            redis.notes_push({ 'user'=> @user, 'date'=> @date, 'note' => @note })
            redirect "/resque/#{appn.downcase}"
          end
          
          app.post "/#{appn.downcase}_del_note/:note" do
            @note_id= params[:note]
            redis.notes_del(@note_id)
            redirect "/resque/#{appn.downcase}"
          end
          
          # Start a task
          app.post "/telework/start_task" do
            @host= params[:h]
            @queue= params[:q]
            @qmanual= params[:qmanual]
            @count= params[:c]
            #@rev= params[:r].split(' ')
            @envv= params[:e]
            @q= @qmanual.blank? ? @queue : @qmanual
            id= redis.unique_id.to_s
            t= task_default
            redis.tasks_add( @host , id, t.merge( { 'task_id' => id, 'worker_count' => @count,
                                                    'rails_env' => @envv, 'queue' => @q,
                                                    'worker_id' => [], 'worker_status' => 'Stopped'} ) )
            redirect "/resque/#{appn.downcase}"          
          end
          
          app.post "/#{appn.downcase}/delete" do
            @task_id= params[:task]
            @host= params[:host]
            redis.tasks_rem( @host, @task_id )
            redirect "/resque/#{appn.downcase}"            
          end
          
          # Start workers
          app.post "/#{appn.downcase}/start" do
            @task_id= params[:task]
            @host= params[:host]
            @rev= params[:rev].split(',')
            @task= redis.tasks_by_id(@host, @task_id)
            count= params[:count]
            id= []
            for i in 1..count.to_i do
              w= @task
              w['worker_id']= redis.unique_id.to_s
              id << w['worker_id']
              w['worker_status']= 'Starting'
              w['revision']= @rev[0]
              w['revision_small']= @rev[1]
              w['command']= 'start_worker'
              w['task_id']= @task_id
              redis.cmds_push( @host, w )
            end
            @task['worker_id']= id
            @task['worker_count']= count
            redis.tasks_add( @host, @task_id, @task )
            redirect "/resque/#{appn.downcase}"
          end

          app.post "/#{appn.downcase}/start_auto" do
            @task_id= params[:task]
            @host= params[:host]
            @rev= params[:rev].split(',')
            @task= redis.tasks_by_id(@host, @task_id)
            count= params[:count]        
            wid= []
            for i in 1..count.to_i do
              wid << redis.unique_id.to_s
              #redis.cmds_push( @host, w )
            end
            @task['worker_id']= wid
            @task['worker_count']= count
            @task['mode']= 'auto'
            cmd= @task
            cmd['task_id']= @task_id
            cmd['revision']= @rev[0]
            cmd['revision_small']= @rev[1]
            cmd['command']= 'start_auto'
            redis.cmds_push( @host, cmd )
            redis.tasks_add( @host, @task_id, @task )
            redirect "/resque/#{appn.downcase}"
          end

          app.post "/#{appn.downcase}/stop_auto" do
            @task_id= params[:task]
            @host= params[:host]
            @task= redis.tasks_by_id(@host, @task_id)
            cmd= @task
            cmd['command']= 'stop_auto' 
            redis.cmds_push( @host, cmd )
            redirect "/resque/#{appn.downcase}"                
          end


          app.post "/#{appn.downcase}/pause" do
            @task_id= params[:task]
            @host= params[:host]
            @cont= params[:cont]=="true"
            @task= redis.tasks_by_id(@host, @task_id)
            @task['worker_id'].each do |id|
              redis.cmds_push( @host, { 'command' => 'signal_worker', 'worker_id'=> id, 'action' => @cont ? 'CONT' : 'PAUSE' } ) 
            end
            redirect "/resque/#{appn.downcase}"
          end

          app.post "/#{appn.downcase}/stop" do
            @task_id= params[:task]
            @host= params[:host]
            @kill= params[:kill]=="true"
            @task= redis.tasks_by_id(@host, @task_id)
            @task['worker_id'].each do |id|
              redis.cmds_push( @host, { 'command' => 'signal_worker', 'worker_id'=> id, 'action' => @kill ? 'KILL' : 'QUIT' } ) 
            end
            redirect "/resque/#{appn.downcase}"
          end

          app.post "/#{appn.downcase}/stop_all" do
            @kill= params[:mode]=="Kill"
            hl= [ params[:h] ]
            hl= redis.hosts if params[:h]=="[All hosts]"
            hl.each do |h|
              redis.workers(h).each do |id, info|
                unless info['worker_status']=='Stopped'
                  redis.cmds_push( h, { 'command' => 'signal_worker', 'worker_id'=> id, 'action' => @kill ? 'KILL' : 'QUIT' } ) 
                end
              end
            end
            redirect "/resque/#{appn.downcase}"
          end

                              
          app.tabs << appn
          
        end
      
      end
    end
  end
end

Resque::Server.register Resque::Plugins::Telework::Server
