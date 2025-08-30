class AddContentTypeToSequences < ActiveRecord::Migration[7.2]
  def change
    add_column :sequences, :content_type, :text, array: true, default: []
    add_index :sequences, :content_type, using: 'gin'
  end
end
