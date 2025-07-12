class CreateCoinDeductionRules < ActiveRecord::Migration[7.2]
  def change
    create_table :coin_deduction_rules do |t|
      t.string :name, null: false
      t.integer :duration_seconds, null: false
      t.integer :coins_deducted, null: false
      t.boolean :active, default: true
      t.text :description
      t.integer :sort_order, default: 0

      t.timestamps
    end

    add_index :coin_deduction_rules, :active
    add_index :coin_deduction_rules, :sort_order
  end
end
