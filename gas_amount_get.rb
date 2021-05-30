### ====================
#
#   gas_amount_get.rb
#
#   purpose:
#      get cas amount data from looop DENKI
#
#   environment:
#      ruby 2.6.0p0 (2018-12-25 revision 66547)
#
#   version:
#      1.0   First edition create        Kei Yoshiyama
#
### =====================

require 'open-uri'
require 'selenium-webdriver'
require 'json'
require 'net/https'
require 'logger'

url = "https://looop-denki.com/own/"

begin
    credentials = JSON.parse(File.read('./credentials.json'))
    user_id = credentials["user_id"]
    password = credentials["password"]
    webhook_url = credentials["webhook_url"]
rescue => e
    log.error(e)
    abort
end

log = Logger.new('./execute.log')
log.info('====== START EXECUTION =====')
driver = Selenium::WebDriver.for :chrome
driver.get url

wait = Selenium::WebDriver::Wait.new(:timeout => 10)

# ==== SEND NOTIFICATION TO WEBHOOK
def send_notification(data, webhook_url)
    log = Logger.new('./execute.log')
    log.info("Sending information to Webhook")
    
    begin
        
        uri = URI.parse(webhook_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        
        hash = {}
        hash[:value1] = data[:date]
        hash[:value2] = "ガス代"
        hash[:value3] = data[:amount]
        
        req = Net::HTTP::Post.new(uri.path)
        req.set_form_data(hash)
        
        res = http.request(req)
    rescue => e
        log.error(e)
    end
    
end


begin
  # ==== LOGIN
  log.info('Selenium execution started')
  id_input = wait.until { driver.find_element(id: "login-id") }
  pw_input = wait.until { driver.find_element(id: "password") }
  id_input.send_keys( user_id )
  pw_input.send_keys( password )
  id_input.submit
  
  # ==== NAVIGATE TO AMOUNT PAGE
  log.info('Navigating to /own/mypage/invoice')
  driver.get "https://looop-denki.com/own/mypage/invoice_gas/"
  select_place = Selenium::WebDriver::Support::Select.new(driver.find_element(id: "demand-contract-id"))
  select_year = Selenium::WebDriver::Support::Select.new(driver.find_element(id: "target-date-year"))
  select_place.select_by(:index, 0)
  select_year.select_by(:index, 1)

  # ==== GET AMOUNT
  result = []
  log.info('Fetching data from detail table')
  data_table_div = wait.until { driver.find_element(class: "detailTbl") }
  data_table = data_table_div.find_element(tag_name: "table")
  data_table.find_elements(tag_name: "tr").each_with_index do |tr, i|
    if i != 0 then
      data = tr.find_elements(tag_name: "td")
      result.push({date: data[2].text, amount: data[3].text.chop.delete(",").to_i})
    end
  end
  
  # ==== COMPARE WITH EXISTING DATA
  file_path = "./data_gas.json"
  json_file = File.open(file_path)
  existing_datas = json_file.read

  if existing_datas.empty? then
    log.info("existing data is empty - adding all datas but it will NOT send notification")
    File.write(file_path, result.to_json)
  else
    existing_datas_hash = JSON.parse(existing_datas)
    new_data = existing_datas_hash
    
    # ==== JUDGE WHETHER DATA EXISTS
    result.each do |el|
        s = existing_datas_hash.find{ |h| h["date"] == el[:date] }
        if s.nil? then
            log.info("processing entry: " + el.to_s)
            new_data.push(el)
            send_notification(el, webhook_url)
        end
    end
    
    # ==== WRITE NEW DATA
    File.delete(file_path)
    File.write(file_path, new_data.to_json)
  end
  json_file.flush
rescue => e
  log.error(e)
ensure
  log.info("Shutting Down Driver")
  driver.quit
  log.info("===== FINISHED EXECUTION =====")
end

