require 'bundler/setup'
Bundler.require
require 'sinatra/reloader' if development?

require "./lib/music/music.rb"
require "./lib/google.rb"
require "./models/dj_system-api.rb"

require "net/http"

require "jwt"

Dotenv.load

CORS_DOMAINS = ["http://dj.lit-kansai-mentors.com", "https://dj.lit-kansai-mentors.com", "http://localhost:3000", "http://127.0.0.1:3000"]

options '*' do
    response.headers["Access-Control-Allow-Methods"] = "GET, PUT, POST, DELETE, OPTIONS"
    response.headers["Access-Control-Allow-Origin"] = CORS_DOMAINS.find { |domain| request.env["HTTP_ORIGIN"] == domain } || CORS_DOMAINS.first
    response.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type, Accept, X-User-Email, X-Auth-Token, X-Requested-With"
    response.headers["Access-Control-Allow-Credentials"] = "true"
end
  
before do
    response.headers["Access-Control-Allow-Origin"] = CORS_DOMAINS.find { |domain| request.env["HTTP_ORIGIN"] == domain } || CORS_DOMAINS.first
    response.headers["Access-Control-Allow-Credentials"] = "true"

    if request.env["HTTP_API_TOKEN"]
        decoded_token = JWT.decode(request.env["HTTP_API_TOKEN"], ENV['JWT_SECRET'], true, { algorithm: 'HS256' })
        @user = User.find_by(id: decoded_token[0]['user_id'])
        puts @user
        return unless @user
        google_token = @user.access_tokens.find_by(provider: 'google')
        @google = Google.new(google_token.access_token) if google_token
    end
end
 
get '/' do
    "Hello World!"
end

get "/test" do
    data = nil
    if data
        data = {
            status: "OK"
        }
    else
        data = message_404
    end


    #Header情報取得
    headers = request.env.select { |k, v| k.start_with?('HTTP_') }

    headers.each do |k, v|
        puts "#{k} -> #{v}"
    end

    # tokenを複合化
    # JWT.decode(token, rsa_public, true, { algorithm: 'RS256' })

    data.to_json
end

# roomの作成
post "/room" do
    return unauthorized unless @user
    return bad_request("invalid parameters") unless has_params?(params, [:url_name, :room_name, :description])

    room = @user.rooms.build(
        users: [@user],
        url_name: params[:url_name],
        room_name: params[:room_name],
        description: params[:description]
    )
    return bad_request("Failed to save") unless room.save

    send_json room
end

# 全room情報取得(管理可能なroomのみ)
get "/room/all" do
    rooms = Room.all
    data = []
    if rooms
        # code: 204 No Content
        if rooms.empty
            data = message_204
        # code: 200 Success
        else 
            rooms.each do |room|
                room_data = {
                    url_name: room.url_name,
                    room_name: room.room_name,
                    description: room.description,
                    users: room.users,
                    created_at: room.created_at,
                    updated_at: room.updated_at
                }
                data.push(room_data)
            end
            status 200
        end

    # error
    else
        data = message_error
    end
    
    data.to_json
end

# room個別情報表示
get "/room/:id" do
    room = Room.find_by(params[:roomId])
    # code: 200 Success
    if room
        data = {
            url_name: room.url_name,
            room_name: room.room_name,
            description: room.description,
            users: room.users,
            created_at: room.created_at,
            updated_at: room.updated_at
        }
        status 200

    # status: 404 Not Found
    else
        status 404
    end
    
    data.to_json
end

# room個別情報更新
put "/room/:roomId" do
    room = Room.find_by(params[:roomId])
    # status: 200 Success
    if room
        room.update(
            url_name: params[:url_name],
            room_name: params[:room_name],
            description: params[:description],
            users: params[:users],
            created_at: params[:created_at],
            updated_at: :params[updated_at]
        )

        # data = {
        #     url_name: room.url_name,
        #     room_name: room.room_name,
        #     description: room.description,
        #     users: room.users,
        #     created_at: room.created_at,
        #     updated_at: room.updated_at
        # }

        status 200

    # status: 404 Not Found
    else
        status 404
    end
    
    data.to_json
end

