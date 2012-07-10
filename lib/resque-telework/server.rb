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
              #html += "<option value=\"\">-</option>"
              value= list[0]
              list.each do |k|
                selected = k == value ? 'selected="selected"' : ''
                html += "<option #{selected} value=\"#{k}\">#{k}</option>"
              end
              html += "</select>"
            end
            
          end

          app.get "/#{appn.downcase}" do
            redirect "/resque/#{appn.downcase}/Overview"
          end
          
          app.get "/#{appn.downcase}/Overview" do
            @status_messages= 100
            @refresh= 10
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
          
          app.post "/#{appn.downcase}_add_note" do
            @user= params[:user]
            @date= Time.now
            @note= params[:note]
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
            @rev= params[:r].split(' ')
            @env= params[:e]
            @q= @qmanual.blank? ? @queue : @qmanual
            id= redis.unique_id.to_s
            redis.tasks_add( @host , id, { 'revision' => @rev[0], 'revision_small' => @rev[1],
                                           'task_id' => id, 'worker_count' => @count,
                                           'rails_env' => @env, 'queue' => @q,
                                           'exec' => "bundle exec rake resque:work --trace",
                                           'worker_id' => [], 'worker_status' => 'Stopped',
                                           'log_snapshot_period' => 30,
                                           'log_snapshot_lines' => 40 } )
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
            count= @task['worker_count'] || 1
            id= []
            for i in 1..count.to_i do
              w= @task
              w['worker_id']= redis.unique_id.to_s
              id << w['worker_id']
              w['worker_status']= 'Starting'
              w['revision']= @rev[0]
              w['revision_small']= @rev[1]
              w['command']= 'start_worker'
              redis.cmds_push( @host, w )
            end
            @task['worker_id']= id
            redis.tasks_add( @host, @task_id, @task )
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
                              
          app.tabs << appn
          
        end
      
      end
    end
  end
end

Resque::Server.register Resque::Plugins::Telework::Server
