class RemovePlaintextPinFromFamilyMembers < ActiveRecord::Migration[8.1]
  # Phase two: drop the plaintext column now that every PIN is digested.
  # Reversible, but rolling back restores the column empty - the plaintext is
  # gone for good, which is the entire point. Organizers set a new PIN from the
  # Admin Control Center if this is ever rolled back.
  def up
    remove_column :family_members, :pin
  end

  def down
    add_column :family_members, :pin, :string
  end
end
