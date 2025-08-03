class CreateSequences < ActiveRecord::Migration[7.2]
  def change
    create_table :sequences do |t|
      t.integer :video_count, null: false, default: 0
      t.boolean :active, default: true, null: false
      t.integer :position, null: false, default: 0
      t.references :pool, null: false, foreign_key: true

      t.timestamps
    end

    add_index :sequences, :active
    add_index :sequences, :position
    add_index :sequences, [:pool_id, :position]
  end
end
