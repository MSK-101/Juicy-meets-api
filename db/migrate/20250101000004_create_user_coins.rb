class CreateUserCoins < ActiveRecord::Migration[7.2]
  def change
    create_table :user_coins do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :balance, default: 0, null: false
      t.integer :total_earned, default: 0, null: false
      t.integer :total_spent, default: 0, null: false
      t.datetime :last_activity_at

      t.timestamps
    end

    add_index :user_coins, :balance
    add_index :user_coins, :last_activity_at
  end
end
