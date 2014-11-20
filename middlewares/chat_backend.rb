require 'faye/websocket'
require 'thread'
require 'redis'
require 'json'
require 'erb'

module ChatDemo
  class ChatBackend
    KEEPALIVE_TIME = 15 # in seconds
    CHANNEL        = "chat-demo"

    

    def initialize(app)
      @app     = app
      @clients = []
      uri = URI.parse(ENV["REDISCLOUD_URL"])
      @redis = Redis.new(host: uri.host, port: uri.port, password: uri.password)
      Thread.new do
        update_count = 1
        p 'start listening thread'
        while true do
            #p 'send update with 100ms pause'
            

            #TODO: Grab Flow Sensor Reading Here
            lastline = `tail -1 SENSOR_DATA.txt`

            @clients.each {|ws| ws.send('{"handle":"Update #' + update_count.to_s + '   ","text":"Rate = ' + lastline.to_s + ' "}') }
            update_count+=1
            sleep 0.1
        end
      end
    end

    def call(env)
      if Faye::WebSocket.websocket?(env)
        ws = Faye::WebSocket.new(env, nil, {ping: KEEPALIVE_TIME })
        ws.on :open do |event|
          p 'OPEN'
          p [:open, ws.object_id]
          @clients << ws
          p @clients
          p 'done open'
        end

        ws.on :message do |event|
          p 'GETTING A MESSAGE'
          p [:message, event.data]

          @clients.each {|ws| ws.send(event.data) }

          #@redis.publish(CHANNEL, sanitize(event.data))
          p 'DONE get message'
        end

        ws.on :close do |event|
          p [:close, ws.object_id, event.code, event.reason]
          @clients.delete(ws)
          ws = nil
        end

        # Return async Rack response
        ws.rack_response

      else
        @app.call(env)
      end
    end

    private
    def sanitize(message)
      json = JSON.parse(message)
      json.each {|key, value| json[key] = ERB::Util.html_escape(value) }
      JSON.generate(json)
    end
  end
end
