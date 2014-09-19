#!/usr/bin/env ruby
require 'socket'
require 'pp'

# This script runs every minute, captures stats about redis
# and forwards them to statsd.

# Graphite/carbon settings
STATSD_HOST="127.0.0.1"
STATSD_PORT=8125

def instrument_redis(redis_host)
  namespace = "redis"
  redis = {}
  `/usr/bin/redis-cli -h #{redis_host} info`.each_line do |line|
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
     connected_slaves}.each do |item|
     send_gauge("#{namespace}.#{item}", redis[item].to_i)
  end

  # Miss percentage
  hits = redis['keyspace_hits'].to_i + redis['keyspace_misses'].to_i
  if hits > 0
     miss_percentage = 100*(redis['keyspace_misses'].to_i / hits)
  else
    miss_percentage = 0.0
  end
  send_gauge("#{namespace}.miss_percentage", miss_percentage)

  # Memory fragmentation ratio
  send_gauge("#{namespace}.mem_fragmentation_ratio", redis['mem_fragmentation_ratio'])

  # Master link status
  if redis['role'] == 'slave'
    if redis['master_link_status'] == 'up'

  # Databases
  # send number of keys in each database, e.g. 
  #  db0.keys = value
  #  db1.keys = value
  #  ...
  `/usr/bin/redis-cli -h #{redis_host} info keyspace`.each_line do |line|
    if /^db/.match(line)
      db_data = line.match(/(db.*?):keys=(.*?),.*/).to_a
      database_key = db_data[1].to_s + ".keys"
      num_keys = db_data[2].to_i
      send_gauge("#{namespace}.#{database_key}", num_keys)
    end
  end

end

def send_gauge(path, value, time=nil)
  time ||= Time.new
  msg = "#{path}:#{value}|g\n"
  #puts msg
  @socket.send(msg, 0, STATSD_HOST, STATSD_PORT)
  msg
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
  instrument_redis('127.0.0.1')
  sleep(1)
  if interrupted
    @socket.close
    #puts "closed the socket"
    exit
  end
end
