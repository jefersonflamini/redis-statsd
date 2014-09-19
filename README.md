# redis-statsd

This is a shameless hack starting from: https://gist.github.com/somebox/7039510

By default, it runs in the foreground, sending redis stats to statsd every second. There are about a million ways this could be better... It's designed to run on the ancient version of ruby supplied by default in CentOS 6.

    $ ./redis-statsd.rb

## Nice to have in future

- Ability to run as a daemon
- Connect to redis using a suitable driver rather than performing a shell exec

