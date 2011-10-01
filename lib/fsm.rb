#!/usr/bin/ruby -w
#
# $Id: fsm.rb,v 1.1 2005/09/30 13:22:12 simonp38 Exp $
#

class FSM
  def initialize
    @handlers    = {}
    @start_state = nil
    @end_states  = []
  end

  # Note: last statement of handler() block should be 'return state, handler'
  def add_state(name, end_state = nil, &handler)
    name = name.to_s.intern
    @handlers[name] = handler
    @end_states.push(name) if end_state
  end

  def set_start(name)
    @start_state = name.to_s.intern
  end
  
  def run(cargo)
    if not (handler = @handlers[@start_state])
      raise "Must call set_start() before run()."
    end
    raise "At least one state must be an end_state." if @end_states.empty?

    new_state = nil
    loop do
      current_state = new_state
      new_state, cargo = handler.call(cargo)
      break if @end_states.include?(new_state)
      handler = @handlers[new_state]
      raise "No handler defined for state #{new_state}" unless handler
    end
    return new_state
  end
end