
Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :payments, only: [:create, :show, :index] do
        member do
          delete :cancel
        end
      end
    end
  end

  # Sidekiq Web UI (protect in production)
  # require "sidekiq/web"
  # mount Sidekiq::Web => "/sidekiq"
end