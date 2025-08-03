class CreateDefaultPools < ActiveRecord::Migration[7.2]
  def up
    Pool.create!([
      { name: 'Pool A', active: true },
      { name: 'Pool B', active: true },
      { name: 'Pool C', active: true }
    ])
  end

  def down
    Pool.where(name: ['Pool A', 'Pool B', 'Pool C']).destroy_all
  end
end
