#!/usr/bin/env ruby

require 'bundler/setup'
require 'optparse'
require 'json'
require 'selenium-webdriver'

use_webdriver = :firefox
browser_window = false

nonopt_args = OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options] <URL list file>"

  opts.on('-d', '--driver DRIVER', 'Use specified WebDriver') do |arg|
    use_webdriver = arg.to_sym
  end

  opts.on('-w', '--browser-window', 'Show browser window') do
    browser_window = true
  end

  opts.on('-h', '--help', 'Show help') do
    puts opts
    exit
  end
end.parse(ARGV)

url_list_file = nonopt_args[0]
if !url_list_file
  puts "No URL list file provided."
  exit 1
end
urls = File.readlines(url_list_file).map(&:strip).select{|a| !a.empty? && !a.start_with?('#') }

if !browser_window && use_webdriver == :firefox
  drv = Selenium::WebDriver.for(:firefox, options: Selenium::WebDriver::Firefox::Options.new(args: ['-headless']))
elsif !browser_window && use_webdriver == :chrome
  drv = Selenium::WebDriver.for(:chrome, options: Selenium::WebDriver::Chrome::Options.new(args: ['--headless']))
else
  drv = Selenium::WebDriver.for(use_webdriver)
end
at_exit { drv.quit }

urls.each_with_index do |url, i|
  puts "(#{i + 1}/#{urls.length}) #{url}"
  drv.execute_script("window.location = " + JSON.generate(url))
  sleep 1
  while drv.execute_script("document.readyState") == 'loading'
    sleep 1
  end
  original_handle = drv.window_handles[0]

  drv.switch_to.window(original_handle)
  drv.execute_script("window.open('https://web.archive.org/save/'+location.href);");
  sleep 1
  wayback_machine_handle = (drv.window_handles - [original_handle])[0]
  wayback_machine_completed = false

  drv.switch_to.window(original_handle)
  drv.execute_script("window.open('https://archive.today/?run=1&url='+encodeURIComponent(location.href));")
  sleep 1
  archive_today_handle = (drv.window_handles - [original_handle, wayback_machine_handle])[0]
  archive_today_completed = false

  additional_sleep = 0

  loop do
    drv.switch_to.window(wayback_machine_handle)
    if drv.find_elements(id: 'wm-ipp-base').any?
      if !wayback_machine_completed
        puts "  Wayback Machine: done"
        wayback_machine_completed = true
      end
    end
    sleep 1

    drv.switch_to.window(archive_today_handle)
    if drv.find_elements(id: 'HEADER').any?
      if drv.find_elements(id: 'DIVALREADY').any?
        drv.execute_script("document.querySelector('#DIVALREADY input[type=submit]').click()")
        additional_sleep += 4
      else
        if !archive_today_completed
          puts "  Archive.today: done"
          archive_today_completed = true
        end
      end
    end
    sleep 1

    if wayback_machine_completed && archive_today_completed
      break
    end

    sleep additional_sleep
    additional_sleep = 0
  end

  drv.switch_to.window(wayback_machine_handle)
  drv.close
  drv.switch_to.window(archive_today_handle)
  drv.close
  drv.switch_to.window(original_handle)
end
