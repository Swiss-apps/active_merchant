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
      end

      def purchase(amount, payment_method, options = {})
        post = {}
        add_invoice(post, amount, payment_method, options)
        add_payment_method(post, payment_method, options)
        add_customer_details(post, options)
        add_three_d_secure_data(post, options)
        add_redirect_url(post, options)
        # commit
      end

      def refund(amount, authorization, options = {})
        post = {}
        add_refund_details(post, amount, options)
        # commit
      end

      def store(payment_method, options = {})
        post = {}
        save_payment_details(post, payment_method, options)
        # commit
      end

      def confirm(options = {})
        post = { txnReference: options[:order_id] }
        # commit
      end

      private

      def add_payment_method(post, payment_method, options)
        post[:transaction][:paymentDetail] = {}
        if payment_method.is_a?(String)
          post[:transaction][:paymentDetail][:tokenID] = payment_method
        else
          post[:transaction][:paymentDetail][:cardNumber] = payment_method.number
          post[:transaction][:paymentDetail][:expMonth] = format(payment_method.month, :two_digits)
          post[:transaction][:paymentDetail][:expYear] = format(payment_method.year, :four_digits)
          post[:transaction][:paymentDetail][:cvv] = payment_method.verification_value unless empty?(payment_method.verification_value)
        end
      end

      def add_invoice(amount, post, options)
        post[:transaction] = {}
        post[:transaction][:txnAmount] = amount
        post[:transaction][:paymentMode] = 'CreditCard'
        post[:transaction][:currencyCode] = options[:currency]
        post[:transaction][:txnReference] = options[:order_id]
      end

      def add_customer_details(post, options)
        post[:customer] = {}
        post[:customer][:ipAddress] = options[:ip]
        post[:customer][:email] = options[:email]
        if options[:billing_address].present?
          first_name, _ = split_names(options[:billing_address][:name])
          options[:customer][:billing_address] = {}
          options[:customer][:billing_address][:firstName] = first_name
          options[:customer][:billing_address][:addressLine1] = options[:billing_address][:address1]
          options[:customer][:billing_address][:city] = options[:billing_address][:city]
          options[:customer][:billing_address][:state] = options[:billing_address][:state]
          options[:customer][:billing_address][:zip] = options[:billing_address][:zip]
          options[:customer][:billing_address][:country] = options[:billing_address][:country]
          options[:customer][:billing_address][:mobileNo] = options[:billing_address][:phone]
        end
      end

      def add_redirect_url(post, options)
        post[:url] = {}
        redirect_links = options[:redirect_links]

        post[:url][:successURL] = redirect_links[:success_url] if redirect_links
        post[:url][:failURL] = redirect_links[:failure_url] if redirect_links
        post[:url][:cancelURL] = redirect_links[:failure_url] if redirect_links
      end

      def add_refund_details(amount, options)
        post[:refund] = {}
        post[:refund][:refundAmount] = amount
        post[:refund][:txnReference] = options[:order_id]
      end

      def add_three_d_secure_data(post, options)
        if options[:three_d_secure].present?
          post[:transaction][:"3DSecure"] = {}
          post[:transaction][:"3DSecure"][:externalThreeds] = {}
          post[:transaction][:"3DSecure"][:externalThreeds][:xid] = options[:three_d_secure_data][:xid]
          post[:transaction][:"3DSecure"][:externalThreeds][:eciCode] = options[:three_d_secure][:eci]
          post[:transaction][:"3DSecure"][:externalThreeds][:authenticationValue] = options[:three_d_secure][:authenticationValue]
          post[:transaction][:"3DSecure"][:externalThreeds][:threedsServerTransactionId] = options[:three_d_secure][:threedsServerTransactionId]
        end
      end

      def save_payment_details(post, payment_method, options)
        post[:card] = {}
        post[:card][:cardNumber] = payment_method.number
        post[:card][:expMonth] = format(payment_method.month, :two_digits)
        post[:card][:expYear] = format(payment_method.year, :four_digits)
        post[:card][:nameOnCard] = options[:billing_address][:name]
        post[:card][:cardType] = payment_method.card_type # need card brand here to run store API
        # cvv can not be saved
      end

      def commit(action, params, authorization=nil)
        params[:merchant] = { merchantID: @options[:merchant_id] }
        request_body = post_data(action, params)
        raw_response = ssl_request(:post, base_url, request_body, headers)
        response = JSON.parse(raw_response)

        succeeded = success_from(response)
        Response.new(
          succeeded,
          message_from(succeeded, response),
          response,
          authorization: authorization_from(response, params["paymentType"]),
          response_type: response_type(response.dig('result', 'code')),
          test: test?,
          response_http_code: @response_http_code,
          request_endpoint:,
          request_method: method,
          request_body: params
        )
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

      def base_url
        test? ? test_url : live_url
      end

      def headers
      end
    end
  end
end
