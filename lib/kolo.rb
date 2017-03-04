require 'json'
require 'rack'
require 'nest'
require 'ohm_util'

class Kolo
  def initialize(&block)
    instance_eval(&block)
  end

  def self.redis; @redis = settings[:redis] || Redic.new end
  def self.settings; @settings ||= {} end

  def self.application(&block)
    @app = new(&block) 
  end

	def self.call(env)
    @app.call(env)
	end

  def routes; @routes ||= {} end

  def resources(name, &block)
    routes[name] = Resource.factor(&block)
  end

  def call(env)
    request = Rack::Request.new(env)
    seg = Seg.new(request.path_info)
    
    inbox = {}
    resource = nil 
    while seg.capture(:segment, inbox)
      segment = inbox[:segment].to_sym

      if resource.nil? && klass = routes[segment] 
        resource = klass.new(segment)
      elsif resource.run(segment)
      end
    end
    
    return resource.render(request)
  end

  class Resource 
    attr :status
    
    def id; @id end

    # status code sytax suger
    def ok;                    @status = 200 end
    def created;               @status = 201 end
    def no_cotent;             @status = 204 end
    def bad_request;           @status = 400 end
    def not_found;             @status = 404 end
    def internal_server_error; @status = 500 end
    def not_implemented;       @status = 501 end
    def bad_gateway;           @status = 502 end

    def run(segment)  
      if !defined?(@element_name) && element = self.class.elements[segment]
        @element_name = segment
        return instance_eval(&element)
      elsif !defined?(@bulk_name) && bulk = self.class.bulks[segment] 
        @bulk_name = segment
				
        return instance_eval(&bulk)
      end
      @id = segment
      load!
    end

    def render(request)
      # throw out error if method not found
      return unless method_block = @request_methods[request.request_method]
      
      execute( request.params, &method_block)
      ok if status.nil?
      [status, {}, [to_json]]
    end

    def execute(params)
      if @id.nil?

      else

      end
      yield params
    end

    def self.factor(&block)
      klass = dup
      klass.class_eval(&block)
      klass 
    end

    def initialize(name)
      @resource_name = name
      @attributes = Hash[self.class.attributes.map{|key| [key, nil]}]
      @status = nil 
      default_actions
    end

    def self.attribute(name)
      attributes << name unless attributes.include? name
      define_method(name) do 
        @attributes[name]
      end
      define_method(:"#{name}=") do |value|
        @attributes[name] = value
      end
    end
    
    def self.attributes; @attributes ||= [] end
    
    def self.bulks; @bulks ||= {} end

    def self.bulk(name, &block)
      bulks[name] = block
    end
    
    def self.elements; @elements ||= {} end
    
    def self.element(name, &block)
      elements[name] = block
    end
    
    def load!
      update_attributes(Hash[*key[id].call("HGETALL")])
    end

    def update_attributes(atts)
      @attributes.each do |key, value|
        attributes[key] = atts[key.to_s] if atts.has_key?(key.to_s)
      end
    end

    def save
      feature = {name: @resource_name}
      feature["id"] = @id if defined?(@id)
      @id = OhmUtil.script( redis,
                            OhmUtil::LUA_SAVE,
                            0,
                            feature.to_json,
                            serialize_attributes.to_json,
                            {}.to_json,
                            {}.to_json)
    end  

    def attributes; @attributes end

    private 
      def redis; Kolo.redis end
      def key;   @key ||= Nest.new(@resource_name, redis) end

      def serialize_attributes
        result = []
        
        attributes.each do |key, value| 
          result.push(key, value.to_s) if value
        end

        result
      end

      def show(&block);   @request_methods['GET']    = block end
      def create(&block); @request_methods['POST']   = block end
      def update(&block); @request_methods['PUT']    = block end
      def delete(&block); @request_methods['DELETE'] = block end
      
      def default_actions
        @request_methods = {} 

        show do |params|
        end

        create do |params|
          update_attributes(params)
          save
          created
        end
      end

      def []
        attributes 
      end

      def to_json
        JSON.dump(attributes.merge({id: id}))
      end 
  end
end
