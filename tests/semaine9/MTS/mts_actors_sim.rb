#.....................................
# (c) jean-christophe le lann 2008
#  ENSTA Bretagne
#.....................................

require 'fiber'
require 'pp'
require_relative "mts_types"

module MTS

  # reopen classes for simulation purposes
  class Port
    def recv()
      @channel.recv()
    end

    def send(data)
      @channel.send(data)
    end
  end

  class TaggedValue
    attr_accessor :time,:value
    def initialize time,val
      @time,@value=time,val
    end
  end

  class Actor
    attr_reader :state
    attr_reader :executed_steps
    attr_accessor :log, :vars, :varsTypes

    # def behavior
    # end

    def increment_time inc
      @log[:time] << now+inc
    end

    def set_time time
      @log[:time] << time
    end

    def now
      @log[:time].last
    end

    def log_data data,value
      @log[data]||=[]
      @log[data] << {now => value}
    end

    def fix_current_time_with time
      current_time=(time<=now) ? nil : [time,now].max
      if current_time #not nil
        puts "fixing time for causality. Was : #{time} <= #{now} !"
        @log[:time].pop
        set_time current_time
      end
    end

    def register sym, var
      puts "REGISTER(#{sym}, #{var}) ==> #{var.class}"
      @varsTypes ||= {}
      @vars ||= {}

      #@varsTypes[sym] ||= nil
      @vars[sym] ||= nil

      @varsTypes[sym] = TypeFactory.create(@vars[sym],var)
    end

    def send!(data, port)
      puts "SEND(#{data}, #{port})! CALLED"
      cEntity = @name.to_sym
      cClass = self.class.to_s.to_sym

      # 1/ write the value in the correspondig symbol
  		DATA.inouts[cClass].each do |hash|
  			if hash[:symbol] == port

            pValue = hash[:value] # will be nil if doesnt exist yet
            hash[:value] = data
            typeObj = TypeFactory.create pValue, data
            hash[:typeObj] = typeObj
            hash[:type] = typeObj.cpp_signature

  			end
  		end

  		# 2/ write it to the symbols that are connected to the previous one
  		DATA.connexions.each do |connexion|
  			if ( connexion[0][:ename] == cEntity )  &&  ( connexion[0][:port] == port )
  				# then repeat 1/ on the connected symbol (might happen more than once if multiple connexions)
  				DATA.inouts[ connexion[1][:cname] ].each do |hash|
  					if hash[:symbol] == connexion[1][:port]

                pValue = hash[:value] # will be nil if doesnt exist yet
                hash[:value] = data
                typeObj = TypeFactory.create pValue, data
                hash[:typeObj] = typeObj
                hash[:type] = typeObj.cpp_signature

  					end
  				end
  			end
  		end

      @ports[port].send TaggedValue.new(now,data)
      increment_time(1)
    end

    def receive?(port)
      puts "RECEIVE(#{port})! CALLED"
      tagged_value = @ports[port].recv()
      fix_current_time_with(tagged_value.time)
      return tagged_value.value
    end

    def init
      @state = :IDLE
      @executed_steps=0
      @history=[]
      @log={:time=>[0]}
    end

    def wait #clock barrier
      Fiber.yield("WAIT_#{self.name}")
    end

    def start
      @fiber = Fiber.new {
        self.method(:behavior).call
        @state = :ENDED
      }
      puts " - actor #{self.name} ready"
    end

    def step
      @state = @fiber.resume
      @executed_steps+=1
      @state
    end

  end

  class CspChannel < Channel

    def recv
      sender=self.sender.actor.name.upcase
      state="RECV_STATE_#{sender}".to_sym
      Fiber.yield(state) until (data=@data)
      @data = nil
      data #[t,value]
    end

    def send_(data)
      Fiber.yield(:SEND_STATE) while @data
      @data = data
    end
  end

  class KpnChannel < Channel

    def recv
      sender=self.sender.actor.name.upcase #OR .receiver ????
      state="RECV_STATE_#{sender}".to_sym
      Fiber.yield(state) until (data=@fifo.shift)
      data
    end

    def send(data)
      receiver=self.receiver.actor.name.upcase #OR .sender ????
      state="SEND_STATE_#{receiver}".to_sym
      Fiber.yield(state) while @fifo.size >= @capacity
      @fifo.push data
    end
  end

  class WireChannel < Channel

    def read
    end

    def write(data)
    end
  end

  class System
    attr_reader :log
  end
end #MTS
