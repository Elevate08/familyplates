class CreateFamilyMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :family_members do |t|
      t.references :household, null: false, foreign_key: true
      t.string :name, null: false
      t.string :avatar_color, default: "#3B82F6"
      t.string :avatar_icon, default: "chef-hat"
      t.string :role, default: "member"

      t.timestamps
    end
  end
end
