require 'rubygems'
require 'sinatra'
require 'google/api_client'
require 'httpadapter/adapters/net_http'
require 'pp'
require 'yaml'

use Rack::Session::Pool, :expire_after => 86400 # 1 day

# Configuration
# See README for getting API id and secret

if (ARGV.size < 2)
  set :oauth_client_id, '125798150893-m3mqj9q1lkc4hrq5hjqasns5e8mebc2e.apps.googleusercontent.com'
  set :oauth_client_secret, 'eXVT_LmXvFErH0ZnYCcWGWWj'

  if (settings.oauth_client_id == 'oauth_client_id')
    puts 'See README for getting API id and secret.  Server terminated.'
    exit(0)
  end
else
  set :oauth_client_id, ARGV[0]
  set :oauth_client_secret, ARGV[1]
end

# Configuration that you probably don't have to change
set :oauth_scopes, 'https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/userinfo.email'

class TokenPair
  @refresh_token
  @access_token
  @expires_in
  @issued_at

  def update_token!(object)
    @refresh_token = object.refresh_token
    @access_token = object.access_token
    @expires_in = object.expires_in
    @issued_at = object.issued_at
  end

  def to_hash
    return {
      :refresh_token => @refresh_token,
      :access_token => @access_token,
      :expires_in => @expires_in,
      :issued_at => Time.at(@issued_at)
    }
  end
end

# At the beginning of any request, make sure the OAuth token is available.
# If it's not available, kick off the OAuth 2 flow to authorize.
before do
  @client = Google::APIClient.new(
    :authorization => :oauth_2,
    :host => 'www.googleapis.com',
    :http_adapter => HTTPAdapter::NetHTTPAdapter.new
  )

  @client.authorization.client_id = settings.oauth_client_id
  @client.authorization.client_secret = settings.oauth_client_secret
  @client.authorization.scope = settings.oauth_scopes
  @client.authorization.redirect_uri = to('/oauth2callback')
  @client.authorization.code = params[:code] if params[:code]
  if session[:token]
    # Load the access token here if it's available
    @client.authorization.update_token!(session[:token].to_hash)
  end

  # @service = @client.discovered_api('userinfo', 'v1')
  unless @client.authorization.access_token || request.path_info =~ /^\/oauth2/
    redirect to('/oauth2authorize')
  end
end

# Part of the OAuth flow
get '/oauth2authorize' do
  <<OUT
<!DOCTYPE html>
<html>
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
  <title>Google Ruby API Login Sample</title>
</head>
<body>
<header><h1>Google Ruby API Login Sample(profile and mailadress)</h1></header>
<div class="box">
<a class='login' href='#{@client.authorization.authorization_uri.to_s}'>Login and get your profile!</a>
</div>
</body>
</html>
OUT
end

# Part of the OAuth flow
get '/oauth2callback' do
  @client.authorization.fetch_access_token!
  unless session[:token]
    token_pair = TokenPair.new
    token_pair.update_token!(@client.authorization)
    # Persist the token here
    session[:token] = token_pair
  end
  redirect to('/')
end

# The method you're probably actually interested in. This one lists a page of your
# most recent activities
get '/' do
  result = @client.execute(:uri => 'https://www.googleapis.com/oauth2/v1/userinfo')
  response = result.response
  json = response.to_s
  ary = YAML.load(json)
  profile_json = ary[2][0]
  profile = YAML.load(profile_json)
  <<OUT
<!DOCTYPE html>
<html>
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
  <title>Google Ruby API Login Sample</title>
</head>
<body>
<header><h1>Google Ruby API Login Sample(profile and mailadress)</h1></header>
<div class="box">
<h5> id : #{profile['id']} </h5>
<h5> email : #{profile['email']} </h5>
<h5> verified_email : #{profile['verified_email']} </h5>
<h5> name : #{profile['name']} </h5>
<h5> given_name : #{profile['given_name']} </h5>
<h5> family_name : #{profile['family_name']} </h5>
<h5> picture : #{profile['picture']} </h5>
<h5> gender : #{profile['gender']} </h5>
<h5> locale : #{profile['locale']} </h5>
</div>
</body>
</html>
OUT
end