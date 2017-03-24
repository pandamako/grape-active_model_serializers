module Grape
  module Formatter
    module ActiveModelSerializers
      class << self
        def call(resource, env)
          serializer = fetch_serializer(resource, env)

          if serializer
            serializer.to_json
          else
            Grape::Formatter::Json.call resource, env
          end
        end

        def fetch_serializer(resource, env)
          endpoint = env['api.endpoint']
          options = build_options_from_endpoint(endpoint)
          ams_options = {}.tap do |ns|
            # Extracting declared version from Grape
            ns[:namespace] = options[:version].try(:classify) if options.try(:[], :version)
          end

          serializer = from_options options, serializer_klass(resource, options)
          return nil unless serializer

          options[:scope] = endpoint unless options.key?(:scope)
          # ensure we have an root to fallback on
          options[:resource_name] = default_root(endpoint) if resource.respond_to?(:to_ary)
          serializer.new(resource, options.merge(other_options(env)))
        end

        def other_options(env)
          options = {}
          ams_meta = env['ams_meta'] || {}
          meta = ams_meta.delete(:meta)
          meta_key = ams_meta.delete(:meta_key)
          options[:meta_key] = meta_key if meta && meta_key
          options[meta_key || :meta] = meta if meta
          options
        end

        def build_options_from_endpoint(endpoint)
          [endpoint.default_serializer_options || {}, endpoint.namespace_options, endpoint.route_options, endpoint.options, endpoint.options.fetch(:route_options)].reduce(:merge)
        end

        # array root is the innermost namespace name ('space') if there is one,
        # otherwise the route name (e.g. get 'name')
        def default_root(endpoint)
          innermost_scope = if endpoint.respond_to?(:namespace_stackable)
                              endpoint.namespace_stackable(:namespace).last
                            else
                              endpoint.settings.peek[:namespace]
                            end

          if innermost_scope
            innermost_scope.space
          else
            endpoint.options[:path][0].to_s.split('/')[-1]
          end
        end

        def serializer_klass resource, options
          serializer_class = resource_defined_class resource
          serializer_class ||= namespace_inferred_class resource, options
          serializer_class ||= version_inferred_class resource, options
          serializer_class ||= resource_serializer_klass resource
          serializer_class
        end

        def from_options options, default_serializer
          return default_serializer unless options[:serializer]
          if options[:serializer].respond_to? :call
            options[:serializer].call
          else
            options[:serializer]
          end
        end

        def resource_defined_class resource
          resource.serializer_class if resource.respond_to?(:serializer_class)
        end

        def version_inferred_class resource, options
          klass = resource_serializer_klass(resource)
          return unless klass
          "#{version(options)}::#{klass}".safe_constantize
        end

        def version options
          options[:version].try(:classify)
        end

        def resource_serializer_klass resource
          ActiveModel::Serializer.serializer_for(resource)
        end

        def namespace_inferred_class resource, options
          return nil unless options[:for]
          namespace = options[:for].to_s.deconstantize
          klass = resource_serializer_klass(resource)
          return unless klass
          "#{namespace}::#{klass}".safe_constantize
        end
      end
    end
  end
end
