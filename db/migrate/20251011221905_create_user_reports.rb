class CreateUserReports < ActiveRecord::Migration[7.2]
  def change
    create_table :user_reports do |t|
      t.bigint :reporter_id, null: false
      t.bigint :reported_user_id, null: false
      t.timestamps
    end

    add_index :user_reports, :reporter_id
    add_index :user_reports, :reported_user_id
    add_index :user_reports, [:reporter_id, :reported_user_id], unique: true

    add_foreign_key :user_reports, :users, column: :reporter_id
    add_foreign_key :user_reports, :users, column: :reported_user_id
  end
end
