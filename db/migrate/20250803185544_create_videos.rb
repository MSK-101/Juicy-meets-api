class CreateVideos < ActiveRecord::Migration[7.2]
  def change
    create_table :videos do |t|
      t.string :name, null: false
      t.integer :gender, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.references :sequence, null: false, foreign_key: true
      t.references :pool, null: false, foreign_key: true
      t.references :admin, null: false, foreign_key: true

      t.timestamps
    end

    add_index :videos, :gender
    add_index :videos, :status
    add_index :videos, [:sequence_id, :status]
    add_index :videos, [:pool_id, :status]
  end
end
