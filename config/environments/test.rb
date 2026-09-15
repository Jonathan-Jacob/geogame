Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = true
  config.public_file_server.enabled = true
  config.active_storage.service = :local
  config.action_mailer.raise_delivery_errors = false
  config.cache_store = :null_store
end
