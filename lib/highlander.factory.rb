require_relative './highlander.dsl'
require_relative './highlander.template.finder'
require 'fileutils'
require 'git'


module Highlander

  module Factory

    class Component

      attr_accessor :component_dir,
          :config,
          :highlander_dsl_path,
          :cfndsl_path,
          :highlander_dsl,
          :cfndsl_content,
          :mappings,
          :name,
          :template,
          :version,
          :distribution_bucket,
          :distribution_prefix,
          :component_files,
          :cfndsl_ext_files,
          :lambda_src_files

      def initialize(template_meta, component_name)
        @template = template_meta
        @name = component_name
        @component_dir = template_meta.template_location
        @mappings = {}
        @version = template_meta.template_version
        @distribution_bucket = nil
        @distribution_prefix = nil
        @component_files = []
        @cfndsl_ext_files = []
        @lambda_src_files = []
      end

      def load_config()
        @config = {} if @config.nil?
        Dir["#{@component_dir}/*.config.yaml"].each do |config_file|
          puts "Loading config for #{@name}:\n\tread #{config_file} "
          partial_config = YAML.load(File.read(config_file))
          unless partial_config.nil?
            @config.extend(partial_config)
            @component_files << config_file
          end
        end
      end


      def loadDepandantExt()
        @highlander_dsl.dependson_components.each do |requirement|
          requirement.component_loaded.cfndsl_ext_files.each do |file|
            cfndsl_ext_files << file
          end
        end
      end

      # @param [Hash] config_override
      def load(config_override = nil)
        if @component_dir.start_with? 'http'
          raise StandardError, 'http(s) sources not supported yet'
        end


        @highlander_dsl_path = "#{@component_dir}/#{@template.template_name}.highlander.rb"
        @cfndsl_path = "#{@component_dir}/#{@template.template_name}.cfndsl.rb"
        candidate_mappings_path = "#{@component_dir}/*.mappings.yaml"
        candidate_dynamic_mappings_path = "#{@component_dir}/#{@template.template_name}.mappings.rb"

        @cfndsl_ext_files += Dir["#{@component_dir}/ext/cfndsl/*.rb"]
        @lambda_src_files += Dir["#{@component_dir}/lambdas/**/*"].find_all {|p| not File.directory? p}
        @component_files += @cfndsl_ext_files
        @component_files += @lambda_src_files

        @config = {} if @config.nil?

        @config.extend config_override unless config_override.nil?
        @config['component_version'] = @version unless @version.nil?
        @config['component_name'] = @name
        @config['template_name'] = @template.template_name
        @config['template_version'] = @template.template_version
        # allow override of components
        # config_override.each do |key, value|
        #   @config[key] = value
        # end unless config_override.nil?

        Dir[candidate_mappings_path].each do |mapping_file|
          mappings = YAML.load(File.read(mapping_file))
          @component_files << mapping_file
          mappings.each do |name, map|
            @mappings[name] = map
          end unless mappings.nil?
        end

        if File.exist? candidate_dynamic_mappings_path
          require candidate_dynamic_mappings_path
          @component_files << candidate_dynamic_mappings_path
        end

        # 1st pass - parse the file
        @component_files << @highlander_dsl_path
        @highlander_dsl = eval(File.read(@highlander_dsl_path), binding)
        # set version if not defined
        @highlander_dsl.ComponentVersion(@version) unless @version.nil?


        if @highlander_dsl.description.nil?
          if template.template_name == @name
            description = "#{@name}@#{template.template_version} - v#{@highlander_dsl.version}"
          else
            description = "#{@name} - v#{@highlander_dsl.version}"
            description += " (#{template.template_name}@#{template.template_version})"
          end

          @highlander_dsl.Description(description)
        end

        # set (override) distribution options
        @highlander_dsl.DistributionBucket(@distribution_bucket) unless @distribution_bucket.nil?
        @highlander_dsl.DistributionPrefix(@distribution_prefix) unless @distribution_prefix.nil?

        if File.exist? @cfndsl_path
          @component_files << @cfndsl_path
          @cfndsl_content = File.read(@cfndsl_path)
          @cfndsl_content.strip!
          # if there is CloudFormation do [content] end extract only contents
          ### Regex \s is whitespace
          match_data = /^CloudFormation do\s(.*)end\s?$/m.match(@cfndsl_content)
          if not match_data.nil?
            @cfndsl_content = match_data[1]
          end

        else
          @cfndsl_content = ''
        end

        loadDepandantExt()
      end
    end

    class ComponentFactory

      attr_accessor :component_sources


      def initialize(component_sources = [])
        @template_finder = Highlander::Template::TemplateFinder.new(component_sources)
      end

      # Find component and given list of sources
      # @return [Highlander::Factory::Component]
      def loadComponentFromTemplate(template_name, template_version = nil, component_name = nil)

        template_meta = @template_finder.findTemplate(template_name, template_version)

        raise StandardError, "highlander template #{template_name}@#{component_version_s} not located" +
            " in sources #{@component_sources}" if template_meta.nil?

        return buildComponentFromLocation(template_meta, component_name)

      end


      def buildComponentFromLocation(template_meta, component_name)
        component = Component.new(template_meta, component_name)
        component.load_config
        return component
      end

    end
  end

end
