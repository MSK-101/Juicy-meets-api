class CreateUserCoinPurchases < ActiveRecord::Migration[7.2]
  def change
    create_table :user_coin_purchases do |t|
      t.references :user, null: false, foreign_key: true
      t.references :coin_package, null: false, foreign_key: true
      t.integer :coins_count, null: false
      t.decimal :price, precision: 10, scale: 2, null: false
      t.string :transaction_id
      t.string :payment_status, default: 'pending'
      t.datetime :purchased_at

      t.timestamps
    end

    add_index :user_coin_purchases, :transaction_id
    add_index :user_coin_purchases, :payment_status
    add_index :user_coin_purchases, :purchased_at
  end
end
