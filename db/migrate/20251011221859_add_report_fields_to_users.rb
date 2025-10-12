class AddReportFieldsToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :report_count, :integer, default: 0, null: false
    add_column :users, :blocked_users, :text, default: [], array: true
    add_index :users, :report_count
  end
end