# room個別削除
delete "/room/:roomId" do
    room = Room.find_by(params[:roomId])
    # status: 200 Success
    if room
        room.destroy

        # data = {
        #     url_name: room.url_name,
        #     room_name: room.room_name,
        #     description: room.description,
        #     users: room.users,
        #     created_at: room.created_at,
        #     updated_at: room.updated_at
        # }
        status 200

    # status: 404 Not Found
    else
        status 404
    end

    data.to_json
end

# リクエスト送信
get "/room/:roomId/request" do
    room = Room.find_by(prams[:roomId])
    # status: 200 Success
    if room
        
        # リクエスト処理
        reqMusic = RequestMusic.create(
            musics: params[:musics],
            radio_name: params[:radio_name],
            message: params[:message]
        )

        if reqMusic
        elsif
            data = message_error
        end

        status 200

    # status: 404 Not Found
    else
        status 404
    end
end

# 音楽サービスとの連携
get "/music/search" do

    #Header情報取得
    headers = request.env.select { |k, v| k.start_with?('HTTP_') }

    headers.each do |k, v|
        puts "#{k} -> #{v}"
    end



    # tokenを複合化
    JWT.decode(token, rsa_public, true, { algorithm: 'RS256' })

    spotify_api = Music::SpotifyApi.new("access_token")

    puts spotify_api
end

# ユーザー(管理者&MC)ログイン(新規作成も)
get "/user/login" do
    return bad_request("invalid parameters") unless has_params?(params, [:redirect_url])

    data = { redirect_url: Google.get_oauth_url(params['redirect_url']) }
    send_json data
end

# Googleログイン後に呼び出す。クエリなどをサーバー側に渡す。
post "/user/loggedInGoogle" do
    return bad_request("invalid parameters") unless has_params?(params, [:code, :redirect_url])

    google_token = Google.get_token_by_code(params['code'], params['redirect_url'])
    return bad_request unless google_token['access_token']

    google_id = Google.new(google_token['access_token']).profile['id']
    return bad_request unless google_id

    user = User.find_or_create_by(google_id: google_id)
    user.access_tokens.find_or_create_by(provider: 'google').update(access_token: google_token['access_token'], refresh_token: google_token['refresh_token'])
    token = JWT.encode({ user_id: user.id }, ENV['JWT_SECRET'], 'HS256')
    
    data = { api_token: token, user_id: user.id }
    send_json data
end

# ユーザー(管理者&MC)情報取得
get "/user/:userId" do
    user = User.find_by(userId: params[:userId])
    if user
        data = {
            name: user.name,
            avatar_url: user.avatar_url,
            is_admin: user.is_admin
        }

        data.to_json

        status 200
    else
        status 404
    end
end

# ユーザー(管理者&MC)情報更新
get "/user/:userId" do
    user = User.find_by(userId: params[:userId])
    user.update(
        name: params[:name],
        avatar_url: params[:avatar_url],
        is_admin: params[:is_admin]
    )

    if user.save
        data = {
            name: user.name,
            avatar_url: user.avatar_url,
            is_admin: user.is_admin
        }

        data.to_json

        status 200
    else
        status 404
    end
end

# ユーザー(管理者&MC)情報削除
get "/user/:userId" do
    user = User.find_by(userId: params[:userId])
    user.delete

    if user.save
        status 200
    else
        status 404
    end
end

# Spotifyとの連携
get "/user/link/spotify" do

end

private
    def send_json(data)
        content_type :json
        data.to_json
    end

    def has_params?(params, keys)
        keys.all? { |key| params.has_key?(key) && !params[key].empty? }
    end

    # error

    def bad_request(message=nil)
        data = {
            "message": message || "Bad Request",
            "status": 400
        }
        status 400
        send_json data
    end

    def unauthorized(message=nil)
        data = {
            "message": message || "Unauthorized",
            "status": 401
        }
        status 401
        send_json data
    end

    def internal_server_error(message=nil)
        data = {
            "message": message || "Internal Server Error",
            "status": 500
        }
        status 500
        send_json data
    end

    def message_error
        data = {
            code: "---",
            message: "Error"
        }
        return data
    end

# アクセストークン → ユーザーがアプリに対して他あしくログインしていることを示すトークン（googleOathに紐づけられるトークン）
# リフレッシュトークン → セッション的なトークン
# APIトークン → Spotify

# jwt は　ログインの時に生成されるトークン　これを投げ合う　headerで取得git branch
