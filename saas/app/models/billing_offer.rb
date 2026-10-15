# frozen_string_literal: true

require "digest"

# One paid plan as the subscription page offers it: the price, the renewal
# terms the billing owner agrees to, and a signed token that ties their
# agreement to exactly that offer. The page, the consent record, Checkout and
# the acknowledgment email all read from here, so they cannot drift apart.
class BillingOffer
  # How long a rendered offer can be accepted. An older page, or one rendered
  # before the terms or the price changed, has to be reloaded and agreed to again.
  TOKEN_TTL = 30.minutes

  # Subscribing charges at Checkout. The no-card trial never charges on its own.
  IMMEDIATE_CHARGE = "You will be charged today. Your free trial ends when your paid subscription starts."

  SUPPORT_EMAIL = "support@familyplates.org"

  # The owner-approved refund clause, word for word. The acknowledgment email
  # repeats it beside the payment it applies to.
  REFUND_REQUEST = "To request a refund, contact #{SUPPORT_EMAIL} within 7 days of the charge. We may grant a refund. " \
    "Refunds are considered case by case and are not guaranteed, except where a law that applies to that charge requires one."

  attr_reader :plan_key

  def self.for(plan_key)
    key = plan_key.to_s.downcase.to_sym
    new(key) if Household::PLANS.key?(key)
  end

  def self.verifier
    Rails.application.message_verifier(:billing_consent)
  end

  def initialize(plan_key)
    @plan_key = plan_key
    @plan = Household::PLANS.fetch(plan_key)
  end

  def name = @plan[:name]
  def description = @plan[:description]
  def interval = @plan[:interval]
  def currency = @plan[:currency]
  def amount_minor_units = @plan[:amount_minor_units]

  # The Stripe Price from deploy config. Without one, Checkout is given this
  # plan's amount inline.
  def stripe_price_id
    ENV["STRIPE_#{plan_key.to_s.upcase}_PRICE_ID"].presence
  end

  # "$4", or "$4.50" when there are cents.
  def price
    money(amount_minor_units)
  end

  # What one month costs on this plan, rounded to the nearest cent as
  # Stripe's Checkout shows it: $50 a year is "$4.17".
  def monthly_equivalent
    months = interval == "year" ? 12 : 1
    ActiveSupport::NumberHelper.number_to_currency((amount_minor_units.to_r / months).round / 100.0)
  end

  # Whole percent saved against paying for twelve months of the other offer.
  def savings_percent_against(monthly)
    return 0 unless interval == "year" && monthly.interval == "month"

    ((1 - amount_minor_units.to_r / (monthly.amount_minor_units * 12)) * 100).floor
  end

  def disclosure_sentences
    [
      "The FamilyPlates #{name} plan is #{price} #{currency.upcase} per #{interval}. It renews automatically every #{interval} until you cancel.",
      IMMEDIATE_CHARGE,
      "Cancel anytime on the Subscription & Billing page in FamilyPlates. Canceling stops the next renewal, and you keep access until the end of the period you have paid for.",
      REFUND_REQUEST,
      "Otherwise, payments are not refunded for the rest of a billing period after you cancel, except where required by law."
    ]
  end

  def disclosure
    disclosure_sentences.join(" ")
  end

  # Changes whenever anything the billing owner agrees to changes, so a page
  # rendered before the change cannot be accepted after it.
  def digest
    Digest::SHA256.hexdigest(
      [ Legal::TERMS_VERSION, plan_key, amount_minor_units, currency, interval, stripe_price_id.to_s, disclosure ].join("\u0000")
    )
  end

  def token_for(household:, user:)
    self.class.verifier.generate(token_payload(household, user), purpose: :billing_consent, expires_in: TOKEN_TTL)
  end

  # The token was rendered for this offer, as it stands now, to this user
  # for this household, and has not expired.
  def accepted_token?(token, household:, user:)
    return false if token.blank? || household.nil? || user.nil?

    self.class.verifier.verified(token.to_s, purpose: :billing_consent) == token_payload(household, user)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError
    false
  end

  # Stripe has to charge what the page shows. A configured Price that differs
  # in amount, currency or interval, or is archived, stops Checkout rather than
  # charging something the billing owner did not agree to.
  def stripe_price_matches?
    return true if stripe_price_id.nil?

    price = ::Stripe::Price.retrieve(stripe_price_id)
    recurring = price[:recurring]
    price[:active] == true &&
      price[:unit_amount] == amount_minor_units &&
      price[:currency].to_s.downcase == currency &&
      !recurring.nil? && recurring[:interval] == interval && recurring[:interval_count] == 1
  end

  # Checkout's line item: the configured Price, or this plan's amount inline.
  def checkout_line_item
    return { price: stripe_price_id, quantity: 1 } if stripe_price_id

    {
      price_data: {
        currency: currency,
        unit_amount: amount_minor_units,
        recurring: { interval: interval },
        product_data: { name: "FamilyPlates #{name} Plan", description: description }
      },
      quantity: 1
    }
  end

  private

  def token_payload(household, user)
    { "household_id" => household.id.to_s, "user_id" => user.id.to_s, "plan" => plan_key.to_s, "digest" => digest }
  end

  def money(minor_units)
    self.class.format_money(minor_units)
  end

  # "$5" or "$4.50", with the currency code appended when one is given.
  def self.format_money(minor_units, currency = nil)
    precision = (minor_units % 100).zero? ? 0 : 2
    amount = ActiveSupport::NumberHelper.number_to_currency(minor_units / 100.0, precision: precision)
    currency ? "#{amount} #{currency.to_s.upcase}" : amount
  end
end
