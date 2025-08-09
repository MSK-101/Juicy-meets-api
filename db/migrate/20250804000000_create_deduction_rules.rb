class CreateDeductionRules < ActiveRecord::Migration[7.2]
  def change
    create_table :deduction_rules do |t|
      t.string  :name
      t.integer :threshold_seconds, null: false
      t.integer :coins, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :deduction_rules, :active
    add_index :deduction_rules, :threshold_seconds, unique: true
  end
end
