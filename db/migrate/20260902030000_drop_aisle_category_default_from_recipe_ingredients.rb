class DropAisleCategoryDefaultFromRecipeIngredients < ActiveRecord::Migration[8.1]
  # The column defaulted to "Other", so a new ingredient was never "unset" - it
  # arrived already claiming an aisle. That is why the model treated "Other" as
  # a synonym for blank and re-classified over it, which in turn overwrote the
  # aisle of anyone who deliberately chose "Other" in the form.
  #
  # With no default, absent means absent. The model still guarantees a value
  # before save, so the NOT NULL constraint stays.
  def up
    change_column_default :recipe_ingredients, :aisle_category, from: "Other", to: nil
  end

  def down
    change_column_default :recipe_ingredients, :aisle_category, from: nil, to: "Other"
  end
end
