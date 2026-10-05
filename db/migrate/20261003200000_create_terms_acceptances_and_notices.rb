class CreateTermsAcceptancesAndNotices < ActiveRecord::Migration[8.1]
  # Hosted Terms of Service evidence. users.terms_version stays the version a
  # person last agreed to, which is what the app checks; these keep the
  # history.
  #
  # terms_acceptances: each agreement - who, which version, when, and how.
  # terms_notices: each notice that a new version is coming, sent to someone
  # who agreed to an earlier one, and when it was submitted for delivery. A
  # new version is enforced on them only NOTICE_LEAD_TIME after that.
  #
  # No foreign keys, and no email or IP addresses: the evidence outlives the
  # user and household it names, and keeps only what proves the agreement.
  def change
    create_table :terms_acceptances, id: :string do |t|
      t.string :user_id, null: false
      t.string :household_id
      t.string :terms_version, null: false
      t.string :context, null: false
      t.datetime :accepted_at, null: false
      t.timestamps
    end
    add_index :terms_acceptances, %i[user_id accepted_at]

    create_table :terms_notices, id: :string do |t|
      t.string :user_id, null: false
      t.string :terms_version, null: false
      t.string :previous_terms_version
      t.string :state, null: false, default: "queued"
      t.integer :attempts, null: false, default: 0
      t.datetime :claimed_at
      t.datetime :stated_enforcement_at
      t.datetime :submitted_at
      t.string :last_error
      t.timestamps
    end
    add_index :terms_notices, %i[user_id terms_version], unique: true
    add_index :terms_notices, :state
  end
end
