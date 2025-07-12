class CreateCoinPackages < ActiveRecord::Migration[7.2]
  def change
    create_table :coin_packages do |t|
      t.string :name, null: false
      t.decimal :price, precision: 10, scale: 2, null: false
      t.integer :coins_count, null: false
      t.boolean :active, default: true
      t.text :description
      t.integer :sort_order, default: 0

      t.timestamps
    end

    add_index :coin_packages, :active
    add_index :coin_packages, :sort_order
  end
end
