module Telegram
  class ApplicationController
    module Errors
      extend ActiveSupport::Concern
      included do
        class EmptyUsernameError < StandardError; end

        class ChatIsNotPrivate < StandardError; end

        class UrlNotAllowed < StandardError; end

        rescue_from StandardError, with: :fallback_error!
        rescue_from EmptyUsernameError, with: :empty_username!
        rescue_from ChatIsNotPrivate, with: :chat_is_not_private!
        rescue_from UrlNotAllowed, with: :url_not_allowed!

        def url_not_allowed!
          respond_with :message, text: t('errors.url_not_allowed')
        end

        def empty_username!
          respond_with :message, text: t('errors.empty_username'), parse_mode: 'HTML'
        end

        def chat_is_not_private!
          respond_with :message, text: t('errors.chat_is_not_private')
        end

        def fallback_error!(e)
          message = Rails.env.development? ? e : t('errors.fallback_error')
          case e
          when Telegram::Bot::Forbidden
            forbidden_error!
          else
            Rails.logger.error("[telegram-bot] exception: #{[e.message, *e.backtrace].join($/)}")
            respond_with :message, text: message
          end
        end

        def forbidden_error!
          Rails.logger.error("[telegram-bot] Bot was blocked by the user (#{params.dig(:username)})!")
        end
      end
    end
  end
end
