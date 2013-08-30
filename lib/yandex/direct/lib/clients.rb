module Yandex
  module Direct
    module ClientsMethods
      # include ::Api::Helpers

      def get_client_info logins = []
        if logins.is_a?(Array)
          assert_send([logins, :present?])

          direct_method_call param: logins
        else
          direct_method_call(param: [logins]).first
        end
      end

      def get_clients_list params = {}
        raise_with_link_to_help do
          assert_send([params, :is_a?, Hash])
        end

        direct_method_call params = {}
      end
    end
  end
end
