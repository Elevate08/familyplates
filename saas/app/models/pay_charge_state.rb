# frozen_string_literal: true

# How an operator should read one Pay charge. Pay stores the Stripe Charge
# object, whose status is only succeeded, pending, or failed. Dispute, refund,
# and capture are separate fields on that object, and a dispute outranks a
# refund because that is the one an operator has to answer.
class PayChargeState
  def self.for(charge)
    new(charge)
  end

  def initialize(charge)
    @charge = charge
    @object = (charge.object || {}).stringify_keys
  end

  def key
    return :disputed if disputed?
    return :failed if @object["status"] == "failed"
    return :pending if @object["status"] == "pending"
    return :uncaptured if uncaptured?
    return :refunded if @charge.full_refund? || @object["refunded"] == true
    return :partially_refunded if @charge.partial_refund?
    return :paid if @object["status"].blank? || @object["status"] == "succeeded"

    :other
  end

  def label
    case key
    when :disputed then "Disputed"
    when :failed then "Failed"
    when :pending then "Pending"
    when :uncaptured then "Uncaptured"
    when :refunded then "Refunded"
    when :partially_refunded then "Partially refunded"
    when :paid then "Paid"
    else @object["status"].to_s.humanize
    end
  end

  def tone_classes
    case key
    when :disputed, :failed
      "bg-rose-100 text-rose-800 dark:bg-rose-950 dark:text-rose-300"
    when :pending, :uncaptured
      "bg-amber-100 text-amber-800 dark:bg-amber-950 dark:text-amber-300"
    when :refunded, :partially_refunded
      "bg-slate-200 text-slate-700 dark:bg-slate-800 dark:text-slate-300"
    else
      "bg-emerald-100 text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300"
    end
  end

  private

  def disputed?
    @object["disputed"] == true || @object["dispute"].present?
  end

  def uncaptured?
    @object.key?("captured") && @object["captured"] == false && @object["status"] == "succeeded"
  end
end
