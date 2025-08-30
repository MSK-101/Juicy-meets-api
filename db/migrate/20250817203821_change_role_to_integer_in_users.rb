class ChangeRoleToIntegerInUsers < ActiveRecord::Migration[7.2]
  def up
    # Remove old role column
    remove_column :users, :role

    # Add new role column as integer
    add_column :users, :role, :integer, default: 0, null: false

    # Add index for better performance
    add_index :users, :role
  end

  def down
    # Remove index
    remove_index :users, :role

    # Remove new column
    remove_column :users, :role

    # Add back old string column
    add_column :users, :role, :string, default: 'user', null: false
  end
end
