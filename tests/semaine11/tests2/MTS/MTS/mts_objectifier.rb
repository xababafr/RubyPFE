require_relative "./mts_objects"

module NMTS
  class Analyzer
    attr_reader :ast,:sys, :behaviors, :methods_code_h

    def evaluate filename
      rcode=IO.read(filename)
      eval(rcode)
    end

    def open filename
      @behaviors = []
      @filename=filename
      @sys=evaluate(filename)
      @ast=parse()
      build_hash_code_for_classes # @class_code_h[:Sensor]=...

      pp @class_code_h

      #puts "HASH FOR CLASSES"
      #pp @class_code_h
      @class_code_h.keys.each do |klass|
        get_methods klass
      end
      #puts "HASH FOR METHODS"
      #pp @methods_code_h
    end

    def get_actor_classes
      classes_code={}
      recursive_code_for_class
    end

    def parse
      Parser::CurrentRuby.parse(File.open(@filename, "r").read)
    end

    def build_hash_code_for_classes
      rec_build_hash_code_for_classes @ast
    end

    def rec_build_hash_code_for_classes ast
      ast.children.each do |child|
        if child.class.to_s == "Parser::AST::Node"
          if child.type.to_s == "class"
            class_name=child.children[0].children[1]
            @class_code_h||={}
            @class_code_h[class_name]=child
          else
            rec_build_hash_code_for_classes child
          end
        end
      end
    end

    def get_methods klass
      @methods_code_h ||= {}
      rec_get_methods @class_code_h[klass], klass
    end

    def rec_get_methods node, klass
      node.children.each do |child|
        next unless child.class.to_s == "Parser::AST::Node"
        if (child.type==:def)
          @methods_code_h[ [klass, child.children[0]] ] = child
        else
          rec_get_methods child, klass unless (child == nil)
        end
      end
    end

  end


  class Objectifier

    # the onky goal of this class is to give access to these two accessors

    attr_accessor :methods_ast, :methods_objects

    def initialize filename
      analyzer = Analyzer.new
      analyzer.open filename

      @methods_ast = analyzer.methods_code_h
      @methods_objects = {}
      @methods_ast.keys.each do |key|
        parse_method @methods_ast[ [key[0],key[1]] ], key
      end
    end

    def parse_body body, bodyWrapper = false
      puts "PARSE_BODY(#{caller_locations(1,1)[0].label})"
      if body != nil && body.type==:begin
        stmts=body.children.collect{|stmt| to_object(stmt)}
      else
        stmts=[]
        stmts << to_object(body)
      end
      Body.new(stmts, bodyWrapper)
    end

    def parse_method sexp, key
      name,args,body=*sexp.children[0..2]
      args=args.children.collect{|e| e.children.first}
      body=parse_body(body, true)
      met = Method.new(name,args,body)
      @methods_objects[key] = met
    end

    def to_object sexp
      return sexp unless sexp.is_a? Parser::AST::Node
      case sexp.type
      when :begin
        Convert::node( parse_body(sexp) )
      when :lvasgn
        Convert::node( parse_assign(sexp,:local) )
      when :ivasgn
        Convert::node( parse_assign(sexp,:instance) )
      when :op_asgn
        Convert::node( parse_op_assign(sexp) )
      when :if
        Convert::node( parse_if(sexp) )
      when :while
        Convert::node( parse_while(sexp) )
      when :for
        Convert::node( parse_for(sexp) )
      when :case
        Convert::node( parse_case(sexp) )
      when :and
        Convert::node( parse_and(sexp) )
      when :or
        Convert::node( parse_or(sexp) )
      when :when
        Convert::node( parse_when(sexp) )
      when :true
        Convert::node( parse_true(sexp) )
      when :false
        Convert::node( parse_false(sexp) )
      when :send
        Convert::node( parse_send(sexp) )
      when :block
        Convert::node( parse_block(sexp) )
      when :args
        Convert::node( parse_args(sexp) )
      # seems like ivar and lvar are the same for us?
      when :ivar
        Convert::node( parse_ivar(sexp) )
      when :lvar
        Convert::node( parse_lvar(sexp) )
      when :int
        Convert::node( parse_int(sexp) )
      when :float
        Convert::node( parse_float(sexp) )
      when :str
        Convert::node( parse_str(sexp) )
      when :return
        Convert::node( parse_return(sexp) )
      when :super
        Convert::node( parse_super(sexp) )
      when :irange
        Convert::node( parse_irange(sexp) )
      when :erange
        Convert::node( parse_erange(sexp) )
      when :array
        Convert::node( parse_array(sexp) )
      when :hash
        Convert::node( parse_hash(sexp) )
      when :regexp
        Convert::node( parse_regexp(sexp) )
      when :const
        Convert::node( parse_const(sexp) )
      when :sym
        Convert::node( parse_sym(sexp) )
      when :dstr
        Convert::node( parse_dstr(sexp) )
      else
        #raise "NIY : #{sexp.type} => #{sexp}"
        Unknown.new sexp
      end
    end

    def parse_int sexp
      IntLit.new(sexp.children.first)
    end

    def parse_float sexp
      FloatLit.new(sexp.children.first)
    end

    def parse_str sexp
      StrLit.new(sexp.children.first)
    end

    def parse_return sexp
      Return.new(to_object sexp.children.first)
    end

    def parse_irange sexp
      lhs,rhs=*sexp.children[0..1].collect{|stmt| to_object(stmt)}
      IRange.new(lhs,rhs)
    end

    def parse_erange sexp
      lhs,rhs=*sexp.children[0..1].collect{|stmt| to_object(stmt)}
      ERange.new(lhs,rhs)
    end

    def parse_ivar sexp
      IVar.new(sexp.children.first)
    end

    def parse_lvar sexp
      LVar.new(sexp.children.first)
    end

    def parse_true sexp
      TrueLit.new()
    end

    def parse_false sexp
      FalseLit.new()
    end

    def parse_op_assign sexp
      lhs,mid,rhs=*sexp.children[0..2].collect{|stmt| to_object(stmt)}
      OpAssign.new(lhs,mid,rhs)
    end

    def parse_assign sexp,locality
      lhs,rhs=*sexp.children[0..1].collect{|stmt| to_object(stmt)}
      Assign.new(lhs,rhs)
    end

    def parse_if sexp
      cond,body,else_=sexp.children.collect{|e| to_object(e)}
      # happens if only one line of code is in the body of the if
      pp body
      if !body.is_a?(Body)
        b = body.dup
        body = Body.new([b])
      end
      if !else_.is_a?(Body)
        e = else_.dup
        else_ = Body.new([e])
      end
      body.wrapperBody = true
      else_.wrapperBody = true
      If.new(cond,body,else_)
    end

    def parse_and sexp
      pp sexp.children
      lhs,rhs = sexp.children.collect{|e| to_object(e)}
      And.new(lhs,rhs)
    end

    def parse_or sexp
      lhs,rhs = sexp.children.collect{|e| to_object(e)}
      Or.new(lhs,rhs)
    end

    def parse_while sexp
      cond,body=sexp.children.collect{|e| to_object(e)}
      # happens if only one line of code is in the body of the while
      pp body
      if !body.is_a?(Body)
        b = body.dup
        body = Body.new([b])
      end
      body.wrapperBody = true
      While.new(cond,body)
    end

    def parse_for sexp
      idx,range,body=sexp.children.collect{|e| to_object(e)}
      # happens if only one line of code is in the body of the for
      pp body
      if !body.is_a?(Body)
        b = body.dup
        body = Body.new([b])
      end
      body.wrapperBody = true
      range.idx = idx.lhs unless (idx.nil? || idx.lhs.nil?)
      For.new(idx,range,body)
    end

    def parse_case sexp
      pp sexp
      elems=sexp.children.collect{|e| to_object(e)}
      expr=elems.shift
      whens=elems.select{|e| e.is_a? MTS::When}
      else_=elems.pop
      Case.new(expr,whens,else_)
    end

    def parse_super sexp
      args = sexp.children.collect{|e| to_object(e)}
      Super.new(args)
    end

    def parse_when sexp
      expr,body=sexp.children.collect{|e| to_object(e)}
      When.new(expr,body)
    end

    def parse_send sexp
      caller,method,args=to_object(sexp.children[0]), to_object(sexp.children[1]), []
      (sexp.children.size-2).times do |i|
        args << to_object(sexp.children[i+2])
      end
      MCall.new(caller,method,args)
    end

    def parse_block sexp
      #caller,method,args=*sexp.children.collect{|e| to_object(e)}
      puts "BLOCKBLOCK"
      pp sexp
      #pp sexp.children
      caller,args,body=sexp.children.collect{|e| to_object(e)}
      Block.new(caller,args,body)
    end

    def parse_args sexp
      Args.new(sexp.children)
    end

    def parse_array sexp
      elements=*sexp.children.collect{|e| to_object(e)}
      Ary.new(elements)
    end

    def parse_hash sexp
      Hsh.new()
    end

    def parse_regexp sexp
      RegExp.new
    end

    def parse_const sexp
      Const.new sexp.children
    end

    def parse_sym sexp
      Sym.new sexp.children.first
    end

    def parse_dstr sexp
      elements=*sexp.children.collect{|e| to_object(e)}
      Dstr.new(elements)
    end

  end
end
