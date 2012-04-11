##
# Copyright (c) 2009 Rahmal Conda <rahmal@gmail.com>
#
# This class parses key/value based properties files used for configuration.
# It is used by rconfig to import configuration files of the aforementioned
# format. Unlike yaml, and xml files it can only support three levels. First,
# it can have root level properties:
#
#            server_url=host.domain.com
#            server_port=8080
#
# Secondly, it can have properties grouped into catagories. The group names
# must be specified within brackets like [ ... ]
#
#            [server]
#            url=host.domain.com
#            port=8080
#
# Finally, groups can also be qualified with namespaces, similar to git 
# config files. Group names are same as before, but with namespace in
# within the brackets like [ <group> "<name>" ]
#
#            [host "dev"]
#            domain=dev.server.com
#
#            [host "prod"]
#            domain=www.server.com
#
# These can be retrieved using dot-notation or variable to do it dynamically.
#
#            RConfig.props.host.dev.domain
#                      - or -
#            RConfig.props.host[env].domain  (where env is 'dev' or 'prod')
#
module RConfig
  class PropertiesFileParser
    include Singleton # Don't instantiate this class

    COMMENT = /^\#/
    KEYVAL  = /\s*=\s*/
    QUOTES  = /^['"](.*)['"]$/
    GROUP   = /^\[(.+)\]$/
    NAMEGRP = /^\[(.+) \"(.+)\"\]$/
    KEY_REF = /(.+)?\%\{(.+)\}(.+)?/

    ##
    # Parse config file and import data into hash to be stored in config.
    #
    def self.parse(config_file)
      raise ArgumentError, 'Invalid config file name.' unless config_file

      config = {}

      # The config is top down.. anything after a [group] gets added as part
      # of that group until a new [group] is found.  
      group, topgrp = nil
      config_file.each do |line|   # for each line in the config file
        line.strip!
        unless COMMENT.match(line) # skip comments (lines that state with '#')
          if KEYVAL.match(line)    # if this line is a config property
            key, val = line.split(KEYVAL, 2) # parse key and value from line
            key = key.chomp.strip
            val = val.chomp.strip
            if val
              if val =~ QUOTES # if the value is in quotes
                value = $1     # strip out value from quotes
              else
                value = val    # otherwise, leave as-is
              end
            else
              value = ''       # if value was nil, set it to empty string
            end

            if topgrp                                # If there was a top-level named group, then there must be a group.
              config[topgrp][group][key] = value     # so add the prop to the named group
            elsif group                              # if this property is part of a group
              config[group][key] = value             # then add it to the group
            else                                     # otherwise... 
              config[key] = value                    # add the prop to top-level config
            end

          elsif match = NAMEGRP.match(line) # This line is a named group (i.e. [env "test"], [env "qa"], [env "production"])
            topgrp, group = match.to_a[1..-1] # There can be multiple groups within a single top-level group
            config[topgrp] ||= {} # add group to top-level group
            config[topgrp][group] ||= {} # add name of group as subgroup (properties are added to subgroup)

          elsif match = GROUP.match(line) # if this line is a config group
            group = match.to_a[1] # parse the group name from line
            topgrp = nil # we got a new group with no namespace, so reset topgrp
            config[group] ||= {} # add group to top-level config
          end
        end
      end

      # Pre-populate the values that refer to other properties
      # Example:
      #   root_path = /path/to/root
      #   image_path = %{root_path}/images
      config = parse_references(config)

      config # return config hash
    end # def parse
  
    ##
    # Recursively checks all the values in the hash for references to other properties,
    # and replaces the references with the actual values.  The syntax for referring to 
    # another property in the config file is the ley of the property wrapped in curly
    # braces, preceded by a percent sign.  If the property is in a group, then the full 
    # namespace must be used.
    #
    # Example:
    #   root_path = /path/to/root             # In this property file snippet 
    #   image_path = %{root_path}/images      # image path refers to root path
    #
    #
    def self.parse_references hash, config=nil
      config ||= hash.dup

      hash.each do |key, val|
        case val
        when Hash
          hash[key] = parse_references(val, config)
        when String
          pre, ref, post = KEY_REF.match(val).to_a[1..-1]
          hash[key] = if ref
              ref = ref.split('.').inject(config){|c,i| c && c[i] }
              [pre, ref, post].join              
            else
              val
            end         
        end
      end

      hash
    end # def parse_references

  end # class PropertiesFileParser
end # module RConfig
