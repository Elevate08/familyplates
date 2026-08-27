class AddPinToFamilyMembersAndEmojiToPantryItems < ActiveRecord::Migration[8.1]
  def change
    add_column :family_members, :pin, :string
    add_column :pantry_items, :emoji, :string
  end
end
