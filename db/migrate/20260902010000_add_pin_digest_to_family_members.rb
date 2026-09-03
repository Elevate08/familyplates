class AddPinDigestToFamilyMembers < ActiveRecord::Migration[8.1]
  # Phase one of two: add the digest column and backfill it, leaving the
  # plaintext column in place. Separating the drop into its own migration means
  # this one can be rolled back on a live SQLite volume without stranding an
  # organizer outside their own admin profile.
  def up
    add_column :family_members, :pin_digest, :string

    say_with_time "backfilling pin_digest from plaintext pins" do
      backfilled = 0
      FamilyMember.reset_column_information
      FamilyMember.where.not(pin: [ nil, "" ]).find_each do |member|
        member.update_columns(pin_digest: BCrypt::Password.create(member.pin))
        backfilled += 1
      end
      backfilled
    end
  end

  def down
    remove_column :family_members, :pin_digest
  end
end
