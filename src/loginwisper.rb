#!/usr/bin/ruby -wI./lib
#
# Original is wisper-main.rb by simonp38.
#
# $Id$
#

require 'rubygems'
require 'wispr-client'
require 'getoptlong'
require 'yaml'
require 'open-uri'
require 'FileUtils'

def usage
  script_name = File.basename( $0 )
  puts %{
Usage: ruby #{script_name} --essid|-e ESSID
                         --status|-s
                         [--debug_file|-d FILENAME]
                         [--http_debug_file|-h FILENAME]
    }
end

http_debug_file = debug_filename = username = password = essid = status = nil

options = GetoptLong.new(
  [ "--essid", "-e", GetoptLong::REQUIRED_ARGUMENT ],
  [ "--status", "-s", GetoptLong::REQUIRED_ARGUMENT ],
  [ "--debug_file", "-d", GetoptLong::REQUIRED_ARGUMENT ],
  [ "--http_debug_file", "-h", GetoptLong::REQUIRED_ARGUMENT ]
)
options.ordering = GetoptLong::PERMUTE

begin
  options.each { |option, argument|
    case option
      when "--essid"
        essid = argument
      when "--status"
        status = argument
      when "--debug_file"
        debug_filename = argument
      when "--http_debug_file"
        http_debug_file = argument
    end
  }
rescue => err
  usage
  exit 
end

if essid.nil?
  puts "Please provide essid." 
  usage
  exit 
end

# Search username and password from ~/.wifispot.yam
f = open(ENV['HOME'] + "/.wifispot.yam")
strWifiSettings = f.read();
f.close();
yamlWifiSettings = YAML.load(strWifiSettings)
username =  yamlWifiSettings[essid]['login'];
password =  yamlWifiSettings[essid]['password'];

client = WisprClient.new( Logger.new( debug_filename ), http_debug_file )

if ( status == "on" )
  ret = client.login( username, password)
  if ( ret == NO_ERROR )
    puts "login success"
  else
    print "login failure: "
    puts ret
  end
  if !client.logoff_url.nil?
    open("/tmp/loginwisper.logout.url","w") {|f|
      f.write client.logout_url
    }
  end

else
  logout_url = nil
begin
  open("/tmp/loginwisper.logout.url","r") {|f|
    logout_url = f.read
  }
  open(logout_url) {|f|
    print "logout status: "
    puts f.status
  }
rescue => err
end
#  FileUtils.rm("/tmp/loginwisper.logout.url")
end
client.print_wispr_messages
