require 'singleton'

module MTS

  # globals for the module
  class MetaData
    attr_accessor :contexts, :currentContext, :returnTypes, :methods, :signatures
    include Singleton

    def initialize
      @contexts, @currentContext, @methods, @returnTypes, @signatures = nil, nil, nil, nil, nil
    end
  end

  DATA = MetaData.instance
  DATA.signatures = {
    # the key is the name of the class . the name of the method
    # the value is a hash of inputs to outputs types
    "MTS::FloatLit.*" => {
      ["MTS::IntLit"] => "MTS::FloatLit"
    },
    "MTS::IntLit.+" => {
      ["MTS::IntLit"] => "MTS::IntLit"
    },
    "MTS::FloatLit.+" => {
      ["MTS::IntLit"] => "MTS::FloatLit",
      ["MTS::FloatLit"] => "MTS::FloatLit",
    },
  }

end
