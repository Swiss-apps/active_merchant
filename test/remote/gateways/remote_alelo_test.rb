require 'test_helper'

class RemoteAleloTest < Test::Unit::TestCase
  def setup
    @gateway = AleloGateway.new(fixtures(:alelo))

    @amount = 100
    @credit_card = credit_card('4000100011112224')
    @declined_card = credit_card('4000300011112220')
    @options = {
      billing_address: address,
      description: 'Store Purchase'
    }
  end

  def test_access_token_success
    options = {}
    @gateway.send(:access_token, options)

    refute_nil options[:access_token]
  end

  def test_failure_access_token_with_invalid_keys
    gateway = AleloGateway.new({ client_id: 'abc123', client_secret: 'abc456' })

    options = {}
    gateway.send(:access_token, options)
  end

  def test_successful_remote_encryption_key_with_provided_access_token
    options = {}
    access_token = @gateway.send(:access_token, options)

    options = { access_token: access_token }
    resp = @gateway.send(:remote_encryption_key, options)

    assert_equal options[:access_token], access_token
    assert resp.is_a? String
  end

  def test_success_remote_encryption_key_without_access_token
    options = {}
    resp = @gateway.send(:remote_encryption_key, options)

    refute_nil resp
    assert_equal resp, @gateway.send(:remote_encryption_key, options)
  end

  def test_succesfull_failure_recovery_with_expired_access_token_on_encryption_key_generation
    options = { access_token: 'abc123' }

    resp = @gateway.send(:remote_encryption_key, options)

    refute_equal options[:access_token], 'abc123'
    refute_nil resp
  end

  def test_successful_purchase
    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'REPLACE WITH SUCCESS MESSAGE', response.message
  end

  def test_successful_purchase_with_more_options
    options = {
      order_id: '1',
      ip: '127.0.0.1',
      email: 'joe@example.com'
    }

    response = @gateway.purchase(@amount, @credit_card, options)
    assert_success response
    assert_equal 'REPLACE WITH SUCCESS MESSAGE', response.message
  end

  def test_failed_purchase
    response = @gateway.purchase(@amount, @declined_card, @options)
    assert_failure response
    assert_equal 'REPLACE WITH FAILED PURCHASE MESSAGE', response.message
  end

  def test_successful_authorize_and_capture
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert capture = @gateway.capture(@amount, auth.authorization)
    assert_success capture
    assert_equal 'REPLACE WITH SUCCESS MESSAGE', capture.message
  end

  def test_failed_authorize
    response = @gateway.authorize(@amount, @declined_card, @options)
    assert_failure response
    assert_equal 'REPLACE WITH FAILED AUTHORIZE MESSAGE', response.message
  end

  def test_partial_capture
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert capture = @gateway.capture(@amount - 1, auth.authorization)
    assert_success capture
  end

  def test_failed_capture
    response = @gateway.capture(@amount, '')
    assert_failure response
    assert_equal 'REPLACE WITH FAILED CAPTURE MESSAGE', response.message
  end

  def test_successful_refund
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

    assert refund = @gateway.refund(@amount, purchase.authorization)
    assert_success refund
    assert_equal 'REPLACE WITH SUCCESSFUL REFUND MESSAGE', refund.message
  end

  def test_partial_refund
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

    assert refund = @gateway.refund(@amount - 1, purchase.authorization)
    assert_success refund
  end

  def test_failed_refund
    response = @gateway.refund(@amount, '')
    assert_failure response
    assert_equal 'REPLACE WITH FAILED REFUND MESSAGE', response.message
  end

  def test_successful_void
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert void = @gateway.void(auth.authorization)
    assert_success void
    assert_equal 'REPLACE WITH SUCCESSFUL VOID MESSAGE', void.message
  end

  def test_failed_void
    response = @gateway.void('')
    assert_failure response
    assert_equal 'REPLACE WITH FAILED VOID MESSAGE', response.message
  end

  def test_successful_verify
    response = @gateway.verify(@credit_card, @options)
    assert_success response
    assert_match %r{REPLACE WITH SUCCESS MESSAGE}, response.message
  end

  def test_failed_verify
    response = @gateway.verify(@declined_card, @options)
    assert_failure response
    assert_match %r{REPLACE WITH FAILED PURCHASE MESSAGE}, response.message
  end

  def test_invalid_login
    gateway = AleloGateway.new(login: '', password: '')

    response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_match %r{REPLACE WITH FAILED LOGIN MESSAGE}, response.message
  end

  def test_dump_transcript
    # This test will run a purchase transaction on your gateway
    # and dump a transcript of the HTTP conversation so that
    # you can use that transcript as a reference while
    # implementing your scrubbing logic.  You can delete
    # this helper after completing your scrub implementation.
    dump_transcript_and_fail(@gateway, @amount, @credit_card, @options)
  end

  def test_transcript_scrubbing
    transcript = capture_transcript(@gateway) do
      @gateway.purchase(@amount, @credit_card, @options)
    end
    transcript = @gateway.scrub(transcript)

    assert_scrubbed(@credit_card.number, transcript)
    assert_scrubbed(@credit_card.verification_value, transcript)
    assert_scrubbed(@gateway.options[:password], transcript)
  end
end
