#!/usr/bin/ruby -w
#
# $Id: wispr-client.rb,v 1.5 2006/09/07 14:22:47 pwdng Exp $
#

require 'http-client'
require 'html/htmltokenizer'
require 'fsm'
require 'wispr'
require 'constants'

module Wispr_State_Machine
  # states of the WISPr client
  IDLE = '0'.intern
  PROXIED = '1'.intern
  REDIRECTED = '2'.intern
  LOGIN = '3'.intern
  LOGGED = '4'.intern
  REJECTED = '5'.intern
  FAILED = '6'.intern
end

class WisprClient
  include Wispr_State_Machine

  s = %w$Id: wispr-client.rb,v 1.5 2006/09/07 14:22:47 pwdng Exp $
  RCS_FILE, RCS_REVISION = s[1][/.*(?=,v$)/], s[2]

  attr_reader :username, :password
  attr_reader :initial_url, :logoff_url
  
  def initialize( logger, http_debug_file = nil )
    @username = @password = @initial_url = @logoff_url = nil

    @logger = logger

    @wispr_messages = Array.new
    @wispr_factory = WisprMessageFactory.new( @logger )
    
    # initialize the state machine
    @fsm = FSM.new
    @fsm.add_state( IDLE, true ) { |c| self.idle_handler(c) }
    @fsm.add_state( PROXIED, false ) { |c| self.proxied_handler(c) }
    @fsm.add_state( REDIRECTED, false ) { |c| self.redirected_handler(c) }
    @fsm.add_state( LOGIN, false ) { |c| self.login_handler(c) }
    @fsm.add_state( LOGGED, true ) { |c| self.logged_handler(c) }
    @fsm.add_state( REJECTED, true ) { |c| self.rejected_handler(c) }
    @fsm.add_state( FAILED, true ) { |c| self.failed_handler(c) }
    
    # initialize HTTP client
    @http_client = HttpClient.new(@logger, http_debug_file )
    @http_client.follow_refresh_tag = true
    @http_client.callback_on_redirect = self.method(:process_html_content)

