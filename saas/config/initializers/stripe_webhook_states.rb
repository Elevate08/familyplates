# frozen_string_literal: true

# Pay syncs charge.succeeded, charge.updated, and charge.refunded. Stripe also
# sends charge.failed, charge.pending, and charge.dispute.created for the
# states an operator has to see. A dispute's payload is the dispute, not the
# charge, so that event syncs the charge it names.
class StripeChargeStateSync
  def call(event)
    object = event.data.object
    if object.object == "dispute"
      Pay::Stripe::Charge.sync(object.charge)
    else
      Pay::Stripe::Charge.sync(object.id)
    end
  end
end

# A new subscription is when a promotion code is redeemed.
class PromotionRedemptionSync
  def call(_event)
    PromotionProgram.refresh_redemptions!
  end
end

Pay::Webhooks.configure do |events|
  handler = StripeChargeStateSync.new
  events.subscribe "stripe.charge.failed", handler
  events.subscribe "stripe.charge.pending", handler
  events.subscribe "stripe.charge.dispute.created", handler
  events.subscribe "stripe.customer.subscription.created", PromotionRedemptionSync.new
end
