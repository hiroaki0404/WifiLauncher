#!/usr/bin/ruby -w
#
# $Id$

require 'yaml'
require 'getoptlong'
require 'net/https'
require 'uri'
require 'pp'
require 'socket'

def usage
  script_name = File.basename( $0 )
  puts %{
Usage: ruby #{script_name} --essid|-e ESSID
                         --status|-s on|off
                         [--debug|-d]
    }
end

response = loginuri = status = debug = username = password = essid = nil

options = GetoptLong.new(
  [ "--essid", "-e", GetoptLong::REQUIRED_ARGUMENT ],
  [ "--status", "-s", GetoptLong::REQUIRED_ARGUMENT ],
  [ "--debug", "-d", GetoptLong::NO_ARGUMENT ]
)
options.ordering = GetoptLong::PERMUTE

begin
  options.each { |option, argument|
    case option
      when "--essid"
        essid = argument
      when "--debug"
        debug = true
      when "--status"
        status = argument
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

# When logout, do nothing
exit if status == "off"

# Search username and password from ~/.wifispot.yam
f = open(ENV['HOME'] + "/.wifispot.yam")
strWifiSettings = f.read()
f.close()
yamlWifiSettings = YAML.load(strWifiSettings)
username = URI.encode(yamlWifiSettings[essid]['login'])
password = URI.encode(yamlWifiSettings[essid]['password'])

# Try to access Google and get login url.
retrycount = 0
while status && retrycount < 16 do
  begin
    Socket::getaddrinfo('vauth.lw.livedoor.com', 'www')
    break
  rescue => err
    retrycount += 1
  end
end
p 'Failed to resolve address.' if debug && retrycount >= 16

response = Net::HTTP.get_response(URI.parse('http://www.google.com/'))
if response.code == "302"
  loginurl = URI.parse('https://vauth.lw.livedoor.com/auth/index?sn=009&name='+username+'&password='+password+'&original_url=http://www.google.com/')
  p loginurl.path if debug
  p loginurl.query if debug
  https = Net::HTTP.new(loginurl.host, loginurl.port)
  https.use_ssl = true
  https.verify_mode = OpenSSL::SSL::VERIFY_PEER
  https.verify_depth = 5
  https.start {
    response = https.post(loginurl.path, loginurl.query)
  }
  p response.code if debug
  p response.body if debug
else
  p response.code if debug
end
