#!/usr/bin/ruby -w
#
# $Id: wispr.rb,v 1.1 2005/09/30 13:22:12 simonp38 Exp $
#


require 'rexml/document'

class WisprMessage
  attr_reader :message_type, :response_code
  
  MESSAGE_TYPES = 
  {
    '100' => 'Initial redirect message',
    '110' => 'Proxy notification',
    '120' => 'Authentication notification',
    '130' => 'Logoff notification',
    '140' => 'Response to Authentication Poll',
    '150' => 'Response to Abort Login'
  }
  
  RESPONSE_CODES = 
  {
    '0' => 'No error',
    '50' => 'Login suceeded (Access ACCEPT)',
    '100' => 'Login failed (Access REJECT)',
    '102' => 'RADIUS server error/timeout',
    '105' => 'Network Admistrator Error: Does not have RADIUS enabled',
    '150' => 'Logoff succeeded',
    '151' => 'Login aborted',
    '200' => 'Proxy detection/repeat operation',
    '201' => 'Authentication pending',
    '255' => 'Access gateway internal error'
  }
  
  def initialize( xml, logger = nil )
    @message_type = REXML::XPath.first( xml, '//MessageType' ).text.to_s
    @response_code = REXML::XPath.first( xml, '//ResponseCode' ).text.to_s
  end

end

class WisprRedirect < WisprMessage
  attr_reader :access_procedure, :access_location, :location_name, \
              :login_url, :abort_login_url

  def initialize( xml, logger = nil )
    super( xml )
    if (element = REXML::XPath.first( xml, '//AccessProcedure' ) )
      @access_procedure = element.text.to_s
    elsif logger
      logger.warn "<AccessProcedure> is missing in WisprRedirect message"
    end
    if (element = REXML::XPath.first( xml, '//AccessLocation' ) )
      @access_location = element.text.to_s
    elsif logger
      logger.warn "<AccessLocation> is missing in WisprRedirect message"
    end
    if (element = REXML::XPath.first( xml, '//LocationName' ) )
      @location_name = element.text.to_s
    elsif logger
      logger.warn "<LocationName> is missing in WisprRedirect message"
    end
    @login_url = REXML::XPath.first( xml, '//LoginURL' ).text.to_s
    @abort_login_url = REXML::XPath.first( xml, '//AbortLoginURL' ).text.to_s
  end
  
end

class WisprProxy < WisprMessage
  attr_reader :next_url, :delay

  def initialize( xml, logger = nil )
    super( xml )
    if ( element = REXML::XPath.first( xml, '//NextURL' ) )
      @next_url = element.text.to_s
    end
    if ( element = REXML::XPath.first( xml, '//Delay' ) )
      @delay = element.text.to_s
    end
  end
  
end

class WisprAuthenticationReply < WisprMessage
  attr_reader :reply_message, :login_results_url, :logoff_url

  def initialize( xml, logger = nil )
    super( xml )
    if ( element = REXML::XPath.first( xml, '//ReplyMessage' ) )
	    @reply_message = element.text.to_s
    end
    if ( element = REXML::XPath.first( xml, '//LoginResultsURL' ) )
      @login_results_url = element.text.to_s
    end
    if ( element = REXML::XPath.first( xml, '//LogoffURL' ) )
      @logoff_url = element.text.to_s
    end
  end
  
  def accepted?
    @response_code == '50'
  end
  
  def rejected?
    @response_code == '100'
  end
  
  def pending?
    @response_code == '201'
  end
end

class WisprAuthenticationPollReply < WisprMessage
  attr_reader :reply_message, :delay, :logoff_url

  def initialize( xml, logger = nil )
    super( xml )
    if ( element = REXML::XPath.first( xml, '//ReplyMessage' ) )
      @reply_message = element.text.to_s
    end
    if ( element = REXML::XPath.first( xml, '//Delay' ) )
      @delay = element.text.to_s
    end
    if ( element = REXML::XPath.first( xml, '//LogoffURL' ) )
      @logoff_url = element.text.to_s
    end
  end

  def accepted?
    @response_code == '50'
  end
  
  def rejected?
    @response_code == '100'
  end
  
  def pending?
    @response_code == '201'
  end
end

class WisprLogoffReply < WisprMessage

  def initialize( xml, logger = nil )
    super( xml )
  end
  
  def reply_ok?
    @response_code == '150'
  end
end

class WisprAbortLoginReply < WisprMessage
  attr_reader :logoff_url

  def initialize( xml, logger = nil )
    super( xml )
    if ( element = REXML::XPath.first( xml, '//LogoffURL' ) )
      @logoff_url = element.text.to_s
    end
  end
  
end

class WisprMessageFactory

  # associates XML tags to Wispr classes
  STRINGS_TO_CLASSES = 
  {
    'Redirect' => WisprRedirect,
    'Proxy' => WisprProxy,
    'AuthenticationReply' => WisprAuthenticationReply,
    'AuthenticationPollReply'=> WisprAuthenticationPollReply,
    'LogoffReply' => WisprLogoffReply,
    'AbortLoginReply' => WisprAbortLoginReply
  }
  WISPR_ELEMENT = 'WISPAccessGatewayParam'
  XML_ROOT = 'wispr_root'

  def initialize( logger = nil )
    @logger = logger
  end
  
  def createWisprMessage( xml_string )
    begin
      wispr_object = nil
      
      # First check if the string contains 'WISPAccessGatewayParam' 
      # because sometimes the XML parser crashes with complex/long strings...
      regexp = Regexp.new( "#{WISPR_ELEMENT}" )
      if ( regexp.match( xml_string ).nil? )
        raise "String doesn't contain #{WISPR_ELEMENT}"
      end
  
      # Embed the string into a root element because sometimes the string 
      # contains 2 root XML elements (Otenet case)
      xml_string = "<#{XML_ROOT}>" + xml_string + "</#{XML_ROOT}>"
      xml_doc = REXML::Document.new( xml_string )
      
      raise "REXML document cannot be created" if xml_doc.nil? || xml_doc.root.nil?

      # Check that the xml document 
      if REXML::XPath.first( xml_doc, "/#{XML_ROOT}/#{WISPR_ELEMENT}").nil?
        raise "#{WISPR_ELEMENT} could not be found"
      end
    
      STRINGS_TO_CLASSES.each_pair { |name, klass|
        if ( message = REXML::XPath.first( xml_doc, "/#{XML_ROOT}/#{WISPR_ELEMENT}/#{name}" ) )
          wispr_object = klass.new( message, @logger )
          break
        end
      }
      if wispr_object.nil?
        # Unexpected type
        raise "Unexpected WISPr message type in #{xml_string}"
      end
      @logger.info wispr_object.class.to_s + " created." if ( @logger )
      wispr_object
    rescue Exception => err
      if ( @logger )
        @logger.info "Exception catched in WisprMessageFactory::createWisprMessage():"
        @logger.info "  #{err.message[0..100]}"
        @logger.info "Input string: #{xml_string[0..100]}"
        @logger.info err.backtrace.join("\n")
      end
      nil
    end
  end

end
