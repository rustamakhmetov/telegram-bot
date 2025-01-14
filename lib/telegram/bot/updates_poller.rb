module Telegram
  module Bot
    # Supposed to be used in development environments only.
    class UpdatesPoller
      class << self
        @@instances = {} # rubocop:disable ClassVars

        def instances
          @@instances
        end

        # Create, start and add poller instnace to tracked instances list.
        def add(bot, controller)
          new(bot, controller).tap { |x| instances[bot] = x }
        end

        def start(bot_id, controller = nil)
          bot = bot_id.is_a?(Symbol) ? Telegram.bots[bot_id] : Client.wrap(bot_id)
          instance = controller ? new(bot, controller) : instances[bot]
          raise "Poller not found for #{bot_id.inspect}" unless instance
          instance.start
        end
      end

      DEFAULT_TIMEOUT = 5

      attr_reader :bot, :controller, :timeout, :offset, :logger, :running, :reload

      def initialize(bot, controller, **options)
        @logger = options.fetch(:logger) { defined?(Rails.logger) && Rails.logger }
        @bot = bot
        @controller = controller
        @timeout = options.fetch(:timeout) { DEFAULT_TIMEOUT }
        @offset = options[:offset]
        @reload = options.fetch(:reload) { defined?(Rails.env) && Rails.env.development? }
        @notifier = options[:notifier]
      end

      def log(only_log: false, type: :info, &block)
        logger&.send(type, &block)
        notifier_message(only_notify: true, &block) unless only_log
      end

      def start
        return if running
        begin
          @running = true
          log { "Started bot poller. v#{Telegram::Bot::VERSION}" }
          run
        rescue Interrupt
          nil # noop
        rescue StandardError => e
          notifier_message("остановлен: #{e.message}")
        ensure
          @running = false
        end
        log { 'Stoped polling bot updates.' }
      end

      def run
        while running
          begin
            updates = fetch_updates
            process_updates(updates) if updates&.any?
            notifier_message("работает")
          rescue StandardError => e
            notifier_message("не работает, недоступен апи телеграма, ошибка: #{e.message}", log_type: :warn)
          end
        end
      end

      # Method to stop poller from other thread.
      def stop
        return unless running
        log { 'Stopping polling bot updates.' }
        @running = false
      end

      def fetch_updates(offset = self.offset)
        response = bot.async(false) { bot.get_updates(offset: offset, timeout: timeout) }
        response.is_a?(Array) ? response : response['result']
      rescue Timeout::Error
        log { 'Fetch timeout' }
        nil
      end

      def process_updates(updates)
        reload! do
          updates.each do |update|
            @offset = update['update_id'] + 1
            process_update(update)
          end
        end
      rescue StandardError => e
        logger.error { ([e.message] + e.backtrace).join("\n") } if logger
      end

      # Override this method to setup custom error collector.
      def process_update(update)
        controller.dispatch(bot, update)
      end

      def reload!
        return yield unless reload
        reloading_code do
          if controller.is_a?(Class) && controller.name
            @controller = Object.const_get(controller.name)
          end
          yield
        end
      end

      if defined?(Rails.application) && Rails.application.respond_to?(:reloader)
        def reloading_code
          Rails.application.reloader.wrap do
            yield
          end
        end
      else
        def reloading_code
          ActionDispatch::Reloader.prepare!
          yield.tap { ActionDispatch::Reloader.cleanup! }
        end
      end

      private

      def notifier_message(message=nil, only_notify: false, log_type: :info)
        message = yield if block_given?
        return if @notifier.nil? || message.blank?

        if @notifier_message != message
          @notifier_message = message
          _message = "#{@bot.username}: #{message}"
          logger&.send(log_type, _message) unless only_notify
          @notifier.ping(_message)
        end
      rescue Slack::Notifier::APIError, SocketError => e
        message = "notifier error: #{e.message}"
        if @notifier_error_message != message
          logger&.warn(message)
          @notifier_error_message = message
        end
      end
    end
  end
end
