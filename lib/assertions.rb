require 'minitest/unit'
require 'pp'

module Test
  module Unit
    module Assertions
      include MiniTest::Assertions

      def assert_not_blank exp, msg = nil
        msg = message(msg) { "<#{mu_pp(exp)}> expected to not be blank" }
        assert(!exp.blank?, msg)
      end
    end
  end
end
