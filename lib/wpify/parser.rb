module Wpify
  # Parses the contents of a wp-config.php file into a Hash
  # reasonably well.
  class Parser
    # Loader
    def self.load(*args)
      load = self.new(*args)
      load.wpconfig
    end

    attr_reader :options, :files, :wpconfig

    # Provide a comma separated list or files
    # and a hash of options at the end (not yet used)
    def initialize(*args)
      @options = args.last.kind_of?(Hash) ? args.pop : Hash.new
      @files = args
      parse
    end

    # Parse all the files in @files and
    # add the configuration hash to @wpconfig
    def parse
      @wpconfig = Hash.new
      @files.each do |f|
        f = File.expand_path(f)
        next if not File.exist?(f)
        raw = File.open(f).read
        raw.scan(constant_pattern).each {|c| @wpconfig[c[0].downcase.to_sym] = c[1] }
        raw.scan(var_pattern).each {|v| @wpconfig[v[0].downcase.to_sym] = v[1] }
      end
      @wpconfig
    end

    private

    # Pattern to find $table_prefix = "wp_"; strings
    def var_pattern
      /\$(\w+)\s*=\s*['"]([^'"]+)['"]\s*;/
    end

    # Pattern to find define('DB_NAME', 'wordpress'); strings
    def constant_pattern
      /define\(\s*['"]([^'"]+)['"]\s*,\s*['"]([^'"]+)['"]\s*\)/
    end
  end
end
