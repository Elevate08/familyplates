# Conversations with the operator, and requests to delete the household.
module Household::Support
  extend ActiveSupport::Concern

  included do
    has_many :support_threads, dependent: :destroy
    has_many :account_deletion_requests, dependent: :destroy
  end
end
