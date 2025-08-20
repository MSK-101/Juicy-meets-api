class ConsolidateUserStatusFields < ActiveRecord::Migration[7.2]
  def up
    # Add new consolidated status field
    add_column :users, :status, :integer, default: 0, null: false
    
    # Remove old fields
    remove_column :users, :online_status
    remove_column :users, :in_chat
    
    # Add index for better performance
    add_index :users, :status
  end

  def down
    # Add back old fields
    add_column :users, :online_status, :string, default: 'offline'
    add_column :users, :in_chat, :boolean, default: false
    
    # Remove new field
    remove_column :users, :status
  end
end
