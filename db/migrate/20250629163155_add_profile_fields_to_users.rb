class AddProfileFieldsToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :age, :integer
    add_column :users, :gender, :integer
    add_column :users, :interested_in, :integer
    add_column :users, :profile_completed, :boolean, default: false
  end
end