end
  
  # Process content of HTML pages
  def process_html_content( html_content )
    raise ArgumentError, "invalid argument type #{html_content.class.to_s}" if html_content.class != String

    wispr_obj = nil
    tokenizer = HTMLTokenizer.new( html_content )

    while token = tokenizer.getNextToken( )
      if token.is_a?( HTMLComment )
        wispr_obj = @wispr_factory.createWisprMessage( token.contents )
        if wispr_obj != nil
          # Stop when receiving one message
          @logger.info "Found a #{wispr_obj.class.to_s} message"
          @wispr_messages.push wispr_obj
          break
        end
      end
    end

    wispr_obj
  end
  
  # Login with WISPr method
  def login( username, password, initial_url = 'http://www.google.com/' )
    @username = username
    @password = password
    @initial_url = initial_url
    
    @fsm.set_start( IDLE )
    last_state = @fsm.run( self )
    print_wispr_messages
    
    # check state
    if (last_state == LOGGED )
      @logger.info "SUCCESSFUL LOGIN!!!"
      return NO_ERROR
    elsif (last_state == REJECTED )
      @logger.info "LOGIN REJECTED by home server!!!"
      return LOGIN_REJECTED
    else
      @logger.warn "LOGIN FAILED: last state is " + last_state.to_s
    end
    return OPERATION_FAILED
  end

  # Logout with WISPr method
  def logout
    # find URL for logout
    @wispr_messages.reverse_each { |msg|
      if ( msg.is_a?(WisprAuthenticationReply) || msg.is_a?(WisprAuthenticationPollReply) )
        @logoff_url = msg.logoff_url
      end
      break unless @logoff_url.nil?
    }
    
    @fsm.set_start( LOGGED )
    last_state = @fsm.run( self )
    print_wispr_messages
    
    # check state
    if (last_state == IDLE )
      @logger.info "SUCCESSFUL LOGOUT!!!"
      return NO_ERROR
    else
      @logger.warn "LOGOUT FAILED: last state is " + last_state.to_s
    end
    return OPERATION_FAILED
  end
  
  def idle_handler ( object )
    # GET to google.com
    begin
      
      url = @initial_url
      res = @http_client.get_content( url, nil )
      process_html_content( res )
      @http_client.follow_refresh_tag = false
    
    rescue Exception => err
      @logger.error "Exception '" + err.class.to_s + "' raised in idle_handler(): '" + err.message + "'"
      @logger.error err.backtrace.join("\n")
      return FAILED, self
    end
    
    if (@wispr_messages.empty?)
      @logger.error "No WISPr message found"
      return FAILED, self
    end
    
    last_msg = @wispr_messages.last
    if ( last_msg.is_a?( WisprRedirect ) )
      if ( last_msg.response_code == '0' )
        @logger.debug "Going to REDIRECTED state"
        return REDIRECTED, self
      else
        @logger.error "WisprRedirect message with #{last_msg.response_code} code"
        return FAILED, self
      end
    elsif ( last_msg.is_a?( WisprProxy ) )
      if ( last_msg.response_code == '200' )
        @logger.debug "Going to PROXIED state"
        return PROXIED, self
      else
        @logger.error "WisprProxy message with #{last_msg.response_code} code"
        return FAILED, self
      end
    else
        @logger.error "Found a #{last_msg.class.to_s} message"
      return FAILED, self
    end
  end
  
  def proxied_handler( object )
    next_url = delay = nil
    @wispr_messages.reverse_each { |item|
      if ( item.is_a?( WisprProxy ) )
        next_url = item.next_url if next_url.nil?
        delay = item.delay if delay.nil?
      end
      break unless ( next_url.nil? || delay.nil? )
    }

    # GET to nextURL
    sleep( delay.to_i )
    res = @http_client.get_content( next_url )
    process_html_content( res )
    
    last_msg = @wispr_messages.last
    if ( last_msg.is_a?( WisprRedirect ) )
      if ( last_msg.response_code == '0' )
        @logger.debug "Going to REDIRECTED state"
        return REDIRECTED, self
      else
        @logger.error "WisprRedirect message with #{last_msg.response_code} code"
        return FAILED, self
      end
    elsif ( last_msg.is_a?( WisprProxy ) )
      if ( last_msg.response_code == '200' )
        @logger.debug "Going to PROXIED state"
        return PROXIED, self
      else
        @logger.error "WisprProxy message with #{last_msg.response_code} code"
        return FAILED, self
      end
    else
      @logger.error "Found a #{last_msg.class.to_s} message"
      return FAILED, self
    end
  end
  
  def redirected_handler( object )
    # POST to loginURL
    last_msg = @wispr_messages.last
    
    begin
      post_params = "FNAME=0&UserName=#{@username}&Password=#{@password}&button=Login&OriginatingServer=#{@initial_url}"

      @logger.debug "Params to POST: " + post_params
      res = @http_client.post( last_msg.login_url, post_params )
      process_html_content( res )
      @logger.debug "Response to POST: " + res
    rescue Exception => err
      @logger.error "Exception '" + err.class.to_s + "' raised in redirection_handler(): '" + err.message + "'"
      @logger.error err.backtrace.join("\n")
      return FAILED, self
    end
 
    last_msg = @wispr_messages.last
    if ( last_msg.is_a?( WisprRedirect ) )
      if ( last_msg.response_code == '0' )
        @logger.debug "Going to REDIRECTED state"
        return REDIRECTED, self
      else
        @logger.error "WisprRedirect message with #{last_msg.response_code} code"
        return FAILED, self
      end
    else
      @logger.debug "Going to LOGIN state"
      return LOGIN, self    
    end
    
  end
  
  def login_handler( object )
    # GET to LoginResultsURL

    last_msg = @wispr_messages.last
    if ( last_msg.is_a?( WisprAuthenticationReply ) || 
         last_msg.is_a?( WisprAuthenticationPollReply ))
      if ( last_msg.accepted? )
        @logger.info "Found a #{last_msg.class.to_s} message with ACCEPT code"
        @logger.debug "Going to LOGGED state"
        return LOGGED, self
      elsif ( last_msg.rejected? )
        @logger.info "Found a #{last_msg.class.to_s} message with REJECT code"
        @logger.debug "Going to REJECTED state"
        return REJECTED, self
      elsif ( last_msg.pending? )
        # pending state
        results_url = delay = nil
        @wispr_messages.reverse_each { |item|
          if ( item.is_a?( WisprAuthenticationReply ) || item.is_a?( WisprAuthenticationPollReply ) )
            if results_url.nil? && item.is_a?( WisprAuthenticationReply )
              results_url = item.login_results_url
            end
            if delay.nil? && item.is_a?( WisprAuthenticationPollReply )
              delay = item.delay
            end
          end
          break unless ( results_url.nil? || delay.nil? )
        }
        sleep( delay.to_i )
        begin
          res = @http_client.get_content( results_url )
          process_html_content( res )
          @logger.debug "Going to LOGIN state"
          return LOGIN, self
        rescue Exception => err
          @logger.error "Exception #{err.class.to_s} raised for URL '" + results_url.to_s + "' in login_handler()"
          @logger.error @wispr_messages.last.inspect
        end
      else
        # an error occured on the NAS...
        @logger.error "Got a #{last_msg.class.to_s} message with #{last_msg.response_code} code"
      end
    else
      @logger.error "Got a #{last_msg.class.to_s} message!"
    end
    return FAILED, self
  end

  def logged_handler( object )
    begin
      # GET to Logoff URL
      res = @http_client.get_content( @logoff_url )
      process_html_content( res )
      
      if (@wispr_messages.last.is_a?( WisprLogoffReply) )
        if ( @wispr_messages.last.reply_ok? )
          @logger.debug "Going to IDLE state"
          return IDLE, self
        end
      end
    rescue Exception => err
      @logger.error "Exception #{err.class.to_s} raised for URL '" + @logoff_url.to_s + "' in logged_handler()"
      @logger.error @wispr_messages.last.inspect
    end
    @logger.error "Going to FAILED state"
    return FAILED, self
  end
  
  def rejected_handler( object )
    return REJECTED, self
  end
  
  def failed_handler( object )
    return FAILED, self
  end
  
  def print_wispr_messages
    @logger.info "-----"
    @wispr_messages.each_index { |idx|
      msg = @wispr_messages[idx]
      @logger.info "#{idx.to_s}: message '#{WisprMessage::MESSAGE_TYPES[msg.message_type]}', " + \
           "code '#{WisprMessage::RESPONSE_CODES[msg.response_code]}' (class #{msg.class.to_s})"
    }
    @logger.info "-----"
  end

  # Close the client's http debug file
  def close_http_debug_file
    @http_client.close_http_debug_file
  end

end

