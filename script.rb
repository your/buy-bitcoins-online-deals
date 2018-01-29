#!/usr/bin/env ruby

require 'json'
require 'mailgun'
require 'open-uri'
require 'rake/thread_pool'

MAX_ADS = 100

MAILGUN_API_KEY = ''.freeze
MAILGUN_DOMAIN  = ''.freeze
NOTIFICATION_EMAIL = ''.freeze

STDOUT.sync = true

flag_allow_new_traders = ARGV.include?('--allow-new-traders')

def send_email(subject, txt, recipient = NOTIFICATION_EMAIL, sender = recipient)
  mg_client = Mailgun::Client.new(MAILGUN_API_KEY)

  message_params = {
    from: sender,
    to: recipient,
    subject: subject,
    text: txt
  }

  mg_client.send_message(MAILGUN_DOMAIN, message_params)
end

def fetch_tot_pages
  fetch_and_parse('https://localbitcoins.com/buy-bitcoins-online/.json?page=10000')
    .fetch(:pagination).fetch(:prev)
    .match(/.*?page=(\d+)/)[1]
    .to_i
end

def fetch_page(page)
  fetch_and_parse(
    "https://localbitcoins.com/buy-bitcoins-online/.json?page=#{page}"
  ).fetch(:data).fetch(:ad_list)
end

def fetch_and_parse(url)
  JSON.parse(open(url).read, symbolize_names: true)
end

tot_pages = fetch_tot_pages
fetched_pages = 0

pool = Rake::ThreadPool.new(4)
fetched_ads = []

puts
puts 'Fetching data...'
puts

1.upto(tot_pages) do |page|
  pool.future do
    ad_list = fetch_page(page)
    ad_list.each do |ad|
      data = ad[:data]
      actually_allow_new_traders = data[:require_trade_volume].zero? &&
                                   data[:volume_coefficient_btc].to_f.zero? &&
                                   data[:require_feedback_score].zero?

      next if flag_allow_new_traders && actually_allow_new_traders

      fetched_ads << {
        price: data[:temp_price_usd].to_f,
        link: ad[:actions][:public_view],
        method: data[:online_provider],
        country: data[:countrycode]
      }
    end
    fetched_pages += 1
    puts <<-EOS
Fetched #{fetched_pages}/#{tot_pages} pages - #{fetched_ads.count} ads total
EOS
  end
end

pool.join
puts '...done.'

fetched_ads.sort_by! { |k| k[:price] }

results = "\n"
results += "Top #{MAX_ADS} cheapest buy-bitcoins-online deals:\n\n"

results += format "%-15s | %-20s | %-10s | %s\n",
                  'Price/BTC (USD)',
                  'Payment Method',
                  'Country',
                  'Link'

results += "#{'-' * 90}\n"

fetched_ads.first(MAX_ADS).each do |ad|
  results += format "%-15s | %-20s | %-10s | %s\n",
                    ad[:price], ad[:method], ad[:country], ad[:link]
end

results += "\n"

puts results

unless NOTIFICATION_EMAIL.empty?
  send_email(
    "Top #{MAX_ADS} cheapest buy-bitcoins-online deals",
    results,
    NOTIFICATION_EMAIL
  )
  puts "Sent notification email to #{NOTIFICATION_EMAIL}."
end
