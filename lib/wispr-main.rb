#!/usr/bin/ruby -w
#
# $Id: wispr-main.rb,v 1.1 2005/09/30 13:22:12 simonp38 Exp $
#

require 'wispr-client'
require 'getoptlong'

def usage
  script_name = File.basename( $0 )
  puts %{
Usage: ruby #{script_name} --user|-u USERNAME
                         --password|-p PASSWORD
                         [--debug_file|-d FILENAME]
                         [--http_debug_file|-h FILENAME]
                          
    }
end

http_debug_file = debug_filename = username = password = nil

options = GetoptLong.new(
  [ "--user", "-u", GetoptLong::REQUIRED_ARGUMENT ],
  [ "--password", "-p", GetoptLong::REQUIRED_ARGUMENT ],
  [ "--debug_file", "-d", GetoptLong::REQUIRED_ARGUMENT ],
  [ "--http_debug_file", "-h", GetoptLong::REQUIRED_ARGUMENT ]
)
options.ordering = GetoptLong::PERMUTE

begin
  options.each { |option, argument|
    case option
      when "--user"
        username = argument
      when "--password"
        password = argument
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

if username.nil? || password.nil? 
  puts "Please provide username and password." 
  usage
  exit 
end

client = WisprClient.new( Logger.new( debug_filename ), http_debug_file )

if ( client.login( username, password ) == NO_ERROR )
  puts "login success"
  puts "\nPress Enter to logout...\n"
  STDIN.gets
  if ( client.logout == NO_ERROR )
    puts "logout success"
  else
    puts "logout failed"
  end
else
  puts "login failure"
end
client.print_wispr_messages