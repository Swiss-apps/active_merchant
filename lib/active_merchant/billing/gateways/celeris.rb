module ActiveMerchant
  module Billing
    class CelerisGateway < Gateway
      include Empty

      self.test_url = 'https://stagapi.celerispay.com/partnerAPI'
      self.live_url = 'https://celerispay.com/partnerAPI'
      self.default_currency = 'USD'
      self.homepage_url = 'https://celerispay.com/'
      self.supported_cardtypes = %w[CARTASI CARTEBLEUE CMRFalabella Cordial DANKORT DinersClub DISCOVER HIPERCARD JCB LASER MasterCard Maestro MaestroUK POSTEPAY Presto Rupay SOLO UNIONPAY VisaCard VISAELECTRON VPAY AMEX]
      self.display_name = 'CelerisPay'

      SUCCESS_CODES = [200 201]

      def initialize(options = {})
        requires!(options, :merchant_id, :access_token)
        super
      end

      def purchase(amount, payment_method, options = {})
        post = {}
        add_transaction_details(post, amount, payment_method, options)
        add_customer_details(post, options)
        add_three_d_secure_data(post, options)
        add_redirect_url(post, options)
        # commit
      end

      def refund(amount, options = {})
        post = {}
        add_refund_details(post, amount, options)
        # commit
      end

      def confirm(options = {})
        post = { txnReference: options[:order_id] }
        # commit
      end

      private

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

      def add_transaction_details(amount, post, payment_method, options)
        post[:transaction] = {}
        post[:transaction][:paymentDetail] = {}
        post[:transaction][:txnAmount] = amount
        post[:transaction][:paymentMode] = 'CreditCard'
        post[:transaction][:currencyCode] = options[:currency]
        post[:transaction] = { orderId: options[:order_id], txnReference: options[:order_id] }
        post[:transaction][:isApp] = true # open 3DS view

        post[:transaction][:paymentDetail][:cardNumber] = payment_method.number
        post[:transaction][:paymentDetail][:expMonth] = format(payment_method.month, :two_digits)
        post[:transaction][:paymentDetail][:expYear] = format(payment_method.year, :four_digits)
        post[:transaction][:paymentDetail][:nameOnCard] = payment_method.name
        post[:transaction][:paymentDetail][:cvv] = payment_method.verification_value unless empty?(payment_method.verification_value)
      end

      def add_customer_details(post, options)
        post[:customer] = {}
        post[:customer][:ipAddress] = options[:ip]
        post[:customer][:email] = options[:email]
        if options[:billing_address].present?
          options[:customer][:billing_address] = {}
          options[:customer][:billing_address][:firstName] = options[:billing_address][:name]
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
        post[:url][:successURL] = options[:redirect_links][:success_url]
        post[:url][:failURL] = options[:redirect_links][:success_url]
        post[:url][:cancelURL] = options[:redirect_links][:success_url]
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

      def base_url
        test? ? test_url : live_url
      end

      def headers
        # headers = { 'Authorization' => 'Bearer ' + @options[:token] }
        # headers
      end
    end
  end
end
