class ConvertQuickTagInRecipes < ActiveRecord::Migration[8.0]
  def up
    Recipe.where("tags LIKE ?", "%Quick (<30m)%").find_each do |recipe|
      new_tags = recipe.tags.gsub("Quick (<30m)", "Quick").split(",").map(&:strip).uniq.join(", ")
      recipe.update_columns(tags: new_tags)
    end
  end

  def down
    # No rollback needed
  end
end
