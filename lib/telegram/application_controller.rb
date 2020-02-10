require 'telegram/bot/updates_controller'

module Telegram
  class ApplicationController < Bot::UpdatesController
    require 'telegram/application_controller/errors'

    include Errors
    include Bot::UpdatesController::MessageContext
    include ActionView::Helpers::TextHelper

    DATA_PREFIX = 'tg://btn/'.freeze

    attr_reader :current_user

    before_action :set_current_user, :update_telegram_pref

    def params
      {payload: payload, session: session, username: payload.dig('from', 'username'), chat_id: payload.dig('from', 'id')}
    end

    def set_current_user
      @current_user ||= User
                          .joins(:preference)
                          .where('user_preferences.telegram_username = ? or user_preferences.telegram_id = ?',
                                 params[:username], params[:chat_id]).take
    end

    def version!
      respond_with(:message, text: Telegram::Bot::VERSION)
    end

    protected

    def reload_env
      Dotenv.overload
      Setting.check_cache
    end

    def encode_data(data)
      "<a href=\"#{DATA_PREFIX}#{Base64.encode64(data.to_json)}\">\u200b</a>"
    end

    def decode_data(*args, **kwargs)
      entities = params.dig(:payload, 'message', 'entities')
      return unless entities

      entity = entities.find { |entity| entity['type'] == 'text_link' && entity['url'].start_with?(DATA_PREFIX) }
      JSON.parse(Base64.decode64(entity['url'].sub(DATA_PREFIX, ''))) if entity
    end

    private

    def update_telegram_pref
      return if current_user.blank?

      if params[:chat_id].present? && current_user.pref.telegram_id != params[:chat_id]
        current_user.pref.update(telegram_id: params[:chat_id])
      end

      if params[:username].present? && current_user.pref.telegram_username != params[:username]
        current_user.pref.update(telegram_username: params[:username])
      end
    end
    
  end
end
