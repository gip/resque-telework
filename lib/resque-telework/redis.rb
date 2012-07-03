module Resque
  module Plugins
    module Telework      
      module Redis
      
      def key_prefix
        "plugins:#{Resque::Plugins::Telework::Nickname}"
      end

      def redis_interface_key # String
        "#{key_prefix}:redisif"
      end

      def ids_key # String
        "#{key_prefix}:ids"
      end
      
      def hosts_key # Set
        "#{key_prefix}:hosts"
      end
      
      def revisions_key( h ) # List
        "#{key_prefix}:host:#{h}:revisions"
      end
        
      def workers_key( h ) # Hash
        "#{key_prefix}:host:#{h}:workers"
      end

      def tasks_key( h ) # Hash
        "#{key_prefix}:host:#{h}:tasks"
      end
      
      def logs_key( h ) # Hash
        "#{key_prefix}:host:#{h}:logs"        
      end
      
      def cmds_key( h ) # List
        "#{key_prefix}:host:#{h}:cmds"
      end

      def acks_key( h ) # List
        "#{key_prefix}:host:#{h}:acks"
      end
      
      def status_key # List
        "#{key_prefix}:status"
      end
      
      def alive_key( h ) # String, with TTL
        "#{key_prefix}:host:#{h}:alive"
      end
      
      def last_seen_key( h ) # String, no TTL
        "#{key_prefix}:host:#{h}:last_seen"
      end

      def notes_key # List
        "#{key_prefix}:notes"
      end
  
      # Checks
      def check_redis
        res= true
        v0= Resque::Plugins::Telework::REDIS_INTERFACE_VERSION
        v= Resque.redis.get(redis_interface_key)
        if v!=v0
          Resque.redis.set(redis_interface_key, v0) unless v
          res=false if v
        end
        res
      end
        
      # Clients (hosts) side
    
      def i_am_alive( info= {}, ttl=10 )
        h= @HOST
        t= Time.now
        info= info.merge( { 'date' => t, 'version' => Resque::Plugins::Telework::Version } )
        k= alive_key(h)
        hosts_add(h)
        Resque.redis.set(k, info.to_json )
        Resque.redis.expire(k, ttl)
        Resque.redis.set(last_seen_key(h), t)
      end
      
      def register_revision( h, rev, lim=9 )
        k= revisions_key(h)
        Resque.redis.ltrim(k, 0, lim-1)
        rem= []
        Resque.redis.lrange(k, 0, lim-1).each do |s|
          info= ActiveSupport::JSON.decode(s)
          if info['revision']==rev['revision']
            rem << s
            puts "Telework: Info: Revision #{rev['revision']} was already registered for this host, so the previous one will be unregistered" 
          end
          if info['revision_path']==rev['revision_path']
            rem << s
            puts "Telework: Info: Path for revision #{rev['revision']} was already registedred by another revision which will therefore by removed"
          end
        end
        rem.each { |r| Resque.redis.lrem(k, 0, r) }
        revisions_add( h, rev )
      end
      
      def find_revision( rev )
        revisions(@HOST).each do |r|
          return r if rev==r['revision']
        end
        nil
      end
        
      def hosts_add( h )
        Resque.redis.sadd(hosts_key, h)
      end
      
      def revisions_add( h, v )
        hosts_add(h)
        k= revisions_key(h)
        Resque.redis.lpush(k, v.to_json )
      end
            
      def workers_delall( h )
        Resque.redis.del(workers_key(h))
      end      
            
      def workers_add( h, id, info, ttl=10 )
        k= workers_key(h)
        Resque.redis.hset(k, id, info.to_json )
        Resque.redis.expire(k, ttl)
      end
      
      def workers_rem( h , id )
        k= workers_key(h)
        Resque.redis.hdel(k, id)
      end

      def tasks_add( h, id, info)
        k= tasks_key(h)
        Resque.redis.hset(k, id, info.to_json )
      end
      
      def tasks_rem( h , id )
        k= tasks_key(h)
        Resque.redis.hdel(k, id)
      end
      
      def cmds_pop( h )
        info= Resque.redis.rpop(cmds_key(h))
        info ? ActiveSupport::JSON.decode(info) : nil
      end
      
      def logs_add( h, id, info )
        k= logs_key(h)
        Resque.redis.hset(k, id, info.to_json ) 
      end
      
      def acks_push( h, info, lim=10 )
        Resque.redis.lpush(acks_key(h), info)
        Resque.redis.ltrim(acks_key(h), 0, lim-1)
      end

      def status_push( info, lim=100 )
        Resque.redis.lpush(status_key, info.to_json )
        Resque.redis.ltrim(status_key, 0, lim-1)
      end
      
      # Server side
        
      def workers_state( clean = 30000000 )
        alive= []
        dead= []
        unknown= []
        hosts.each do |h|
          life= is_alive(h)
          alive << [h, "Alive", life]  if life
          unless life
            ls= last_seen(h)
            dead << [h, "Last seen #{fmt_date(ls, true)}", {} ] if ls
            unknown << [h, 'Unknown', {} ] unless ls
          end
        end
        alive+dead+unknown
      end
      
      def workers( h )
         Resque.redis.hgetall(workers_key(h)).collect { |id, info| [id,  ActiveSupport::JSON.decode(info)] }
      end
      
      def workers_by_id( h, id )
        k= workers_key(h)
        info= Resque.redis.hget(k, id)
        info ? ActiveSupport::JSON.decode(info) : nil
      end

      def tasks( h )
         Resque.redis.hgetall(tasks_key(h)).collect { |id, info| [id,  ActiveSupport::JSON.decode(info)] }
      end
      
      def tasks_by_id( h, id )
        k= tasks_key(h)
        info= Resque.redis.hget(k, id)
        info ? ActiveSupport::JSON.decode(info) : nil
      end      
      
      def logs_by_id( h, id )
        k= logs_key(h)
        info= Resque.redis.hget(k, id)
        info ? ActiveSupport::JSON.decode(info) : nil      
      end
      
      def unique_id
        Resque.redis.incr(ids_key)
      end
      
      def cmds_push( h, info )
        Resque.redis.lpush(cmds_key(h), info.to_json)
      end

      def notes_push( info )
        Resque.redis.lpush(notes_key, info.to_json)
      end
      
      def notes_pop ( lim= 100 )
        Resque.redis.lrange(notes_key, 0, lim-1).collect { |s| ActiveSupport::JSON.decode(s) }
      end
      
      def notes_del( id )
        info= Resque.redis.lindex(notes_key, id)
        Resque.redis.lrem(notes_key, 0, info)
      end

      def acks_pop( h )
        Resque.redis.rpop(acks_key(h))
      end

      def statuses( lim=100 )
        Resque.redis.lrange(status_key, 0, lim-1).collect { |s| ActiveSupport::JSON.decode(s) }
      end
      
      def hosts_rem( h )
        [ revisions_key(h), workers_key(h),
          cmds_key(h), alive_key(h), last_seen_key(h) ].each do |k|
          Resque.redis.del(k)
        end
        Resque.redis.srem( hosts_key, h )
      end
         
      def hosts
        Resque.redis.smembers(hosts_key)
      end

      def revisions( h, lim=30 )
        k= revisions_key(h)
        Resque.redis.ltrim(k, 0, lim-1)
        Resque.redis.lrange(k, 0, lim-1).map { |s| ActiveSupport::JSON.decode(s) }
      end
      
      def is_alive( h )
        v= Resque.redis.get(alive_key(h))
        return nil unless v
        begin
          ActiveSupport::JSON.decode(v)
        rescue
          {}
        end
      end
      
      def last_seen( h )
        Resque.redis.get(last_seen_key(h))
      end
      
      def nb_keys
        Resque.redis.keys("#{key_prefix}:*").length
      end
      
      def fmt_date( t, rel=false ) # This is not redis-specific and should be moved to another class!
        begin
          if rel
            "#{time_ago_in_words(Time.parse(t))} ago"
          else
            Time.parse(t).strftime("%a %b %e %R %Y")
          end
        rescue
          "(unknown date)"
        end
      end
      
      def text_to_html(s)
        return "" unless s
        ss= s.gsub(/\n/, '<br>')
      end
        
      end
    end
  end
end

class TeleworkRedis
  include ActionView::Helpers::DateHelper
  include Resque::Plugins::Telework::Redis
end