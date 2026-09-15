require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)

module Geogame
  class Application < Rails::Application
    config.load_defaults 8.1
    config.autoload_lib(ignore: %w[assets tasks])

    config.i18n.available_locales = %i[de en]
    config.i18n.default_locale = :de

    # Private app: tell proxies/crawlers not to index (belt + suspenders with robots.txt + meta tags)
    config.action_dispatch.default_headers = {
      "X-Robots-Tag" => "noindex, nofollow, noarchive"
    }
  end
end
