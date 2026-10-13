class CreateRegions < ActiveRecord::Migration[8.0]
  def change
    create_table :regions do |t|
      t.string :code, null: false
      t.string :edition, null: false
      t.string :name_de, null: false
      t.string :name_en, null: false
      t.text :aliases_de, default: "[]"
      t.text :aliases_en, default: "[]"

      t.timestamps
    end

    add_index :regions, :code, unique: true
    add_index :regions, :edition
  end
end
