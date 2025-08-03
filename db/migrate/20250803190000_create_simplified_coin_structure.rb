class CreateSimplifiedCoinStructure < ActiveRecord::Migration[7.2]
  def change
    # Add coin_balance to users table
    add_column :users, :coin_balance, :integer, default: 0, null: false

    # Create purchases table (simplified from user_coin_purchases)
    create_table :purchases do |t|
      t.references :user, null: false, foreign_key: true
      t.references :coin_package, null: false, foreign_key: true
      t.integer :coins_count, null: false
      t.decimal :price, precision: 10, scale: 2, null: false
      t.string :transaction_id
      t.string :payment_status, default: 'pending'
      t.datetime :purchased_at
      t.timestamps

      t.index [:user_id, :created_at]
      t.index :payment_status
      t.index :transaction_id, unique: true
    end

    # Create simplified coin_transactions table
    create_table :coin_transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :amount, null: false
      t.integer :balance_after, null: false
      t.string :transaction_type, default: 'credit', null: false
      t.string :description
      t.integer :reference_id
      t.string :reference_type
      t.timestamps

      t.index :transaction_type
      t.index [:user_id, :created_at]
      t.index [:reference_type, :reference_id]
    end

    # Add indexes for better performance
    add_index :users, :coin_balance
  end
end
