# frozen_string_literal: true

# One service sends all customer email: the app, through its own SMTP.
# Billing email comes from Pay's mailer, not Stripe, whose customer emails are
# switched off in the Stripe Dashboard.
Pay.setup do |config|
  config.application_name = "FamilyPlates"
  # business_name and business_address stay unset: no company or address
  # exists yet, and the templates render nothing for them.

  # The app's own `from` address and mail layout.
  config.parent_mailer = "ApplicationMailer"

  # The household's billing owner, not whichever account Household#email finds.
  config.mail_arguments = -> {
    {
      to: ActionMailer::Base.email_address_with_name(params[:pay_customer].owner.pay_customer_email, params[:pay_customer].customer_name),
      subject: default_i18n_subject(application: Pay.application_name)
    }
  }

  config.emails.receipt = true
  config.emails.refund = true
  config.emails.payment_failed = true
  config.emails.payment_action_required = true
  # Pay's default: only annual plans get a renewal reminder.

  # FamilyPlates' free trial is not a Stripe trial. A Stripe trial exists only
  # when an operator comps free months on a paying subscription, so "your
  # trial is ending" would mislead a paying customer.
  config.emails.subscription_trial_will_end = false
  config.emails.subscription_trial_ended = false
end

# Pay's invoice.upcoming handler gives the mailer only the date, but a
# subscription with a coupon renews for less than the plan price, and a
# renewal notice has to state what will actually be charged. This reproduces
# Pay 11.7.2's SubscriptionRenewing#call (lib/pay/stripe/webhooks/
# subscription_renewing.rb) and adds the upcoming invoice's amount_due and
# currency. It is a copy, so re-check it against Pay's handler on every Pay
# upgrade.
module PayRenewalAmount
  def call(event)
    invoice = event.data.object
    subscription_id = invoice.parent.try(:subscription_details).try(:subscription)

    pay_subscription = Pay::Subscription.find_by_processor_and_id(:stripe, subscription_id)
    return unless pay_subscription

    price = ::Stripe::Price.retrieve({ id: invoice.lines.first.pricing.price_details.price }, { stripe_account: event.try(:account) }.compact)

    if Pay.send_email?(:subscription_renewing, pay_subscription, price) && (next_payment_attempt = invoice.next_payment_attempt)
      Pay.mailer.with(
        pay_customer: pay_subscription.customer,
        pay_subscription: pay_subscription,
        date: Time.zone.at(next_payment_attempt),
        amount_due: invoice.amount_due,
        currency: invoice.currency
      ).subscription_renewing.deliver_later
    end
  end
end

# BillingOffer is autoloaded, so it cannot be named while initializers run.
Rails.application.config.to_prepare do
  Pay.support_email = BillingOffer::SUPPORT_EMAIL

  handler = Pay::Stripe::Webhooks::SubscriptionRenewing
  handler.prepend(PayRenewalAmount) unless handler.ancestors.include?(PayRenewalAmount)
end
