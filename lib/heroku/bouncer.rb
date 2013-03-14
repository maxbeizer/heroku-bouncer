require 'sinatra/base'
require 'omniauth-heroku'
require 'faraday'
require 'multi_json'

Heroku ||= Module.new

class Heroku::Bouncer < Sinatra::Base

  enable :sessions
  set :session_secret, ENV['HEROKU_ID'].to_s + ENV['HEROKU_SECRET'].to_s

  # sets up the /auth/heroku endpoint
  use OmniAuth::Builder do
    provider :heroku, ENV['HEROKU_ID'], ENV['HEROKU_SECRET']
  end

  def initialize(app, options = {})
    super(app)
    @herokai_only = extract_option(options, :herokai_only, false)
    @expose_token = extract_option(options, :expose_token, false)
    @expose_email = extract_option(options, :expose_email, true)
    @expose_user = extract_option(options, :expose_user, true)
  end

  def extract_option(options, option, default = nil)
    options.has_key?(option) ? options[option] : default
  end

  def fetch_user(token)
    MultiJson.decode(
      Faraday.new(ENV["HEROKU_API_URL"] || "https://api.heroku.com/").get('/account') do |r|
        r.headers['Accept'] = 'application/json'
        r.headers['Authorization'] = "Bearer #{token}"
      end.body)
  end

  def store(key, value)
    session[:store] ||= {}
    session[:store][key] = value
  end

  def expose_store
    session[:store].each_pair do |key, value|
      request.env["bouncer.#{key}"] = value
    end
  end

  before do
    if session[:user]
      expose_store
    elsif ! %w[/auth/heroku/callback /auth/heroku /auth/failure /auth/sso-logout /auth/logout].include?(request.path)
      session[:return_to] = request.url
      redirect to('/auth/heroku')
    end
  end

  # callback when successful, time to save data
  get '/auth/heroku/callback' do
    session[:user] = true
    token = request.env['omniauth.auth']['credentials']['token']
    store(:token, token) if @expose_token
    if @expose_email || @expose_user || @herokai_only
      user = fetch_user(token)
      store(:user, user) if @expose_user
      store(:email, user['email']) if @expose_email

      if @herokai_only && !user['email'].end_with?("@heroku.com")
        url = @herokai_only.is_a?(String) ? @herokai_only : 'https://www.heroku.com'
        redirect to(url) and return
      end
    end
    redirect to(session.delete(:return_to) || '/')
  end

  # something went wrong
  get '/auth/failure' do
    session.destroy
    redirect to("/")
  end

  # logout, single sign-on style
  get '/auth/sso-logout' do
    session.destroy
    auth_url = ENV["HEROKU_AUTH_URL"] || "https://id.heroku.com"
    redirect to("#{auth_url}/logout")
  end

  # logout but only locally
  get '/auth/logout' do
    session.destroy
    redirect to("/")
  end

end
