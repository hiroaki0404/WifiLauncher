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
                         --status|-s
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
        status = true
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
strWifiSettings = f.read()
f.close()
yamlWifiSettings = YAML.load(strWifiSettings)
username = URI.encode(yamlWifiSettings[essid]['login'])
password = URI.encode(yamlWifiSettings[essid]['password'])

# Try to access Google and get login url.
while status do
  begin
    Socket::getaddrinfo('www.google.com', 'www')
    break
  rescue => err
  end
end

response = Net::HTTP.get_response(URI.parse('http://www.google.com/'))
if response.code == "302"
  loginurl = URI.parse(response['location']+"&login_name="+username+"&password="+password)
  p loginurl.path if debug
  p loginurl.query if debug
  https = Net::HTTP.new(loginurl.host, loginurl.port)
  https.use_ssl = true
  https.verify_mode = OpenSSL::SSL::VERIFY_PEER
  https.verify_depth = 5
  https.start {
    response = https.get(loginurl.path + '?' + loginurl.query)
  }
  p response.code if debug
  p response.body if debug
else
  p response.code if debug
end
