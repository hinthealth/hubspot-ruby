module Hubspot
  class RequestError < StandardError
    attr_accessor :response

    def initialize(response, message=nil)
      message += "\n" if message
      super("#{message}Response body: #{response.body}",)

      self.response = response
    end
  end

  class ContactExistsError < RequestError; end
  class RateLimitedError < RequestError; end

  class ConfigurationError < StandardError; end
  class MissingInterpolation < StandardError; end
  class InvalidParams < StandardError; end
  class ApiError < StandardError; end
end
