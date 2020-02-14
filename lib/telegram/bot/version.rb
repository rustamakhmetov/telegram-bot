module Telegram
  module Bot
    VERSION = '0.14.8'.freeze

    def self.gem_version
      Gem::Version.new VERSION
    end

    module_function

    def version
      VERSION
    end
  end
end
