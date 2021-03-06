module Hubspot
  class Connection
    include HTTParty

    class << self
      def get_json(path, opts)
        url = generate_url(path, opts)
        response = get(url, headers: authorization_header, format: :json)
        log_request_and_response url, response

        handle_response(response, true)
      end

      def post_json(path, opts)
        parse_response = !opts[:params].delete(:no_parse) { false }

        url = generate_url(path, opts[:params])
        response = post(url, body: opts[:body].to_json, headers: { 'Content-Type' => 'application/json' }.merge(authorization_header), format: :json)
        log_request_and_response url, response, opts[:body]

        handle_response(response, parse_response)
      end

      def put_json(path, opts)
        url = generate_url(path, opts[:params])
        response = put(url, body: opts[:body].to_json, headers: { 'Content-Type' => 'application/json' }.merge(authorization_header), format: :json)
        log_request_and_response url, response, opts[:body]

        handle_response(response, true)
      end

      def delete_json(path, opts)
        url = generate_url(path, opts)
        response = delete(url, headers: authorization_header, format: :json)
        log_request_and_response url, response, opts[:body]

        handle_response(response, false)
      end

      protected

      def log_request_and_response(uri, response, body=nil)
        Hubspot::Config.logger.info "Hubspot: #{uri}.\nBody: #{body}.\nResponse: #{response.code} #{response.body}"
      end

      def generate_url(path, params={}, options={})
        if Hubspot::Config.access_token.present?
          options[:hapikey] = false
        else
          Hubspot::Config.ensure! :hapikey
        end
        path = path.clone
        params = params.clone
        base_url = options[:base_url] || Hubspot::Config.base_url
        params["hapikey"] = Hubspot::Config.hapikey unless options[:hapikey] == false

        if path =~ /:portal_id/
          Hubspot::Config.ensure! :portal_id
          params["portal_id"] = Hubspot::Config.portal_id if path =~ /:portal_id/
        end

        params.each do |k,v|
          if path.match(":#{k}")
            path.gsub!(":#{k}", CGI.escape(v.to_s))
            params.delete(k)
          end
        end
        raise(Hubspot::MissingInterpolation.new("Interpolation not resolved")) if path =~ /:/

        query = params.map do |k,v|
          v.is_a?(Array) ? v.map { |value| param_string(k,value) } : param_string(k,v)
        end.join("&")

        path += path.include?('?') ? '&' : "?" if query.present?
        base_url + path + query
      end

      # convert into milliseconds since epoch
      def converted_value(value)
        value.is_a?(Time) ? (value.to_i * 1000) : CGI.escape(value.to_s)
      end

      def param_string(key,value)
        case key
        when /range/
          raise "Value must be a range" unless value.is_a?(Range)
          "#{key}=#{converted_value(value.begin)}&#{key}=#{converted_value(value.end)}"
        when /^batch_(.*)$/
          key = $1.gsub(/(_.)/) { |w| w.last.upcase }
          "#{key}=#{converted_value(value)}"
        else
          "#{key}=#{converted_value(value)}"
        end
      end

      def authorization_header
        return {} unless Hubspot::Config.access_token.present?

        access_token = if Hubspot::Config.access_token.respond_to?(:call)
                         Hubspot::Config.access_token.call
                       else
                         Hubspot::Config.access_token
                       end

        { 'Authorization' => "Bearer #{access_token}" }
      end

      def handle_response(response, parse_response)
        raise error_from_response(response) unless response.success?

        parse_response ? response.parsed_response : response
      end

      def error_from_response(response)
        if response['errorType'] == 'RATE_LIMIT'
          Hubspot::RateLimitedError.new(response)
        else
          Hubspot::RequestError.new(response)
        end
      rescue => _
        raise Hubspot::RequestError.new(response)
      end
    end
  end

  class FormsConnection < Connection
    follow_redirects true

    def self.submit(path, opts)
      url = generate_url(path, opts[:params], { base_url: 'https://forms.hubspot.com', hapikey: false })
      post(url, body: opts[:body], headers: { 'Content-Type' => 'application/x-www-form-urlencoded' })
    end
  end
end
