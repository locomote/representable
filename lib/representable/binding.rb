require "representable/deserializer"
require "representable/serializer"

module Representable
  # The Binding wraps the Definition instance for this property and provides methods to read/write fragments.
  class Binding
    class FragmentNotFound
    end

    def self.build(definition, *args)
      # DISCUSS: move #create_binding to this class?
      return definition.create_binding(*args) if definition[:binding]
      build_for(definition, *args)
    end

    def initialize(definition, represented, decorator, user_options={})  # TODO: remove default arg for user options.
      @definition = definition
      @represented  = represented
      @decorator    = decorator
      @user_options = user_options

      setup_exec_context!
    end

    attr_reader :user_options, :represented # TODO: make private/remove.

    def as # DISCUSS: private?
      evaluate_option(:as)
    end

    # Retrieve value and write fragment to the doc.
    def compile_fragment(doc)
      evaluate_option(:writer, doc) do
        value = render_filter(get)
        write_fragment(doc, value)
      end
    end

    # Parse value from doc and update the model property.
    def uncompile_fragment(doc)
      evaluate_option(:reader, doc) do
        read_fragment(doc) do |value|
          value = parse_filter(value)
          set(value)
          value
        end
      end.tap do |value|
        if eval = @definition[:eval]
          setter_name = setter.to_sym
          lam = -> {
            case eval.parameters.size
              when 0
                send(setter_name, instance_exec(&eval))
              when 1
                send(setter_name, instance_exec(value, &eval))
            end
          }
          Representable.hooks[:eval] ||= []
          Representable.hooks[:eval] << -> { exec_context.instance_exec(&lam) }
        end
      end
    end

    def write_fragment(doc, value)
      value = default_for(value)

      write_fragment_for(value, doc)
    end

    def write_fragment_for(value, doc)
      return if skipable_empty_value?(value)
      write(doc, value)
    end

    def read_fragment(doc)
      value = read_fragment_for(doc)

      if value == FragmentNotFound
        return unless has_default?
        value = self[:default]
      end

      yield value
    end

    def read_fragment_for(doc)
      read(doc)
    end

    def render_filter(value)
      evaluate_option(:render_filter, value) { value }
    end

    def parse_filter(value)
      evaluate_option(:parse_filter, value) { value }
    end

    def get
      evaluate_option(:getter) do
        exec_context.send(getter)
      end
    end

    def set(value)
      evaluate_option(:setter, value) do
        if type = @definition[:type]
          cls = type.is_a?(Symbol) ? Kernel.const_get(type.to_s.classify) : type
          value = if cls.respond_to? :new
            cls.new(value)
          else
            cls(value)
          end
        end

        return if @definition[:eval]

        if set = @definition[:set]
          exec_context.instance_exec(value, &set) if set
        else
          exec_context.send(setter, value)
        end
      end
    end

    # DISCUSS: do we really need that?
    def representer_module_for(object, *args)
      evaluate_option(:extend, object) # TODO: pass args? do we actually have args at the time this is called (compile-time)?
    end

  private
    # Apparently, SimpleDelegator is super slow due to a regex, so we do it
    # ourselves, right, Jimmy?
    def method_missing(*args, &block)
      @definition.send(*args, &block)
    end

    def setup_exec_context!
      context = represented
      context = self        if self[:exec_context] == :binding
      context = decorator   if self[:exec_context] == :decorator

      @exec_context = context
    end

    attr_reader :exec_context, :decorator

    # Evaluate the option (either nil, static, a block or an instance method call) or
    # executes passed block when option not defined.
    def evaluate_option(name, *args)
      unless proc = self[name]
        return yield if block_given?
        return
      end

      # TODO: it would be better if user_options was nil per default and then we just don't pass it into lambdas.
      options = self[:pass_options] ? Options.new(self, user_options, represented, decorator) : user_options

      proc.evaluate(exec_context, *(args << options)) # from Uber::Options::Value.
    end

    # Options instance gets passed to lambdas when pass_options: true.
    # This is considered the new standard way and should be used everywhere for forward-compat.
    Options = Struct.new(:binding, :user_options, :represented, :decorator)


    # Delegates to call #to_*/from_*.
    module Object
      def serialize(object)
        ObjectSerializer.new(self, object).call
      end

      def deserialize(data)
        # DISCUSS: does it make sense to skip deserialization of nil-values here?
        ObjectDeserializer.new(self).call(data)
      end

      def create_object(fragment, *args)
        instance_for(fragment, *args) or class_for(fragment, *args)
      end

    private
      # DISCUSS: deprecate :class in favour of :instance and simplicity?
      def class_for(fragment, *args)
        item_class = class_from(fragment, *args) or raise DeserializeError.new(":class did not return class constant.")
        item_class.new
      end

      def class_from(fragment, *args)
        evaluate_option(:class, fragment, *args)
      end

      def instance_for(fragment, *args)
        # cool: if no :instance set, { return } will jump out of this method.
        evaluate_option(:instance, fragment, *args) { return } or raise DeserializeError.new(":instance did not return object.")
      end
    end
  end


  class DeserializeError < RuntimeError
  end
end
