module Yandex
  module Direct
    module Helpers
      def fib n
        return n if (0..1).include? n

        fib(n - 1) + fib(n - 2) if n > 1
      end

      def sleep_iterator retry_count
        (2..(retry_count + 1)).map { |step| fib step }
      end

      def retry_block retry_count = (Rails.env.test? ? 1 : 5), exceptions = [], &block
        iterator = sleep_iterator retry_count

        begin
          result = block.()

          break
        rescue *exceptions => e
          raise e if Rails.env.test?

          Rails.logger.error "retry_block! #{e.class} => #{e}\n#{e.backtrace.join("\n")}"

          timeout = iterator.shift

          sleep(timeout) unless Rails.env.test?
          retry_count -= 1

          raise e if retry_count.zero?
        end while retry_count > 0

        result
      end

      def convert_value value
        if value == 'Yes'
          true
        elsif value == 'No'
          false
        elsif value =~ /\A\d{4}\-\d{2}\-\d{2}\z/
          Date.parse value
        elsif value.is_a?(Hash) || value.is_a?(Array)
          convert_response value
        else
          value
        end
      end

      def convert_hash response
        HashWithIndifferentAccess[
            underscore_hash_keys(response).map { |key, value|
              [key, convert_value(value)]
            }
        ]
      end

      def convert_response response
        if response.is_a?(Hash)
          convert_hash response
        elsif response.is_a?(Array)
          response.map { |item| convert_response item }
        else
          response
        end
      end
  
      def underscore_hash_keys hash
        result = hash.map do |key, value|
          value = underscore_hash_keys value if value.is_a?(Hash)

          [key.to_s.underscore, value]
        end

        HashWithIndifferentAccess[result]
      end
  
      def set_date_with_format value, format
        if value.is_a?(Date) || value.is_a?(DateTime) || value.is_a?(Time)
          value.to_date.strftime(format)
        else
          value
        end
      end

      def set_date_format_for_hash hash, format = '%Y-%m-%d'
        result = hash.map do |key, value|
          value = set_date_with_format(value, format)
          value = set_date_format_for_hash(value, format) if value.is_a?(Hash) || value.is_a?(HashWithIndifferentAccess)

          [key, value]
        end

        Hash[result]
      end

      def get_state_from_hash hash
        hash = HashWithIndifferentAccess.new hash

        if hash[:status_archive]
          :archive
        elsif hash[:status_show]
          :showing
        elsif hash[:is_active]
          :active
        elsif hash[:status_activating] == true
          :running
        elsif [:status_moderate, :status_activating, :status_banner_moderate].any? { |_| hash[_] == 'Pending' }
          :pending
        elsif [:status_moderate, :status_banner_moderate].any? { |_| hash[_] == 'New' }
          :on_moderation
        elsif [:status_moderate, :status_banner_moderate].any? { |_| hash[_] == false }
          :fail_moderation
        else
          :unknown
        end
      end

      def convert_to_direct_value value
        if value.is_a?(TrueClass) || value.is_a?(FalseClass)
          value ? 'Yes' : 'No'
        else
          value
        end
      end
    end
  end
end
