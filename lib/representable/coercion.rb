require "virtus"

module Representable
  module Coercion
    class Coercer
      def call(value, options)
        Virtus::Attribute.build(options.binding[:type]).coerce(value)
      end
    end


    def self.included(base)
      base.class_eval do
        extend ClassMethods
        register_feature Coercion
      end
    end


    module ClassMethods
      def property(name, options={})
        return super unless type = options[:type]

        options = options.merge(
          :pass_options  => true,
          :render_filter => coercer = Pipeline[Coercer.new],
          :parse_filter  => coercer
        )

        super
      end
    end
  end
end
