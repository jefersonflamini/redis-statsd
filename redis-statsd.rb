#!/usr/bin/env ruby
require 'socket'
require 'pp'

# This script runs every minute, captures stats about redis
# and forwards them to statsd.

# pass by command line arguments 
#    hostname    ->  redis server
#    namespace   ->  name to show on graphite
#
#   ex.  ruby redis-statsd.rb redis.acme.com myredis

# Graphite/carbon settings
STATSD_HOST="127.0.0.1"
STATSD_PORT=8125

def instrument_redis(redis_host, namespace)

  puts "-----------"

  redis = {}
  `redis-cli -h #{redis_host} info`.each_line do |line|
    key,value = line.chomp.split(/:/)
    redis[key]=value
  end

  # --------
  #  Gauges
  # --------
  %w{uptime_in_seconds
     connected_clients
     used_memory
     used_memory_rss
     changes_since_last_save
     connected_clients
     evicted_keys
     expired_keys
     total_commands_processed
     instantaneous_ops_per_sec
     connected_slaves}.each do |item|
     send_gauge("#{namespace}.#{item}", redis[item].to_i)
  end

  # Miss percentage
  hits = redis['keyspace_hits'].to_i + redis['keyspace_misses'].to_i
  if hits > 0
    miss_percentage = 100.0*(redis['keyspace_misses'].to_f / hits.to_f)
  else
    miss_percentage = 0.0
  end
  send_gauge("#{namespace}.miss_percentage", miss_percentage)

  # Memory fragmentation ratio
  send_gauge("#{namespace}.mem_fragmentation_ratio", redis['mem_fragmentation_ratio'])

  # Databases
  # send number of keys in each database, e.g.
  #  db0.keys = value
  #  db1.keys = value
  #  ...
  `redis-cli -h #{redis_host} info keyspace`.each_line do |line|
    if /^db/.match(line)
      db_data = line.match(/(db.*?):keys=(.*?),expires=(.*?),avg_ttl=(.*?)\r/).to_a
      send_gauge("#{namespace}." + db_data[1].to_s + ".keys", db_data[2].to_i)
      send_gauge("#{namespace}." + db_data[1].to_s + ".expires", db_data[3].to_i)
      send_gauge("#{namespace}." + db_data[1].to_s + ".agv_ttl", db_data[4].to_i)
    end
  end

end

def send_gauge(path, value, time=nil)
  time ||= Time.new
  msg = "#{path}:#{value}|g\n"
  puts msg
  @socket.send(msg, 0, STATSD_HOST, STATSD_PORT)
end

# ----------------
# Collect metrics
# ----------------

# Interrupt handler to exit gracefully
interrupted = false
trap("INT") { interrupted = true }

@socket = UDPSocket.new
while true
  #puts "collecting"
  instrument_redis(ARGV[0], ARGV[1])
  sleep(1)
  if interrupted
    @socket.close
    #puts "closed the socket"
    exit
  end
end
