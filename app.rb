require 'sinatra'
require 'sinatra/json'
require 'dotenv'
require 'oauth'
require 'nokogiri'
require 'mongo'
require 'eth'

Dotenv.load

GOODREADS_BASE_URL   = 'https://www.goodreads.com'.freeze
GOODREADS_API_KEY    = ENV['GOODREADS_API_KEY'].freeze
GOODREADS_API_SECRET = ENV['GOODREADS_API_SECRET'].freeze

set :db, Mongo::Client.new(ENV['MONGO_URL'] || 'mongodb://127.0.0.1:27017/rey-example-bestreads')

puts settings.port
enable :sessions

# REY-App Manifest

MANIFEST = {
  version: '1.0',
  name: 'Bestreads',
  description: 'Returns statistics about your last 100 read books from Goodreads website',
  homepage_url: ENV['HOMEPAGE_URL'] || 'http://localhost:8000',
  picture_url: ENV['PICTURE_URL'] || 'https://avatars1.githubusercontent.com/u/42174428?s=200&v=4',
  address: ENV['APP_ADDRESS'] || '0x88032398beab20017e61064af3c7c8bd38f4c968',
  app_url: ENV['APP_URL'] || 'http://localhost:8000/data',
  app_reward: 0,
  app_dependencies: []
}.freeze

get '/manifest' do
  json MANIFEST
end

# REY-App Data Endpoint

get '/data' do
  subject = parse_subject_header(request.env)
  token_entry = settings.db[:tokens].find(address: subject.to_s.downcase).first
  return status 404 unless token_entry
  call_goodreads(token_entry[:_id])
end

def parse_subject_header(headers)
  Base64.decode64(headers['HTTP_X_PERMISSION_SUBJECT'] || 'null').gsub(/\A"|"\Z/, '')
end

# App Specific Endpoints

get '/' do
  erb :index
end

get '/sign' do
  erb :sign
end

get '/done' do
  erb :done
end

get '/connect' do
  goodreads_consumer = OAuth::Consumer.new(GOODREADS_API_KEY, GOODREADS_API_SECRET, site: GOODREADS_BASE_URL)
  session[:request_token] = goodreads_consumer.get_request_token
  authorize_url = session[:request_token].authorize_url
  redirect authorize_url
end

get '/connect/callback' do
  access_token = session[:request_token].get_access_token
  token = "#{access_token.token},#{access_token.secret}"
  redirect "/sign?token=#{token}"
end

post '/sign' do
  token = params[:token]
  signature = params[:signature]
  public_key = Eth::Utils.public_key_to_address(Eth::Key.personal_recover(token, signature))
  store_public_key(token, public_key)
end

private

# App Helper Methods

def call_goodreads(token)
  api = goodreads_api_for(token)
  user_id = goodreads_user_id(api)
  num_pages_array = get_num_pages_from_books_from_read_shelf(api, user_id)
  num_pages_array.reject! { |e| e.zero? }
  mean = (num_pages_array.reduce(:+) / num_pages_array.size) if num_pages_array.size > 0
  {
    min: num_pages_array.min,
    max: num_pages_array.max,
    mean: mean
  }.to_json
end

def goodreads_api_for(access_token)
  token, secret = access_token.split(',')
  goodreads_consumer = OAuth::Consumer.new(GOODREADS_API_KEY, GOODREADS_API_SECRET, site: GOODREADS_BASE_URL)
  OAuth::AccessToken.new(goodreads_consumer, token, secret)
end

def goodreads_user_id(api)
  response = api.get("#{GOODREADS_BASE_URL}/api/auth_user").body
  doc = Nokogiri::Slop(response)
  doc.GoodreadsResponse.user.attributes['id'].value
end

def get_num_pages_from_books_from_read_shelf(api, user_id)
  params_string = "v=2&shelf=read&per_page=100"
  response = api.get("#{GOODREADS_BASE_URL}/review/list/#{user_id}.xml?#{params_string}").body
  doc = Nokogiri::Slop(response)
  books = doc.GoodreadsResponse.search('book')
  books.map do |book|
    book.elements.select { |e| e.name == 'num_pages' }.first.text.to_i
  end
end

def store_public_key(token, public_key)
  settings.db[:tokens].find_one_and_replace({ _id: token }, { _id: token, address: public_key.downcase }, upsert: true)
end
