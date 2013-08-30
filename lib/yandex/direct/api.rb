require 'test/unit/assertions'

require_relative 'lib/helpers'
require_relative 'lib/clients'

module Api
  module Helpers
    def include_module_and_camelize_methods klass
      self.send :include, klass

      klass.public_instance_methods.each { |method| self.send :alias_method, method.to_s.camelize, method }
    end
  end
end

module Yandex
  module Direct
    class ApiException < StandardError;end
    class YandexApiException < ApiException;end
    class YandexApiException < ApiException;end
    class YandexDirectApiException < YandexApiException;end
    class YandexDirectNoDataApiException < YandexDirectApiException;end

    class Api
      include ::Test::Unit::Assertions
      include ::Yandex::Direct::Helpers

      extend ::Api::Helpers

      include_module_and_camelize_methods ClientsMethods

      VERSION = '4'
      CURRENCY_RATIO = 30

      attr_reader :environment, :url, :version, :token, :application_id, :login

      def initialize params = {}
        @version = VERSION

        @environment = params[:environment] || :production
        assert_send([[:sandbox, :production], :include?, @environment])

        @token = params[:token]
        assert_not_blank @token

        if params[:agency].present?
          @agency = params[:agency]
          assert @agency.is_a?(TrueClass) || @agency.is_a?(FalseClass)
        end

        @login = params[:login].gsub(/@.*\z/, '')
        assert_not_blank @login

        @application_id = Settings.yandex.oauth_credentials.id
        assert_not_blank @application_id

        subdomain = @environment == :sandbox ? 'api-sandbox' : 'api'
        @url = "https://#{subdomain}.direct.yandex.ru/json-api/v4/"
      end

      def is_valid?
        result = method_call(:GetClientInfo)
        result.is_a?(Array) && result.present?
      end

      def method_call method, params = {}
        puts "\n" * 2
        #ap "direct.method_call #{method}"
        assert_not_blank method

        params = set_date_format_for_hash params
        call_params = params.merge({
          method: method.to_s.camelize,
          application_id: @application_id,
          login: @login,
          token: @token
        })

        body = Oj.dump(call_params, mode: :compat)

        ap "body: #{body}"

        response =
            retry_block 3, [Faraday::Error::TimeoutError, Faraday::Error::ConnectionFailed] do
              connection.post @url, body, { 'Content-Type' => 'application/json; charset=utf-8' }
            end

        begin
          call_response = MultiJson.load response.body, symbolize_keys: true
        rescue MultiJson::DecodeError => e
          raise e if Rails.env.test?

          Rails.logger.error e

          raise YandexDirectApiException, 'JSON decode error'
        end

        if call_response[:error_code].present?
          error_description = call_response[:error_detail].present? ? "\nError description: #{call_response[:error_detail]}." : nil
          error_code = call_response[:error_code]

          exception = case error_code
                        when 2
                          YandexDirectNoDataApiException
                        else
                          YandexDirectApiException
                      end

          raise exception, "##{error_code}. #{call_response[:error_str]}!#{error_description}\n\nRead more at http://api.yandex.ru/direct/doc/reference/ErrorCodes.xml#ErrorCode#{error_code}\n\n"
        else
          convert_response call_response[:data]
        end
      end

      def direct_method_call params = {}
        method_name = caller[0][/`(.*?)'\z/, 1]
        assert_not_blank method_name

        params = HashWithIndifferentAccess.new params
        params = { param: camelize_hash_keys(params[:param]) } if params[:param].is_a?(Hash)

        method_call method_name, params
      end

      def agency
        @agency = get_client_info(@login)[:role] == 'Agency' if @agency.nil?
        @agency
      end

      def is_agency?
        agency.eql? true
      end

      def clients
        if is_agency?
          get_clients_list.map { |client| Client.new self, client }
        else
          []
        end
      end

      private

      def raise_with_link_to_help &block
        method_name = caller[0][/`(.*?)'\z/, 1]
        assert_not_blank method_name

        begin
          block.()
        rescue MiniTest::Assertion => e
          raise e if Rails.env.test?

          message = "#{e.message}\n\nRead more at http://api.yandex.ru/direct/doc/reference/#{method_name.camelize}.xml\n\n"

          raise e, message
        end
      end

      def connection
        Faraday.new url: @url, ssl: { verify: false } do |builder|
          builder.request  :url_encoded
          builder.response :logger
          builder.adapter Faraday.default_adapter
          builder.options[:timeout] = 120 # I hate yandex
          builder.options[:open_timeout] = 60 # I hate yandex
          builder.headers[:user_agent] = 'Mediatron'
        end
      end
    end
  end
end
