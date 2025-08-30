class CreateStaffAssignments < ActiveRecord::Migration[7.2]
  def change
    create_table :staff_assignments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :pool, null: false, foreign_key: true
      t.references :sequence, null: false, foreign_key: true
      t.string :status, default: 'active', null: false
      t.string :assigned_gender, null: false
      t.text :notes
      t.datetime :last_online_at
      t.integer :total_chat_time, default: 0
      t.integer :total_chats, default: 0

      t.timestamps
    end

    add_index :staff_assignments, [:pool_id, :status]
    add_index :staff_assignments, [:status, :assigned_gender]
    add_index :staff_assignments, [:last_online_at]
  end
end



