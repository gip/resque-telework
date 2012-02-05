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
            @refresh= 5
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
          
          app.post "/#{appn.downcase}_stopit/:worker" do
            @worker= params[:worker]
            @host= nil
            redis.hosts.each do |h|
              redis.workers(h).each do |id, info|
                @host= h if id==@worker # TODO: break nested loops
              end
            end
            redis.cmds_push( @host, { 'command' => 'stop_worker', 'worker_id'=> @worker } ) if @host
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
          
          app.post "/#{appn.downcase}_do_start" do
            @host= params[:h]
            @queue= params[:q]
            @qmanual= params[:qmanual]
            @count= params[:c]
            @rev= params[:r]
            @env= params[:e]
            @q= @qmanual.blank? ? @queue : @qmanual
            redis.cmds_push( @host, { 'command' => 'start_worker', 'revision' => @rev,
                                      'worker_id' => redis.unique_id.to_s, 'worker_count' => @count,
                                      'rails_env' => @env, 'worker_queue' => @q,
                                      'exec' => "bundle exec rake resque:work --trace",
                                      'log_snapshot' => 30 } )
            redirect "/resque/#{appn.downcase}"
          end
          
          app.post "/#{appn.downcase}_do_stop" do
            @host= params[:h2]
            @mid= params[:mid]
            @kill= params[:kill]
            puts "Stop on host '#{@host}' for id #{@mid}, kill is #{@kill}"
            redis.cmds_push( @host, { 'command' => (@kill ? 'kill_worker' : 'stop_worker'), 'worker_id'=> @mid } )            
            redirect "/resque/#{appn.downcase}"
          end
                              
          app.tabs << appn
          
        end
      
      end
    end
  end
end

Resque::Server.register Resque::Plugins::Telework::Server
