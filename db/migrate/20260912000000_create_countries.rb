class CreateCountries < ActiveRecord::Migration[8.0]
  def change
    create_table :countries do |t|
      t.string :iso2, null: false
      t.string :iso3, null: false
      t.string :sporcle_name, null: false
      t.string :name_de, null: false
      t.string :name_en, null: false
      t.text :aliases_de, default: "[]"
      t.text :aliases_en, default: "[]"
      t.string :difficulty_shape, null: false, default: "medium"
      t.string :difficulty_flag, null: false, default: "medium"

      t.timestamps
    end

    add_index :countries, :iso2, unique: true
    add_index :countries, :iso3, unique: true
    add_index :countries, :sporcle_name, unique: true
    add_index :countries, :difficulty_shape
    add_index :countries, :difficulty_flag
  end
end
