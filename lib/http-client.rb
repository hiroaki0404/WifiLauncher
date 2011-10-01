#!/usr/bin/ruby -w
#
# $Id: http-client.rb,v 1.7 2006/09/15 15:35:31 fredzanaroli Exp $
#

require 'http-access2'
require 'html/htmltokenizer'
require 'logger'

class HttpClient

  attr_writer :follow_refresh_tag
  s = %w$Id: http-client.rb,v 1.7 2006/09/15 15:35:31 fredzanaroli Exp $
  RCS_FILE, RCS_REVISION = s[1][/.*(?=,v$)/], s[2]

  def initialize( logger, http_debug_file = nil )
    @logger = logger
    @callback_on_redirect = nil
    @callback_on_redirect_content_only = true
    @follow_refresh_tag = false
  
    # initialize HTTP client
    @http_client = HTTPAccess2::Client.new( nil, "Wispr-Ruby-Client rev#{RCS_REVISION}" )
    @http_client.redirect_uri_callback = self.method(:redirect)
    @http_client.set_cookie_store('cookie.dat')

    # Disable sync so that complete frames can be sent at once.
    @http_client.socket_sync = false

    # setup available ciphers (man ciphers for details)
    @http_client.ssl_config.options = OpenSSL::SSL::OP_ALL
    @http_client.ssl_config.ciphers = "ALL:!ADH:!LOW:!EXP:@STRENGTH"
    if !ENV['CERTPATH'].nil?
      # Look for directory in CERTPATH environment variable
      load_certificates_from_dir( ENV['CERTPATH'] )
    else
      # Default to cert/ from current working directory
      load_certificates_from_dir( 'certs/' )
    end
    
    if ( http_debug_file )
      @http_client.debug_dev = File.new( http_debug_file, File::CREAT|File::TRUNC|File::RDWR )
    end
  end

  def close_http_debug_file
    if @http_client.debug_dev
      @http_client.debug_dev.close
    end
  end  

  def callback_on_redirect=( callback_on_redirect)
    @callback_on_redirect = callback_on_redirect
  end

  def callback_on_redirect_content_only=( callback_on_redirect_content_only)
    @callback_on_redirect_content_only = callback_on_redirect_content_only
  end  
  
  def load_certificates_from_dir( dirname )
    if !FileTest.directory?(dirname)
      @logger.warn "Certificate directory #{dirname} not found."
      return
    end
    
    # Load SSL certificates
    Dir.foreach( dirname ) { |entry|
      if FileTest.file?(dirname + entry) && /^.*\.crt/.match(entry)
        @http_client.ssl_config.set_trust_ca( dirname + entry )
      end
    }
  end
  
  # Callback for HTTP redirections
  def redirect( res )
    uri = res.header['location'][0]
    if /^http/.match( uri ).nil?
     # rebuild full URL path
      uri = "#{@original_uri.scheme}://#{@original_uri.host}:#{@original_uri.port}#{uri}"
    end
    if @callback_on_redirect
      if @callback_on_redirect_content_only
        @callback_on_redirect.call( res.content )
      else
        @callback_on_redirect.call( res )
      end
    end
    @logger.debug "Redirection to: #{uri}"
    uri
  end
  

  # Returns true if meta refresh tag was found and false otherwise.
  def analyse_page( html_content )
    @refresh_url = @refresh_delay = nil
  
    tokenizer = HTMLTokenizer.new( html_content )
    
    while token = tokenizer.getNextToken( )
      if token.is_a?( HTMLTag )
        if token.tag_name.downcase == 'meta'
          if ( token.attr_hash['http-equiv'].to_s.downcase == 'refresh' ||
                token.attr_hash['equiv'].to_s.downcase == 'refresh' )
            content = token.attr_hash['content'].to_s
            @logger.info "Found a refresh tag (#{content})"
            regexpr = Regexp.new( '^(\d+);\s*url=(.*)$', Regexp::IGNORECASE )
            if ( regexpr.match( content ) )
              @refresh_delay = $1.to_i
              @refresh_url = $2
  
              # Test that refresh URL is a 'full' absolute URL
              if /^http/.match( @refresh_url ).nil?
                # rebuild full URL path
                @refresh_url = "#{@original_uri.scheme}://#{@original_uri.host}:#{@original_uri.port}#{@refresh_url}"
              end
            elsif ( /^(\d+)$/.match( content ) )
              @refresh_delay = $1.to_i
            end
            return true
          end
        end
      end
    end
  
    return false
  end
  
  def get_content(uri, query = nil, extheader = {}, &block)
    @original_uri = URI.parse( uri )
    
    res = @http_client.get_content(uri, query, extheader, &block)
    @http_client.reset uri
    if ( @follow_refresh_tag )
      # If @url page contained meta refresh tag, continue until final page.
      while analyse_page(res)
        # trigger redirect callback
        if @callback_on_redirect
          @callback_on_redirect.call( res )
        end
        
        # go to next url
        sleep @refresh_delay
    
        @original_uri = URI.parse @refresh_url
        res = @http_client.get_content( @refresh_url, nil )
        @http_client.reset @refresh_url
      end
    end
    res
  end

   
  def post(uri, body = nil, extheader = {}, &block)
    @original_uri = URI.parse uri
    
    res = @http_client.post( uri, body , extheader, &block )
    @http_client.reset uri
    
    # Check if answer to post was a redirect
    if HTTP::Status.redirect?( res.status )
      uri = redirect( res )
      res = self.get_content( uri, nil )
      @http_client.reset uri
    else
      res = res.content
    end
    
    res
  end
  
  def save_cookie_store
    @http_client.save_cookie_store
  end

end