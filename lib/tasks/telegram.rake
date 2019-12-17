require 'logger'
require 'ruby-progressbar'


namespace :telegram do
  task active: :environment do
    puts "Active bots:"
    Telegram.bots.each_with_index do |(key, bot), index|
      puts "#{index + 1}. #{bot.username}"
    end
  end

  task :send_messages, [:menu] do |task, args|
    abort("Ошибка: не передан параметр 'Меню'. Запускать: rake telegram:send_messages[menu1]") if args[:menu].blank?

    users = User
             .joins(:preference)
             .where("user_preferences.telegram_send_messages")
    abort("Ошибка: нет выбранных пользователей") if users.blank?

    progressbar = ProgressBar.create(
      total: users.count,
      format: '%a, %J, %E' # elapsed time, percent complete, estimate
    )

    menu = args[:menu].to_sym

    puts "Отправляем сообщения из `#{I18n.t("telegram.button.#{menu}", locale: :ru)}` - #{users.count} пользователям"
    options = Telegram.bots_config.dig(:default)
    token = options[:token]
    proxy = options[:proxy]
    bot = Telegram::Bot::Client.new(token, username: options.dig(:username), proxy: proxy)

    params = { session: { menus_stack: [:main] }, payload: {} }
    tg_messages = Telegram::Actions::Messages.new(menu, params).generate
    users.find_each do |user|
      telegram_id = user.pref.telegram_id
      next if telegram_id.blank?

      tg_messages.messages.each do |message|
        type = message[:type] == :photo ? :photo : :message
        bot.public_send("send_#{type}", message[:options].merge(chat_id: telegram_id))
      end
      progressbar.increment
    end
    puts "Отправка успешно завершена"
  end

  task :start, [:timeout] do |task, args|
    slack_webhook_url = env("SLACK_WEBHOOK_URL", "https://hooks.slack.com/services/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")
    slack_channel = env("SLACK_CHANNEL","#bots", true)
    notifier =
      if slack_webhook_url.present? && slack_channel.present?
        Slack::Notifier.new slack_webhook_url do
          defaults channel: slack_channel,
                   username: "gitlab"
        end
      end
    options = Telegram.bots_config.dig(:default)
    token = options[:token]
    proxy = options[:proxy]
    bot = Telegram::Bot::Client.new(token, username: options.dig(:username), proxy: proxy)
    bot.delete_webhook

    # poller-mode
    timeout = args.fetch(:timeout) { 3 }
    log_file = Rails.root.join('log', 'telegram-bot.log')
    logger = Logger.new("| tee -a #{log_file}") # and output to STDOUT
    logger.info("Starting #{options[:username]} ...")
    if notifier
      logger.info("Enable slack notifier in channel '#{slack_channel}'")
    else
      logger.info("Disable slack notifier")
    end
    poller = Telegram::Bot::UpdatesPoller.new(bot, Telegram::WebhooksController,
                                              logger: logger, reload: false,
                                              timeout: timeout.to_i, notifier: notifier)
    poller.start
  end

  def env(name, default=nil, only_production=false)
    return ENV[name] if ENV[name].present?

    default if !only_production || ENV['BOT_PRODUCTION']
  end
end
