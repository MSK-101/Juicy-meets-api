class RemoveAssignedGenderFromStaffAssignments < ActiveRecord::Migration[7.2]
  def change
    remove_column :staff_assignments, :assigned_gender, :string
  end
end
