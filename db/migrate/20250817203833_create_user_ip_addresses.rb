class CreateUserIpAddresses < ActiveRecord::Migration[7.2]
  def change
    create_table :user_ip_addresses do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ip_address, null: false
      t.datetime :created_at, null: false
    end

    add_index :user_ip_addresses, [:user_id, :ip_address], unique: true
    add_index :user_ip_addresses, :ip_address
  end
end



