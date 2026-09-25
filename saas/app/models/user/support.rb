module User::Support
  extend ActiveSupport::Concern

  included do
    has_many :support_threads, foreign_key: :created_by_user_id, dependent: :nullify
    has_many :support_messages, dependent: :nullify
    has_many :account_deletion_requests, foreign_key: :requested_by_user_id, dependent: :nullify
  end
end
