module ActiveMerchant
  module Billing
    class CelerisPayGateway < Gateway
      include Empty

      self.test_url = 'https://stagapi.celerispay.com/partnerapi'
      self.live_url = 'https://celerispay.com/partnerapi'
      self.default_currency = 'USD'
      self.homepage_url = 'https://celerispay.com/'
      self.supported_cardtypes = %w[american_express astropay_card cartasi carte_bleue cmr_falabella cordial dankort diners_club discover hipercard jcb laser master_card maestro maestro_uk postepay presto rupay solo unionpay visacard visa_electron vpay]
      self.display_name = 'CelerisPay'

      SUCCESS_CODES = [200, 201, 202]
      SOFT_DECLINE_CODES = [417]

      def initialize(options = {})
        requires!(options, :merchant_id, :access_token, :fingerprint)
        super

        init_config
      end

      def purchase(amount, payment_method, options)
        post = {}
        set_merchant_details
        set_address_details(options)
        set_customer_details
        set_payment_details(payment_method, options)
        set_transaction(amount, options)
        set_redirect_url(options)
        set_dynamic_descriptor(post, options)
        set_three_d_secure(options)

        initiate_payment
        response = @payment.without_hpp

        generate_response(response)
      rescue Celeris::ApplicationError => e
        generate_response(e.response)
      end

      def refund(amount, authorization, options)
        post = {}
        set_merchant_details
        set_refund_details(amount, authorization)

        response = @refund.execute

        generate_response(response)
      rescue Celeris::ApplicationError => e
        generate_response(e.response)
      end

      def store(payment_method, options)
        set_merchant_details
        set_card_details(payment_method, options)

        initiate_token
        response = @token.save_card(options[:customer_id]&.to_s, @card_detail)

        generate_response(response)
      rescue Celeris::ApplicationError => e
        generate_response(e.response)
      end

      def confirm(authorization)
        set_merchant_details
        init_transaction_status

        response = @payment.transaction_status(authorization)

        generate_response(response)
      rescue Celeris::ApplicationError => e
        generate_response(e.response)
      end

      private

      def set_merchant_details
        @merchant = ::Celeris::Merchant.new(@options[:merchant_id])
      end

      def set_address_details(options)
        return unless options[:billing_address].present?

        first_name, last_name = split_names(options[:billing_address][:name])
        phoneNo = options[:billing_address][:phone]

        @address = ::Celeris::Address.new(first_name, last_name, options[:email], phoneNo)
      end

      def set_customer_details
        @customer = ::Celeris::Customer.new(@address)
      end

      def set_payment_details(payment_method, options)
        if payment_method.is_a?(String)
          token = payment_method
          @payment_detail = ::Celeris::TokenId.new(token)
        else
          number = payment_method.number
          month = format(payment_method.month, :two_digits)
          year = format(payment_method.year, :four_digits)
          name_on_card = options[:billing_address] ? options[:billing_address][:name] : ''
          card_type = payment_method.cc_type
          cvv = empty?(payment_method.verification_value) ? '' : payment_method.verification_value

          @payment_detail = ::Celeris::CardDetail.new(number, year, month, name_on_card, card_type, cvv)
        end
      end

      def set_transaction(amount, options)
        currency = options[:currency]
        txnReference = options[:order_id]
        paymentMode = 'CreditCard'

        @transaction = ::Celeris::Transaction.new(amount, currency, txnReference, paymentMode)
        @transaction.paymentDetail = @payment_detail
      end

      def set_redirect_url(options)
        return unless options[:redirect_links]
        redirect_links = options[:redirect_links]

        @url = ::Celeris::Url.new(redirect_links[:success_url], redirect_links[:failure_url], redirect_links[:failure_url])
      end

      def set_dynamic_descriptor(post, options)
        post[:dynamic_descriptor] = {}
        post[:dynamic_descriptor][:name] = options[:billing_address][:name] if options[:billing_address]
        post[:dynamic_descriptor][:email] = options[:email]
        post[:dynamic_descriptor][:mobile] = options[:billing_address][:phone] if options[:billing_address]

        @dynamic_descriptor = ::Celeris::DynamicDescriptor.new
        @dynamic_descriptor.name = post[:dynamic_descriptor][:name]
        @dynamic_descriptor.email = post[:dynamic_descriptor][:email]
        @dynamic_descriptor.mobile = post[:dynamic_descriptor][:mobile]
      end

      def initiate_payment
        @payment = ::Celeris::Payment.new(@config)
        @payment.merchant = @merchant
        @payment.customer = @customer
        @payment.transaction = @transaction
        @payment.url = @url
        @payment.dynamicDescriptor = @dynamic_descriptor
        @payment.sync!
      end

      def set_card_details(payment_method, options)
        number = payment_method.number
        month = format(payment_method.month, :two_digits)
        year = format(payment_method.year, :four_digits)
        name_on_card = options[:billing_address] ? options[:billing_address][:name] : ''
        card_type = payment_method.cc_type

        @card_detail = ::Celeris::CardDetail.new(number, year, month, name_on_card, card_type)
      end

      def initiate_token
        @token = ::Celeris::Token.new(@config)
      end

      def set_refund_details(amount, authorization)
        txn_reference = authorization
        refund_amount = amount

        @refund = ::Celeris::RefundTransaction.new(@config)
        @refund.create_refund(txn_reference, refund_amount)
      end

      def init_transaction_status
        @payment = ::Celeris::Payment.new(@config)
      end

      def set_three_d_secure(options)
        return unless options[:browser_details].present?
        device_fingerprint = ::Celeris::DeviceFingerprint.new
        browser_details = options[:browser_details]

        device_fingerprint.timezone = browser_details[:time_zone]
        device_fingerprint.browserScreenWidth, device_fingerprint.browserScreenHeight, device_fingerprint.browserColorDepth = browser_details_screen_size(browser_details)
        device_fingerprint.browserLanguage = browser_details[:accept_language]
        device_fingerprint.os = "windows"
        device_fingerprint.browserAcceptHeader = browser_details[:accept_content]
        device_fingerprint.userAgent = browser_details[:identity]
        device_fingerprint.browserJavascriptEnabled = browser_details[:capabilities] == 'javascript' ? true : false
        device_fingerprint.browserJavaEnabled = browser_details[:capabilities] ? false : true
        device_fingerprint.acceptContent = browser_details[:accept_content]
        device_fingerprint.browserIP = options[:ip]

        @three_d_secure = ::Celeris::ThreeDSecure.new(device_fingerprint)
      end

      def browser_details_screen_size(browser_details)
        browser_details[:screen_resolution].split('x') if browser_details[:screen_resolution]
      end

      def generate_response(response)
        parsed_response = JSON.parse(response.body)
        response_code = parsed_response["response"] ? parsed_response["response"]["responseCode"] : ''
        response_message = parsed_response["response"] ? parsed_response["response"]["description"] : response.reason_phrase

        if response.success?
          generate_success_response(response, parsed_response, response_code, response_message)
        else
          generate_failure_response(response, parsed_response, response_code, response_message)
        end
      end

      def generate_success_response(response, parsed_response, response_code, response_message)
        ActiveMerchant::Billing::Response.new(
          true,
          response_message,
          parsed_response,
          {
            authorization: authorization_from(parsed_response),
            response_http_code: response.env&.status,
            request_endpoint: response.env&.url&.to_s,
            request_method: response.env&.method,
            request_body: response.env&.request_body,
            response_type: response_type(response_code),
            test: test?
          }
        )
      end

      def generate_failure_response(response, parsed_response, response_code, response_message)
        ActiveMerchant::Billing::Response.new(
          false,
          response_message,
          parsed_response,
          {
            error_code: response_code,
            response_http_code: response.env&.status,
            request_endpoint: response.env&.url&.to_s,
            request_method: response.env&.method,
            request_body: response.env&.request_body,
            response_type: response_type(response_code),
            test: test?
          }
        )
      end

      def authorization_from(response)
        response["response"] ? response["response"]["txnReference"] : ''
      end

      def response_type(code)
        if SUCCESS_CODES.include?(code)
          0
        elsif SOFT_DECLINE_CODES.include?(code)
          1
        else
          2
        end
      end

      def init_config
        @config = ::Celeris::Config.new(@options[:merchant_id], @options[:access_token], @options[:fingerprint])
        @config.staging! if test?
      end
    end
  end
end
