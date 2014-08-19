module Representable
  module Declarative
    def representable_attrs
      @representable_attrs ||= build_config
    end

    def representable_hooks
      @representable_hooks ||= {}
    end

    def representation_wrap=(name)
      representable_attrs.wrap = name
    end

    def collection(name, options={}, &block)
      options[:collection] = true # FIXME: don't override original.
      options[:default] ||= []
      options[:class] ||= Representable.config.try(:collection_class)

      class_name = "#{name.to_s.singularize}_representer".classify
      options[:extend] ||= class_name.constantize if class_exists?(class_name) && !block_given?

      property(name, options, &block)
    end

    def hash(name=nil, options={}, &block)
      return super() unless name  # allow Object.hash.

      options[:hash] = true
      property(name, options, &block)
    end

    # Allows you to nest a block of properties in a separate section while still mapping them to the outer object.
    def nested(name, options={}, &block)
      options = options.merge(
        :use_decorator => true,
        :getter        => lambda { |*| self },
        :setter        => lambda { |*| },
        :instance      => lambda { |*| self }
      ) # DISCUSS: should this be a macro just as :parse_strategy?

      property(name, options, &block)
    end

    def property(name, options={}, &block)
      base     = nil

      if eval = options[:eval]
        representable_hooks[:eval] ||= []

        representable_hooks[:eval] << -> {
          case eval.parameters.size
            when 0
              send("#{name}=", instance_exec(&eval))
            when 1
              send("#{name}=", instance_exec(send("#{name}"),&eval))
          end
        }
      end

      if set = options[:set]
        representable_hooks[:set] ||= []
        representable_hooks[:set] << set
      end

      if options[:inherit] # TODO: move this to Definition.
        base = representable_attrs.get(name).representer_module
      end # FIXME: can we handle this in super/Definition.new ?

      if block_given?
        options[:_inline] = true
        options[:extend]  = inline_representer_for(base, representable_attrs.features, name, options, &block)
      end

      representable_attrs.add(name, options) # handles :inherit.
    end

    def after &block
      representable_hooks[:after] = block
    end

    def build_inline(base, features, name, options, &block) # DISCUSS: separate module?
      Module.new do
        include *features # Representable::JSON or similar.
        include base if base # base when :inherit, or in decorator.

        instance_exec &block
      end
    end

  private
    def class_exists?(class_name)
      klass = Module.const_get(class_name)
      return true
    rescue NameError
      return false
    end

    def inline_representer_for(base, features, name, options, &block)
      representer = options[:use_decorator] ? Decorator : self

      representer.build_inline(base, features.reverse, name, options, &block)
    end

    def build_config
      Config.new
    end
  end # Declarations
end
