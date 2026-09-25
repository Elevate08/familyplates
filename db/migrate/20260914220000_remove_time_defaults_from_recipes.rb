# A recipe's prep and cook time are facts about the recipe, not guesses. The
# column defaults stamped 15 and 20 minutes onto any recipe that did not state
# them, which then read as real timings on the card and in Cook Mode. Existing
# rows are left alone: there is no way to tell a defaulted 20 from a real one.
class RemoveTimeDefaultsFromRecipes < ActiveRecord::Migration[8.1]
  def change
    change_column_default :recipes, :prep_time, from: 15, to: nil
    change_column_default :recipes, :cook_time, from: 20, to: nil
  end
end
