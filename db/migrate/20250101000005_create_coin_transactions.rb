class CreateCoinTransactions < ActiveRecord::Migration[7.2]
  def change
    create_table :coin_transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :transaction_type, null: false # 'purchase', 'deduction', 'bonus', 'refund'
      t.integer :amount, null: false # positive for credits, negative for debits
      t.integer :balance_after, null: false
      t.references :coin_package, foreign_key: true
      t.references :coin_deduction_rule, foreign_key: true
      t.references :user_coin_purchase, foreign_key: true
      t.string :reference_id # for external payment systems
      t.text :description
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :coin_transactions, :transaction_type
    add_index :coin_transactions, :reference_id
    add_index :coin_transactions, :metadata, using: :gin
  end
end
