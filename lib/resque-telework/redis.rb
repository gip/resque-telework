module Resque
  module Plugins
    module Telework      
      module Redis
      
      def key_prefix
        "plugins:#{Resque::Plugins::Telework::Name}"
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
  
      # Check
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
    
      def i_am_alive( ttl=10 )
        h= @HOST
        t= Time.now
        k= alive_key(h)
        hosts_add(h)
        Resque.redis.set(k, t)
        Resque.redis.expire(k, ttl)
        Resque.redis.set(last_seen_key(h), t)
      end
      
      def register_revision( h, rev )
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
        Resque.redis.hdel(h, id)
      end
      
      def cmds_pop( h )
        info= Resque.redis.rpop(cmds_key(h))
        info ? ActiveSupport::JSON.decode(info) : nil
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
          alive << [h, "Alive"]  if is_alive(h)
          unless is_alive(h)
            ls= last_seen(h)
            dead << [h, "Last seen #{fmt_date(ls)}"] if ls
            unknown << [h, 'Unknown'] unless ls
          end
        end
        alive+dead+unknown
      end
      
      def workers( h )
         Resque.redis.hgetall(workers_key(h)).collect { |id, info| [id,  ActiveSupport::JSON.decode(info)] }
      end
      
      def unique_id
        Resque.redis.incr(ids_key)
      end
      
      def cmds_push( h, info )
        Resque.redis.lpush(cmds_key(h), info.to_json)
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
        Resque.redis.exists(alive_key(h))
      end
      
      def last_seen( h )
        Resque.redis.get(last_seen_key(h))
      end
      
      def nb_keys
        Resque.redis.keys("#{key_prefix}:*").length
      end
      
      def fmt_date( t )
        begin
          Time.parse(t).strftime("%a %b %e %R %Y")
        rescue
          "(unknown date)"
        end
      end
      
      def text_to_html(s)
        ss= s.gsub(/\n/, '<br>')
      end
        
      end
    end
  end
end

class TeleworkRedis
  include Resque::Plugins::Telework::Redis
end