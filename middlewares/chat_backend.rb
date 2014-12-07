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
        sum = 0
        pad5_value = 8
        cost_per_person = 30 # the amount of money it takes to serve one person

        # FINALIZE THE FOLLOWING BY MONDAY
        people_served_by_one_liter = 20 # this is the number of people served by 1 liter
        max_people_to_serve = 33000 # the amount of people that can be served before putting up the "we did it!" screen
        while true do
          # STREAM FROM FILE 2 (millileters)
          files = Dir.entries("public")
          stream = "" # file to stream from
          files.each do |f|
            stream = f unless f.match(/outpour_ML.*/).nil?
          end
          p "trying to read from #{stream}"

          # TRANSFORM DATA: people_served, dollars_raised, liters_pumped
          lastline = `tail -1 public/#{stream}`
          p "lastline: #{lastline.strip}"
          sum = (sum + lastline.strip.to_i + pad5_value) if lastline.strip.to_i > 0
          p "sum: #{sum}"

          liters_pumped = sum / 1000 # convert milliliters to liters
          people_served = liters_pumped * people_served_by_one_liter
          dollars_raised = people_served * cost_per_person
          max_people_served = (people_served >= max_people_to_serve) ? true : false

          # SEND DATA TO THE CLIENT
          message = "{\"ml_pumped\":\"#{sum.to_s}\"\, \"dollars_raised\":\"#{dollars_raised.to_s}\"\, \"max_people_served\":\"#{max_people_served.to_s}\"\, \"people_served\":\"#{people_served.to_s}\"}"
          p "message: #{message}"
          @clients.each {|ws| ws.send(message) }
          sleep 1
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
